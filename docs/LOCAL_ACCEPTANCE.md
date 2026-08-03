# Local acceptance

Peeker stops at a local, unpublished build in this round.

## Required checks

On a fresh checkout, resolve dependencies explicitly once:

```bash
./scripts/bootstrap-dependencies.sh
```

The application build path is offline after that bootstrap. It requires the
project `Package.resolved` and the project-local GRDB checkout, and fails
early if either is missing.

```bash
swift package describe
swift build --disable-sandbox --disable-automatic-resolution
swift test --disable-sandbox --disable-automatic-resolution
bash -n script/*.sh scripts/*.sh
./Tests/Shell/build_script_contract.sh
./scripts/package-release.sh 1.0.0
./scripts/verify-bundle.sh
./scripts/verify-cask.sh 1.0.0
```

The Codex Run action calls `./script/build_and_run.sh`. The generated app is
`dist/Peeker.app`; local builds use ad-hoc signing when `PEEKER_SIGN_IDENTITY`
is not set. To inspect the existing bundle without invoking SwiftPM, run
`./script/build_and_run.sh run-existing`.

## Xcode conditional check

```bash
xcodebuild -version
xcodebuild -scheme Peeker -destination 'platform=macOS' build
```

If `xcodebuild -version` reports that the active developer directory is Command Line Tools, record `SKIPPED-XCODE` and rerun these commands after installing or selecting a complete Xcode. Do not use that skip for Swift compiler, package, database, script or Cask failures.

## Manual hardware checks

- Verify the island on notched and non-notched displays.
- Disconnect the selected external display and confirm immediate fallback without automatic return.
- Exercise hover, pin, Escape, outside click, Popovers, text editing and drag blockers.
- Start a Timer, sleep the Mac through its target, and verify one completion sound after wake.
- Quit with a Timer running, relaunch after its target, and verify completion without a stale sound.
- Move Pusher tasks within and across columns and relaunch to verify order.
- Check all Spaces and full-screen applications.
- Toggle the login item and compare the UI with macOS System Settings.

No tag, push, pull request, GitHub Release or Homebrew Tap mutation is part of local acceptance.
