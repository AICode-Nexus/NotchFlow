import Foundation
@testable import NotchFlow
import XCTest

final class WallpaperAndAppSearchRegressionTests: XCTestCase {
    @MainActor
    func testEmptyWallpaperFolderReschedulesAutomaticRefresh() async throws {
        let fixture = try WallpaperRetryFixture(scanner: RetryWallpaperScanner(wallpaperURL: nil))
        defer { fixture.service.stop() }

        fixture.service.start()
        let originalRefreshDate = try XCTUnwrap(fixture.service.nextRefreshDate)
        try await Task.sleep(for: .milliseconds(20))

        fixture.service.refresh()
        try await waitUntil { fixture.service.statusMessage == "文件夹内没有可用图片" }

        XCTAssertGreaterThan(try XCTUnwrap(fixture.service.nextRefreshDate), originalRefreshDate)
    }

    @MainActor
    func testWallpaperApplyFailureReschedulesAutomaticRefresh() async throws {
        let fixture = try WallpaperRetryFixture(
            scanner: RetryWallpaperScanner(wallpaperURL: URL(fileURLWithPath: "/tmp/wallpaper.png")),
            applier: FailingWallpaperApplier()
        )
        defer { fixture.service.stop() }

        fixture.service.start()
        let originalRefreshDate = try XCTUnwrap(fixture.service.nextRefreshDate)
        try await Task.sleep(for: .milliseconds(20))

        fixture.service.refresh()
        try await waitUntil { fixture.service.statusMessage.hasPrefix("刷新失败：") }

        XCTAssertGreaterThan(try XCTUnwrap(fixture.service.nextRefreshDate), originalRefreshDate)
    }

    @MainActor
    func testTemporarilyUnavailableWallpaperFolderReschedulesAutomaticRefresh() async throws {
        let defaults = isolatedDefaults()
        let unavailableDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchFlowMissingWallpaperFolder-\(UUID().uuidString)", isDirectory: true)
        configureAutomaticWallpaperRefresh(defaults: defaults, directoryURL: unavailableDirectoryURL)

        let settings = AppSettings(defaults: defaults)
        let service = WallpaperRefreshService(settings: settings, defaults: defaults)
        defer { service.stop() }

        service.start()
        let originalRefreshDate = try XCTUnwrap(service.nextRefreshDate)
        try await Task.sleep(for: .milliseconds(20))

        service.refresh()

        XCTAssertEqual(service.statusMessage, "壁纸文件夹不可用")
        XCTAssertGreaterThan(try XCTUnwrap(service.nextRefreshDate), originalRefreshDate)
    }

    @MainActor
    func testLocalAppIndexingDoesNotRunScannerOnMainThread() async throws {
        let scanner = SlowRecordingAppScanner(delay: 0.2)
        let service = LocalAppSearchService(scanner: scanner)

        let startedAt = Date()
        service.start()
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.10)
        XCTAssertTrue(service.isIndexing)

        try await waitUntil(timeout: 1) { !service.isIndexing }
        XCTAssertEqual(scanner.wasCalledOnMainThread, false)

        service.query = "test"
        XCTAssertEqual(service.visibleResults.map(\.displayName), ["Test App"])
    }

    @MainActor
    func testChangingWallpaperFolderCancelsOldRefreshBeforeApplyingWallpaper() async throws {
        let directories = try TemporaryWallpaperDirectories()
        let defaults = isolatedDefaults()
        defaults.set(directories.first.path, forKey: "WallpaperRefreshSelectedFolderPath")
        let settings = AppSettings(defaults: defaults)
        let scanner = FirstCallSlowDirectoryWallpaperScanner(delay: 0.2)
        let applier = RecordingWallpaperApplier()
        let service = WallpaperRefreshService(
            settings: settings,
            defaults: defaults,
            fileScanner: scanner,
            wallpaperApplier: applier
        )
        defer { service.stop() }

        service.refresh()
        try await waitUntil { scanner.callCount == 1 }

        service.setWallpaperFolder(directories.second)
        XCTAssertFalse(service.isRefreshing)
        service.refresh()

        try await waitUntil { !service.isRefreshing && applier.appliedURLs.count == 1 }
        try await Task.sleep(for: .milliseconds(250))

        let expectedURL = directories.second.appendingPathComponent("wallpaper.png")
        XCTAssertEqual(applier.appliedURLs, [expectedURL])
        XCTAssertEqual(service.lastWallpaperURL, expectedURL)
    }

    @MainActor
    func testStoppingLocalAppSearchCancelsIndexingTaskAndIgnoresItsResult() async throws {
        let scanner = SlowRecordingAppScanner(delay: 0.2)
        let service = LocalAppSearchService(scanner: scanner)

        service.start()
        try await waitUntil { scanner.wasCalledOnMainThread != nil }
        service.stop()

        XCTAssertFalse(service.isIndexing)
        try await waitUntil { scanner.observedCancellation == true }

        service.query = "test"
        XCTAssertTrue(service.visibleResults.isEmpty)
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

    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "NotchFlowWallpaperRetryTests-\(UUID().uuidString)")!
    }

    private func configureAutomaticWallpaperRefresh(defaults: UserDefaults, directoryURL: URL) {
        defaults.set(true, forKey: "WallpaperAutoRefreshEnabled")
        defaults.set(WallpaperRefreshIntervalPreset.fiveMinutes.rawValue, forKey: "WallpaperRefreshIntervalPreset")
        defaults.set(directoryURL.path, forKey: "WallpaperRefreshSelectedFolderPath")
    }
}

