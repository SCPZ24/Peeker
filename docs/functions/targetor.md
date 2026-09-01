# Targetor：长期目标推进管理器（v2.1）

> 文档状态：已确认，可直接用于设计、实现和验收。
>
> 目标版本：v2.1.0。
>
> 通用岛状态、提示队列、CLI envelope、升级与错误规则以 [Peeker v2 PRD](../v2/PRD.md) 为准。

Targetor 是 Peeker 的第 5 张内置功能卡，用周期打卡帮助用户持续推进长期主线目标。Pusher 管理当前业务日的短期事项；Targetor 只记录长期目标在日、周或月周期内被推进了多少次。

## 1. 目标与非目标

### 1.1 目标

1. 让用户建立可长期保留、可排序的推进项。
2. 用明确的周期和次数上限记录推进频率。
3. 在岛内通过拖拽完成快速打卡，并提供阶段反馈。
4. 以混合周期可比较的方式展示近期整体完成度和单项目历史。
5. 让 UI 与公开 CLI 共用同一周期恢复、事务、校验和提示规则。

### 1.2 非目标

- 子任务、里程碑、截止日期、提醒、计时或项目依赖；
- 目标颜色、自定义 SVG、运行时下载图标；
- Targetor Compact；
- GUI 撤销、GUI 非拖拽打卡或 CLI 排序；
- 归档目标恢复或物理删除历史；
- 云同步、账号、协作、数据导入或导出。

## 2. 功能卡注册与配置

Targetor 注册参数：

| 参数 | 值 |
| --- | --- |
| Feature ID | `targetor` |
| 默认顺序 | `4`，位于 Agentor 后 |
| introduced configuration version | `4` |
| 默认启用 | 是；新安装和升级均启用 |
| Compact | 不提供 |
| 最大展开表面 | `960×480pt` |
| 功能卡图标 | Bundle 中的 Lucide `target` |

功能卡启用开关只出现在统一“功能卡”设置页。Targetor 设置页包含：

- 全局本地刷新时刻，默认 `00:00`，精确到分钟；
- 推进项新增、编辑、软删除和拖拽排序；
- Lucide 图标搜索与选择。

禁用 Targetor 时：

- 不显示标签、Expanded、Compact 或 Targetor Prompt；
- 保留数据库、偏好和周期调度状态；
- CLI 业务操作继续执行；
- 重新启用时恢复当前周期，只安排未来边界，不补过期 Prompt。

### 2.1 设置页交互

活动推进项按 position 显示在可拖拽排序列表中。新目标追加到末尾；删除后其余活动 position 重新连续化。新增/编辑表单包含标题、可空描述、Lucide 图标、周期、条件周期字段和最大次数：

- daily 隐藏周/月字段；
- weekly 必须选择星期，UI 初始值为周一；
- monthly 必须选择 `0...30`，UI 初始值为 `1`；
- 新增默认 icon `target`、daily、max `1`；
- 标题、周期组合、max 或 icon 无效时保存按钮禁用；
- 编辑周期规则前明确说明“保存后会结算当前周期并从 0 开始”；
- 保存失败时保留草稿并显示可重试错误；
- 删除需二次确认；
- 排序只作用于活动目标，保存失败时恢复原顺序。

图标选择器使用虚拟化网格；搜索框按 canonical name 和 manifest tags 过滤，选择结果同时显示 SVG 预览和 canonical name。

## 3. 推进项模型

每个推进项包含：

| 字段 | 规则 |
| --- | --- |
| Target ID | UUID，创建后稳定；标题不是身份 |
| 标题 | 去除首尾空白后非空；允许重名 |
| 描述 | 可空；空值与空字符串统一保存为空 |
| Icon name | Lucide v1.27.0 manifest 中的 canonical name；默认 `target` |
| 周期规则 | `daily`、`weekly` 或 `monthly` |
| 周期最大次数 | `1...99`，默认 `1` |
| 排序位置 | 活动目标内连续、稳定；只由设置页调整 |
| 创建/更新时间 | 毫秒时间戳 |
| 归档时间 | 活动目标为空；删除后记录时间 |

推进卡不保存颜色。卡片后方实体块统一使用亮灰色设计 token；前方玻璃的描边和动画表达完成状态。

## 4. 周期模型

### 4.1 通用定义

