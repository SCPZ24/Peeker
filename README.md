<div align="center">
  <img src="LOGO.png" alt="Peeker Logo" width="160" />

  # Peeker

  极简、轻量的 MacBook 灵动岛

  [English](README_EN.md)
</div>

完全使用 Swift 实现的 macOS 原生效率工具。

> 当前公开版本为 **v2.0.1**：包含静息岛、Timer 运行收敛态、统一提示、Scheduler 和 `peeker` CLI。下方截图是 v1 历史截图。

## 运行效果（v1）

收敛时贴在屏幕顶部：

<p align="center">
  <img src="assets/fold.png" alt="v1 收敛状态" width="50%" />
</p>

鼠标移入灵动岛后展开功能卡：

| 展开状态 | 任务卡片 |
| --- | --- |
| ![v1 展开状态](assets/unfold.png) | ![v1 任务卡片](assets/unfold1.png) |

## 安装当前公开稳定版

```bash
brew install --cask SCPZ24/peeker/peeker
```

Cask 会安装 App，并将内置 CLI 暴露为 `peeker`：

```bash
peeker --version
peeker status
```

除 `--version` 和 `status` 外，CLI 命令要求 App 已运行；CLI 不会启动 App 或直接打开 SQLite。首次启动后，请前往“系统设置 → 隐私与安全”，选择信任 Peeker。

## 文档

- [v1 产品需求](docs/v1/PRD.md)
- [v1 架构](docs/v1/ARCHITECTURE.md)
- [v2 增量需求](docs/v2/PRD.md)
- [v2 架构](docs/v2/ARCHITECTURE.md)
- [v2 功能卡设计](docs/functions/)

## 贡献

欢迎提交 Issue 汇报 Bug、提出 Feature Request，或直接发起 PR。
