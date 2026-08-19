# Local acceptance — v2.0.0

This checklist validates the repository's local v2 implementation. It does not publish a tag, GitHub Release, formal ZIP, or external Homebrew Tap update.

## Automated gate

After the one-time dependency bootstrap, normal checks are offline:

```bash
swift package describe
swift build --disable-sandbox --disable-automatic-resolution
swift build --disable-sandbox --disable-automatic-resolution -c release
swift test --disable-sandbox --disable-automatic-resolution
bash -n script/*.sh scripts/*.sh Tests/Shell/*.sh
./Tests/Shell/build_script_contract.sh
./Tests/Shell/feature_boundary_contract.sh
./Tests/Shell/release_script_contract.sh
plutil -lint Resources/Info.plist Resources/Peeker.entitlements
./scripts/build-app.sh release
./scripts/verify-bundle.sh dist/Peeker.app 2.0.0
```

Validate Cask syntax from a temporary archive under `.build/verification`; do not run `package-release.sh` for local v2 acceptance.

## CLI process boundary

Before starting the App:

- `peeker-cli --version` exits 0 with CLI `2.0.0`, protocol `1`, schema `1`.
- `peeker-cli status` exits 0 with `running:false`.
- A feature command exits 3 with `app_not_running`.
- These commands do not create or modify `Peeker.sqlite`.

After starting the verified Bundle, `status` must report `running:true`, App `2.0.0`, protocol `1`, and a positive pid. Run non-destructive `timer config get`, `pusher config get`, and `scheduler config get` to verify routing.

## Upgrade safety

Before first v2 launch:

1. Stop all Peeker processes.
2. Copy `~/Library/Application Support/Peeker/` and `com.scpz24.Peeker` preferences to `dist/pre-v2-backup-<timestamp>/`.
3. Run read-only `PRAGMA integrity_check` against the backup SQLite database when present.
4. Abort launch if any copy or integrity check fails.

After launch verify Timer/Pusher data and active Timer state remain present, prior disabled cards remain disabled, and Scheduler is appended and enabled once.

## Manual hardware checks

- Notched display: Resting hit region covers the top safe area and extends 16pt beyond both notch sides; no black surface or seam is visible.
- Non-notched display: only the centered `220×8pt` Resting region intercepts hover; surrounding menu-bar controls remain clickable.
- Timer shows Compact only while running. Pause, completion, deletion, or day transition returns to Resting when no other card is eligible.
- Pusher and Scheduler never show Compact.
- Prompt is silent, top-attached, single-line, FIFO, six seconds per item, and starts 1.5 seconds after expansion fully ends.
- Hovering Prompt consumes it and opens its source card. Disabling a card clears its prompts.
- Exercise hover, pin, Escape, outside click, Popovers, text editing, Pusher drag blockers, rapid animation reversal, and Reduce Motion.
- Sleep through a Timer target and Scheduler reminder; state must recover without stale Prompt or sound.
- Verify Pusher optimistic drag success and failure rollback. Create/delete/cross-column move prompt; edit and same-column reorder do not.
- Scheduler: Monday-first week, all-day/timed/cross-midnight events, overlap visibility, 15-minute creation, editor CRUD, recurrence scopes, ICS import/refresh/relocation/removal, and reminder off/1–60.
- Test Retina scaling, negative-origin external displays, Spaces, full-screen apps, screen disconnect fallback, and both notched/non-notched geometry.

Xcode may be recorded as `SKIPPED-XCODE` only for the known IDE plug-in failure before project loading. SwiftPM, database, script, Bundle, or Cask failures are not skippable.
