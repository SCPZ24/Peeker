# Peeker v2.1 增量概念

> 当前代码版本为 v2.1.0；本文概述该版本的产品方向。
>
> 可开发、可验收规则以 [v2 PRD](PRD.md) 和 [功能文档](../functions/) 为准。

Peeker v2.1 继承 [v1 产品需求](../v1/PRD.md)，保持本地优先、无账号、无遥测的顶部效率入口。v2 已建立静息岛、统一提示、Scheduler、本地 CLI 和 Agentor；v2.1 新增 Timer 临时任务与 Targetor 长期目标打卡。

## 岛的四类表面

- **静息 Resting**：不绘制黑色表面，只保留屏幕顶部中央透明热区。
- **收敛 Compact**：功能卡确有持续信息时才出现。Timer 运行任务时、Agentor 有活跃会话时可以提供 Compact。
- **展开 Expanded**：从热区、Compact 或 Prompt 进入功能卡详情。
- **提示 Prompt**：功能卡通过统一静音 FIFO 短暂展示主动消息。

Pusher、Scheduler 和 Targetor 不提供 Compact。多张卡同时具备资格时，宿主按最近打开时间和启用顺序选择，不为某张卡设置特权。

## 五张内置功能卡

| 卡片 | 作用 |
| --- | --- |
| Timer | 记录每日 routine 和一次性临时任务的真实投入时长 |
| Pusher | 管理当前业务日 Planned、Processing、Done 三列短期事项 |
| Scheduler | 查看和编辑本地周日历、重复日程与 ICS 来源 |
| Agentor | 观察本机 Agent 顶层执行、等待回答和结束状态 |
| Targetor | 按日、周、月周期记录长期目标的推进次数 |

新安装默认顺序为 Timer、Pusher、Scheduler、Agentor、Targetor。v2.0.x 用户升级时保留已有卡状态和相对顺序，并把默认启用的 Targetor 追加到末尾。

## Timer 临时任务

Timer 原有每日模板继续在每个业务日重建。v2.1 允许用户在设置中打开“允许临时计时任务”，再从展开态右上板快速新建一次性目标。

临时任务：

- 不创建每日模板；
- 与每日任务共用唯一活动会话；
- 可选择在下一刷新边界归档；
- 默认跨业务日携带同一任务和累计进度，完成后在下一边界归档；
- 在仍活动的每个业务日进入今日完成度和历史快照；
- 自然在线完成时使用现有静音 Timer Prompt。

允许开关对新安装和升级用户默认关闭。关闭只禁止新建，不隐藏或冻结已有临时任务。

完整设计见 [Timer 功能文档](../functions/timer.md)。

## Targetor 长期推进

Targetor 面向长期主线，不替代短期任务或计时器。用户为推进项选择 Lucide 图标、日/周/月周期和周期内最大打卡次数。

展开态左侧每行显示三张玻璃推进卡，右侧展示近期完成度日历。用户把未完成卡拖到右侧完成打卡；成功后显示阶段预览、1 秒反馈和统一 Prompt。GUI 不提供撤销，CLI 可按 event ID 撤销当前周期打卡。

Targetor 的默认汇总把每个目标在日期所属周期的 `count/max` 归一化后等权平均，因此不同频率和不同 max 的目标仍可共同显示。软归档目标从当前列表移除，但过去历史保留。

图标使用随 App 离线分发的 209 张 Lucide v1.27.0 精选资源；构建、安装和运行时都不联网补齐，也不接受用户 SVG。

完整设计见 [Targetor 功能文档](../functions/targetor.md)。

## Scheduler

Scheduler 是完全本地的周日历功能卡，支持：

- 全天和定时日程；
- 常用重复规则及“本次 / 今后 / 全部”编辑；
- 周视图和表单 CRUD；
- 手动导入、刷新和移除可追踪 ICS 来源；
- 全局可关闭的提前提醒。

完整设计见 [Scheduler 功能文档](../functions/scheduler.md)。

## Agentor

Agentor 是 v2.0.2 已实现的第 4 张卡。它通过用户主动安装的 hook/plugin 观察 Pi、OpenCode、Hermes、Codex 和 Claude Code 顶层会话。

有活跃会话时 Agentor 可提供 Compact；等待回答和开始/结束/失败通过统一 Prompt 展示。Claude Code 与 OpenCode 可在可靠上游接口存在时从岛内回答，其他 Agent 采用只读提醒和原生界面回落。Agentor 不使用公开 `peeker agentor` 命令，也不写业务数据库。

完整设计见 [Agentor 功能文档](../functions/agentor.md)。

## 统一 Prompt

功能卡只在事务成功或在线定时事件准点发生后发布 Prompt。提示静音、FIFO 播放；用户正在展开岛时先排队，收起后再显示。

- Timer：每日或临时任务自然在线达标；
- Pusher：新建、删除和跨状态移动；
- Scheduler：非全天日程提前提醒；
- Agentor：执行开始、结束、失败、取消和等待回答；
- Targetor：UI 或 CLI 成功打卡。

App 未运行或 Mac 睡眠期间错过的定时提示不补播。禁用来源卡会清除并抑制该来源 Prompt，但各模块按自身规则决定后台业务是否继续。

## CLI

Peeker 仍只有一个长期运行、唯一写入数据库的 App 进程。`peeker` 是短生命周期客户端，通过同用户本地 IPC 请求已运行的 App 执行业务操作；它不直接访问数据库，也不自动启动 App。

```bash
peeker --help
peeker status
peeker timer list
peeker timer temporary --help
peeker pusher list
peeker scheduler list
peeker targetor --help
peeker targetor checkin "长期写作"
```

帮助文本以外的结果和错误只输出结构化 JSON。Timer temporary 和 Targetor 增加功能级、命令级分层帮助。Agentor 继续不暴露公共 CLI。

完整公共契约见 [v2 PRD](PRD.md#7-cli-公共契约)，模块命令见：

- [Timer](../functions/timer.md#16-cli-通用数据约定)
- [Pusher](../functions/pusher.md#14-cli-接口)
- [Scheduler](../functions/scheduler.md#15-cli-接口)
- [Targetor](../functions/targetor.md#10-cli-数据与选择器)
