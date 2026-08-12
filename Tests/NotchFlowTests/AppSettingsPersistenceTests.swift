import Foundation
@testable import NotchFlow
import XCTest

@MainActor
final class AppSettingsPersistenceTests: XCTestCase {
    func testMutationsPersistToInjectedDefaultsSuite() {
        let suiteName = "AppSettingsPersistenceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(LogRetentionPreset.thirtyDays.rawValue, forKey: "LogRetentionPreset")
        defaults.set(false, forKey: "NowPlayingEnabled")

        let settings = AppSettings(defaults: defaults)
        settings.logRetentionPreset = .fourteenDays
        settings.nowPlayingEnabled = true

        XCTAssertEqual(
            defaults.integer(forKey: "LogRetentionPreset"),
            LogRetentionPreset.fourteenDays.rawValue
        )
        XCTAssertTrue(defaults.bool(forKey: "NowPlayingEnabled"))
    }
}
