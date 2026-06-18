import Foundation
@testable import NotchFlow
import XCTest

final class NowPlayingSnapshotTests: XCTestCase {
    func testDisplayTitleIsNilForEmptyTitle() {
        XCTAssertNil(NowPlayingSnapshot.empty.displayTitle)
        XCTAssertFalse(NowPlayingSnapshot.empty.hasContent)
    }

    func testDisplayTitleIsNilForWhitespaceTitle() {
        let snapshot = NowPlayingSnapshot(
            title: " \n\t ",
            artist: "Artist",
            album: "Album",
            sourceApp: "Test",
            isPlaying: true,
            artworkData: nil
        )

        XCTAssertNil(snapshot.displayTitle)
        XCTAssertFalse(snapshot.hasContent)
    }

    func testDisplayTitleTrimsPlayableTitle() {
        let snapshot = NowPlayingSnapshot(
            title: "  Song Title  ",
            artist: "Artist",
            album: "Album",
            sourceApp: "Test",
            isPlaying: true,
            artworkData: nil
        )

        XCTAssertEqual(snapshot.displayTitle, "Song Title")
        XCTAssertTrue(snapshot.hasContent)
    }
}
