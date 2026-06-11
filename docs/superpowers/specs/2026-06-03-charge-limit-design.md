# 充电限制功能设计

## 概述

在 NotchFlow 中实现电池充电限制功能，当电量达到 80% 时自动停止充电，低于 75% 时恢复充电，保护电池寿命。

## 架构

```
NotchFlow App (用户态)
    ├── ChargeLimitService (监听电量 + 决策逻辑)
    ├── Settings UI (电量 tab 内详细配置)
    └── Panel UI (快捷开关)
            │
            │  通过 AppleScript "do shell script ... with administrator privileges"
            ▼
notchflow-smc-helper (独立 CLI, 需要 root)
    ├── enable-charging
    ├── disable-charging
    └── status
```

## 组件设计

### 1. SMC Helper CLI

独立的 Swift 命令行可执行文件，内嵌从 Battery-Toolkit 移植的 SMC 通信代码。

**位置：** App Bundle 的 `Contents/Resources/notchflow-smc-helper`

**命令：**
- `notchflow-smc-helper enable-charging` — 恢复充电
- `notchflow-smc-helper disable-charging` — 禁止充电
- `notchflow-smc-helper status` — 输出 JSON：`{"chargingDisabled": bool, "supported": bool}`

**退出码：** 0 成功，1 不支持，2 SMC 错误

**安全措施：**
- 仅操作已知的充电控制 SMC key（CHTE/CH0C）
- 写入后读回验证
- 运行时探测硬件支持的 key 变体

**移植的核心代码（来自 Battery-Toolkit）：**
- `SMCParamStruct.h` — C 结构体定义（AppleSMC.kext 协议）
- `SMCComm.swift` — IOKit SMC 连接、读写
- `SMCComm+Power.swift` — 充电控制 key 定义和操作

### 2. ChargeLimitService

`@MainActor ObservableObject`，遵循项目现有 Service 模式。

**职责：**
- 通过 `notify_register_dispatch` 监听 `com.apple.system.powersources.percent`
- 迟滞逻辑：电量 >= 80% 时禁止充电，< 75% 时恢复充电
- 通过 AppleScript 提权执行 helper CLI
- 跟踪状态：helper 是否已安装、充电是否被限制、功能是否激活
- 功能关闭或 app 退出时恢复充电

**状态枚举：**
- `idle` — 功能未启用
- `monitoring` — 正在监听，当前电量在阈值范围内
- `chargingDisabled` — 已禁止充电（电量 >= 80%）
- `helperNotInstalled` — helper 未安装
- `unsupported` — 硬件不支持
- `error(String)` — 错误信息

**提权方式：**
```swift
NSAppleScript("do shell script \"\(helperPath) disable-charging\" with administrator privileges")
```

### 3. Settings UI

在现有 `SettingsView` 的 `batterySections` 中新增 Section "充电限制"：

- Toggle "启用充电限制"
- LabeledContent 显示当前状态
- Button "安装 Helper"（仅 helper 未安装时显示）
- 说明文字

### 4. Panel UI

在 Notch 面板电池区域添加充电限制快捷开关：
- 图标按钮，点击切换启用/禁用
- 已启用且充电被暂停时，电池图标显示限制标记

### 5. AppSettings 新增

```swift
// Keys
static let chargeLimitEnabled = "ChargeLimitEnabled"

// Properties
@Published var chargeLimitEnabled: Bool  // 默认 false

// 内部常量（不暴露给用户）
let chargeLimitMax: Int = 80
let chargeLimitMin: Int = 75
```

## 数据流

1. 用户在设置页开启充电限制 → `chargeLimitEnabled = true`
2. `ChargeLimitService.start()` 注册电量通知
3. 电量变化时触发回调 → 检查是否越过阈值
4. 需要禁止/恢复充电时 → AppleScript 提权执行 helper
5. helper 写入 SMC key → 充电控制器响应
6. Service 更新 `@Published` 状态 → UI 响应

## 错误处理

- helper 未安装：显示安装按钮，禁用功能
- 用户取消密码输入：静默失败，保持当前状态
- SMC 不支持（非 Apple Silicon 或旧机型）：显示"不支持"提示
- App 退出时：如果充电处于禁用状态，尝试恢复充电

## 文件清单

新增文件：
- `Sources/NotchFlow/Services/ChargeLimitService.swift`
- `Sources/NotchFlow/SMCHelper/main.swift`
- `Sources/NotchFlow/SMCHelper/SMCComm.swift`
- `Sources/NotchFlow/SMCHelper/SMCComm+Power.swift`
- `Sources/NotchFlow/SMCHelper/SMCParamStruct.h`
- `Sources/NotchFlow/SMCHelper/module.modulemap`

修改文件：
- `Sources/NotchFlow/Models/AppSettings.swift` — 新增 chargeLimitEnabled
- `Sources/NotchFlow/NotchFlowAppModel.swift` — 注册 ChargeLimitService
- `Sources/NotchFlow/UI/SettingsView.swift` — batterySections 新增充电限制 UI
- `Sources/NotchFlow/UI/NotchPanelView.swift` — 电池区域快捷开关
- `Package.swift` — 新增 helper target（如果用 SPM 构建）
