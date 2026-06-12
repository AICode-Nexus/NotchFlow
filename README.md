# NotchFlow

Mac 灵动岛插件。

macOS 刘海应用调研与第一版原型目录。

## 目标

研究现有 macOS 刘海区 / 灵动岛风格应用的实现方式，再把可复用的模式整理成一个原生小原型。

## 当前重点

- 竞品功能梳理
- 窗口与刘海定位策略
- 交互方式：悬停、展开、活动卡片、快捷动作
- 权限与后台常驻约束

## 当前原型能力

- 菜单栏常驻入口
- 顶部中央刘海面板
- 悬停展开、点击固定、自动收起
- 全局快捷键：`Option + Command + Space`
- 正在播放卡片
- 播放 / 暂停、上一首 / 下一首
- 设置窗口
- 非刘海屏降级定位
- 多屏基础重定位

## 运行方式

### 正式工程

直接打开：

- `NotchFlow.xcodeproj`

命令行构建：

```bash
xcodebuild -project NotchFlow.xcodeproj -scheme NotchFlow -configuration Debug build
```

构建产物默认在：

- `DerivedData/Build/Products/Debug/NotchFlow.app`

### 轻量原型运行

保留 `Swift Package` 入口，便于快速调试：

在项目根目录执行：

```bash
swift run
```

## 工程生成

Xcode 工程由脚本生成，后续增删源文件后可以重新执行：

```bash
ruby scripts/generate_xcodeproj.rb
```

## 当前已知限制

- “开机自启”在 `swift run` 这种开发模式下可能不可用，真正打包成 App Bundle 后更合适
- “正在播放”优先读取系统媒体状态，失败时降级到 Music App
- 现在的多屏策略是优先跟随当前鼠标所在屏幕，后面还可以继续打磨

## 调研文件

- `research/competitors.md`
- `research/feature-list.md`
- `research/v1-scope.md`

## 接下来要回答的问题

- 第一版原型是偏媒体工具、系统工具，还是偏开发工作流？
- 是先只面向刘海屏 Mac，还是一开始就兼容非刘海屏？
- 窗口的最佳触发方式是什么：悬停展开、点击展开，还是快捷键唤起？
