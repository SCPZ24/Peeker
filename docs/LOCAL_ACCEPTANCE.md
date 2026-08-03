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

- On a notched MacBook, verify compact and expanded surfaces meet the physical top edge with no bright or transparent seam and fully cover the camera region. On the current `1512 × 982pt @2x` built-in display, verify the system-reported top safe inset is `32pt` and the compact surface is exactly `32pt` high.
- Record expansion and collapse at 60 fps and inspect the start, 25%, 50%, 75%, and end frames. The visible black surface must remain top-centered in every frame; it must not appear first as a detached box and snap to the top only at the end.
- Rapidly enter and leave while expansion or collapse is still running. Confirm the animation reverses from its current visual state and an old completion does not resize the newly expanded island.
- In compact Timer, verify the color dot and task name stay left of the physical notch, the remaining time stays right of it, and no progress bar appears; verify the completed and unconfigured variants too. On the current built-in display, the expected width is approximately `369pt` (`(144 - 64) × 2 + 189 + 20`). Both wings are compressed by `64pt` while keeping the notch exactly centered; long task names may truncate but must not enter the camera region.
- In compact Pusher, verify orange Planned and green Done stay left of the physical notch; only the red urgent, blue progress, and yellow planning counts stay right of it, including the all-zero state. The Processing total must not be displayed, while the three visible counts must still sum to Processing. On the current built-in display, the expected width is approximately `449pt` (`(184 - 64) × 2 + 189 + 20`). Compact content may tighten within each `120pt` wing but must not enter the camera region.
- On a non-notched display, verify the island remains top-attached with the same soft-rectangle silhouette and the compact summary has no artificial center gap.
- Verify compact corners are visibly flatter than a capsule and expanded corners remain a larger soft rectangle.
- In expanded Timer and Pusher, verify card borders are fully visible and the feature tabs and settings gear remain comfortably inside the soft-rectangle outline; the gear should have at least `28pt` trailing clearance.
- Test Retina and scaled resolutions and a display whose global frame origin is negative; the island must remain horizontally centered and top-attached.
- Disconnect the selected external display and confirm immediate fallback without automatic return.
- Exercise hover, pin, Escape, outside click, Popovers, text editing and drag blockers.
- Start a Timer, sleep the Mac through its target, and verify one completion sound after wake.
- Quit with a Timer running, relaunch after its target, and verify completion without a stale sound.
- Prepare at least three Planned tasks, two Processing tasks and one Done task. Move Planned into empty and nonempty target columns at the head, middle and tail; move the first task of one column to its tail, the tail task to its head, and swap adjacent tasks. Every accepted drop must visually settle before persistence finishes and must survive relaunch in the same order.
- Cancel a Pusher drag outside the island and confirm that no task or compact count changes. With a failing test repository, confirm that the optimistic destination appears first, then the task animates back to its exact source position with the visible recovery error.
- Drag ordinary text or another app's content over a Pusher column and confirm that Peeker advertises no move and changes no task. During a deliberately suspended move/recovery test, confirm that a second drag and task CRUD remain disabled until persistence and deferred recovery both finish.
- Record a Pusher drop at 60 fps and inspect the first three frames after mouse-up. The task must not remain as a suspended drag preview for roughly half a second, and a successful CRUD completion must not cause a second jump.
- Check all Spaces and full-screen applications.
- Toggle the login item and compare the UI with macOS System Settings.

No tag, push, pull request, GitHub Release or Homebrew Tap mutation is part of local acceptance.
