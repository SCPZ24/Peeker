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

## Local release candidate

```bash
./scripts/package-release.sh 1.0.0
./scripts/verify-bundle.sh
./scripts/verify-cask.sh 1.0.0
```

Without `PEEKER_SIGN_IDENTITY`, the app is ad-hoc signed for local validation only. Public distribution, notarization, GitHub Release creation and Homebrew Tap updates are intentionally not performed in this development round.

## Future Homebrew installation

After an approved release is uploaded to the project’s own Tap:

```bash
brew install --cask peeker
```

Peeker is licensed under the MIT License. Atoll is an interaction reference only; Peeker does not copy its GPL source, assets, sounds or animation parameters.
