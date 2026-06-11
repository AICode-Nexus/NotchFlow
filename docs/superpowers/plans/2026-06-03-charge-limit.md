# 充电限制功能 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 NotchFlow 中实现电池充电限制功能，通过 SMC 控制在电量达到 8 时停止充电，低于 75% 时恢复。

**Architecture:** 独立的 SMC Helper CLI 处理特权 SMC 写入操作，主 App 通过 AppleScript 提权调用。ChargeLimitService 监听电量变化并执行迟滞逻辑。UI 在设置页和 Notch 面板同时提供控制入口。

**Tech Stack:** Swift 6, IOKit (AppleSMC), SwiftUI, NSAppleScript, notify API (Darwin)

---

## File Structure

**新增文件：**
- `Sources/NotchFlow/SMCHelper/SMCParamStruct.h` — AppleSMC.kext C 结构体定义
- `Sources/NotchFlow/SMCHelper/module.modulemapper/SMCComm.swift` — SMC IOKit 通信层
- `Sources/NotchFlow/SMCHelper/SMCPower.swift` — 充电控制 SMC key 操作
- `Sources/NotchFlow/SMCHelper/main.swift` — CLI 入口，解析命令并执行
- `Sources/NotchFlow/Services/ChargeLimitService.swift` — 充电限制核心 Service

**修改文件：**
- `Package.swift` — 新增 SMCHelper executable target
- `Sources/NotchFlow/Models/AppSettings.swift` — 新增 chargeLimitEnabled 设置
- `Sources/NotchFlow/NotchFlowAppModel.swift` — 注册 ChargeLimitService
- `Sources/NotchFlow/UI/SettingsView.swift` — 电量 tab 新增充电限制 Section
- `Sources/NotchFlow/UI/NotchPanelView.swift` — 电池模块新增快捷开关

---

### Task 1: SMC C Module

**Files:**
- Create: `Sources/NotchFlow/SMCHelper/SMCParamStruct.h`
- Create: `Sources/NotchFlow/SMCHelper/include/module.modulemap`

- [ ] **Step 1: 创建 SMCParamStruct.h**

```c
#ifndef SMCParamStruct_h
#define SMCParamStruct_h

#include <stdint.h>

enum {
    kSMCSuccess     = 0,
    kSMCError       = 1
};

enum {
    kSMCUserClientOpen  = 0,
    kSMCUserClientClose = 1,
    kSMCHandleYPCEvent  = 2,
    kSMCReadKey         = 5,
    kSMCWriteKey        = 6,
    kSMCGetKeyInfo      = 9
};

typedef struct {
    unsigned char major;
    unsigned char minor;
    unsigned char build;
    unsigned char reserved;
    unsigned short release;
} SMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCPLimitData;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t  dataAttributes;
} SMCKeyInfoData;

typedef struct {
    uint32_t       key;
    SMCVersion     vers;
    SMCPLimitData  pLimitData;
    SMCKeyInfoData keyInfo;
    uint8_t        result;
    uint8_t        status;
    uint8_t        data8;
    uint32_t       data32;
    uint8_t        bytes[32];
} SMCParamStruct;

#endif
```

- [ ] **Step 2: 创建 module.modulemap**

```
module CSMCParamStruct {
    header "../SMCParamStruct.h"
    export *
}
```

- [ ] **Step 3: Commit**

```bash
git add Sources/NotchFlow/SMCHelper/SMCParamStruct.h Sources/NotchFlow/SMCHelper/include/module.modulemap
git commit -m "feat(charge-limit): add SMC C struct definitions"
```

---

### Task 2: SMC Communication Layer

**Files:**
- Create: `Sources/NotchFlow/SMCHelper/SMCComm.swift`

- [ ] **Step 1: 创建 SMCComm.swift**

