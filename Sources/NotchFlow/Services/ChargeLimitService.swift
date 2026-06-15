import Foundation
import Darwin
import IOKit.ps
import notify

enum ChargeLimitState: Equatable {
    case idle
    case monitoring
    case chargingDisabled
    case helperNotInstalled
    case unsupported
    case error(String)

    var displayText: String {
        switch self {
        case .idle:
            return "未启用"
        case .monitoring:
            return "监控中，正常充电"
        case .chargingDisabled:
            return "已暂停充电"
        case .helperNotInstalled:
            return "需要安装 Helper"
        case .unsupported:
            return "设备不支持"
        case .error(let msg):
            return "错误：\(msg)"
        }
    }
}

@MainActor
final class ChargeLimitService: ObservableObject {
    @Published private(set) var state: ChargeLimitState = .idle
    @Published private(set) var currentPercent: Int = 0
    @Published private(set) var isHelperInstalled: Bool = false

    private let settings: AppSettings
    private let helperExecutablePath: String
    private let helperCommandRunner: ((String) -> String)?
    private let currentPercentProvider: () -> Int?
    private var notifyToken: Int32 = 0
    private var isRegistered = false

    init(
        settings: AppSettings,
        installedHelperPath: String = "/usr/local/bin/notchflow-smc-helper",
        helperCommandRunner: ((String) -> String)? = nil,
        currentPercentProvider: @escaping () -> Int? = ChargeLimitService.systemInternalBatteryPercent
    ) {
        self.settings = settings
        self.helperExecutablePath = installedHelperPath
        self.helperCommandRunner = helperCommandRunner
        self.currentPercentProvider = currentPercentProvider
        self.isHelperInstalled = helperInstalled()
    }

    func start() {
        isHelperInstalled = helperInstalled()

        guard settings.chargeLimitEnabled else {
            unregisterPercentNotification()
            restoreChargingIfNeeded()
            return
        }

        guard isHelperInstalled else {
            unregisterPercentNotification()
            state = helperSourcePath() == nil ? .error("未找到 Helper 可执行文件") : .helperNotInstalled
            return
        }

        guard let status = helperStatus() else {
            unregisterPercentNotification()
            return
        }

        guard status.supported else {
            unregisterPercentNotification()
            settings.chargeLimitEnabled = false
            state = .unsupported
            return
        }

        state = status.chargingDisabled ? .chargingDisabled : .monitoring
        registerPercentNotification()
    }

    func stop() {
        unregisterPercentNotification()
        restoreChargingIfNeeded()
    }

    func toggle() {
        setEnabled(!settings.chargeLimitEnabled)
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            settings.chargeLimitEnabled = true
            start()
            return
        }

