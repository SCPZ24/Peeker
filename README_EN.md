<div align="center">
  <img src="LOGO.png" alt="Peeker Logo" width="160" />

  # Peeker

  A minimal, lightweight Dynamic Island for MacBook.

  [中文](README.md)
</div>

A native macOS productivity tool built entirely with Swift.

> The repository now implements **v2.0.0**, including the resting island, Timer compact state, unified prompts, Scheduler, and the `peeker` CLI. v2 is not publicly released yet; the public Homebrew stable version may remain v1.0.4 until release. The screenshots below are historical v1 screenshots.

## Preview (v1)

The compact surface stays attached to the top of the screen:

<p align="center">
  <img src="assets/fold.png" alt="v1 compact state" width="50%" />
</p>

Hover over the island to expand its feature cards.

| Expanded state | Task card |
| --- | --- |
| ![v1 expanded state](assets/unfold.png) | ![v1 task card](assets/unfold1.png) |

## Local v2 CLI

The locally built `Peeker.app` contains `Contents/MacOS/peeker-cli`. The App must already be running; the CLI neither launches it nor opens SQLite directly.

```bash
./dist/Peeker.app/Contents/MacOS/peeker-cli --version
./dist/Peeker.app/Contents/MacOS/peeker-cli status
```

## Install the current public stable release

```bash
brew install --cask SCPZ24/peeker/peeker
```

After the first launch, go to **System Settings → Privacy & Security** and choose to trust Peeker.

## Documentation

- [v1 product requirements](docs/v1/PRD.md)
- [v1 architecture](docs/v1/ARCHITECTURE.md)
- [v2 incremental requirements](docs/v2/PRD.md)
- [v2 architecture](docs/v2/ARCHITECTURE.md)
- [v2 feature-card designs](docs/functions/)

## Contributing

Bug reports and feature requests are welcome through Issues. Pull requests are welcome too.
