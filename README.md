<div align="center">
  <img src="LOGO.png" alt="Peeker Logo" width="160" />

  # Peeker

  极简、轻量的 MacBook 灵动岛

  [English](README_EN.md)
</div>

完全使用 Swift 实现的 macOS 原生效率工具。

> 当前稳定实现与下方截图属于 **v1**，包含 Timer 和 Pusher。Scheduler、静息岛、统一提示和 `peeker` CLI 正在按 [v2 设计文档](docs/v2/PRD.md)规划，尚不可用。

## 运行效果（v1）

收敛时贴在屏幕顶部：

<p align="center">
  <img src="assets/fold.png" alt="v1 收敛状态" width="50%" />
</p>

鼠标移入灵动岛后展开功能卡：

| 展开状态 | 任务卡片 |
| --- | --- |
| ![v1 展开状态](assets/unfold.png) | ![v1 任务卡片](assets/unfold1.png) |

## 安装当前稳定版

```bash
brew install --cask SCPZ24/peeker/peeker
```

首次启动后，请前往“系统设置 → 隐私与安全”，选择信任 Peeker。

## 文档

- [v1 产品需求](docs/v1/PRD.md)
- [v1 架构](docs/v1/ARCHITECTURE.md)
- [v2 增量需求](docs/v2/PRD.md)
- [v2 功能卡设计](docs/functions/)

## 贡献

欢迎提交 Issue 汇报 Bug、提出 Feature Request，或直接发起 PR。
