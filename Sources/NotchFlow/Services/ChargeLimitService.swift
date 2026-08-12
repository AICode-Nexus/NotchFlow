import Foundation
import Darwin
import IOKit.ps
import notify

enum ChargeLimitState: Equatable {
    case idle
    case monitoring
    case chargingDisabled
    case actionRequired
    case performingAction
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
        case .actionRequired:
            return "需要点击确认并授权"
        case .performingAction:
            return "正在等待授权..."
        case .helperNotInstalled:
            return "需要安装 Helper"
        case .unsupported:
            return "设备不支持"
        case .error(let msg):
            return "错误：\(msg)"
        }
    }
}

enum ChargeLimitPendingAction: Equatable, Sendable {
    case enableCharging
    case disableCharging

    var buttonTitle: String {
        switch self {
        case .enableCharging:
            return "授权恢复充电"
        case .disableCharging:
            return "授权暂停充电"
        }
    }

    fileprivate var command: String {
        switch self {
        case .enableCharging:
            return "enable-charging"
        case .disableCharging:
            return "disable-charging"
        }
    }
}

struct ChargeLimitHelperFileSecurity: Equatable {
    let isRegularFile: Bool
    let ownerID: UInt32
    let permissions: UInt16
}

@MainActor
final class ChargeLimitService: ObservableObject {
    @Published private(set) var state: ChargeLimitState = .idle
    @Published private(set) var currentPercent: Int = 0
    @Published private(set) var isHelperInstalled: Bool = false
    @Published private(set) var pendingAction: ChargeLimitPendingAction?
    @Published private(set) var isPerformingAction = false

    private let settings: AppSettings
    private let helperExecutablePath: String
    private let helperCommandRunner: ((String) -> String)?
    private let currentPercentProvider: () -> Int?
    private var notifyToken: Int32 = 0
    private var isRegistered = false
    private var actionTask: Task<Void, Never>?

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

        guard isHelperInstalled else {
            unregisterPercentNotification()
            pendingAction = nil
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
            pendingAction = nil
            state = .unsupported
            return
        }

        guard settings.chargeLimitEnabled else {
            unregisterPercentNotification()
            updateState(using: status, evaluateThresholds: false)
            return
        }