```swift
import Foundation
import IOKit

private func fourCharCode(_ c0: Character, _ c1: Character, _ c2: Character, _ c3: Character) -> UInt32 {
    let b0 = UInt32(c0.asciiValue!) << 24
    let b1 = UInt32(c1.asciiValue!) << 16
    let b2 = UInt32(c2.asciiValue!) << 8
    let b3 = UInt32(c3.asciiValue!)
    return b0 | b1 | b2 | b3
}

struct SMCKeyInfo {
    let key: UInt32
    let dataSize: UInt32
    let dataType: UInt32
    let dataAttributes: UInt8
}

enum SMCComm {
    private static var connect: io_connect_t = 0

    static func open() -> Bool {
        let service = IOServiceGetMatchingService(
            kIOMasterPortDefault,
            IOServiceMatching("AppleSMC")
        )
        guard service != 0 else { return false }

        var conn: io_connect_t = 0
        let kr = IOServiceOpen(service, mach_task_self_, 1, &conn)
        IOObjectRelease(service)
        guard kr == kIOReturnSuccess, conn != 0 else { return false }

        connect = conn
        var input = SMCParamStruct()
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        input.data8 = UInt8(kSMCUserClientOpen)
        IOConnectCallStructMethod(connect, UInt32(kSMCHandleYPCEvent), &input, MemoryLayout<SMCParamStruct>.stride, &output, &outputSize)
        return true
    }

    static func close() {
        var input = SMCParamStruct()
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        input.data8 = UInt8(kSMCUserClientClose)
        IOConnectCallStructMethod(connect, UInt32(kSMCHandleYPCEvent), &input, MemoryLayout<SMCParamStruct>.stride, &output, &outputSize)
        IOServiceClose(connect)
        connect = 0
    }

    static func getKeyInfo(key: UInt32) -> SMCKeyInfoData? {
        var input = SMCParamStruct()
        input.key = key
        input.data8 = UInt8(kSMCGetKeyInfo)

        guard let output = callSMC(&input) else { return nil }
        return output.keyInfo
    }

    static func readKey(key: UInt32, dataSize: UInt32) -> [UInt8]? {
        var input = SMCParamStruct()
        input.key = key
        input.keyInfo.dataSize = dataSize
        input.data8 = UInt8(kSMCReadKey)

        guard let output = callSMC(&input) else { return nil }
        return withUnsafePointer(to: output.bytes) { ptr in
            let raw = UnsafeRawPointer(ptr)
            return (0..<Int(dataSize)).map { raw.load(fromByteOffset: $0, as: UInt8.self) }
        }
    }

    static func writeKey(key: UInt32, bytes: [UInt8]) -> Bool {
        var input = SMCParamStruct()
        input.key = key
        input.keyInfo.dataSize = UInt32(bytes.count)
        input.data8 = UInt8(kSMCWriteKey)
        withUnsafeMutablePointer(to: &input.bytes) { ptr in
            let raw = UnsafeMutableRawPointer(ptr)
            for i in 0..<bytes.count {
                raw.storeBytes(of: bytes[i], toByteOffset: i, as: UInt8.self)
            }
        }

        let result = callSMC(&input)
        guard result != nil else { return false }

        let readBack = readKey(key: key, dataSize: UInt32(bytes.count))
        return readBack == bytes
    }

    static func keyExists(key: UInt32, expectedSize: UInt32, expectedType: UInt32) -> Bool {
        guard let info = getKeyInfo(key: key) else { return false }
        return info.dataSize == expectedSize && info.dataType == expectedType
    }

    private static func callSMC(_ input: inout SMCParamStruct) -> SMCParamStruct? {
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride

        let kr = IOConnectCallStructMethod(
            connect,
            UInt32(kSMCHandleYPCEvent),
            &input,
            MemoryLayout<SMCParamStruct>.stride,
            &output,
            &outputSize
        )
        guard kr == kIOReturnSuccess, output.result == UInt8(kSMCSuccess) else {
            return nil
        }
        return output
    }

    static func makeKey(_ c0: Character, _ c1: Character, _ c2: Character, _ c3: Character) -> UInt32 {
        fourCharCode(c0, c1, c2, c3)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/NotchFlow/SMCHelper/SMCComm.swift
git commit -m "feat(charge-limit): add SMC IOKit communication layer"
```

---

### Task 3: SMC Power Control

**Files:**
- Create: `Sources/NotchFlow/SMCHelper/SMCPower.swift`

- [ ] **Step 1: 创建 SMCPower.swift**

