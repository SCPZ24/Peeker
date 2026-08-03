# Verification record — 2026-08-03

## Passed

- `swift package --disable-sandbox describe` — package graph resolved.
- `swift test --disable-sandbox` — 26 tests, 0 failures.
- `swift build --disable-sandbox` and release product build — passed.
- `bash -n script/*.sh scripts/*.sh` — passed.
- `plutil -lint Resources/Info.plist Resources/Peeker.entitlements` — passed.
- `./scripts/verify-bundle.sh` — plist and ad-hoc code signature passed; Gatekeeper rejection is expected for the intentionally unnotarized local artifact.
- `./scripts/verify-cask.sh 1.0.0` — Ruby syntax passed and Homebrew inspected one Cask with no offenses.
- Release candidate generated locally at `dist/Peeker.app` and `dist/Peeker-v1.0.0.zip`; `dist/` is gitignored and nothing was uploaded.
- Offline application build contract — passed: `scripts/build-app.sh` requires `Package.resolved`, requires the project-local GRDB checkout, and builds with `--disable-automatic-resolution`.
- Existing-bundle run path — added: `./script/build_and_run.sh run-existing` opens `dist/Peeker.app` without invoking SwiftPM.

The package lock is now present in `Package.resolved` at GRDB.swift 7.11.1. The
explicit `scripts/bootstrap-dependencies.sh` command is the only documented
networked dependency setup path; normal application builds do not perform
automatic dependency resolution or updates.

## SKIPPED-XCODE

Command:

```bash
xcodebuild -scheme Peeker -destination 'platform=macOS' -derivedDataPath .build/XcodeDerivedData -clonedSourcePackagesDirPath .build/XcodePackages build
```

Exit code: `70`

Minimal error:

```text
Failed to load code for plug-in com.apple.dt.IDESimulatorFoundation.
Symbol not found in /Library/Developer/PrivateFrameworks/DVTDownloads.framework.
xcodebuild failed to load a required plug-in.
```

Classification: Xcode 26.6 installation/system-content mismatch before project loading. No project source was compiled by this invocation.

Skipped validation: Xcode’s Swift Package scheme build and Xcode-hosted UI tests.

Rerun after the user has completed Xcode first-launch setup or repaired the installation:

```bash
xcodebuild -version
xcodebuild -scheme Peeker -destination 'platform=macOS' -derivedDataPath .build/XcodeDerivedData -clonedSourcePackagesDirPath .build/XcodePackages build
```

Codex did not run `xcodebuild -runFirstLaunch`, reinstall Xcode or switch toolchains.
