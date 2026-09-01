# Peeker v2.1 增量产品需求文档

> 文档状态：已确认，可用于 v2.1.0 设计、开发和验收
>
> 目标版本：v2.1.0
>
> 当前代码状态：仓库已实现 v2.1.0；本文记录该版本相对 v2.0.2 的增量契约
>
> 最低系统：macOS 26
>
> 继承基线：[Peeker v1 PRD](../v1/PRD.md)

本文档只描述 v2 相对 v1 的新增、修改和删除。未被本文覆盖的 v1 规则继续有效。发生冲突时，优先级如下：

1. 本文档；
2. `docs/functions/` 下的 v2 现行模块文档；
3. `docs/v1/PRD.md`。

五张内置卡的完整行为见 [Timer](../functions/timer.md)、[Pusher](../functions/pusher.md)、[Scheduler](../functions/scheduler.md)、[Agentor](../functions/agentor.md) 和 [Targetor](../functions/targetor.md)。Agentor 自 v2.0.2 已实现；Timer 临时任务与 Targetor 是 v2.1.0 增量。

## 1. 摘要

v2 将 Peeker 从“始终显示摘要的双功能卡岛”扩展为可静息的本地效率入口。v2.1.0 在 v2.0.2 基础上形成五张内置功能卡：

- 无需持续展示信息时，岛完全隐藏黑色表面，只保留顶部透明热区；
- Timer 与 Agentor 可按实时状态提供 Compact，其他卡平时 Resting；
- 功能卡通过统一、静音、FIFO 的岛内提示队列发布消息；
- Scheduler 提供本地周日历、重复规则、ICS 导入和日程提醒；
- Agentor 观察本机五种 Coding Agent 的顶层执行状态；
- Timer 增加默认关闭、可跨业务日累计的临时计时任务；
- Targetor 用日、周、月周期打卡管理长期主线目标；
- `peeker` CLI 由已运行 App 统一执行业务操作，并提供完整分级帮助。

Peeker 仍是本地优先、无账号、无遥测的原生 macOS App。CLI 不是第二套业务实现，也不拥有数据库。

## 2. 目标与非目标

### 2.1 目标

1. 无活跃信息时不持续占用屏幕顶部视觉空间，同时保留可发现的悬停入口。
2. 让内置功能卡通过同一提示机制提供及时但不使用系统通知的反馈。
3. 提供可由 Coding Agent 稳定解析和调用、具有完整分级帮助的本地 CLI。
4. 提供足以替代轻量周日历的本地 Scheduler，并允许导入常见 ICS 数据。
5. 观察本机 Agent 顶层执行与待回答状态，不依赖终端窗口数量。
6. 在不破坏每日 routine 语义的前提下，支持一次性临时计时任务。
7. 用可比较的周期完成度记录长期目标推进。
8. 无损升级既有业务数据、活动会话、卡片顺序和用户偏好。

### 2.2 非目标

- 云同步、CalDAV、账号、团队协作或遥测；
- EventKit、系统 Calendar 或其他第三方日历的实时同步；
- ICS 文件监视、启动刷新、定时刷新或 ICS 导出；
- 邮件邀请、参与者响应、附件或会议服务集成；
- 系统通知中心通知或任何 v2 提示声音；
- Scheduler 拖拽移动、拖边缩放、复杂 RRULE 编辑器或每项独立提醒；
- Targetor 提醒、Compact、GUI 撤销、GUI 非拖拽打卡、CLI 排序或归档恢复；
- Timer 临时任务排序、历史浏览、超过 `23:59:59` 的目标或并行会话；
- 运行时联网下载 Lucide、用户 SVG 或任意外部图标路径；
- CLI 直接访问 SQLite、自动启动 App、后台守护进程或 XPC Service；
- 第三方功能卡 SDK 或插件市场。

## 3. v1 → v2 覆盖矩阵

