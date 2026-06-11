# 竞品调研笔记

## boring.notch

Repo: https://github.com/TheBoredTeam/boring.notch

特色功能：

- 音乐控制和媒体快捷面板
- 文件拖放暂存区，适合接住临时拖拽和类似 AirDrop 的动作
- 提醒事项、日历一类的小组件
- 可自定义刘海外观和尺寸
- `boringHUD`，用于替代或增强系统默认的音量、亮度浮层

结论：

这是目前最值得参考的开源“用户型刘海工具应用”，不只是一个演示项目。

## Atoll

Repo: https://github.com/Ebullioscopic/Atoll

特色功能：

- 受 iPhone 灵动岛启发的活动卡片
- 天气、日历、系统状态等桌面小组件
- 任务和计时器流程
- 带动效的上下文弹出层
- 不只盯着一个刘海面板，而是更完整的产品形态

结论：

Atoll 适合拿来研究功能广度和产品定位，它证明了刘海区可以被做成一个通用活动层。

## DynamicNotchKit

Repo: https://github.com/MrKai77/DynamicNotchKit

特色功能：

- 面向开发者的 Swift Package，而不是独立成品 App
- 支持把自定义 SwiftUI 视图放进刘海容器
- 内置通知展示和快捷呈现模式
- 同时处理刘海屏和非刘海屏的样式降级
- 可复用的屏幕和定位工具

结论：

这是研究架构和几何计算最有价值的参考，更像工具包而不是产品本身。

## Dynamic-Island-Sketchybar

Repo: https://github.com/crissNb/Dynamic-Island-Sketchybar

特色功能：

- 基于 `SketchyBar`、shell 脚本和辅助代码实现
- 会根据事件动态改变宽度
- 电量、Wi-Fi、音量、亮度、音乐等快捷状态模块
- 适合效率党和自动化爱好者的轻量方案

结论：

它很适合快速实验和脚本玩法，但不太适合作为正式原生产品的底座。

## MioIsland

Repo: https://github.com/MioMioOS/MioIsland

特色功能：

- 面向 AI 编程工作流的刘海界面
- 在刘海区展示会话切换、审批状态、任务状态
- 助手头像和实时状态反馈
- 终端与应用跳转钩子
- 偏插件化的扩展方向

结论：

这是几个项目里产品方向最鲜明的一个，它证明刘海区不一定只能做系统工具，也可以做高频工作流入口。

## 这些项目的共通点

- 菜单栏应用或后台常驻应用壳
- 用 AppKit 管窗口，用 SwiftUI 组织内容
- 把无边框面板钉在顶部中央、靠近刘海
- 很重视动效和短时状态展示
- 都需要处理大量按屏幕区分的几何逻辑

## NotchFlow 需要继续回答的问题

- 我们是要做像 `boring.notch` 那样的通用工具集合，还是像 `MioIsland` 那样聚焦某个工作流？
- 文件拖放 shelf 值不值得进入第一版？
- 活动卡片是不是要作为主交互隐喻？
