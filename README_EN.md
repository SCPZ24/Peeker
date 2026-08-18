<div align="center">
  <img src="LOGO.png" alt="Peeker Logo" width="160" />

  # Peeker

  A minimal, lightweight Dynamic Island for MacBook.

  [中文](README.md)
</div>

A native macOS productivity tool built entirely with Swift.

> The current stable implementation and screenshots below are **v1**, with Timer and Pusher. Scheduler, the resting island, unified prompts, and the `peeker` CLI are planned in the [v2 design](docs/v2/PRD.md) and are not available yet.

## Preview (v1)

The compact surface stays attached to the top of the screen:

<p align="center">
  <img src="assets/fold.png" alt="v1 compact state" width="50%" />
</p>

Hover over the island to expand its feature cards.

| Expanded state | Task card |
| --- | --- |
| ![v1 expanded state](assets/unfold.png) | ![v1 task card](assets/unfold1.png) |

## Install the current stable release

```bash
brew install --cask SCPZ24/peeker/peeker
```

After the first launch, go to **System Settings → Privacy & Security** and choose to trust Peeker.

## Documentation

- [v1 product requirements](docs/v1/PRD.md)
- [v1 architecture](docs/v1/ARCHITECTURE.md)
- [v2 incremental requirements](docs/v2/PRD.md)
- [v2 feature-card designs](docs/functions/)

## Contributing

Bug reports and feature requests are welcome through Issues. Pull requests are welcome too.
