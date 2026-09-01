# Verification record — 2026-09-01 — v2.1.0

## Passed

- `swift test --filter FunctionCardKitTests` — **43 tests, 0 failures**.
- `swift test --filter Timer` — **43 tests, 0 failures**.
- `swift test --filter Targetor` — **11 tests, 0 failures**.
- `swift package describe` completed and includes Targetor Feature/GRDBAdapter/Module targets and tests.
- Debug and release `swift build --disable-sandbox --disable-automatic-resolution` both passed.
- `swift test --disable-sandbox --disable-automatic-resolution` — **261 tests, 0 failures**.
- Shell syntax, build-script, feature-boundary, CLI-help, and release-script contracts passed; both plist files passed `plutil -lint`.
- Pinned Lucide v1.27.0 inventory contains **1,756** manifest entries and SVG files; all SHA-256 values matched. `target`, `chevrons-up`, `rocket`, `badge-check`, and `circle` rendered through `sips`.
- `./scripts/build-app.sh release` built the three arm64 executables in an ad-hoc signed `dist/Peeker.app`.
- `./scripts/verify-bundle.sh dist/Peeker.app 2.1.0` passed Bundle version, CLI schema/protocol, icon/resource, executable, help, and strict signature checks. Gatekeeper rejection is expected for this local ad-hoc, unnotarized artifact.
- A temporary `.build/verification/Peeker-v2.1.0.zip` passed `verify-cask.sh 2.1.0`; Ruby syntax and Homebrew style reported no offenses, and the archive contains the embedded CLI and Targetor resources.
- `git diff --check` passed.

## CLI and migration boundary

With Peeker stopped:

- `peeker-cli --version` returned CLI `2.1.0`, protocol `1`, schema `1`.
- `status` returned `running:false`.
- Timer, Timer temporary, Pusher, Scheduler, and Targetor feature reads returned `app_not_running` with exit `3`.
- `peeker agentor list` remained unavailable and returned `invalid_usage` with exit `2`.

After launching the verified Bundle with an isolated Application Support root, `status` reported App `2.1.0`, protocol `1`, and a positive pid. Read routes succeeded for `timer config get`, `timer temporary list`, `pusher config get`, `scheduler config get`, `targetor config get`, and `targetor list`. End-to-end CLI mutations also succeeded for Timer temporary create/get/start/pause/update/list/delete and Targetor create/get/checkin/history/uncheck/update/delete/archive-list; both runs ended with SQLite integrity and foreign-key checks passing. The fresh SQLite database recorded:

```text
pusher-schema-v1
scheduler-schema-v1
targetor-schema-v1
timer-schema-v1
timer-temporary-schema-v1
v1
v2-feature-runtime-state
```

Legacy migration coverage also passed in the Timer/Pusher adapter suites, including old Timer sessions defaulting to daily and additive temporary-task migration.

## Not performed

- No formal ZIP under `dist/`, commit, tag, GitHub Release, external Tap update, or remote push was created.
- Notch/non-notch geometry, Timer dynamic-height animation, Targetor drag/hover/calendar visuals, Reduce Motion, multi-display/Spaces/full-screen behavior, and sleep/wake hardware scenarios remain manual checks in `docs/LOCAL_ACCEPTANCE.md`.
- No user-provided v2.0.2 Application Support/preferences backup was available for a destructive-copy upgrade rehearsal; additive legacy migration behavior is covered by automated database tests and the fresh-Bundle migration run above.

---

# Historical verification record — 2026-08-19 — v2.0.0

## Passed

- `swift package describe` — package graph includes protocol, IPC, CLI, Timer/Pusher/Scheduler three-layer targets and tests.
- `swift build --disable-sandbox --disable-automatic-resolution` — debug build passed.
- `swift build --disable-sandbox --disable-automatic-resolution -c release` — release build passed.
- `swift test --disable-sandbox --disable-automatic-resolution` — **186 tests, 0 failures**.
- `bash -n script/*.sh scripts/*.sh Tests/Shell/*.sh` — passed.
- `build_script_contract.sh`, `feature_boundary_contract.sh`, `release_script_contract.sh` — passed.
- `plutil -lint Resources/Info.plist Resources/Peeker.entitlements` — both valid.
- `./scripts/build-app.sh release` — built ad-hoc signed `dist/Peeker.app` with `Peeker` and `peeker-cli`.
- `./scripts/verify-bundle.sh dist/Peeker.app 2.0.0` — plist, arm64 binaries, CLI schema/version/protocol, and strict code signature passed. Gatekeeper rejection is expected for this local ad-hoc, unnotarized artifact.
- Temporary Cask archive under `.build/verification/` — Ruby syntax passed; `brew style` inspected one file with no offenses; embedded `peeker-cli` maps to command `peeker`.
- No formal `dist/Peeker-v2.0.0.zip`, tag, GitHub Release, external Tap update, or remote push was created.

## CLI process boundary

With Peeker stopped:

- `peeker-cli --version` returned schema `1`, CLI `2.0.0`, protocol `1`.
- `peeker-cli status` exited 0 with `running:false`.
- `peeker-cli timer list` exited 3 with `app_not_running`.
- Database mtime and size were unchanged by the offline module command.

After launching the already verified release Bundle with `./script/build_and_run.sh run-existing`:

```json
{"data":{"appVersion":"2.0.0","pid":77483,"protocolVersion":1,"running":true},"ok":true,"schemaVersion":1}
```

Read-only routes succeeded for `timer config get`, `pusher config get`, and `scheduler config get`. The App was intentionally left running for manual hardware acceptance.

## v1 backup and upgrade

Backup: `dist/pre-v2-backup-20260819-110950/`

- Application Support copied.
- Preferences plist copied and `defaults export` captured.
- SHA-256 manifest contains five files.
- Backup SQLite `PRAGMA integrity_check` returned `ok`.

After v2 launch, migrations are:

```text
v1
v2-feature-runtime-state
timer-schema-v1
pusher-schema-v1
scheduler-schema-v1
```

All v1 table row counts matched the backup after launch: business days, runtime pointers, Timer templates/instances/sessions/snapshots, and Pusher series/tasks/snapshots. Only the three Scheduler tables were appended. Card preference schema is `2`; enabled order is Timer, Pusher, Scheduler; recent card remains Timer.

## SKIPPED-XCODE

`xcodebuild -version` reported Xcode 26.6 (17F113). The requested scheme build exited `70` before project loading because `com.apple.dt.IDESimulatorFoundation` could not load: the installed framework expects a `DVTDownloads` symbol absent from `/Library/Developer/PrivateFrameworks/DVTDownloads.framework`.

This is the previously documented Xcode installation/system-content mismatch. No project source was compiled by this invocation. SwiftPM debug/release builds and tests are not skipped.

## Manual checks remaining

Notch/non-notch hit testing, menu-bar interaction, animation recording, Reduce Motion, multiple displays/Spaces/full-screen behavior, sleep-through-target behavior, Pusher drag visuals, and Scheduler visual overlap/Popover behavior require user hardware acceptance using `docs/LOCAL_ACCEPTANCE.md`.