| 领域 | v1 | v2 决定 |
| --- | --- | --- |
| 默认岛面 | 始终为最近卡片的收敛态 | 无卡片需要收敛时进入 `Resting`，不绘制黑色表面 |
| 收敛能力 | 每张卡必须提供 | 变为可选、实时能力 |
| Timer 收敛态 | 始终可见最近任务摘要 | 仅已启用且存在运行任务时可见，只显示运行任务 |
| Pusher 收敛态 | 显示三列统计 | 删除；Pusher 平时静息 |
| Agent 状态 | 无 | v2.0.2 增加 Agentor；有活跃会话时可提供 Compact |
| 主动反馈 | Timer 达标动效和声音 | 统一静音提示队列；删除 Timer 声音 |
| 功能卡 | Timer、Pusher | v2.1.0 为 Timer、Pusher、Scheduler、Agentor、Targetor |
| Timer 任务 | 只有每日模板 | v2.1.0 增加默认关闭的临时任务能力 |
| 长期目标 | 无 | v2.1.0 增加 Targetor 周期打卡 |
| 外部操作 | 无 CLI | 新增只调用已运行 App 的 `peeker` CLI |
| 进程边界 | 单 App 进程 | 一个长期 App 数据进程；允许短生命周期 CLI 客户端，但 App 仍是唯一数据库写入者 |

未列出的 v1 平台、窗口、业务日、更新、分发、隐私和模块隔离规则继续有效。

## 4. 产品结构

```mermaid
flowchart TB
    CLI["peeker CLI\n短生命周期客户端"]
    IPC["同用户本地版本化 IPC"]
    Host["Peeker App Host\n唯一数据库写入者"]
    Island["岛状态与提示协调器"]
    Registry["Function Card Registry"]
    Timer["Timer\n每日 + 临时计时"]
    Pusher["Pusher"]
    Scheduler["Scheduler"]
    Agentor["Agentor\n内存状态 + 私有 UDS"]
    Targetor["Targetor\n周期打卡"]
    DB[("Peeker.sqlite + Preferences")]

    CLI --> IPC --> Host
    Host --> Island
    Host --> Registry
    Registry --> Timer
    Registry --> Pusher
    Registry --> Scheduler
    Registry --> Agentor
    Registry --> Targetor
    Timer --> DB
    Pusher --> DB
    Scheduler --> DB
    Targetor --> DB
```

CLI 请求必须进入与 UI 相同的 Store 或应用服务。不得为 CLI 复制跨日恢复、重复规则、事务、提示或校验逻辑。

## 5. 岛状态与交互

### 5.1 状态

```mermaid
stateDiagram-v2
    [*] --> ResolveBase
    ResolveBase --> Resting: 无已启用卡需要收敛
    ResolveBase --> Compact: 存在需要收敛的已启用卡

    Resting --> ExpandedHover: 鼠标进入透明热区
    Compact --> ExpandedHover: 鼠标进入收敛岛
    ExpandedHover --> ExpandedPinned: 点击岛
    ExpandedPinned --> ExpandedHover: Esc 或外部点击解锁
    ExpandedHover --> ResolveBase: 鼠标离开且无阻止条件

    ExpandedHover --> ExpandedBlocked: Popover/拖拽/文本输入
    ExpandedPinned --> ExpandedBlocked: Popover/拖拽/文本输入
    ExpandedBlocked --> ExpandedHover: 阻止结束且此前未锁定
    ExpandedBlocked --> ExpandedPinned: 阻止结束且此前已锁定

    ResolveBase --> Prompt: 队列非空且展开已结束 1.5 秒
    Resting --> Prompt: 新提示可立即播放
    Compact --> Prompt: 新提示可立即播放
    Prompt --> ExpandedHover: 鼠标进入，消费当前提示并打开来源卡
    Prompt --> Prompt: 6 秒结束且仍有下一条
    Prompt --> ResolveBase: 6 秒结束且队列为空
```

`ResolveBase` 是重新计算动作，不是用户可见表面。用户交互中的展开态优先级最高；展开期间到达的提示只能排队。

### 5.2 Resting

- 不渲染黑色岛面、文字或阴影。
- 保留透明悬停热区以进入最近选择的已启用卡。
- 带刘海屏：热区使用完整顶部安全区高度，宽度为物理刘海宽度左右各外扩 `16pt`。
- 无刘海屏：热区为屏幕顶部中央 `220×8pt`。
- 热区之外不得截获菜单栏鼠标操作。
- 透明热区必须提供可访问性入口，且不得因透明而产生可见缝隙或背景。

### 5.3 Compact

