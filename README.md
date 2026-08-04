# Peeker

Peeker is a native macOS 26 dynamic-island utility for low-distraction daily progress. It runs as a single local process with no Dock or menu-bar icon and provides two independent cards:

- Timer accumulates real elapsed time against daily goals, including sleep, restart and business-day recovery.
- Pusher is a three-column daily board whose status changes are driven by drag and drop.

The app uses Swift 6, SwiftUI, a narrow AppKit panel bridge, SwiftPM, GRDB 7.11.1 and one SQLite database. See [the architecture](docs/ARCHITECTURE.md) and [local acceptance guide](docs/LOCAL_ACCEPTANCE.md).

## Local development

On a new checkout, bootstrap SwiftPM dependencies once in a networked environment:

```bash
./scripts/bootstrap-dependencies.sh
```

After that, application builds are locked to `Package.resolved` and do not perform
automatic dependency updates or remote fetches:

```bash
swift test --disable-automatic-resolution
./script/build_and_run.sh
```

The run script creates `dist/Peeker.app` and opens it as a real GUI bundle. It
supports `--debug`, `--logs`, `--telemetry` and `--verify` modes. To open the
last successfully built bundle without compiling, use:

```bash
./script/build_and_run.sh run-existing
```

If the local checkout or `Package.resolved` is missing, the build stops with an
instruction to run the explicit bootstrap command instead of downloading GRDB
implicitly.

## Install / 安装

Peeker v1 supports Apple Silicon Macs running macOS 26 or later. Install the
public release directly from the project Tap:

Peeker v1 支持运行 macOS 26 或更高版本的 Apple Silicon Mac。可直接从项目
Tap 安装公开版本：

```bash
brew install --cask SCPZ24/peeker/peeker
```

The fully-qualified command automatically registers the Tap. Afterwards the
short cask name can be used for upgrades or reinstalls:

完整命令会自动注册 Tap，之后升级或重新安装可以使用短名称：

```bash
brew upgrade --cask peeker
brew reinstall --cask peeker
```

Peeker is ad-hoc signed and is not notarized because the project does not have
an Apple Developer ID. The first launch will be blocked by Gatekeeper. After
trying to open Peeker once, go to **System Settings → Privacy & Security**, click
**Open Anyway** for Peeker, and confirm **Open**. Do not disable Gatekeeper or
remove the quarantine attribute globally.

由于项目没有 Apple Developer ID，Peeker 使用 ad-hoc 签名且未经 Apple 公证。
首次启动会被 Gatekeeper 拦截。尝试启动一次后，前往**系统设置 → 隐私与安全**，
为 Peeker 点击**仍要打开**，然后确认**打开**。无需关闭 Gatekeeper，也不要全局
移除 quarantine 属性。

## Build a release candidate

```bash
./scripts/package-release.sh 1.0.0
./scripts/verify-bundle.sh
./scripts/verify-cask.sh 1.0.0
```

Without `PEEKER_SIGN_IDENTITY`, the app is ad-hoc signed. The release version
argument must match `CFBundleShortVersionString`; the packaging script refuses
to create a mismatched archive. See [the release guide](docs/RELEASING.md).

Peeker is licensed under the MIT License. Atoll is an interaction reference only; Peeker does not copy its GPL source, assets, sounds or animation parameters.
