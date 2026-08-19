# Peeker v2 Architecture

## Target graph

```text
PeekerApp
  ├─ FunctionCardKit / FeatureRuntimeKit / MacPlatform
  ├─ PeekerProtocol / PeekerIPC
  ├─ TimerModule ─ TimerFeature ─ TimerGRDBAdapter
  ├─ PusherModule ─ PusherFeature ─ PusherGRDBAdapter
  └─ SchedulerModule ─ SchedulerFeature ─ SchedulerGRDBAdapter

peeker-cli ─ PeekerProtocol ─ PeekerIPC
```

Framework targets do not import concrete features. `BuiltInFeatureModules.swift` is the only App assembly point.

## UI and CLI data flow

```text
SwiftUI intent ─┐
                ├─ Feature Store mutation boundary → Repository transaction → published state
CLI → UDS IPC ──┘                                      └→ Prompt/reminder reschedule
```

The App is the only process that opens `Peeker.sqlite`. The CLI parses only the top-level command, performs protocol handshake, and forwards feature arguments to the corresponding module handler. Module handlers call the same Store used by SwiftUI.

## IPC and security

- Socket: current user's temporary directory, `com.scpz24.Peeker/ipc-v1.sock`.
- Parent directory mode `0700`; socket mode `0600`.
- Server validates peer euid with `getpeereid`.
- Frames are 4-byte big-endian length plus UTF-8 JSON, limited to 16 MiB.
- Each connection performs one protocol handshake and one request/response.
- The CLI never starts the App and never links GRDB.

Protocol version and JSON schema version are both `1` for v2.0.0.

## Island and prompts

`CardRegistry` owns enabled order, current selection, and last-opened timestamps. A registration may omit Compact entirely. Eligible Compact cards are selected by most recent user open, then enabled order. Built-in v2 behavior is:

- Timer: Compact only while one current task is running.
- Pusher: no Compact.
- Scheduler: no Compact.

Without an eligible card, the panel uses the transparent Resting hit region. `PromptCenter` owns a 100-item in-memory FIFO, stable-token revocation, six-second playback, and the 1.5-second post-expansion delay. Disabling a card clears that source's prompts.

## Time scheduling

`TemporalEventHub` owns one platform timer and orders simultaneous events by date and priority. Trigger reasons distinguish normal scheduled callbacks from wake and clock/time-zone recovery. Recovery updates business state and future Scheduler reminders without replaying stale prompts. Timer target priority remains above business-day boundary priority.

Scheduler keeps only its next reminder in the hub. Occurrences and reminders are generated lazily; they are not persisted.

## Scheduler persistence boundary

Migration `scheduler-schema-v1` only adds:

- `scheduler_sources`
- `scheduler_events`
- `scheduler_occurrence_overrides`

Timer/Pusher/shared v1 tables are unchanged. Repeating occurrences are expanded from roots and complete overrides. ICS source refresh is grouped by `(source ID, UID)`: valid UIDs replace source data, recognizable invalid UIDs protect previous data, and file-level or transaction failure preserves the previous source snapshot.

## Adding an internal card

1. Add Feature, optional GRDB Adapter, and Module targets.
2. Keep domain and Store free of GRDB records.
3. Return `FunctionCardRuntimeRegistration` with UI registration, command handler, and lifecycle callbacks.
4. Declare Compact only when the feature has a real-time eligibility condition.
5. Publish prompts through host actions and use stable tokens where later revocation is required.
6. Add the module only in `BuiltInFeatureModules.swift` and update the feature-boundary contract.