- 功能卡可实时声明“当前需要收敛态”；没有声明的卡不得占用 Compact。
- 只考虑已启用卡。禁用不停止模块后台数据或 CLI，但禁止该卡产生 Compact 或 Prompt。
- 多张卡同时合格时，选择最近被用户打开的合格卡；没有打开记录时按已启用排序选择第一张。
- 从 Compact 悬停展开时，打开 Compact 的来源卡，并更新该卡的最近打开时间。
- 展开结束后重新计算，而不是无条件恢复展开前的 Compact。

v2.1.0 内置卡中，Timer 在每日或临时任务运行时、Agentor 在存在活跃顶层会话时提供 Compact；Pusher、Scheduler、Targetor 不提供。设计必须保持通用，不得在宿主中硬编码 Timer 或 Agentor 特权。

### 5.4 Expanded

v1 的悬停展开、点击锁定、`Esc`、外部点击、Popover、拖拽、文本输入阻止收起、屏幕定位和减少动态效果规则继续有效。

- 从 Resting 展开最近选择的已启用卡。
- 从 Prompt 展开提示来源卡。
- 如果来源卡在提示播放前已禁用，应移除该提示，不能临时绕过禁用状态。
- 展开结束指岛已离开展开态且所有收起阻止条件消失；从该时刻起等待 `1.5` 秒再播放队列。

### 5.5 Prompt

- 最大表面为 `420×72pt`，顶部居中并与屏幕上沿连续连接。
- 显示来源图标、模块名和单行摘要；过长摘要尾部截断。
- 带刘海屏的文字与图标放在摄像头区下方，不得被物理刘海遮挡。
- 单条显示 `6` 秒。超时后有下一条则立即播放下一条，否则重新计算 Compact/Resting。
- 鼠标进入后立即消费当前项并展开来源卡；未播放项继续等待下一次展开结束。
- 动画尊重系统“减少动态效果”。

### 5.6 功能卡宿主边界

v2 的宿主接口必须保持功能卡无关：

- Function Card 注册可选的 Compact 内容，以及可观察的“当前是否需要 Compact”状态；没有提供者等同永不合格。
- 注册提供 Expanded、Settings、身份、排序、受信任图标描述符和宿主可观察的展开尺寸状态，不要求空 Compact view。
- 图标描述符支持现有 SF Symbol 与模块 Bundle manifest 中的 SVG；不得接受路径、URL 或任意 SVG 内容。
- Timer 可按临时任务开关把展开高度在 `328.571pt` 与 `371.429pt` 间切换；通用宿主观察尺寸状态，不读取 Timer 偏好。
- 宿主向模块提供 Prompt 发布与按稳定 token 撤销能力；提示项至少包含 token、来源 Feature ID、受信任图标、模块名、摘要和发生时间。
- Scheduler 用 occurrence 身份派生稳定 token；Agentor 等待问题使用 request ID；其他成功事件可生成新 token。
- CardRegistry 启用状态是主动展示的统一门禁。禁用时宿主清除该来源当前/待播 Prompt，并排除 Compact，但不得销毁模块 Store。
- Compact 解析、Prompt 排队、1.5 秒延迟、动态图标渲染和鼠标进入行为只在通用宿主实现；不得在各功能卡视图复制宿主状态机。

## 6. 全局提示队列

### 6.1 队列规则

- 严格 FIFO，不合并、不按对象覆盖。
- 当前显示项与待播项合计最多 `100` 条。
- 队列已满时静默丢弃新提示；不得驱逐更早提示。
- 队列只保存在内存中，不跨重启、崩溃或升级恢复。
- 所有提示静音，不调用通知中心。
- 数据库提交失败的操作不得产生提示。

### 6.2 在线与过期

“在线提示”要求 App 进程正在运行，且系统在事件到期时处于唤醒状态并通过正常定时回调处理事件。

- App 未运行期间发生的事件不补提示。
- Mac 睡眠期间发生的事件在唤醒恢复时不补提示。
- 启动或唤醒仍必须正确恢复业务数据，只是不创建过期提示。
- 已过触发点才创建或改期的 Scheduler 日程不立即补提示。

### 6.3 触发来源

