# v2.1.0 功能反馈：Timer 临时任务与 Targetor

> 状态：需求已敲定。
>
> 本文件保留用户反馈来源和决策摘要，不作为实现细节的事实来源。发生差异时，以 [v2.1 PRD](../PRD.md)、[Timer 功能文档](../../functions/timer.md) 和 [Targetor 功能文档](../../functions/targetor.md) 为准。

## 1. 反馈来源

本轮包含两项 feature request：

1. Timer 除每日 routine 外，应允许用户按需建立一次性临时计时任务。
2. 新增 Targetor，用周期打卡表示长期主线目标是否持续推进。

目标版本确定为 v2.1.0。本轮文档定稿不实现源码，不提前更新 README、发布说明或版本号。

## 2. Timer 临时任务决策摘要

- Timer 设置新增“允许临时计时任务”；新安装和升级均默认关闭。
- 开关只控制新建入口。关闭后已有临时任务仍可显示、开始、暂停、编辑和删除。
- 开启后 Timer 展开高度变为 `800×371.429pt`，与 Pusher 同高；关闭时为 `800×328.571pt`。
- 开启后右侧上下等分：上方新增，下方保留今日完成度或月热力日历。
- 临时任务字段为稳定 ID、名称、预设色、`1...86,399` 秒目标及“随刷新消失”。后者默认关闭。
- 未开启随刷新消失的未完成任务跨业务日携带同一 ID 和累计进度；完成后在下一边界归档。
- 开启随刷新消失的任务在下一边界归档；运行中只结算到边界并停止。
- 临时任务在每个仍活动的业务日进入总完成度和边界快照，使用完整目标与跨日累计进度。
- 每日与临时任务共用“最多一个活动会话”。自然在线完成使用现有静音 Timer Prompt。
- CLI 采用 `peeker timer temporary ...` 子命令组；现有 Timer 模板命令语义不变。

完整字段、边界顺序、CLI JSON、错误码、迁移与验收见 [Timer 功能文档](../../functions/timer.md)。

## 3. Targetor 决策摘要

- Targetor 是第 5 张卡，默认启用并追加在 Agentor 后；无 Compact。
- 设置页管理全局刷新时间和推进项 CRUD/排序；推进项最大次数为 `1...99`。
- 周期支持 daily、指定星期的 weekly，以及 `0=月末、1...30=指定日` 的 monthly；短月提前至月末。
- 修改周期规则立即结算并从 0 开始；修改刷新时刻从下一周期生效。
- 展开态为 `960×480pt`，左侧每行 3 张玻璃卡，右侧显示日历或打卡反馈。
- GUI 只通过拖到右侧打卡，不提供按钮或撤销；CLI 可 checkin，并按 event ID 撤销当前周期事件。
- 默认汇总显示前 8 个完整周加当前周；每个日期对当时有效目标的周期完成度等权平均，并使用五级色阶。
- 删除推进项采用软归档，过去周期和打卡继续参与历史。
- 图标离线内置从 Lucide v1.27.0 固定挑选的 209 张资源；Targetor 自身使用 Lucide `target`，构建和安装不补拉全量目录。
- UI 与 CLI 成功打卡均发布 `已打卡：<标题> <count>/<max>` Prompt。

完整领域、日历公式、交互、CLI、持久化、Lucide 许可与验收见 [Targetor 功能文档](../../functions/targetor.md)。

## 4. 总文档同步

v2.1.0 总文档同时修正以下旧状态：

- Agentor 已自 v2.0.2 实现，是第 4 张内置卡；
- Compact 资格不再只有 Timer，Agentor 有活跃会话时也可参与竞争；
- 新安装卡顺序为 Timer、Pusher、Scheduler、Agentor、Targetor；
- 公共 CLI 增加 Targetor 与 Timer temporary，Agentor 仍无公开 CLI；
- 公共 protocol version 与 JSON schema version 保持 `1`。

架构影响见 [v2 Architecture](../ARCHITECTURE.md)，高层概念见 [v2 concept](../concept.md)。