@MainActor
private final class WallpaperRetryFixture {
    let service: WallpaperRefreshService
    private let directoryURL: URL

    init(
        scanner: any WallpaperFileScanning,
        applier: any WallpaperApplying = SuccessfulWallpaperApplier()
    ) throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchFlowWallpaperRetryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let defaults = UserDefaults(suiteName: "NotchFlowWallpaperRetryTests-\(UUID().uuidString)")!
        defaults.set(true, forKey: "WallpaperAutoRefreshEnabled")
        defaults.set(WallpaperRefreshIntervalPreset.fiveMinutes.rawValue, forKey: "WallpaperRefreshIntervalPreset")
        defaults.set(directoryURL.path, forKey: "WallpaperRefreshSelectedFolderPath")

        let settings = AppSettings(defaults: defaults)
        service = WallpaperRefreshService(
            settings: settings,
            defaults: defaults,
            fileScanner: scanner,
            wallpaperApplier: applier
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

private struct RetryWallpaperScanner: WallpaperFileScanning {
    let wallpaperURL: URL?

    func wallpaperURL(in directoryURL: URL, excluding lastWallpaperURL: URL?) -> URL? {
        wallpaperURL
    }
}

private struct SuccessfulWallpaperApplier: WallpaperApplying {
    func applyWallpaper(_ wallpaperURL: URL) throws {}
}

private struct FailingWallpaperApplier: WallpaperApplying {
    func applyWallpaper(_ wallpaperURL: URL) throws {
        throw WallpaperApplyTestError.failed
    }
}

private enum WallpaperApplyTestError: Error {
    case failed
}

private final class FirstCallSlowDirectoryWallpaperScanner: WallpaperFileScanning, @unchecked Sendable {
    private let delay: TimeInterval
    private let lock = NSLock()
    private var calls = 0

    init(delay: TimeInterval) {
        self.delay = delay
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func wallpaperURL(in directoryURL: URL, excluding lastWallpaperURL: URL?) -> URL? {
        lock.lock()
        calls += 1
        let shouldDelay = calls == 1
        lock.unlock()

        if shouldDelay {
            Thread.sleep(forTimeInterval: delay)
        }

        return directoryURL.appendingPathComponent("wallpaper.png")
    }
}

@MainActor
private final class RecordingWallpaperApplier: WallpaperApplying {
    private(set) var appliedURLs: [URL] = []

    func applyWallpaper(_ wallpaperURL: URL) throws {
        appliedURLs.append(wallpaperURL)
    }
}

private final class TemporaryWallpaperDirectories {
    let first: URL
    let second: URL
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchFlowWallpaperGenerationTests-\(UUID().uuidString)", isDirectory: true)
        first = root.appendingPathComponent("First", isDirectory: true)
        second = root.appendingPathComponent("Second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class SlowRecordingAppScanner: LocalApplicationScanning, @unchecked Sendable {
    private let delay: TimeInterval
    private let lock = NSLock()
    private var recordedMainThreadState: Bool?
    private var recordedCancellation = false

    init(delay: TimeInterval) {
        self.delay = delay
    }

    var wasCalledOnMainThread: Bool? {
        lock.lock()
        defer { lock.unlock() }
        return recordedMainThreadState
    }

    var observedCancellation: Bool {
        lock.lock()
        defer { lock.unlock() }
        return recordedCancellation
    }

    func discoverApplications() -> [LocalInstalledApp] {
        lock.lock()
        recordedMainThreadState = Thread.isMainThread
        lock.unlock()

        Thread.sleep(forTimeInterval: delay)
        lock.lock()
        recordedCancellation = Task.isCancelled
        lock.unlock()
        return [
            LocalInstalledApp(
                id: "/Applications/Test App.app",
                displayName: "Test App",
                bundleIdentifier: "com.example.test-app",
                url: URL(fileURLWithPath: "/Applications/Test App.app")
            ),
        ]
    }
}
