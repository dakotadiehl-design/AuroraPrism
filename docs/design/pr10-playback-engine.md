# PR10 — Playback Engine & Scheduler

| Field | Value |
|-------|--------|
| **PR** | PR10 |
| **Status** | Implemented |
| **Depends on** | PR9 |
| **Unlocks** | PR11 cue engine, PR13 programmer |

## Delivered

- `EngineClock` (continuous + manual)
- `EngineConfiguration` (20–44 Hz, default 40)
- `EngineScheduler` (`DispatchSourceTimer`)
- `ActiveLook` + `MergeStub` (single look → DMX)
- `LightingEngine` load / setLook / start / stop / stepForTesting / snapshots
- Output flush via `OutputManager`
- App: null driver, engine start, status bar frame counter
- Demo look: full intensity on all patched fixtures after load

## Non-goals (still open)

- Cue fades / tracking (PR11)
- Programmer layer (PR13)
- Effects (PR22)