| 模块 | 触发 | 不触发 |
| --- | --- | --- |
| Timer | 每日或临时任务在线自然达到目标且事务已提交 | 编辑目标造成完成；启动/唤醒恢复的过期完成；开始、暂停、CRUD、边界归档 |
| Pusher | 成功新建、删除、跨状态移动 | 标题/急迫度/每日属性编辑；同列排序；跨日自动归档或重建 |
| Scheduler | 每个非全天 occurrence 到达全局提前提醒时刻 | 全天日程；过期提醒；CRUD 本身 |
| Agentor | 执行开始、正常结束、失败/取消、等待回答 | 状态心跳、失联清理、已撤销问题 |
| Targetor | UI 或 CLI 成功打卡 | 撤销、周期恢复、CRUD、设置排序 |

Pusher 与 Targetor 的 UI/CLI 操作使用相同触发规则。UI 在展开态完成操作时，提示先入队，收起 `1.5` 秒后再播放。Agentor 的等待提示可按 request ID 撤销。

Scheduler 日程已入队但未显示时：

- 删除 occurrence/系列会移除对应待播提示；
- 改期会移除旧提示，并仅在新触发点仍在未来时重新安排；
- 同时到期的 occurrence 按开始时刻、系列 ID、occurrence key 的稳定顺序入队。

## 7. CLI 公共契约

### 7.1 分发与进程约束

- 用户命令名为 `peeker`。
- App Bundle 内的 CLI 物理文件名不得与主可执行文件 `Peeker` 仅大小写不同；建议使用 `peeker-cli`，由 Homebrew Cask 映射为 `peeker`。
- CLI 是短生命周期请求客户端，不是守护进程，也不直接打开 `Peeker.sqlite`。
- 使用同一登录用户可访问的版本化本地请求/响应 IPC；推荐 Unix domain socket。不得使用本地 HTTP 或 XPC Service。
- App 是唯一数据库写入者和业务状态事实来源。
- 除 `status` 外，App 未运行时命令失败；CLI 不自动启动 App。
- IPC 必须限制为当前登录用户，并在执行命令前完成协议版本握手。

### 7.2 顶层命令

```bash
peeker --help
peeker --version
peeker status
peeker timer ...
peeker timer temporary ...
peeker pusher ...
peeker scheduler ...
peeker targetor ...
```

`--help` 输出用法文本。根命令、功能级、命令组和叶命令都必须支持 `-h`/`--help`，且帮助不要求 App 运行；每页指向可继续发现的下一级或上一级帮助。除此之外，正常结果和错误只输出 JSON，不提供 text 模式或 TTY 自动切换。

### 7.3 JSON envelope

成功输出到 stdout：

```json
{
  "schemaVersion": 1,
  "ok": true,
  "data": {},
  "warnings": []
}
```

无警告时可以省略 `warnings`。失败输出到 stderr：

```json
{
  "schemaVersion": 1,
  "ok": false,
  "error": {
    "code": "validation_error",
    "message": "Human-readable message",
    "details": {}
  }
}
```

JSON key 和 `error.code` 使用英文。`message` 可本地化，但调用方不得依赖其文本解析。

### 7.4 退出码

| 退出码 | 类别 | 典型 error.code |
| --- | --- | --- |
| `0` | 成功；包括 `status` 返回 `running: false` | — |
| `2` | 用法或参数校验失败 | `invalid_usage`, `validation_error` |
| `3` | App 或 IPC 不可用 | `app_not_running`, `ipc_unavailable`, `ipc_timeout` |
| `4` | 对象未找到或名称歧义 | `not_found`, `ambiguous_selector` |
| `5` | 当前业务状态冲突 | `conflict`, `card_enablement_conflict` |
| `6` | 持久化或内部执行失败 | `persistence_error`, `internal_error`, `outcome_unknown` |
| `7` | CLI/App 协议不兼容 | `protocol_mismatch` |

IPC 在提交后、响应前断开时，不得猜测成功或自动重试非幂等命令；返回 `outcome_unknown`，调用方通过 `get`/`list` 核实。

### 7.5 version 与 status

`peeker --version` 不要求 App 运行，退出 `0` 并返回：

```json
{"schemaVersion":1,"ok":true,"data":{"cliVersion":"2.1.0","protocolVersion":1}}
```