        pendingAction = nil
        state = status.chargingDisabled ? .chargingDisabled : .monitoring
        registerPercentNotification()
    }

    func stop() {
        unregisterPercentNotification()
        actionTask?.cancel()
        actionTask = nil
        isPerformingAction = false
    }

    func toggle() {
        setEnabled(!settings.chargeLimitEnabled)
    }

    func setEnabled(_ enabled: Bool) {
        guard !isPerformingAction else {
            return
        }

        settings.chargeLimitEnabled = enabled
        start()
    }

    func installHelper() {
        guard let source = helperSourcePath() else {
            state = .error("未找到 Helper 可执行文件")
            return
        }

        let dest = installedHelperPath()

        guard !helperInstalled() else {
            isHelperInstalled = true
            if state == .helperNotInstalled {
                start()
            }
            return
        }

        let script = Self.helperInstallationScript(source: source, destination: dest)
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

        guard let status = helperStatus() else {
            return
        }

        guard status.supported else {
            settings.chargeLimitEnabled = false
            pendingAction = nil
            state = .unsupported
            return
        }

        updateState(using: status, evaluateThresholds: settings.chargeLimitEnabled)
    }

    func performPendingAction() {
        guard !isPerformingAction, let action = pendingAction else {
            return
        }

        guard helperInstalled() else {
            isHelperInstalled = false
            state = .helperNotInstalled
            return
        }

        isPerformingAction = true
        state = .performingAction

        if let helperCommandRunner {
            finishPendingAction(action, output: helperCommandRunner(action.command))
            return
        }

        let script = Self.privilegedHelperCommandScript(
            path: installedHelperPath(),
            command: action.command
        )
        actionTask?.cancel()
        actionTask = Task { [weak self] in
            let output = await Task.detached(priority: .userInitiated) {
                Self.executeAppleScript(script)
            }.value

            guard !Task.isCancelled, let self else {
                return
            }

            self.finishPendingAction(action, output: output)
        }
    }

    private func updateState(using status: HelperStatus, evaluateThresholds: Bool) {
        if !settings.chargeLimitEnabled {
            pendingAction = status.chargingDisabled ? .enableCharging : nil
            state = pendingAction == nil ? .idle : .actionRequired
            return
        }

        if evaluateThresholds,
           currentPercent >= settings.chargeLimitMax,
           !status.chargingDisabled
        {
            pendingAction = .disableCharging
            state = .actionRequired
            return
        }

        if evaluateThresholds,
           currentPercent < settings.chargeLimitMin,
           status.chargingDisabled
        {
            pendingAction = .enableCharging
            state = .actionRequired
            return
        }

        pendingAction = nil
        state = status.chargingDisabled ? .chargingDisabled : .monitoring
    }

    private func finishPendingAction(_ action: ChargeLimitPendingAction, output: String) {
        actionTask = nil
        isPerformingAction = false

        guard Self.helperCommandSucceeded(output) else {
            state = .error("授权操作已取消或执行失败")
            return
        }

        guard let status = helperStatus() else {
            return
        }

        let reachedExpectedState = switch action {
        case .enableCharging:
            !status.chargingDisabled
        case .disableCharging:
            status.chargingDisabled
        }

        guard reachedExpectedState else {
            state = .error("执行后充电状态未改变")
            return
        }

        updateState(using: status, evaluateThresholds: settings.chargeLimitEnabled)
    }

    private func helperStatus() -> HelperStatus? {
        let output = runHelperStatusCommand()
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

    private func runHelperStatusCommand() -> String {
        if let helperCommandRunner {
            return helperCommandRunner("status")
        }

        let path = installedHelperPath()
        guard helperInstalled() else {
            return "error: helper not installed"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["status"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return "error: \(error.localizedDescription)"
        }
        guard process.terminationStatus == 0 else {
            return "error: exit code \(process.terminationStatus)"
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    @discardableResult
    private func runAppleScript(_ source: String) -> String {
        Self.executeAppleScript(source)
    }

    nonisolated private static func executeAppleScript(_ source: String) -> String {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            return "error: 无法创建 AppleScript"
        }

        let result = script.executeAndReturnError(&error)
        if let error = error {
            let msg = error[NSAppleScript.errorMessage] as? String ?? "未知错误"
            return Self.appleScriptErrorOutput(message: msg)
        }

        guard let output = result.stringValue else {
            return "error: AppleScript 未返回执行结果"
        }
        return output
    }

    private func helperInstalled() -> Bool {
        let path = installedHelperPath()
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return false
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            guard let fileType = attributes[.type] as? FileAttributeType,
                  let ownerID = (attributes[.ownerAccountID] as? NSNumber)?.uint32Value,
                  let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value
            else {
                return false
            }

            let hasSecureMetadata = Self.isSecureInstalledHelper(
                ChargeLimitHelperFileSecurity(
                    isRegularFile: fileType == .typeRegular,
                    ownerID: ownerID,
                    permissions: permissions
                )
            )
            guard hasSecureMetadata else {
                return false
            }

            // Tests inject their own command runner and never execute the file.
            // Production must only trust the exact helper shipped with this app.
            if helperCommandRunner != nil {
                return true
            }

            guard let trustedSourcePath = helperSourcePath() else {
                return false
            }
            return Self.helperMatchesTrustedSource(
                installedPath: path,
                trustedSourcePath: trustedSourcePath
            )
        } catch {
            return false
        }
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

    nonisolated static func helperInstallationScript(source: String, destination: String) -> String {
        let source = shellEscapedPath(source)
        let destinationDirectory = shellEscapedPath(
            URL(fileURLWithPath: destination).deletingLastPathComponent().path
        )
        let destination = shellEscapedPath(destination)
        let command = "mkdir -p '\(destinationDirectory)' && rm -f '\(destination)' && cp '\(source)' '\(destination)' && chown root:wheel '\(destination)' && chmod 0755 '\(destination)'"
        return "do shell script \"\(appleScriptString(command))\" with administrator privileges"
    }

    nonisolated static let helperCommandSuccessMarker = "__NOTCHFLOW_SMC_HELPER_OK__"

    nonisolated static func privilegedHelperCommandScript(path: String, command: String) -> String {
        let path = shellEscapedPath(path)
        let command = shellEscapedPath(command)
        let marker = shellEscapedPath(helperCommandSuccessMarker)
        let shellCommand = "'\(path)' '\(command)' && printf '\\n%s\\n' '\(marker)'"
        return "do shell script \"\(appleScriptString(shellCommand))\" with administrator privileges"
    }

    nonisolated static func helperCommandSucceeded(_ output: String) -> Bool {
        output
            .split(whereSeparator: \Character.isNewline)
            .last == Substring(helperCommandSuccessMarker)
    }

    nonisolated static func isSecureInstalledHelper(_ file: ChargeLimitHelperFileSecurity) -> Bool {
        guard file.isRegularFile, file.ownerID == 0 else {
            return false
        }

        let permissions = file.permissions & 0o7777
        let hasOwnerOrGroupSetID = permissions & 0o6000 != 0
        let isWritableByGroupOrWorld = permissions & 0o0022 != 0
        let isExecutable = permissions & 0o0111 != 0
        return !hasOwnerOrGroupSetID && !isWritableByGroupOrWorld && isExecutable
    }

    nonisolated static func helperMatchesTrustedSource(
        installedPath: String,
        trustedSourcePath: String
    ) -> Bool {
        FileManager.default.contentsEqual(
            atPath: installedPath,
            andPath: trustedSourcePath
        )
    }

    nonisolated static func appleScriptErrorOutput(message: String) -> String {
        "error: \(message)"
    }

    nonisolated private static func shellEscapedPath(_ path: String) -> String {
        path.replacingOccurrences(of: "'", with: "'\"'\"'")
    }

    nonisolated private static func appleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

private struct HelperStatus: Decodable {
    let supported: Bool
    let chargingDisabled: Bool
}
