# Peeker v2 增量概念

> 当前代码与稳定截图仍为 v1。本文描述 v2 方向；可开发、可验收的规则以 [v2 增量 PRD](PRD.md) 为准。

v2 继承 [v1 产品需求](../v1/PRD.md)，重点增加静息岛、功能卡提示、Scheduler 和本地 CLI。

## 静息与可选收敛

岛不再必须持续显示摘要，而有四类可见状态：

- **静息**：不绘制黑色表面，只保留屏幕顶部中央的透明悬停热区；
- **收敛**：仅在某张已启用功能卡主动声明需要持续展示时出现；
- **展开**：从热区、收敛岛或提示进入功能卡详情；
- **提示**：功能卡通过统一队列短暂展示主动消息。

并非每张卡都有收敛态。v2 内置卡中，只有 Timer 在任务正在计时时提供收敛态；Pusher 和 Scheduler 平时静息。

## 功能卡提示

功能卡可在事务成功或定时事件准点发生后发布岛内提示。提示静音、按 FIFO 播放；用户正在展开岛时，消息先排队，收起后再显示。

Timer 用提示反馈自然达标，Pusher 用提示反馈新建、删除和跨状态移动，Scheduler 用提示提醒即将开始的非全天日程。睡眠或 App 未运行期间错过的提示不补播。

## Scheduler

Scheduler 是完全本地的周日历功能卡，支持：

- 全天和定时日程；
- 常用重复规则以及“本次 / 今后 / 全部”编辑；
- 周视图和表单式 CRUD；
- 手动导入、刷新和移除可追踪 ICS 来源；
- 全局可关闭的提前提醒。

完整设计见 [Scheduler 功能文档](../functions/scheduler.md)。

## CLI

Peeker 仍只有一个长期运行、唯一写入数据库的 App 进程。`peeker` 命令是短生命周期客户端，通过同用户本地 IPC 请求已运行的 App 执行业务操作；它不直接访问数据库，也不自动启动 App。

```bash
peeker --help
peeker status
peeker timer list
peeker timer start "work out"
peeker pusher list
peeker scheduler list
```

除帮助文本外，CLI 结果与错误默认只输出结构化 JSON。完整公共契约见 [v2 PRD](PRD.md#7-cli-公共契约)，模块命令见：

- [Timer](../functions/timer.md#14-cli-接口)
- [Pusher](../functions/pusher.md#14-cli-接口)
- [Scheduler](../functions/scheduler.md#15-cli-接口)
