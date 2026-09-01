# Local acceptance — v2.1.0

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
./Tests/Shell/cli_help_contract.sh
./Tests/Shell/release_script_contract.sh
plutil -lint Resources/Info.plist Resources/Peeker.entitlements
./scripts/build-app.sh release
./scripts/verify-bundle.sh dist/Peeker.app 2.1.0
```

Validate Cask syntax from a temporary archive under `.build/verification`; do not run `package-release.sh` for local v2 acceptance.

## CLI process boundary

Before starting the App:

- `peeker-cli --version` exits 0 with CLI `2.1.0`, protocol `1`, schema `1`.
- `peeker-cli status` exits 0 with `running:false`.
- A feature command exits 3 with `app_not_running`.
- These commands do not create or modify `Peeker.sqlite`.

After starting the verified Bundle, `status` must report `running:true`, App `2.1.0`, protocol `1`, and a positive pid. Run non-destructive `timer config get`, `timer temporary list`, `pusher config get`, `scheduler config get`, `targetor config get`, and `targetor list` to verify all five feature routes. `peeker agentor` must remain an unknown public feature.

## Upgrade safety

Before first v2 launch:

1. Stop all Peeker processes.
2. Copy `~/Library/Application Support/Peeker/` and `com.scpz24.Peeker` preferences to `.build/verification/pre-v2.1-backup-<timestamp>/`.
3. Run read-only `PRAGMA integrity_check` against the backup SQLite database when present.
4. Abort launch if any copy or integrity check fails.

After launch verify existing Timer/Pusher/Scheduler data and active Timer state remain present, prior disabled cards remain disabled, Targetor is appended and enabled exactly once, and `temporaryTasksEnabled` initializes false. Confirm the additive `timer-temporary-schema-v1` and `targetor-schema-v1` migrations do not change unrelated table row counts.

## Manual hardware checks

- Notched display: Resting hit region covers the top safe area and extends 16pt beyond both notch sides; no black surface or seam is visible.
- Non-notched display: only the centered `220×8pt` Resting region intercepts hover; surrounding menu-bar controls remain clickable.
- Timer shows Compact for either a daily or temporary running task. Agentor may also compete for Compact; Pusher, Scheduler, and Targetor never do.
- Toggle Timer temporary-task creation and verify the expanded panel changes between `800×328.571pt` and `800×371.429pt` without moving its top edge.
- Verify temporary creation/edit/delete, all four expire-on-refresh states, non-expiring carry, boundary session continuation, and snapshot-before-archive behavior.
- Prompt is silent, top-attached, single-line, FIFO, six seconds per item, and starts 1.5 seconds after expansion fully ends.
- Hovering Prompt consumes it and opens its source card. Disabling a card clears its prompts.
- Exercise hover, pin, Escape, outside click, Popovers, text editing, Pusher drag blockers, rapid animation reversal, and Reduce Motion.
- Sleep through a Timer target, Targetor period boundary, and Scheduler reminder; state must recover without stale Prompt or sound.
- Verify Pusher optimistic drag success and failure rollback. Create/delete/cross-column move prompt; edit and same-column reorder do not.
- Scheduler: Monday-first week, all-day/timed/cross-midnight events, overlap visibility, 15-minute creation, editor CRUD, recurrence scopes, ICS import/refresh/relocation/removal, and reminder off/1–60.
- Targetor: drag envelope rejection after period recovery, one-second success feedback, no Compact, icon search by canonical name/tags, daily/weekly/monthly calendars, latest-start period selection, and no stale recovery Prompt.
- Verify Lucide `target`, `chevrons-up`, `rocket`, `badge-check`, and a representative ordinary icon render from the offline Bundle; Reduce Motion must remove looping movement while retaining static semantics.
- Test Retina scaling, negative-origin external displays, Spaces, full-screen apps, screen disconnect fallback, and both notched/non-notched geometry.

Xcode may be recorded as `SKIPPED-XCODE` only for the known IDE plug-in failure before project loading. SwiftPM, database, script, Bundle, or Cask failures are not skippable.