        settings.chargeLimitEnabled = false
        stop()
    }

    func installHelper() {
        guard let source = helperSourcePath() else {
            state = .error("未找到 Helper 可执行文件")
            return
        }

        let dest = installedHelperPath()

        guard !FileManager.default.isExecutableFile(atPath: dest) else {
            isHelperInstalled = true
            if state == .helperNotInstalled {
                start()
            }
            return
        }

        let script = """
        do shell script "mkdir -p '\(shellEscaped("/usr/local/bin"))' && cp '\(shellEscaped(source))' '\(shellEscaped(dest))' && chown root:wheel '\(shellEscaped(dest))' && chmod 4755 '\(shellEscaped(dest))'" with administrator privileges
        """
        let output = runAppleScript(script)

        isHelperInstalled = helperInstalled()
        if isHelperInstalled {
            start()
        } else if output.hasPrefix("error:") {
            state = .error("安装 Helper 失败")
        }
    }

    private func registerPercentNotification() {
        guard !isRegistered else { return }

        let status = notify_register_dispatch(
            "com.apple.system.powersources.percent",
            &notifyToken,
            DispatchQueue.main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handlePercentChange()
            }
        }

        guard status == NOTIFY_STATUS_OK else {
            state = .error("无法注册电量通知")
            return
        }

        isRegistered = true
        handlePercentChange()
    }

    private func unregisterPercentNotification() {
        guard isRegistered else { return }
        notify_cancel(notifyToken)
        notifyToken = 0
        isRegistered = false
    }

    private func handlePercentChange() {
        guard let percent = currentPercentProvider() else { return }
        reconcile(percent: percent)
    }

    nonisolated private static func systemInternalBatteryPercent() -> Int? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return nil
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                let current = description[kIOPSCurrentCapacityKey] as? Int,
                let maximum = description[kIOPSMaxCapacityKey] as? Int,
                maximum > 0
            else {
                continue
            }

            return min(max(Int((Double(current) / Double(maximum) * 100).rounded()), 0), 100)
        }

        return nil
    }

    func reconcile(percent: Int) {
        currentPercent = min(max(percent, 0), 100)

        guard settings.chargeLimitEnabled else {
            restoreChargingIfNeeded()
            return
        }

        guard let status = helperStatus() else {
            return
        }

        guard status.supported else {
            settings.chargeLimitEnabled = false
            state = .unsupported
            return
        }

        let maxCharge = settings.chargeLimitMax
        let minCharge = settings.chargeLimitMin

        if currentPercent >= maxCharge && !status.chargingDisabled {
            disableCharging()
        } else if currentPercent < minCharge && status.chargingDisabled {
            enableCharging()
        } else {
            state = status.chargingDisabled ? .chargingDisabled : .monitoring
        }
    }

    private func disableCharging() {
        let output = runHelperCommand("disable-charging")
        if !output.contains("error") {
            state = .chargingDisabled
        } else {
            state = .error("禁止充电失败")
        }
    }

    private func enableCharging() {
        let output = runHelperCommand("enable-charging")
        if !output.contains("error") {
            state = .monitoring
        } else {
            state = .error("恢复充电失败")
        }
    }

    private func restoreChargingIfNeeded() {
        guard isHelperInstalled else {
            state = .idle
            return
        }

        guard let status = helperStatus() else {
            return
        }

        guard status.supported, status.chargingDisabled else {
            state = .idle
            return
        }

        let output = runHelperCommand("enable-charging")
        state = output.hasPrefix("error:") ? .error("恢复充电失败") : .idle
    }

    private func helperStatus() -> HelperStatus? {
        let output = runHelperCommand("status")
        if output.hasPrefix("error:") {
            state = .error("无法检测设备支持状态")
            return nil
        }

        guard let data = output.data(using: .utf8),
              let status = try? JSONDecoder().decode(HelperStatus.self, from: data)
        else {
            state = .error("Helper 状态格式无效")
            return nil
        }

        return status
    }

    private func runHelperCommand(_ command: String) -> String {
        if let helperCommandRunner {
            return helperCommandRunner(command)
        }

        let path = installedHelperPath()
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return "error: helper not installed"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = [command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return "error: \(error.localizedDescription)"
        }
        if process.terminationStatus != 0 {
            return "error: exit code \(process.terminationStatus)"
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    @discardableResult
    private func runAppleScript(_ source: String) -> String {
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        let result = script?.executeAndReturnError(&error)
        if let error = error {
            let msg = error[NSAppleScript.errorMessage] as? String ?? "未知错误"
            if !msg.contains("User canceled") {
                return "error: \(msg)"
            }
            return ""
        }
        return result?.stringValue ?? ""
    }

    private func helperInstalled() -> Bool {
        FileManager.default.isExecutableFile(atPath: installedHelperPath())
    }

    private func installedHelperPath() -> String {
        helperExecutablePath
    }

    private func helperSourcePath() -> String? {
        for candidate in helperSourceCandidates() where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }

        return nil
    }

    private func helperSourceCandidates() -> [String] {
        var candidates: [String] = []

        if let bundlePath = Bundle.main.path(forResource: "notchflow-smc-helper", ofType: nil) {
            candidates.append(bundlePath)
        }

        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        candidates.append(currentDirectory.appendingPathComponent(".build/debug/notchflow-smc-helper").path)
        candidates.append(currentDirectory.appendingPathComponent(".build/arm64-apple-macosx/debug/notchflow-smc-helper").path)

        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = sourceFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        candidates.append(projectRoot.appendingPathComponent(".build/debug/notchflow-smc-helper").path)
        candidates.append(projectRoot.appendingPathComponent(".build/arm64-apple-macosx/debug/notchflow-smc-helper").path)

        return Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates
    }

    private func shellEscaped(_ path: String) -> String {
        path.replacingOccurrences(of: "'", with: "'\"'\"'")
    }
}

private struct HelperStatus: Decodable {
    let supported: Bool
    let chargingDisabled: Bool
}