```swift
import Foundation

enum SMCPower {
    private struct KeyControl {
        let key: UInt32
        let dataSize: UInt32
        let dataType: UInt32
        let onBytes: [UInt8]
        let offBytes: [UInt8]
    }

    private static let typeUI32 = SMCComm.makeKey("u", "i", "3", "2")
    private static let typeHex = SMCComm.makeKey("h", "e", "x", "_")

    private static let chargeKeys: [KeyControl] = [
        KeyControl(
            key: SMCComm.makeKey("C", "H", "T", "E"),
            dataSize: 4,
            dataType: typeUI32,
            onBytes: [0x00, 0x00, 0x00, 0x00],
            offBytes: [0x01, 0x00, 0x00, 0x00]
        ),
        KeyControl(
            key: SMCComm.makeKey("C", "H", "0", "C"),
            dataSize: 1,
            dataType: typeHex,
            onBytes: [0x00],
            offBytes: [0x01]
        ),
    ]

    private static var activeChargeKeyIndex: Int?

    static func supported() -> Bool {
        for (index, kc) in chargeKeys.enumerated() {
            if SMCComm.keyExists(key: kc.key, expectedSize: kc.dataSize, expectedType: kc.dataType) {
                activeChargeKeyIndex = index
                return true
            }
        }
        return false
    }

    static func enableCharging() -> Bool {
        guard let index = activeChargeKeyIndex else { return false }
        let kc = chargeKeys[index]
        return SMCComm.writeKey(key: kc.key, bytes: kc.onBytes)
    }

    static func disableCharging() -> Bool {
        guard let index = activeChargeKeyIndex else { return false }
        let kc = chargeKeys[index]
        return SMCComm.writeKey(key: kc.key, bytes: kc.offBytes)
    }

    static func isChargingDisabled() -> Bool {
        guard let index = activeChargeKeyIndex else { return false }
        let kc = chargeKeys[index]
        guard let value = SMCComm.readKey(key: kc.key, dataSize: kc.dataSize) else { return false }
        return value != kc.onBytes
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/NotchFlow/SMCHelper/SMCPower.swift
git commit -m "feat(charge-limit): add SMC power control (charge enable/disable)"
```

---

### Task 4: SMC Helper CLI Entry Point

**Files:**
- Create: `Sources/NotchFlow/SMCHelper/main.swift`

- [ ] **Step 1: 创建 main.swift**

```swift
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
        return success ? .success : .smcError

    case "disable-charging":
        let success = SMCPower.disableCharging()
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
```

- [ ] **Step 2: Commit**

```bash
git add Sources/NotchFlow/SMCHelper/main.swift
git commit -m "feat(charge-limit): add SMC helper CLI entry point"
```

---

### Task 5: Package.swift — 新增 Helper Target

**Files:**
- Modify: `Package.swift`

- [ ] **Step 1: 修改 Package.swift 添加 SMCHelper target**

在 `targets` 数组中，在现有 `executableTarget` 之后新增：

```swift
.systemLibrary(
    name: "CSMCParamStruct",
    path: "Sources/NotchFlow/SMCHelper/include"
),
.executableTarget(
    name: "notchflow-smc-helper",
    dependencies: ["CSMCParamStruct"],
    path: "Sources/NotchFlow/SMCHelper",
    exclude: ["include", "SMCParamStruct.h"],
    linkerSettings: [
        .linkedFramework("IOKit"),
    ]
),
```

- [ ] **Step 2: 验证 build**

Run: `cd /Users/wangyang/Mac插件/NotchFlow && swift build --target notchflow-smc-helper 2>&1 | tail -5`
Expected: Build succeeded 或有明确可修复的错误

- [ ] **Step 3: Commit**

```bash
git add Package.swift
git commit -m "feat(charge-limit): add notchflow-smc-helper target to Package.swift"
```

---

### Task 6: AppSettings — 新增充电限制设置

**Files:**
- Modify: `Sources/NotchFlow/Models/AppSettings.swift`

- [ ] **Step 1: 在 Keys enum 中添加**

在 `Keys` enum 最后一行 `static let panelTextSizePreset` 之后添加：

```swift
static let chargeLimitEnabled = "ChargeLimitEnabled"
```

- [ ] **Step 2: 添加 Published 属性**

在 `@Published var panelTextSizePreset` 之后添加：