周期是半开区间 `[start, end)`。周期内完成度为：

```text
min(有效打卡次数 / 周期最大次数快照, 1)
```

每个周期保存其起止时刻、目标内单调递增的 `sequence`、周期规则快照、最大次数快照和结算状态。首个周期 sequence 为 0；每次正常边界或规则变更创建新周期时加 1。已结算周期不因目标后续编辑而改写。

Targetor 使用自己的全局刷新时刻，不复用 Timer 或 Pusher 的业务日状态。边界按系统本地 Calendar、当前时区和夏令时规则计算，不能用固定 24 小时或固定 30 天近似。

### 4.2 日、周、月边界

- **日周期**：相邻两个每日刷新时刻之间。
- **周周期**：用户选择 `mon...sun`；周期从所选星期的刷新时刻开始，到下一周同一边界结束。
- **月周期**：用户选择 `0...30`。
  - `0` 表示每月最后一个自然日；
  - `1...30` 表示指定日；
  - 短月不存在指定日时，边界提前到该月最后一日。

周、月周期仍使用同一个全局刷新时刻。例如月刷新日为 `0`、刷新时刻为 `04:00` 时，周期在每月最后一天本地 `04:00` 切换。

### 4.3 创建、恢复和变更

- 新目标的首个周期从创建时刻开始，到按规则计算出的下一个未来边界结束；创建前日期不纳入该目标的日历或汇总。
- App 离线、退出或睡眠后，恢复时按时间顺序补齐遗漏周期，包括 0 次周期，直到建立当前周期。
- 离线周期恢复不产生 Prompt 或庆祝反馈，并且必须幂等。
- 修改周期类型、周刷新日或月刷新日时：在一个事务中按编辑时刻结算旧周期，再以新规则创建从 0 开始的当前部分周期。
- 修改标题、描述或图标不结算、不清零。
- 修改最大次数立即更新当前周期的 max 快照并保留已有事件；已结算周期的 max 快照不变。
- 如果降低 max 后 `count > max`，显示完成度 100%，拒绝新增打卡，但不删除既有事件。
- 修改全局刷新时刻不移动当前周期的 start/end；当前周期按旧 end 结算，下一周期才采用新时刻。由此产生的首个新周期可以短于或长于常规周期。
- 时区或夏令时变化只重算尚未创建的未来边界，不修改已保存周期。

### 4.4 删除

设置页删除需二次确认。删除采用软归档：

1. 在删除时刻结算当前周期；
2. 设置目标 `archivedAt`；
3. 从活动目标、展开列表和默认 CLI list 中移除；
4. 保留目标、周期和打卡记录。

归档目标继续参与其创建至归档期间的历史日历。首版不提供恢复入口。

## 5. 打卡状态与事务

打卡状态按当前周期有效事件数计算：

| 状态 | 条件 |
| --- | --- |
| 未开始 | `count == 0` |
| 起始 | `0 < count/max <= 0.5` |
| 行进 | `0.5 < count/max < 1` |
| 完成 | `count/max >= 1` |

打卡必须在 Targetor mutation gate 中执行：

1. 恢复所有已过期周期；
2. 解析活动目标和当前周期；
3. 在数据库事务内重新统计当前事件并校验 `count < max`；
4. 插入具有稳定 UUID 的 check-in event；
5. 提交后发布内存状态、庆祝反馈和 Prompt。

数据库提交失败、无效拖拽或已完成目标不得改变计数或日历。并发 UI/CLI 打卡串行执行，不能突破 max。

## 6. 展开态

### 6.1 布局

- 左侧约 75%：推进项卡片，每行 3 张；按设置 position 排序。
- 右侧约 25%：默认汇总日历、悬停项日历或拖拽反馈。
- 活动目标较多时只滚动左侧；岛不随数据无限增高。
- 没有活动目标时显示空状态和前往 Targetor 设置的操作。

推进卡至少显示 Lucide 图标、标题、可选描述、`count/max` 和完成状态。描述过长时截断，并保留可访问性完整文本。

### 6.2 玻璃卡交互

推进卡采用前方玻璃块和后方亮灰实体块：

- 未开始：前方玻璃不描框；
- 起始：淡色描框；
- 行进：淡色描框，并有两道白色光球沿边框运动；
- 完成：亮白描框。