`peeker status` 在 App 未运行时：

```json
{"schemaVersion":1,"ok":true,"data":{"running":false}}
```

App 运行时，`data` 至少包含：

```json
{
  "running": true,
  "appVersion": "2.1.0",
  "protocolVersion": 1,
  "pid": 12345
}
```

### 7.6 选择器与事务

- UUID 是稳定主键；`list`/`get` 必须返回后续命令所需 ID。
- Timer/Pusher/Targetor 允许名称或标题快捷选择，但仅接受去除首尾空白后的大小写敏感精确唯一匹配。
- 没有匹配返回 `not_found`；多个匹配返回 `ambiguous_selector` 及候选 ID。
- 变更命令只在事务提交后返回成功，并返回提交后的对象状态。
- 删除立即执行，不交互确认，也不要求 `--yes`。
- CLI 请求进入与 UI 相同的恢复和 mutation gate；同一模块的并发变更串行执行。
- `config set --enabled false` 必须保留“至少启用一张卡”的全局约束。
- 禁用卡仍接受业务 CLI 操作，但不产生 Compact 或 Prompt。

模块命令及字段见各功能文档。Agentor 不注册公开 CLI；`peeker agentor` 必须保持未知功能错误。Timer 每日模板命令与 `timer temporary` 使用独立选择器命名空间。

## 8. 功能卡增量概要

### 8.1 Scheduler

Scheduler 是 v2.0.0 新增的单一本地日历功能卡：

- 周一至周日的全天区和 24 小时时间网格；
- 单次、全天、跨日和常用重复日程；
- “本次 / 今后 / 全部”重复编辑范围；
- 手工追踪和刷新 ICS 来源；
- 全局 `off` 或提前 `1–60` 分钟的静音岛内提醒，默认 `10` 分钟；
- UI 与 CLI 共用领域、事务和提醒调度。

Scheduler 不使用 Peeker 业务日或每日快照。完整设计见 [Scheduler 功能文档](../functions/scheduler.md)。

### 8.2 Agentor

Agentor 是 v2.0.2 已实现的第 4 张卡：

- 支持 Pi、OpenCode、Hermes、Codex、Claude Code 顶层执行状态；
- 活跃会话至少为 1 时可提供 Compact；
- Claude Code/OpenCode 在可靠上游接口可用时支持岛内回答，其他 Agent 只读提醒；
- 状态、问题和答案只保存在内存，不注册 GRDB migration；
- 使用私有 helper/UDS，不提供公开 CLI。

完整设计见 [Agentor 功能文档](../functions/agentor.md)。

### 8.3 Timer 临时任务

v2.1.0 在每日模板之外增加临时任务：

- 新建能力默认关闭；关闭后已有临时任务仍可完整管理；
- 未开启随刷新消失的未完成任务携带同一 ID 与累计进度跨业务日；
- 开启随刷新消失的任务在下一边界归档，运行中只结算到边界；
- 每日与临时任务共享唯一活动会话、完成 Prompt 和统计口径；
- CLI 使用 `peeker timer temporary ...` 独立命令组；
- 开启新建能力时 Timer 表面动态变为 `800×371.429pt`，右侧上下等分为新增与统计。

完整设计见 [Timer 功能文档](../functions/timer.md)。

### 8.4 Targetor

Targetor 是 v2.1.0 新增的第 5 张卡：

- 用日、周、月周期记录长期目标 `count/max`；
- GUI 通过把推进卡拖到右侧打卡；CLI 支持打卡与当前周期事件撤销；
- 默认汇总图显示前 8 个完整周加当前周，并对混合周期目标等权平均；
- 软归档目标保留历史；
- 不提供 Compact 或定时提醒；成功打卡发布统一 Prompt；
- 离线内置 Lucide v1.27.0 完整图标目录。

完整设计见 [Targetor 功能文档](../functions/targetor.md)。

## 9. 默认配置与升级

### 9.1 新安装

- 默认启用顺序：Timer、Pusher、Scheduler、Agentor、Targetor。
- Timer 临时任务允许开关默认关闭，不创建示例临时任务。
- Scheduler 提醒默认提前 `10` 分钟，默认事件颜色为系统蓝。
- Targetor 刷新时刻默认 `00:00`，不创建示例推进项。
- Agentor 默认启用，但不自动植入任何 Agent hook/plugin。
- 其他 v1 默认值保持不变。

