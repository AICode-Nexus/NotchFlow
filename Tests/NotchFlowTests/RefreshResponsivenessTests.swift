import Foundation
@testable import NotchFlow
import XCTest

final class RefreshResponsivenessTests: XCTestCase {
    @MainActor
    func testNowPlayingRefreshDoesNotBlockMainActorDuringSlowMusicFallback() async throws {
        let service = NowPlayingService(
            remoteFetcher: EmptyNowPlayingRemoteFetcher(),
            musicFetcher: SlowNowPlayingMusicFetcher(delay: 0.25)
        )
        defer { service.stop() }

        let startedAt = Date()
        service.start()
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.10)
    }

    @MainActor
    func testWallpaperRefreshDoesNotBlockMainActorDuringSlowScanAndAppliesOnMainThread() async throws {
        let fixture = try TemporaryRefreshFixture()
        let wallpaperURL = fixture.url.appendingPathComponent("wallpaper.png")
        try Data("fake image".utf8).write(to: wallpaperURL)

        let defaults = UserDefaults(suiteName: "NotchFlowTests-\(UUID().uuidString)")!
        defaults.set(fixture.url.path, forKey: "WallpaperRefreshSelectedFolderPath")
        let settings = AppSettings(defaults: defaults)
        let applier = MainThreadRecordingWallpaperApplier()
        let service = WallpaperRefreshService(
            settings: settings,
            defaults: defaults,
            fileScanner: SlowWallpaperFileScanner(wallpaperURL: wallpaperURL, delay: 0.25),
            wallpaperApplier: applier
        )

        let startedAt = Date()
        service.refresh()
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.10)
        XCTAssertNil(applier.wasCalledOnMainThread)

        try await waitUntil { !service.isRefreshing }
        XCTAssertEqual(applier.wasCalledOnMainThread, true)
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 1,
        condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                XCTFail("Timed out waiting for condition")
                return
            }

            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private struct EmptyNowPlayingRemoteFetcher: NowPlayingRemoteFetching {
    func fetchNowPlaying() async -> MediaRemotePayload? {
        nil
    }
}

private struct SlowNowPlayingMusicFetcher: NowPlayingMusicFetching {
    let delay: TimeInterval

    func fetchNowPlaying() -> MusicAppPayload? {
        Thread.sleep(forTimeInterval: delay)
        return MusicAppPayload(
            title: "Slow Song",
            artist: "Slow Artist",
            album: "Slow Album",
            isPlaying: false
        )
    }
}

private struct SlowWallpaperFileScanner: WallpaperFileScanning {
    let wallpaperURL: URL?
    let delay: TimeInterval

    func wallpaperURL(in directoryURL: URL, excluding lastWallpaperURL: URL?) -> URL? {
        Thread.sleep(forTimeInterval: delay)
        return wallpaperURL
    }
}

@MainActor
private final class MainThreadRecordingWallpaperApplier: WallpaperApplying {
    private(set) var wasCalledOnMainThread: Bool?

    func applyWallpaper(_ wallpaperURL: URL) throws {
        wasCalledOnMainThread = Thread.isMainThread
    }
}

private final class TemporaryRefreshFixture {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchFlowRefreshTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
