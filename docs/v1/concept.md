# Peeker v1 产品概念

> 文档状态：v1 历史概念。可验收规则以 [v1 PRD](PRD.md) 为准；v2 方向见 [v2 概念](../v2/concept.md)。

Peeker v1 是只适配 macOS 的顶部灵动岛应用。

技术栈：

- 桌面应用：SwiftUI；
- 业务与平台逻辑：Swift；
- 分发：Homebrew Cask。

v1 的最终产品是原生 App，不是 Web、CLI 或 TUI。用户通过 `brew install --cask SCPZ24/peeker/peeker` 安装；当前分发接受首次启动时由 macOS 显示未受信任警告，并要求用户在系统设置中手动放行。

v1 包含两个主要界面：

- 顶部灵动岛；
- 设置窗口。

## 灵动岛

灵动岛平时显示收敛摘要，鼠标移入后展开。展开态通过顶部标签在 Timer 和 Pusher 功能卡之间切换。

Atoll 只作为公开交互参考；许可证和独立实现边界以 v1 PRD 为准。

## 设置窗口

设置窗口用于：

1. 检查更新、退出应用、选择显示器和管理登录启动；
2. 启用、禁用和排序功能卡；
3. 编辑 Timer 与 Pusher 的功能配置。

## 本地数据

SQLite 保存任务、会话、业务日与快照，系统 Preferences 保存轻量配置。业务服务和数据访问位于 App 进程内。