```swift
@Published var chargeLimitEnabled: Bool {
    didSet {
        UserDefaults.standard.set(chargeLimitEnabled, forKey: Keys.chargeLimitEnabled)
    }
}

let chargeLimitMax: Int = 80
let chargeLimitMin: Int = 75
```

- [ ] **Step 3: 在 init 中添加默认值和读取**

在 `init` 方法中 `panelTextSizePreset` 相关初始化之后添加：

```swift
if defaults.object(forKey: Keys.chargeLimitEnabled) == nil {
    defaults.set(false, forKey: Keys.chargeLimitEnabled)
}
```

在 `init` 最后一行赋值之后添加：

```swift
chargeLimitEnabled = defaults.bool(forKey: Keys.chargeLimitEnabled)
```

- [ ] **Step 4: Commit**

```bash
git add Sources/NotchFlow/Models/AppSettings.swift
git commit -m "feat(charge-limit): add chargeLimitEnabled setting"
```

---

### Task 7: ChargeLimitService

**Files:**
- Create: `Sources/NotchFlow/Services/ChargeLimitService.swift`

- [ ] **Step 1: 创建 ChargeLimitService.swift**

```swift
import Foundation
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

    private let settings: AppSettings
    private var notifyToken: Int32 = 0
    private var isRegistered = false

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        guard settings.chargeLimitEnabled else {
            state = .idle
            return
        }

        guard helperInstalled() else {
            state = .helperNotInstalled
            return
        }

        registerPercentNotification()
    }

    func stop() {
        unregisterPercentNotification()
        if state == .chargingDisabled {
            restoreCharging()
        }
        state = .idle
    }

    func toggle() {
        settings.chargeLimitEnabled.toggle()
        if settings.chargeLimitEnabled {
            start()
        } else {
            stop()
        }
    }

    func installHelper() {
        let helperPath = self.helperPath()
        guard !FileManager.default.fileExists(atPath: "/usr/local/bin/notchflow-smc-helper") else {
            if state == .helperNotInstalled {
                start()
            }
            return
        }

        let script = """
        do shell script "cp '\(helperPath)' /usr/local/bin/notchflow-smc-helper && chmod 755 /usr/local/bin/notchflow-smc-helper" with administrator privileges
        """
        runAppleScript(script)

        if helperInstalled() {
            start()
        }
    }

    func checkStatus() {
        guard helperInstalled() else {
            state = .helperNotInstalled
            return
        }

        let output = runHelperCommand("status")
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if json["supported"] as? Bool == false {
            state = .unsupported
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
        var token: Int32 = 0
        let status = notify_register_check("com.apple.system.powersources.percent", &token)
        guard status == NOTIFY_STATUS_OK else { return }

        var packedBits: UInt64 = 0
        notify_get_state(token, &packedBits)
        notify_cancel(token)

        let validBit: UInt64 = 1 << 19
        guard (packedBits & validBit) != 0 else { return }

        let percent = Int(min(packedBits & 0xFF, 100))
        currentPercent = percent

        let maxCharge = settings.chargeLimitMax
        let minCharge = settings.chargeLimitMin

        if percent >= maxCharge && state != .chargingDisabled {
            disableCharging()
        } else if percent < minCharge && state == .chargingDisabled {
            enableCharging()
        } else if state != .chargingDisabled {
            state = .monitoring
        }
    }

    private func disableCharging() {
        let output = runHelperCommand("disable-charging")
        if output.isEmpty || !output.contains("error") {
            state = .chargingDisabled
        } else {
            state = .error("禁止充电失败")
        }
    }

    private func enableCharging() {
        let output = runHelperCommand("enable-charging")
        if output.isEmpty || !output.contains("error") {
            state = .monitoring
        } else {
            state = .error("恢复充电失败")
        }
    }

    private func restoreCharging() {
        _ = runHelperCommand("enable-charging")
    }

    private func runHelperCommand(_ command: String) -> String {
        let path = installedHelperPath()
        let script = "do shell script \"\(path) \(command)\" with administrator privileges"
        return runAppleScript(script)
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
        "/usr/local/bin/notchflow-smc-helper"
    }

    private func helperPath() -> String {
        if let bundlePath = Bundle.main.path(forResource: "notchflow-smc-helper", ofType: nil) {
            return bundlePath
        }
        let buildPath = Bundle.main.bundlePath
            .replacingOccurrences(of: "/NotchFlow.app/Contents/MacOS/NotchFlow", with: "")
            + "/.build/debug/notchflow-smc-helper"
        return buildPath
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/NotchFlow/Services/ChargeLimitService.swift
git commit -m "feat(charge-limit): add ChargeLimitService with hysteresis logic"
```

