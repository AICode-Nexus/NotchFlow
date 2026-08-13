import Combine
import Foundation
@testable import NotchFlow
import XCTest

final class MediaAndSettingsRegressionTests: XCTestCase {
    @MainActor
    func testStoppedNowPlayingServiceDoesNotRestartPollingWhenCadenceChanges() async throws {
        let remoteFetcher = CountingNowPlayingRemoteFetcher()
        let service = NowPlayingService(
            remoteFetcher: remoteFetcher,
            musicFetcher: EmptyNowPlayingMusicFetcher()
        )

        service.start()
        try await waitUntil { remoteFetcher.callCount == 1 }
        service.stop()
        let callCountAfterStop = remoteFetcher.callCount

        service.setInteractiveRefresh(true)
        try await Task.sleep(for: .milliseconds(1_100))

        XCTAssertEqual(remoteFetcher.callCount, callCountAfterStop)
    }

    @MainActor
    func testStoppingNowPlayingClearsPublishedPresentation() async throws {
        let service = NowPlayingService(
            remoteFetcher: ImmediateNowPlayingRemoteFetcher(),
            musicFetcher: EmptyNowPlayingMusicFetcher()
        )

        service.start()
        try await waitUntil { service.snapshot.title == "Playing before stop" }
        service.stop()

        XCTAssertEqual(service.snapshot, .empty)
        XCTAssertEqual(service.sourceLabel, "Idle")
        XCTAssertFalse(service.isRefreshing)
    }

    @MainActor
    func testCancelledNowPlayingRefreshCannotWriteAfterStop() async throws {
        let remoteFetcher = SuspendedNowPlayingRemoteFetcher()
        let service = NowPlayingService(
            remoteFetcher: remoteFetcher,
            musicFetcher: EmptyNowPlayingMusicFetcher()
        )

        service.start()
        try await waitUntil { remoteFetcher.hasPendingRequest }
        service.stop()
        remoteFetcher.resume(
            with: MediaRemotePayload(
                title: "Stale title",
                artist: "Stale artist",
                album: "Stale album",
                artworkData: nil,
                isPlaying: true
            )
        )
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(service.snapshot, .empty)
        XCTAssertEqual(service.sourceLabel, "Idle")
        XCTAssertFalse(service.isRefreshing)
    }

    @MainActor
    func testSlowNowPlayingRefreshesNeverOverlap() async throws {
        let remoteFetcher = SuspendedNowPlayingRemoteFetcher()
        let service = NowPlayingService(
            remoteFetcher: remoteFetcher,
            musicFetcher: EmptyNowPlayingMusicFetcher()
        )

        service.start()
        try await waitUntil { remoteFetcher.callCount == 1 }

        service.refresh()
        service.refresh()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(remoteFetcher.callCount, 1)
        service.stop()
        remoteFetcher.resume(with: nil)
    }

    @MainActor
    func testSettingsViewDirectlyObservesEveryNestedServiceItReads() {
        let view = SettingsView(model: .shared)
        let observedProperties = Set(Mirror(reflecting: view).children.compactMap(\.label))

        let expectedProperties: Set<String> = [
            "_settings",
            "_weather",
            "_battery",
            "_screenHealth",
            "_clipboardHistory",
            "_wallpaper",
            "_nowPlaying",
            "_launchAtLogin",
            "_chargeLimit",
            "_aiTokenUsage",
            "_scriptShortcuts",
        ]

        XCTAssertTrue(
            expectedProperties.isSubset(of: observedProperties),
            "Missing observations: \(expectedProperties.subtracting(observedProperties).sorted())"
        )
    }

    @MainActor
    func testAppModelPublishesPanelStateChangesUsedByMenuBarIcon() {
        let model = NotchFlowAppModel.shared
        model.panelController.collapseToCompact()
        var cancellables: Set<AnyCancellable> = []
        let changed = expectation(description: "App model forwards panel state")
        changed.assertForOverFulfill = false

        model.objectWillChange
            .sink { changed.fulfill() }
            .store(in: &cancellables)

        model.panelController.expandAndPin()

        wait(for: [changed], timeout: 1)
        XCTAssertEqual(model.menuBarIconName, "pin.fill")
        model.panelController.collapseToCompact()
    }

    func testPanelLayoutPolicyRequiresEnabledSettingForNowPlayingSection() throws {
        let controllerSourceURL = packageRoot()
            .appendingPathComponent("Sources/NotchFlow/Services/NotchPanelController.swift")
        let source = try String(contentsOf: controllerSourceURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("if settings.nowPlayingEnabled, nowPlaying.snapshot.hasContent"),
            "Expanded height must not reserve media space while media detection is disabled"
        )
        XCTAssertTrue(
            source.contains("settings.$nowPlayingEnabled"),
            "Changing the media setting must trigger an expanded layout refresh"
        )
    }

    func testAIUsagePrivacyCopyMentionsZCode() throws {
        let settingsSourceURL = packageRoot()
            .appendingPathComponent("Sources/NotchFlow/UI/SettingsView.swift")
        let source = try String(contentsOf: settingsSourceURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("Codex、Claude、ZCode"),
            "AI usage privacy copy should disclose the local ZCode metadata reader"
        )
    }

    func testAIUsageSourceStripRendersAfterPositiveAndEmptyStates() throws {
        let panelSourceURL = packageRoot()
            .appendingPathComponent("Sources/NotchFlow/UI/NotchPanelView.swift")
        let source = try String(contentsOf: panelSourceURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains(
                """
                            }

                            Spacer(minLength: 6)

                            aiTokenUsageSourceStrip
                        }
                    }
                """
            ),
            "Codex 0 and GLM 0 must remain visible after either AI usage state"
        )
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition())
    }
}

@MainActor
private final class CountingNowPlayingRemoteFetcher: NowPlayingRemoteFetching {
    private(set) var callCount = 0

    func fetchNowPlaying() async -> MediaRemotePayload? {
        callCount += 1
        return nil
    }
}

private struct ImmediateNowPlayingRemoteFetcher: NowPlayingRemoteFetching {
    func fetchNowPlaying() async -> MediaRemotePayload? {
        MediaRemotePayload(
            title: "Playing before stop",
            artist: "Artist",
            album: "Album",
            artworkData: nil,
            isPlaying: true
        )
    }
}

@MainActor
private final class SuspendedNowPlayingRemoteFetcher: NowPlayingRemoteFetching {
    private var continuation: CheckedContinuation<MediaRemotePayload?, Never>?
    private(set) var callCount = 0

    var hasPendingRequest: Bool {
        continuation != nil
    }

    func fetchNowPlaying() async -> MediaRemotePayload? {
        callCount += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(with payload: MediaRemotePayload?) {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(returning: payload)
    }
}

private struct EmptyNowPlayingMusicFetcher: NowPlayingMusicFetching {
    func fetchNowPlaying() -> MusicAppPayload? {
        nil
    }
}
