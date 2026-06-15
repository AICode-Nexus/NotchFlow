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

        let startedAt = Date()
        service.refresh()
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.10)
    }

    @MainActor
    func testWallpaperRefreshDoesNotBlockMainActorDuringSlowApply() async throws {
        let fixture = try TemporaryRefreshFixture()
        let wallpaperURL = fixture.url.appendingPathComponent("wallpaper.png")
        try Data("fake image".utf8).write(to: wallpaperURL)

        let defaults = UserDefaults(suiteName: "NotchFlowTests-\(UUID().uuidString)")!
        defaults.set(fixture.url.path, forKey: "WallpaperRefreshSelectedFolderPath")
        let settings = AppSettings(defaults: defaults)
        let service = WallpaperRefreshService(
            settings: settings,
            defaults: defaults,
            fileScanner: StaticWallpaperFileScanner(wallpaperURL: wallpaperURL),
            wallpaperApplier: SlowWallpaperApplier(delay: 0.25)
        )

        let startedAt = Date()
        service.refresh()
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.10)
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

private struct StaticWallpaperFileScanner: WallpaperFileScanning {
    let wallpaperURL: URL?

    func wallpaperURL(in directoryURL: URL, excluding lastWallpaperURL: URL?) -> URL? {
        wallpaperURL
    }
}

private struct SlowWallpaperApplier: WallpaperApplying {
    let delay: TimeInterval

    func applyWallpaper(_ wallpaperURL: URL) throws {
        Thread.sleep(forTimeInterval: delay)
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