### 9.2 升级

- 无损保留 Timer/Pusher/Scheduler SQLite 数据、快照、活动 Timer 会话、Agentor 接入文件和模块偏好。
- 保留用户已有卡片启用状态、相对排序、最近选择和最近打开时间。
- 按 introduced configuration version 追加新卡：Scheduler、Agentor、Targetor；v2.0.x 到 v2.1.0 时启用 Targetor 并追加在 Agentor 后。
- 不得重新启用用户此前主动禁用的旧卡。
- 卡配置版本提升到 `4`；若最近选择卡无效，按升级后的启用顺序回退。
- Timer 临时任务允许开关对所有既有用户初始化为 false；活动每日 Timer 继续按原开始时间计时。
- 只追加 Timer temporary、Targetor、宿主动态图标/尺寸所需 schema 与偏好，不执行破坏性迁移。
- Targetor 不自动创建目标；Agentor 不因升级自动植入 hook。
- Prompt 队列不迁移。

CLI protocol version 与 JSON schema version 继续为 `1`；本轮新增命令和字段保持向后兼容。后续破坏性变更必须提升对应版本并返回明确 `protocol_mismatch`。

## 10. 错误、安全、隐私与性能

- v1 的 SQLite 原子性、幂等迁移、功能卡错误隔离和写入失败回滚规则继续适用。
- IPC 不扩大数据访问到其他本地用户，不接受网络连接。
- CLI 不上传业务数据；ICS 文件只在本地解析和保存。
- Scheduler 来源刷新失败必须保留上次成功数据和来源元数据。
- 无限重复日程只在请求窗口内惰性展开，不预生成无限实例。
- Timer 临时任务边界必须与每日快照、会话拆分和归档原子提交，不能产生不可见运行任务。
- Targetor 打卡上限在事务内重新校验；软归档不得级联删除历史周期或事件。
- Lucide 仅从离线、版本化、哈希校验的 Bundle manifest 读取，不接受网络、任意路径或用户 SVG。
- 全量 Lucide 选择器使用虚拟化网格和本地索引，不能一次实例化全部 SVG View。
- Resting 不得通过高频轮询维持；Prompt、Scheduler 提醒和各模块边界使用统一时间调度。
- 禁止为了 CLI 在 App 外复制 GRDB migration 或业务恢复代码。
- v2.1 仍无账号、遥测、业务数据上传和系统通知。

## 11. 验收标准

### 11.1 文档与升级

- [ ] PRD、Architecture、concept 和五张功能卡文档不存在冲突、TODO 或未决占位符。
- [ ] v2.1.0 当前实现与 v2.0.2 基线明确区分；Agentor 被记录为先前已实现的第 4 张卡。
- [ ] 新安装顺序为 Timer、Pusher、Scheduler、Agentor、Targetor。
- [ ] v2.0.x 升级保留旧卡顺序、最近选择和禁用状态，默认启用的 Targetor 只追加一次。
- [ ] Timer 临时任务允许开关对新安装和升级均为 false，既有数据无损。
- [ ] migration 失败不删除或重建数据库；Prompt 队列不迁移。

### 11.2 岛与宿主

- [ ] 无已启用卡需要 Compact 时不绘制黑框；透明热区仍可展开最近卡。
- [ ] 无刘海屏只有顶部中央 `220×8pt` 热区截获 hover；其余菜单栏可交互。
- [ ] Timer 运行时、Agentor 有活跃会话时可提供 Compact，并按最近打开时间/启用顺序竞争。
- [ ] Pusher、Scheduler、Targetor 不提供 Compact。
- [ ] Timer 临时任务开关变化时展开高度在 `328.571pt` 与 `371.429pt` 间平滑重算，宿主无 Timer 特判。
- [ ] SF Symbol 与受信任 Bundle SVG 可在标签、设置和 Prompt 中统一渲染。
- [ ] 展开、锁定、Popover、拖拽和文本输入继续遵守收起 blocker 规则。

### 11.3 Prompt

