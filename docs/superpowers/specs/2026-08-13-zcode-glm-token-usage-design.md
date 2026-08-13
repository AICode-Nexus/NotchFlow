# ZCode GLM Token 用量统计设计

## 背景

NotchFlow 当前从 Codex 与 Claude 的本地日志汇总 AI token 用量，并在刘海面板中展示当日用量最高的两个来源。用户主要通过 ZCode 使用 GLM，因此需要将 ZCode 中的 GLM token 作为独立来源纳入统计，并在刘海面板中用 GLM 替换 Claude 的位置。

本机验证表明，ZCode 将逐次模型调用的用量写入 `~/.zcode/cli/db/db.sqlite` 的 `model_usage` 表。该表包含稳定记录 ID、模型 ID、开始时间、输入/输出 token、缓存 token、推理 token 与 ZCode 已计算的总 token。相比 rollout JSONL，该数据库覆盖完整得多，适合作为唯一的 ZCode GLM 统计来源。

## 目标

- 新增独立 AI 用量来源 `GLM`。
- 从 ZCode 本地数据库统计所有模型 ID 以 `glm` 开头的调用，匹配时忽略大小写。
- 将 GLM 纳入今日、近 7 天、近 14 天和近 30 天等现有聚合结果。
- 保留 Claude 统计及其设置页状态，不改变 AI 总量的现有含义。
- 刘海面板固定展示 `Codex + GLM`，不再按当日用量动态选择前两个来源。
- 不读取对话正文、不访问网络，也不让 NotchFlow 删除 ZCode 数据库或 ZCode 会话。

## 非目标

- 不读取 ZCode Coding Plan 的远程额度、剩余额度或计费倍率。
- 不读取 CC-Switch 的代理日志或日汇总。
- 不从 Claude Code 日志中二次识别 GLM，以免与 ZCode 数据重复计算。
- 不统计 ZCode 中 Claude、GPT 或其他非 GLM 模型。
- 不把 ZCode 数据纳入 NotchFlow 的历史日志清理功能。

## 数据源与读取策略

### 数据库位置

默认路径为：

```text
~/.zcode/cli/db/db.sqlite
```

读取器允许测试注入其他数据库路径，但产品默认只使用上述路径。

### SQLite 连接

- 使用系统 `SQLite3`，以 `SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX` 打开数据库。
- 使用 SQLite 自身的只读事务/快照语义读取正在写入且可能启用 WAL 的数据库，不复制数据库文件。
- 查询前验证 `model_usage` 表及必需字段存在；字段缺失时将来源标记为“不支持”，而不是返回错误总量。
- 不执行建表、迁移、PRAGMA 写操作或任何其他修改。

### 查询口径

读取满足以下条件的 `model_usage` 行：

- `lower(model_id) LIKE 'glm%'`；
- `started_at >= 统计窗口起点`；
- `computed_total_tokens > 0`。

不按 `status` 排除记录。失败或取消的请求如果已经产生正 token，也属于实际处理量；当前本机此类记录为 0，但读取规则对未来数据保持正确。

每行映射为一个 `AITokenUsageEvent`：

- `sourceID`: `.glm`
- `timestamp`: `started_at`（Unix 毫秒）
- `stableID`: `zcode-glm:<model_usage.id>`
- `model`: `model_id`
- `inputTokens`: `input_tokens`
- `outputTokens`: `output_tokens`
- `reasoningOutputTokens`: `reasoning_tokens`
- `cacheReadInputTokens`: `cache_read_input_tokens`
- `cacheCreationInputTokens`: `cache_creation_input_tokens`
- `totalTokens`: `computed_total_tokens`

ZCode 当前的 `computed_total_tokens` 等于输入与输出之和，缓存读取属于输入 token 的子集。因此总量必须显式使用 `computed_total_tokens`，不能把缓存字段再次加到总量中。

数据库行以主键 `id` 唯一标识，不需要跨文件去重。查询结果按开始时间读取，但现有聚合器仍负责按本地自然日汇总。

## 组件设计

### 来源标识

向 `AITokenUsageSourceID` 增加 `.glm`，显示名称为 `GLM`。它参与现有来源状态、每日拆分、区间总量与设置页数据源列表。

### ZCode GLM 读取器

