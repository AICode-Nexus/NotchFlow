import Foundation
@testable import NotchFlow
import XCTest

@MainActor
final class ChargeLimitServiceTests: XCTestCase {
    func testStartRestoresChargingWhenFeatureIsDisabledButHardwareIsStillBlocked() {
        let fixture = makeFixture(enabled: false, chargingDisabled: true)

        fixture.service.start()

        XCTAssertEqual(fixture.commands.commands, ["status", "enable-charging"])
        XCTAssertEqual(fixture.service.state, .idle)
    }

    func testReconcileRestoresChargingBelowMinimumUsingHardwareState() {
        let fixture = makeFixture(enabled: true, chargingDisabled: true)

        fixture.service.reconcile(percent: 67)

        XCTAssertEqual(fixture.commands.commands, ["status", "enable-charging"])
        XCTAssertEqual(fixture.service.currentPercent, 67)
        XCTAssertEqual(fixture.service.state, .monitoring)
    }

    func testStartDisablesChargingImmediatelyWhenBatteryIsAboveLimit() {
        let fixture = makeFixture(
            enabled: true,
            chargingDisabled: false,
            currentPercent: 83
        )

        fixture.service.start()

        XCTAssertEqual(fixture.commands.commands, ["status", "status", "disable-charging"])
        XCTAssertEqual(fixture.service.currentPercent, 83)
        XCTAssertEqual(fixture.service.state, .chargingDisabled)
    }

    private func makeFixture(
        enabled: Bool,
        chargingDisabled: Bool,
        currentPercent: Int = 50
    ) -> (service: ChargeLimitService, commands: CommandLog) {
        let suiteName = "ChargeLimitServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(enabled, forKey: "ChargeLimitEnabled")

        let settings = AppSettings(defaults: defaults)
        let commands = CommandLog(chargingDisabled: chargingDisabled)
        let service = ChargeLimitService(
            settings: settings,
            installedHelperPath: "/usr/bin/true",
            helperCommandRunner: { command in
                commands.run(command)
            },
            currentPercentProvider: { currentPercent }
        )

        return (service, commands)
    }
}

private final class CommandLog {
    private(set) var commands: [String] = []
    private var chargingDisabled: Bool

    init(chargingDisabled: Bool) {
        self.chargingDisabled = chargingDisabled
    }

    func run(_ command: String) -> String {
        commands.append(command)

        switch command {
        case "status":
            return #"{"supported":true,"chargingDisabled":\#(chargingDisabled)}"#
        case "enable-charging":
            chargingDisabled = false
            return ""
        case "disable-charging":
            chargingDisabled = true
            return ""
        default:
            return "error: unexpected command"
        }
    }
}
