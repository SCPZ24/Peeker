# 产品概念文档


> 一个只适配MacOS的灵动岛应用。


技术栈：
- 桌面应用：SwiftUI
- 后端：Swift
- 分发：brew

最终产品是一个应用程序而不是一个web项目或是CLI/TUI工具。
当前，我们接受用户安装(brew --cask install)并首次启动时，被MacOS系统弹出“未受信任”警告。


第一版产品分为两个页面
- 灵动岛（dynamic island）
- 设置页


## 灵动岛

整个灵动岛的视觉设计参考[Ebullioscopic/Atoll](https://github.com/Ebullioscopic/Atoll)。

1. 一个灵动岛，平时处于收敛显示状态，用户鼠标移动到岛上后展开详细状态。

2. 灵动岛展开后分为多个功能卡，通过顶部选项卡调节当前所处的功能卡页面。


## 设置页

设置页上可以做

1. 检查更新和退出应用

2. 选中启用，排序启用中的功能卡，以及完成功能卡详情设置。

功能卡的设计放在docs/functions/。


## 后端

负责SQLite的CRUD以及其他service逻辑。