新增 `ZCodeGLMTokenUsageSourceReader`，实现现有 `AITokenUsageSourceReading` 协议。职责仅包括：

1. 检查数据库是否存在且可读；
2. 验证表结构；
3. 查询统计窗口内的 GLM 用量元数据；
4. 映射为统一事件与来源状态。

状态行为：

- 数据库不存在：`.missing`，提示“未找到 ZCode 本地用量数据库”。
- 数据库存在、结构兼容但没有 GLM 正 token：`.detected`。
- 成功读取至少一条：`.available`。
- SQLite 打开或查询失败：`.unreadable`。
- 必需表或字段缺失：`.unsupported`。

任一 GLM 读取失败都不得阻止 Codex、Claude 或其他来源完成刷新。

### 默认读取器

将 ZCode GLM 读取器加入 `AITokenUsageService.defaultReaders`。Claude 读取器继续原样工作，不把其内部模型为 GLM 的记录重新分类，以避免臆测其他工具来源；本次统计只认 ZCode 数据库。

### 刘海展示

刘海的来源条不再使用“今日用量最高的前两个来源”，而是固定按以下顺序构造：

1. Codex
2. GLM

即使某个来源当天为 0，也显示 `Codex 0` 或 `GLM 0`，让卡片位置稳定、含义明确。Claude 仍计入上方的“今日总 token”，并继续出现在设置页数据源列表中。

固定来源选择逻辑应下沉为可单元测试的纯数据方法，SwiftUI 视图只负责渲染结果。

### 设置页与文案

- 隐私说明改为“Codex、Claude、ZCode 等工具日志中的 usage/token 元数据”。
- 数据源区域展示 GLM 的检测状态。
- 存储管理仍只展示和清理现有 Codex/Claude 日志目录，不展示 ZCode 数据库大小。
- 清理确认文案继续明确只影响 Codex/Claude，避免用户误以为会清理 ZCode。

## 错误处理与兼容性

- 所有 SQLite 语句使用预编译参数，不拼接用户输入。
- token 值转换为非负 `Int`；溢出或非法值使该行被忽略，不让汇总崩溃。
- 数据库在查询期间繁忙、损坏或权限不足时返回可读状态消息，并保留其他来源结果。
- ZCode 更新导致 schema 不兼容时返回 `.unsupported`，不猜测新字段含义。
- 读取器不缓存 SQLite 连接；每次刷新打开、读取并关闭，避免长期持有 ZCode 文件与 WAL 快照。

## 隐私与安全

- SQL 只选择用量所需字段：ID、模型、时间和 token 数值。
- 不查询 `message`、`part`、`session`、`input_history` 等可能含正文的表。
- 不记录或展示数据库中的请求内容、工作区路径、账号、供应商凭据或错误正文。
- 数据处理完全在本机进行，不产生网络请求。

## 测试策略

遵循测试先行，先用临时 SQLite 数据库写出失败测试，再实现读取器。

读取器测试覆盖：

- 正确读取大小写不同的 GLM 模型并排除 Claude/GPT；
- 使用 `computed_total_tokens`，缓存字段不重复计入总量；
- Unix 毫秒时间正确进入今日、7 天、14 天和 30 天窗口；
- 正 token 的错误/取消记录仍被统计，0 token 被忽略；
- 数据库缺失、表缺失、字段缺失和不可读状态；
- 稳定 ID 使用数据库主键，不产生重复事件。

展示测试覆盖：

- 刘海来源始终按 `Codex、GLM` 排序；
- 当日无数据时仍返回两个 0 值来源；
- Claude 仍计入总量但不占用刘海来源条位置。

回归验证包括完整 `swift test`、Swift 6 Release 构建，以及用本机 ZCode 数据只读对账今日汇总。验证期间不打印对话正文。

## 成功标准

- 设置页可检测到 GLM 并显示 ZCode 本地用量状态。
- GLM 数值与同一时间窗口下 ZCode `model_usage` 表的 `computed_total_tokens` 汇总一致。
- 刘海稳定显示 Codex 与 GLM，不因 Claude 当日用量更高而改变位置。
- 现有 Codex、Claude、时间范围切换及存储管理测试全部继续通过。
- NotchFlow 对 ZCode 数据库保持严格只读，历史清理不会触碰 `~/.zcode`。
