import Foundation
@testable import NotchFlow
import XCTest

@MainActor
final class ChargeLimitServiceTests: XCTestCase {
    func testHelperInstallScriptUsesPerInvocationPrivilegeWithoutSetuid() {
        let source = "/tmp/source ' helper\"\\binary"
        let destination = "/usr/local/bin/notchflow-smc-\"\\helper"
        let script = ChargeLimitService.helperInstallationScript(
            source: source,
            destination: destination
        )

        XCTAssertTrue(script.contains("chmod 0755"))
        XCTAssertFalse(script.contains("chmod 4755"))
        XCTAssertLessThan(
            script.range(of: "rm -f")!.lowerBound,
            script.range(of: "cp '")!.lowerBound
        )
        assertAppleScriptCompiles(script)
    }

    func testPrivilegedWriteCommandEscapesPathsAndRequiresExplicitSuccessMarker() {
        let script = ChargeLimitService.privilegedHelperCommandScript(
            path: "/tmp/helper ' \" \\ executable",
            command: "disable-charging"
        )

        XCTAssertTrue(script.contains(ChargeLimitService.helperCommandSuccessMarker))
        assertAppleScriptCompiles(script)
        XCTAssertTrue(
            ChargeLimitService.helperCommandSucceeded(
                "diagnostic\n\(ChargeLimitService.helperCommandSuccessMarker)"
            )
        )
        XCTAssertFalse(ChargeLimitService.helperCommandSucceeded(""))
        XCTAssertFalse(ChargeLimitService.helperCommandSucceeded("diagnostic only"))
        XCTAssertFalse(
            ChargeLimitService.helperCommandSucceeded(
                "\(ChargeLimitService.helperCommandSuccessMarker)\ntrailing output"
            )
        )
    }

    func testSecureHelperPermissionsRequireRootOwnedImmutableRegularExecutable() {
        XCTAssertTrue(
            ChargeLimitService.isSecureInstalledHelper(
                helperFile(ownerID: 0, permissions: 0o755)
            )
        )

        XCTAssertFalse(
            ChargeLimitService.isSecureInstalledHelper(
                helperFile(ownerID: 501, permissions: 0o755)
            ),
            "Helper must be owned by root"
        )
        XCTAssertFalse(
            ChargeLimitService.isSecureInstalledHelper(
                helperFile(ownerID: 0, permissions: 0o4755)
            ),
            "setuid helpers must be migrated"
        )
        XCTAssertFalse(
            ChargeLimitService.isSecureInstalledHelper(
                helperFile(ownerID: 0, permissions: 0o2755)
            ),
            "setgid helpers must be migrated"
        )
        XCTAssertFalse(
            ChargeLimitService.isSecureInstalledHelper(
                helperFile(ownerID: 0, permissions: 0o775)
            ),
            "group-writable helpers can be replaced before privileged execution"
        )
        XCTAssertFalse(
            ChargeLimitService.isSecureInstalledHelper(
                helperFile(ownerID: 0, permissions: 0o757)
            ),
            "world-writable helpers can be replaced before privileged execution"
        )
        XCTAssertFalse(
            ChargeLimitService.isSecureInstalledHelper(
                helperFile(isRegularFile: false, ownerID: 0, permissions: 0o755)
            )
        )
        XCTAssertFalse(
            ChargeLimitService.isSecureInstalledHelper(
                helperFile(ownerID: 0, permissions: 0o644)
            )
        )
    }

    func testInstalledHelperMustExactlyMatchTheBundledTrustedCopy() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChargeLimitHelperTrust-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let trusted = directory.appendingPathComponent("trusted")
        let installed = directory.appendingPathComponent("installed")
        try Data("trusted helper".utf8).write(to: trusted)
        try Data("trusted helper".utf8).write(to: installed)

        XCTAssertTrue(
            ChargeLimitService.helperMatchesTrustedSource(
                installedPath: installed.path,
                trustedSourcePath: trusted.path
            )
        )

        try Data("different helper".utf8).write(to: installed)
        XCTAssertFalse(
            ChargeLimitService.helperMatchesTrustedSource(
                installedPath: installed.path,
                trustedSourcePath: trusted.path
            )
        )
    }

    func testAppleScriptCancellationIsReportedAsError() {
        XCTAssertEqual(
            ChargeLimitService.appleScriptErrorOutput(message: "User canceled."),
            "error: User canceled."
        )
    }

    func testStartNeverRestoresChargingWithoutAnExplicitUserAction() {
        let fixture = makeFixture(enabled: false, chargingDisabled: true)

        fixture.service.start()

        XCTAssertEqual(fixture.commands.commands, ["status"])
        XCTAssertEqual(fixture.service.pendingAction, .enableCharging)
        XCTAssertEqual(fixture.service.state, .actionRequired)
    }

    func testReconcileBelowMinimumRequestsApprovalWithoutWritingHardware() {
        let fixture = makeFixture(enabled: true, chargingDisabled: true)

        fixture.service.reconcile(percent: 67)

        XCTAssertEqual(fixture.commands.commands, ["status"])
        XCTAssertEqual(fixture.service.currentPercent, 67)
        XCTAssertEqual(fixture.service.pendingAction, .enableCharging)
        XCTAssertEqual(fixture.service.state, .actionRequired)
    }

    func testStartAboveLimitRequestsApprovalWithoutWritingHardware() {
        let fixture = makeFixture(
            enabled: true,
            chargingDisabled: false,
            currentPercent: 83
        )

        fixture.service.start()

        XCTAssertEqual(fixture.commands.commands, ["status", "status"])
        XCTAssertEqual(fixture.service.currentPercent, 83)
        XCTAssertEqual(fixture.service.pendingAction, .disableCharging)
        XCTAssertEqual(fixture.service.state, .actionRequired)
    }

    func testExplicitUserActionWritesThenReadsBackHardwareState() async throws {
        let fixture = makeFixture(
            enabled: true,
            chargingDisabled: false,
            currentPercent: 83
        )
        fixture.service.start()

        fixture.service.performPendingAction()
        try await waitUntil { !fixture.service.isPerformingAction }

        XCTAssertEqual(
            fixture.commands.commands,
            ["status", "status", "disable-charging", "status"]
        )
        XCTAssertNil(fixture.service.pendingAction)
        XCTAssertEqual(fixture.service.state, .chargingDisabled)
    }

    func testStoppingServiceNeverRunsAPrivilegedWrite() {
        let fixture = makeFixture(enabled: true, chargingDisabled: true)

        fixture.service.start()
        let commandsBeforeStop = fixture.commands.commands
        fixture.service.stop()

        XCTAssertEqual(fixture.commands.commands, commandsBeforeStop)
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

    private func helperFile(
        isRegularFile: Bool = true,
        ownerID: UInt32,
        permissions: UInt16
    ) -> ChargeLimitHelperFileSecurity {
        ChargeLimitHelperFileSecurity(
            isRegularFile: isRegularFile,
            ownerID: ownerID,
            permissions: permissions
        )
    }

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

    private func assertAppleScriptCompiles(
        _ source: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            XCTFail("Unable to create AppleScript", file: file, line: line)
            return
        }

        XCTAssertTrue(
            script.compileAndReturnError(&error),
            "AppleScript compile error: \(error?.description ?? "unknown")",
            file: file,
            line: line
        )
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
            return ChargeLimitService.helperCommandSuccessMarker
        case "disable-charging":
            chargingDisabled = true
            return ChargeLimitService.helperCommandSuccessMarker
        default:
            return "error: unexpected command"
        }
    }
}
