# Checkpoint — Post-C6 Whole-Codebase Hardening

**Spec:** `Aurora_Post_C6_Whole_Codebase_Audit_Remediation.md`  
**Date:** 2026-08-15  
**Status:** Implementation complete — **STOP before Programmer Color Engine / Advanced MIDI**

---

## Summary

Focused pre–Programmer/MIDI hardening pass. No rewrite of C4 Stage, C5 float architecture, or C6 splash design.

| Pass | Status |
|------|--------|
| P0 engine frame serialization | Done |
| P0 schema-aware package integrity | Done |
| P0 trapping dictionary removal | Done |
| P0 Stage media collision safety | Done |
| P1 ENTTEC / Art-Net / sACN | Done |
| P1 library package integrity | Done |
| P1 real splash/float policy tests | Done |
| P1 Stage error reporting | Done |
| P2 dead StagePanel path / WindowCloseProxy | Done |
| P2 presentation revision skip | Done |
| Native build/tests | Done (503 tests) |

---

## P0 fixes

### LightingEngine frame pipeline
- Dedicated `frameQueue` serializes all frame bodies (scheduler + panic/unfreeze/clear/test).
- Panic/unfreeze use synchronous wait for immediate physical output.
- `stop()` disables frames then barriers the queue so no post-stop flush.
- Class-level threading contract documented.
- `LightingEngineFrameSerializationTests` — concurrent panic/clear/freeze, monotonic index, post-stop no flush.

### ProjectPackage required files
- Schema-aware: v2+ requires `stage-layout.json`; v3+ requires MIDI extension files; current schema requires `effects.json`.
- Missing current-schema files → package damage error (not silent empty).
- Tests for missing Stage/MIDI/effects + legacy v1 still loads without stage.

### Dictionary traps
- `EffectRunner.load` first-wins (no trap).
- `ProgrammerPanel.fixtureNames` first-wins.
- `StageMediaSupport.materializeStageMedia` first-wins map.
- Validator: `duplicate-media-relative-path`.

### Stage media
- Legacy absolute paths → UUID filenames (not basename).
- Dual `logo.png` migration test.
- Path-component package containment (not string prefix).

---

## P1 fixes

### ENTTEC
- Transport `ioLock` around open/write/close.
- `POSIXWrite.completeWrite` partial-write loop + EINTR retry.
- Generic serial → `deviceType: .other` (only DMX/ENTTEC name → Pro).
- `universeFilter` private locked storage.

### Art-Net
- Startup timeout → **degraded**, never ready.
- `stateUpdateHandler` updates health across lifecycle.
- Queue-safe startup box for error/ready flags.

### sACN
- Connection create/store under lock; key `host:port`.

### Library package
- Required content files; no silent `?? []`.
- Backup/replace save path.
- Size limit on JSON.
- Missing palettes fails load (test).

### Splash / float tests
- `LaunchSplashPolicy` + `FloatWindowClosePolicy` in AuroraUI.
- Production constants + auto-dismiss / max-hold / redock-vs-quit decisions tested.

### Stage errors
- `StageCanvasView.commitLayout` reports status note (no empty catch).

---

## P2 / cleanup

- Removed dead `stageMainRow` / production `StagePanel` host from `BuildWorkspaceHost`.
- Removed unused `WindowCloseProxy`.
- `ProgrammerPresentationStore.refresh` skips revision when presentation equal.
- Checkpoint tooling may still reference StagePanel under DEBUG exporters — non-production.

### Deferred (documented, not blockers)

- Full IOKit VID/PID ENTTEC identification (hardware smoke).
- Broad `notifyUI()` inventory instrumentation (measurement-first; presentation equality skip landed).
- Incremental strict concurrency enablement module-by-module.
- Mechanical `try?` classification sweep across all UI commands.

---

## Verification

```text
swift test                          → 503 tests, 0 failures
swift build --target Aurora         → success
xcodebuild -scheme Aurora (macOS)   → success (after xcodegen)
```

---

## STOP

> **Do not begin Programmer Color Engine or Advanced MIDI Engine until this checkpoint is accepted.**

C4–C6 UX remains closed. Next feature work starts only after human review of this hardening pass.