- [ ] Prompt 使用 `420×72pt` 上限、单行摘要和静音显示。
- [ ] 展开期间提示排队，并在展开结束 `1.5` 秒后开始；每条显示 `6` 秒。
- [ ] 鼠标进入 Prompt 会消费当前项并打开来源卡。
- [ ] FIFO 次序稳定；第 101 条新提示在总数已达 100 时被丢弃且不驱逐旧项。
- [ ] App 未运行或 Mac 睡眠期间的 Timer 完成、Scheduler 提醒不补播。
- [ ] Targetor UI/CLI 成功打卡提示，撤销与周期恢复不提示。
- [ ] 禁用来源卡清除其待播提示并禁止后续主动展示；数据库失败不提示。

### 11.4 CLI

- [ ] Cask 可同时安装 `Peeker.app` 和命令名 `peeker`，物理 CLI 文件不与 `Peeker` 大小写冲突。
- [ ] `peeker status` 在 App 未运行时退出 `0` 并返回合法 JSON `running:false`。
- [ ] 其他业务命令在 App 未运行时不启动 App、不打开数据库，并返回 `app_not_running`。
- [ ] 根、功能、命令组和叶命令帮助不要求 App 运行，并形成可发现层级。
- [ ] `timer temporary` 与每日模板选择器、返回类型隔离；`targetor` 全部命令与错误码符合模块文档。
- [ ] 正常结果、错误、退出码、名称歧义和协议不兼容符合公共契约。
- [ ] UI 与 CLI 同类操作产生相同数据、恢复、事务和提示结果。
- [ ] 提交后响应丢失返回 `outcome_unknown`，客户端不自动重放变更。
- [ ] Agentor 不出现在公开 CLI 功能命令中；protocol/JSON schema 保持版本 `1`。

### 11.5 Timer 与 Pusher

- [ ] Timer 既有计时、每日跨日、快照和单活动任务验收继续通过。
- [ ] 每日与临时任务共享唯一活动会话和自然完成 Prompt，且不播放 v1 提示音。
- [ ] 非 expire 临时任务跨日携带；expire 任务在下一边界按状态正确归档。
- [ ] 边界快照先包含活动临时任务，再执行归档或携带；历史冻结不回写。
- [ ] 关闭临时任务能力时禁止新建，但已有临时任务仍可完整管理。
- [ ] Pusher 无 Compact；新建、删除和跨状态移动提交后提示，字段编辑与同列排序不提示。

### 11.6 Scheduler 与 Agentor

- [ ] Scheduler 周视图、CRUD、重复规则、ICS 来源和提醒继续符合功能文档。
- [ ] 无限重复查询不会预生成无界数据；删除或改期能撤销旧调度和待播 Prompt。
- [ ] Agentor 五种 Agent 的执行状态、Compact、问题表单、私有 IPC 和接入管理继续符合功能文档。
- [ ] Agentor 不注册 GRDB migration，升级不自动植入 hook/plugin。

### 11.7 Targetor

- [ ] 日/周/月周期覆盖任意周刷新日、`0=月末`、短月、DST、时区变化和多周期离线恢复。
- [ ] 周期规则编辑结算清零；普通字段/max 编辑不清零；降低 max 不删除事件。
- [ ] UI 拖拽与 CLI checkin 在事务中校验上限，取消或冲突不写库。
- [ ] CLI uncheck 只物理删除当前周期指定事件，并回退 count、状态和日历。
- [ ] 软归档后当前列表移除，归档前历史和汇总保持。
- [ ] 9 列窗口、混合周期等权平均、五级色阶和单项目日历符合功能文档。
- [ ] 三种阶段预览、1 秒反馈和 Reduce Motion 行为可验收。
- [ ] Lucide v1.27.0 可离线搜索和渲染；未知名称、任意路径和用户 SVG 被拒绝。
- [ ] manifest、哈希、MIT/ISC 许可与 Bundle 验证通过。

## 12. 后续方向

v2.1 不承诺 CalDAV、EventKit、系统通知、复杂 iCalendar 全兼容或第三方扩展。若后续增加这些能力，应另行设计权限、来源冲突、协议兼容和迁移，不得把一次性本地 ICS 来源机制隐式升级为云同步。Targetor 的 GUI 撤销、提醒、归档恢复和 Lucide 在线更新也必须另行设计，不从本轮契约推导。