鼠标悬停时，前方玻璃适度放大并降低 blur；后方亮灰块向左移动并逆时针旋转。移开后复原。

开启 Reduce Motion 后：

- 停止循环位移、旋转、缩放、脉冲和边框光球；
- 保留图标、文字、`count/max` 和静态状态描边；
- 不降低信息完整性。

### 6.3 拖拽打卡

- 只有未完成的活动推进卡可以拖起。
- 展开态拖拽只表示打卡，不能排序；排序只在设置页完成。
- 整个右侧面板是有效放置区。
- 拖拽期间使用宿主 dragging blocker，岛必须保持展开。
- 取消、放到右侧之外、过期 drag envelope 或重复提交均不写库。
- GUI 不提供按钮打卡或撤销；需要非拖拽操作时使用 CLI。

拖起时，右侧从日历切换为“本次打卡成功后”的阶段语义图：

| 成功后的状态 | 草案语义 | Lucide v1.27.0 canonical resource |
| --- | --- | --- |
| 起始 | `chevron-double-up` | `chevrons-up` |
| 行进 | `rocket-launch` | `rocket` |
| 完成 | `check-badge` | `badge-check` |

草案语义不作为持久化身份；实现必须使用上表固定 canonical resource，不在运行时猜测别名。

提交成功后右侧播放 1 秒反馈：

- 起始：边框闪白后褪去；
- 行进：一亮一暗两条白色光带从左向右依次划过；
- 完成：整个右侧闪白后褪去。

反馈结束后回到当前悬停项日历；没有悬停项时回到汇总日历。Reduce Motion 下用 1 秒静态高亮与淡变替代扫光、位移或旋转。

## 7. 日历与完成度颜色

### 7.1 五级色阶

所有日历先计算 `0...1` 完成度，再映射为系统蓝语义色的四档非空明度：

| 完成度 | 色阶 |
| --- | --- |
| `0` | 空 |
| `(0, 0.25]` | 1 级 |
| `(0.25, 0.5]` | 2 级 |
| `(0.5, 1)` | 3 级 |
| `1` | 4 级，最亮 |

未来周期为空。当前周期随打卡或撤销实时更新。

### 7.2 默认汇总图

默认图为 9 列、7 行周格：

- 列范围是前 8 个完整周加当前周；
- 行固定为周一至周日；
- 当前周今天之后的格子为空；
- 每次本地日期跨日后窗口向前滚动。

每个日期格的计算：

1. 找出在该日期对应 Targetor 日区间内有效的目标；创建前和归档后的目标不参与。
2. 对每个目标取得与该日区间相交的日/周/月周期并封顶完成度为 1；若规则切换导致同一日有多个相交周期，选择 `start` 最晚的新周期。
3. 对这些目标等权平均；不按 max 加权。
4. 没有有效目标时为空。

因此日、周、月不同频率可以共同进入一个可解释的归一化汇总。归档目标仍参与归档前日期，历史结果不会因软删除消失。

### 7.3 悬停单项目

悬停推进卡时，右侧改为该目标历史：

- **日周期**：显示当月日历，每格表示对应日周期完成度。
- **周周期**：显示当月日历；同一周期覆盖的 7 天使用相同色相和深浅。橙、黄、绿、蓝、青按该目标持久化的 `period.sequence % 5` 循环，确保跨月查看同一周期时颜色不变。
- **月周期**：显示当前自然年的 `3 column × 4 row` 月格，每格表示对应月周期完成度。

月视图支持前后切换月份；年视图支持前后切换年份。鼠标离开且未拖拽时恢复默认汇总图。

## 8. Prompt

UI 或 CLI 每次成功打卡后发布一条静音 Prompt：

```text
已打卡：<标题> <count>/<max>
```

- 只有数据库事务成功后发布；
- 使用 Targetor 的 Lucide `target` 图标；
- 进入通用 FIFO，遵守 100 条容量、6 秒展示和展开结束后 1.5 秒延迟；
- Targetor 被禁用时宿主抑制 Prompt，但业务事务仍可成功；
- 周期恢复、字段编辑、删除、排序和 CLI 撤销不发布 Prompt。

## 9. Lucide 资源

Targetor 离线随 App Bundle 分发 Lucide v1.27.0 完整图标目录和搜索元数据：

