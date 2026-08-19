<div align="center">
  <img src="LOGO.png" alt="Peeker Logo" width="160" />

  # Peeker

  极简、轻量的 MacBook 灵动岛

  [English](README_EN.md)
</div>

完全使用 Swift 实现的 macOS 原生效率工具。

> 仓库当前实现为 **v2.0.0**：包含静息岛、Timer 运行收敛态、统一提示、Scheduler 和 `peeker` CLI。v2 尚未公开发行；Homebrew 公共稳定版在正式发布前仍可能是 v1.0.4。下方截图是 v1 历史截图。

## 运行效果（v1）

收敛时贴在屏幕顶部：

<p align="center">
  <img src="assets/fold.png" alt="v1 收敛状态" width="50%" />
</p>

鼠标移入灵动岛后展开功能卡：

| 展开状态 | 任务卡片 |
| --- | --- |
| ![v1 展开状态](assets/unfold.png) | ![v1 任务卡片](assets/unfold1.png) |

## 本地 v2 CLI

本地构建的 `Peeker.app` 内含 `Contents/MacOS/peeker-cli`。App 必须已运行；CLI 不会启动 App 或直接打开 SQLite。

```bash
./dist/Peeker.app/Contents/MacOS/peeker-cli --version
./dist/Peeker.app/Contents/MacOS/peeker-cli status
```

## 安装当前公开稳定版

```bash
brew install --cask SCPZ24/peeker/peeker
```

首次启动后，请前往“系统设置 → 隐私与安全”，选择信任 Peeker。

## 文档

- [v1 产品需求](docs/v1/PRD.md)
- [v1 架构](docs/v1/ARCHITECTURE.md)
- [v2 增量需求](docs/v2/PRD.md)
- [v2 架构](docs/v2/ARCHITECTURE.md)
- [v2 功能卡设计](docs/functions/)

## 贡献

欢迎提交 Issue 汇报 Bug、提出 Feature Request，或直接发起 PR。
