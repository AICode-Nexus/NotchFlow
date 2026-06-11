import Foundation

enum ExitCode: Int32 {
    case success = 0
    case unsupported = 1
    case smcError = 2
    case badUsage = 3
}

func printUsage() {
    fputs("Usage: notchflow-smc-helper <command>\n", stderr)
    fputs("Commands: enable-charging, disable-charging, status\n", stderr)
}

func run() -> ExitCode {
    let args = CommandLine.arguments
    guard args.count == 2 else {
        printUsage()
        return .badUsage
    }

    let command = args[1]

    fputs("Running as uid: \(getuid()), euid: \(geteuid())\n", stderr)

    guard SMCComm.open() else {
        fputs("Failed to open SMC connection\n", stderr)
        return .smcError
    }
    defer { SMCComm.close() }

    guard SMCPower.supported() else {
        if command == "status" {
            print(#"{"supported":false,"chargingDisabled":false}"#)
            return .success
        }
        fputs("Hardware not supported\n", stderr)
        return .unsupported
    }

    switch command {
    case "enable-charging":
        let success = SMCPower.enableCharging()
        if !success {
            fputs("Failed to enable charging (write rejected or readback mismatch)\n", stderr)
        }
        return success ? .success : .smcError

    case "disable-charging":
        let success = SMCPower.disableCharging()
        if !success {
            fputs("Failed to disable charging (write rejected or readback mismatch)\n", stderr)
        }
        return success ? .success : .smcError

    case "status":
        let disabled = SMCPower.isChargingDisabled()
        print(#"{"supported":true,"chargingDisabled":\#(disabled)}"#)
        return .success

    default:
        printUsage()
        return .badUsage
    }
}

exit(run().rawValue)