- 不在运行时联网或下载图标；
- 设置页提供虚拟化网格，并按 canonical name 和 manifest tags 本地搜索；
- 持久化 canonical icon name，不保存路径或 SVG 内容；
- 只解析 manifest 白名单内的 Bundle 资源，拒绝用户路径、外部文件和未知名称；
- Targetor 自身的标签、设置和 Prompt 使用同一 manifest 中的 `target`；
- Bundle 包含 icon artwork 的 MIT 许可声明，以及 Lucide 项目代码/元数据的 ISC 许可声明；
- 版本化 manifest 保存资源版本、文件列表和 SHA-256，构建验证资源存在、哈希匹配且可由 macOS SVG 渲染器打开；
- 运行时只通过公开 `NSImage` 与 SwiftUI API 按需渲染，`sips`/CoreSVG 仅属于发布验证，不链接或调用私有 CoreSVG API。

更新 Lucide 版本属于显式依赖升级，必须保留旧目标已使用 icon name 的兼容映射或迁移，不能静默丢失图标。

资源事实来源：

- [Lucide v1.27.0 release](https://github.com/lucide-icons/lucide/releases/tag/1.27.0)
- [Lucide repository and license](https://github.com/lucide-icons/lucide)

## 10. CLI 数据与选择器

Targetor CLI 继承 [v2 CLI 公共契约](../v2/PRD.md#7-cli-公共契约)。除 `--help` 外只输出 JSON。

选择器形式为：

```text
--id <target-id>
<exact-title>
```

两者互斥。标题去除首尾空白后按大小写敏感精确匹配；没有匹配返回 `not_found`，多个匹配返回 `ambiguous_selector` 及候选 Target ID。

时间规则：

- `--refresh-time` 使用本地 `HH:mm`；
- `history --from/--to` 使用带 offset 的 RFC 3339，区间为 `[from, to)`；
- from/to 必须同时提供，且 `to > from`。

## 11. CLI 命令

### 11.1 帮助层级

以下各级都必须支持 `-h` 和 `--help`，且不要求 App 运行：

```text
peeker --help
peeker targetor --help
peeker targetor <command> --help
peeker targetor config --help
peeker targetor config <get|set> --help
```

### 11.2 命令矩阵

| 命令 | 作用 |
| --- | --- |
| `peeker targetor list [--archived active\|all\|only]` | 列出活动、全部或仅归档目标；默认 `active` |
| `peeker targetor get (--id <id> \| <title>) [--include-archived <bool>]` | 读取目标；默认不匹配归档项 |
| `peeker targetor create --title <title> [--description <text>] [--icon <name>] [--period <daily\|weekly\|monthly>] [--weekday <mon..sun>] [--month-day <0..30>] [--max-count <1..99>]` | 创建目标并建立当前部分周期 |
| `peeker targetor update (--id <id> \| <title>) [--title <title>] [--description <text> \| --clear-description] [--icon <name>] [--period <daily\|weekly\|monthly>] [--weekday <mon..sun>] [--month-day <0..30>] [--max-count <1..99>]` | 编辑目标；至少一个实际变更 |
| `peeker targetor delete (--id <id> \| <title>)` | 软归档目标并结算当前周期 |
| `peeker targetor checkin (--id <id> \| <title>)` | 当前周期原子打卡一次 |
| `peeker targetor history (--id <id> \| <title>) [--from <rfc3339> --to <rfc3339>]` | 返回事件；默认当前周期 |
| `peeker targetor uncheck --event-id <event-id>` | 物理删除当前周期指定事件 |
| `peeker targetor config get` | 返回 enabled 与 refreshTime |
| `peeker targetor config set [--enabled <bool>] [--refresh-time <HH:mm>]` | 更新核心配置 |

Targetor 不提供 CLI `move`。设置页排序是唯一排序入口。

### 11.3 创建和编辑校验

- create 省略 icon 时为 `target`，省略 period 时为 `daily`，省略 max 时为 `1`。
- daily 不接受 weekday 或 month-day。
- 显式 weekly 必须提供 weekday，且不接受 month-day。
- 显式 monthly 必须提供 month-day，且不接受 weekday。
- update 显式提供 `--period weekly|monthly` 时必须同时提供对应完整附属字段；改为 daily 时不得提供 weekday/month-day。
- 不提供 `--period` 时，`--weekday` 只允许当前规则为 weekly，`--month-day` 只允许当前规则为 monthly；这两种修改同样属于周期规则变更并立即结算清零。
- 只更新 max、标题、描述或 icon 时不要求重复提交未变化的周期字段。
- `--description` 与 `--clear-description` 互斥。
- icon 必须存在于 Lucide manifest。

### 11.4 打卡与撤销

`checkin` 成功返回更新后的目标和新事件：

```json
{
  "target": {
    "targetId": "UUID",
    "title": "长期写作",
    "description": null,
    "icon": "notebook-pen",
    "period": {"frequency":"daily"},
    "currentPeriod": {
      "periodId": "UUID",
      "start": "2026-08-10T00:00:00+08:00",
      "end": "2026-08-11T00:00:00+08:00",
      "count": 1,
      "maxCount": 1,
      "ratio": 1,
      "state": "completed"
    },
    "position": 0,
    "archivedAt": null
  },
  "event": {
    "eventId": "UUID",
    "occurredAt": "2026-08-10T10:00:00+08:00"
  }
}
```

达到 max 后 `checkin` 返回业务冲突，不插入事件。

`uncheck`：

- 只接受活动目标当前周期内仍存在的 event ID；
- 在事务中物理删除，不保留 revoked tombstone；
- 提交后重算 count、ratio、状态和日历；
- 已结算周期、归档目标、未知事件或不属于当前周期的事件拒绝；
- 不发布 Prompt。

### 11.5 list/get/history 输出

CLI 中 `state` 的 wire value 固定为 `notStarted | started | progressing | completed`，不得本地化或改名。

活动目标对象至少包含：

- `targetId`、title、可空 description、icon；
- period 规则；
- `currentPeriod`：ID、起止、count、maxCount、ratio 和 state；
- position、createdAt、updatedAt、`archivedAt:null`。

归档目标返回 `currentPeriod:null`，并通过 `lastPeriod` 返回删除时结算的最后周期摘要。`list --archived all|only` 与 `get --include-archived true` 才返回归档目标。

`history` 可按稳定 ID 查询活动或归档目标；标题选择会在活动和归档目标中共同执行唯一匹配。它返回目标摘要、查询半开区间、周期列表和 check-in events；周期摘要包含 period ID、sequence、起止、规则/max 快照和 ratio，每个事件包含 event ID、period ID 和 occurredAt。活动目标默认查询当前周期；归档目标默认查询最后结算周期。

`delete` 返回被归档目标快照及 `archived:true`。`config get/set` 返回：

```json
{"enabled":true,"refreshTime":"00:00"}
```

### 11.6 模块错误

| error.code | 条件 | 公共退出码类别 |
| --- | --- | --- |
| `targetor_invalid_title` | 标题为空 | `2` |
| `targetor_invalid_icon` | icon 不在 manifest | `2` |
| `targetor_invalid_period` | 周期参数组合无效 | `2` |
| `targetor_invalid_max_count` | max 不在 `1...99` | `2` |
| `targetor_cycle_complete` | 当前周期已达到 max | `5` |
| `targetor_event_not_found` | event ID 不存在 | `4` |
| `targetor_event_not_current` | 事件不属于活动目标当前周期 | `5` |
| `targetor_target_archived` | 对归档目标执行当前业务操作 | `5` |

名称未找到/歧义、功能卡最后一项禁用、持久化和 IPC 错误使用公共错误码。

## 12. 持久化与模块边界

Targetor 使用独立目标：

```text
TargetorModule
  ├─ TargetorFeature       Domain / Period resolver / Store / Views
  └─ TargetorGRDBAdapter   Migrations / Repository / transactions
```

- `TargetorFeature` 不 import GRDB。
- `TargetorGRDBAdapter` 不向 UI 或 CLI 暴露 GRDB Record。
- `TargetorModule` 负责偏好、依赖注入、卡片注册、命令处理和 Host Actions。
- `BuiltInFeatureModules.swift` 是唯一 App 组装点。
- Targetor 不读写 Timer、Pusher、Scheduler 或 Agentor 私有表。

### 12.1 `targetor_targets`

保存目标 ID、标题、描述、icon name、周期规则、max、position、created/updated/archived 时间。活动 position 连续；软归档行不参与活动排序。

### 12.2 `targetor_periods`

保存稳定 Period ID、Target ID、单调 sequence、start/end、周期规则快照、max 快照、创建/结算时间。`(target_id, start)` 与 `(target_id, sequence)` 均唯一。目标软归档不得级联删除周期。

### 12.3 `targetor_checkins`

保存稳定 Event ID、Target ID、Period ID 和 occurredAt。外键必须确保 event 的 target 与 period 所属目标一致。物理撤销只删除当前周期事件。

至少建立目标活动/position、周期 target/start/end、事件 period/time 索引。迁移只追加 Targetor 表和索引。

## 13. 并发、错误与恢复

- 载入、周期恢复、CRUD、设置排序、UI/CLI 打卡和撤销共用 Targetor mutation gate。
- mutation 开始前恢复过期周期；同一目标不能同时存在两个当前周期。
- 周期结算、事件写入或删除、内存发布必须遵守事务顺序；提交失败保持原 UI。
- Prompt 和 1 秒庆祝状态只能在提交成功后产生。
- 恢复损坏目标时隔离该目标并显示可见错误，不得清空其他目标。
- Lucide manifest 缺失或哈希不匹配时拒绝未知资源并显示占位错误，不改写已保存 icon name。
- 禁用卡片清除当前和待播 Targetor Prompt，但不销毁 Store。

## 14. 升级

- v2.1.0 将卡配置版本提升到 `4`。
- 新安装顺序：Timer、Pusher、Scheduler、Agentor、Targetor。
- v2.0.x 用户升级时保留已有启用状态、相对顺序和最近选择，把 Targetor 启用并追加到末尾。
- 不重新启用用户此前禁用的旧卡。
- 不创建示例推进项。
- Targetor 数据迁移失败时不得删除或重建 `Peeker.sqlite`。
- 公共 CLI protocol version 和 JSON schema version 继续为 `1`。

## 15. 验收清单

### 15.1 周期与数据

- [ ] 日/周/月边界覆盖任意周刷新日、`0=月末`、短月、DST 和时区变化。
- [ ] 创建目标从创建时刻进入部分周期，创建前日期不参与历史。
- [ ] 多周期离线恢复补齐 0 次周期且幂等，不发布 Prompt。
- [ ] 周期规则编辑立即结算并清零；普通字段和 max 编辑不清零。
- [ ] 降低 max 不删除事件，完成度封顶并禁止继续打卡。
- [ ] 修改全局刷新时刻只影响当前周期之后的新周期。
- [ ] 软归档保留历史周期与汇总，活动列表不再显示。

### 15.2 UI 与动画

- [ ] `960×480pt`、左 75%/右 25%、3 列卡片和内部滚动符合设计。
- [ ] 拖拽只可向右打卡，不可排序；完成项不可拖起，取消不写库。
- [ ] 未开始、起始、行进、完成的玻璃描边和 hover 行为可区分。
- [ ] 三类预览和 1 秒反馈正确；Reduce Motion 无循环位移、旋转、缩放和扫光。
- [ ] 9 列汇总、等权平均、五级色阶和未来空格符合规则。
- [ ] 日/月/周悬停日历正确，周周期跨月色相一致。

### 15.3 CLI 与提示

- [ ] root、Targetor、config 和每个叶命令均有不依赖 App 的分级帮助。
- [ ] 标题重名返回候选 ID；周期参数、max 和 icon 校验确定。
- [ ] UI 与 CLI checkin 原子加一，达到 max 后返回冲突且不写库。
- [ ] checkin 返回 event ID；uncheck 只物理删除当前周期指定事件。
- [ ] history 默认当前周期，自定义 from/to 成对且为半开区间。
- [ ] UI/CLI 成功打卡提交后各发布一条 Prompt；撤销和恢复不提示。
- [ ] 禁用 Targetor 后无 Compact 或 Prompt，但 CLI 数据操作仍工作。

### 15.4 资源、迁移与隔离

- [ ] Lucide v1.27.0 完整目录可离线搜索和渲染，未知名称拒绝。
- [ ] manifest、哈希、MIT/ISC 许可和 Bundle 资源验证通过。
- [ ] Targetor 默认启用并追加在 Agentor 后，旧卡顺序和禁用状态不变。
- [ ] Targetor migration、Repository 和 Store 不修改其他功能卡数据。
- [ ] 写入失败不改变计数、日历、庆祝状态或 Prompt 队列。