---

### Task 8: 注册 ChargeLimitService 到 AppModel

**Files:**
- Modify: `Sources/NotchFlow/NotchFlowAppModel.swift`

- [ ] **Step 1: 添加 chargeLimit 属性声明**

在 `let launchAtLogin: LaunchAtLoginManager` 之后添加：

```swift
let chargeLimit: ChargeLimitService
```

- [ ] **Step 2: 在 init  `launchAtLogin = LaunchAtLoginManager()` 之后添加：

```swift
chargeLimit = ChargeLimitService(settings: settings)
```

- [ ] **Step 3: 在 start() 中启动**

在 `hotKeyManager.register()` 之后添加：

```swift
chargeLimit.start()
```

- [ ] **Step 4: 在 stop() 中停止**

在 `hotKeyManager.unregister()` 之后添加：

```swift
chargeLimit.stop()
```

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchFlow/NotchFlowAppModel.swift
git commit -m "feat(charge-limit): register ChargeLimitService in AppModel"
```

---

### Task 9: Settings UI — 充电限制 Section

**Files:**
- Modify: `Sources/NotchFlow/UI/SettingsView.swift`

- [ ] **Step 1: 在 batterySections 末尾添加充电限制 Section**

在 `batterySections` 的 `@ViewBuilder` 中，现有 `Section("设备电量") {...}` 之后添加：

```swift
Section("充电限制") {
    Toggle(
        "启用充电限制",
        isOn: Binding(
            get: { model.chargeLimit.state != .idle || model.settings.chargeLimitEnabled },
            set: { enabled in
                if enabled {
                    model.settings.chargeLimitEnabled = true
                    model.chargeLimit.start()
                } else {
                    model.chargeLimit.stop()
                }
            }
        )
    )

    LabeledContent("状态", value: model.chargeLimit.state.displayText)

    if model.chargeLimit.state == .helperNotInstalled {
        Button("安装 Helper") {
            model.chargeLimit.installHelper()
        }
    }

    if model.settings.chargeLimitEnabled {
        LabeledContent("当前电量", value: "\(model.chargeLimit.currentPercent)%")
        LabeledContent("充电上限", value: "\(model.settings.chargeLimitMax)%")
        LabeledContent("恢复阈值", value: "\(model.settings.chargeLimitMin)%")
    }

    Tex\(model.settings.chargeLimitMax)% 时自动停止充电，低于 \(model.settings.chargeLimitMin)% 时恢复。保护电池寿命。")
        .font(.footnote)
        .foregroundStyle(.secondary)
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/NotchFlow/UI/SettingsView.swift
git commit -m "feat(charge-limit): add charge limit section to settings UI"
```

---

### Task 10: Panel UI — 电池模块快捷开关

**Files:**
- Modify: `Sources/NotchFlow/UI/NotchPanelView.swift`

- [ ] **Step 1: 添加 chargeLimit ObservedObject**

在 `NotchPanelView` 结构体的 `@ObservedObject` 属性列表中，在 `@ObservedObject var localAppSearch: LocalAppSearchService` 之后添加：

```swift
@ObservedObject var chargeLimit: ChargeLimitService
```

- [ ] **Step 2: 在 batterySection 的 moduleHeader trailing 中添加充电限制指示器**

在 `batterySection` 的 `moduleHeader` 尾部 closure 中，在现有的 if-else 链最前面（`if battery.isLoading` 之前）插入：

```swift
if settings.chargeLimitEnabled && chargeLimit.state == .chargingDisabled {
    Image(systemName: "bolt.slash.fill")
        .font(panelFont(11, weight: .semibold))
        .foregroundStyle(.orange)
} else if settings.chargeLimitEnabled && chargeLimit.state == .monitoring {
    Image(systemName: "bolt.shield.fill")
        .font(panelFont(11, weight: .semibold))
        .foregroundStyle(style.chargingAccent)
} else
```

注意：最后的 `else` 连接到原来的 `if battery.isLoading` 使得原有逻辑作为 else 分支。

- [ ] **Step 3: 在 batteryFooter 前添加快捷切换按钮**

在 `batterySection` 中，`batteryFooter` 之前添加一个可点击的充电限制行：

```swift
if settings.chargeLimitEnabled || chargeLimit.state == .chargingDisabled {
    Button {
        chargeLimit.toggle()
    } label: {
        HStack(spacing: 5) {
            Image(systemName: chargeLimit.state == .chargingDisabled ? "bolt.slash.fill" : "bolt.shield.fill")
                .font(panelFont(10, weight: .semibold))
                .foregroundStyle(chargeLimit.state == .chargingDisabled ? .orange : style.chargingAccent)

            Text(chargeLimit.state == .chargingDisabled ? "充电已暂停" : "充电保护中")
                .font(panelFont(11, weight: .medium))
                .foregroundStyle(moduleSecondaryTextColor)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(height: 20)
        .background(moduleTileBackgroundColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
    .buttonStyle(.plain)
}
```

- [ ] **Step 4: 更新 NotchPanelController 和 NotchPanelView 初始化以传递 chargeLimit**

在 `NotchPanelController.swift` 中添加 `chargeLimit` 属性：

```swift
private let chargeLimit: ChargeLimitService
```

在 `init` 参数列表最后一个参数 `localAppSearch: LocalAppSearchService` 之后添加：

```swift
chargeLimit: ChargeLimitService
```

在 `init` body 中 `self.localAppSearch = localAppSearch` 之后添加：

```swift
self.chargeLimit = chargeLimit
```

在 `createPanel()` 中 `NotchPanelView(...)` 的参数列表末尾（`localAppSearch: localAppSearch` 之后）添加：

```swift
chargeLimit: chargeLimit
```

- [ ] **Step 5: 更新 NotchFlowAppModel 中 panelController 初始化**

在 `NotchFlowAppModel.init` 中，`panelController = NotchPanelController(...)` 的参数列表末尾添加：

```swift
chargeLimit: chargeLimit
```

注意：`chargeLimit` 的初始化必须在 `panelController` 之前。确认 init 中 `chargeLimit = ChargeLimitService(settings: settings)` 在 `panelController = NotchPanelController(...)` 之前。

- [ ] **Step 6: Commit**

```bash
git add Sources/NotchFlow/UI/NotchPanelView.swift Sources/NotchFlow/Services/NotchPanelController.swift Sources/NotchFlow/NotchFlowAppModel.swift
git commit -m "feat(charge-limit): add charge limit toggle to panel battery module"
```

---

### Task 11: Build 验证和修复

**Files:**
- 可能需要修改以上任何文件来修复编译错误

- [ ] **Step 1: 构建主 App target**

Run: `cd /Users/wangyang/Mac插件/NotchFlow && swift build 2>&1 | tail -20`
Expected: Build succeeded

- [ ] **Step 2: 构建 helper target**

Run: `cd /Users/wangyang/Mac插件/NotchFlow && swift build --target notchflow-smc-helper 2>&1 | tail -20`
Expected: Build succeeded

- [ ] **Step 3: 修复编译错误（如有）**

根据错误信息修复类型不匹配、缺少参数、import 错误等问题。

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "fix(charge-limit): resolve build errors"
```

---

### Task 12: 测试 Helper CLI

- [ ] **Step 1: 运行 helper 的 status 命令验证基本功能**

Run: `cd /Users/wangyang/Mac插件/NotchFlow && sudo .build/debug/notchflow-smc-helper status`
Expected: 输出类似 `{"supported":true,"chargingDisabled":false}` 或 `{"supported":false,"chargingDisabled":false}`

- [ ] **Step 2: 如果 supported=true，测试 disable/enable 循环**

Run:
```bash
sudo .build/debug/notchflow-smc-helper disable-charging && echo "disabled OK"
sudo .build/debug/notchflow-smc-helper status
sudo .build/debug/notchflow-smc-helper enable-charging && echo "enabled OK"
sudo .build/debug/notchflow-smc-helper status
```
Expected: disable 后 chargingDisabled=true，enable 后 chargingDisabled=false
