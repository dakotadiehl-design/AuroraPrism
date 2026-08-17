# Checkpoint — Phase D: AME Core (closeout)

**Date:** 2026-08-16  
**Status:** **CLOSEOUT COMPLETE** (residual mode/document/dry-run fixes landed with Phase E closeout)  
**Reviews:**
- Phase D Pass 1 implementation
- `Aurora_PhaseC_Closeout_PhaseD_Pass1_Deep_Review_Fixes.md` (fixes landed)
- `Aurora_PhaseD_Closeout_PhaseE_Pass1_Deep_Review_Fixes.md` (mode/document provenance + dry-run isolation)

**Suite:** see Phase E checkpoint for latest count

---

## Phase C

**ACCEPTED** (external MIDI timing authority lifecycle). See Phase C checkpoint.

---

## Phase D closeout (review fixes)

### P0 fixes

| ID | Fix |
|----|-----|
| **D1** | `HostTime.fromLegacyMonotonicSeconds` + `ControlActionRouter.ameNormalized` preserves `MIDIEvent.timestamp` (ingress monotonic time). Debounce/burst use ingress HostTime. |
| **D2** | Early held-release path: physical Note Off / CC-low releases by identity **before** scope/timing/enabled/debounce/burst/transform. Wrong source/channel/note does not release. |
| **D3** | `AMEMapping.releaseActions`; held entries snapshot release actions at acquire; Note Off / release-all / document / context / mode transitions emit deactivation. Toggle ON/OFF uses actions / releaseActions. |
| **D4** | Option B: `AMELiveActionSupport.isPhaseDLiveSupported`; unsupported emissions get `shouldExecute=false` + `unsupportedAction` diagnostic; observers never forge `.go` for unbridged actions. |

### P1 fixes

| ID | Fix |
|----|-----|
| **D5** | Transform: `midiValue = raw * 127`; `inMin`/`inMax` define input window; outside range **clamps**; deadZone/threshold in input units. |
| **D6** | Entire `process` serialized under one runtime lock (rate-limit check+reserve atomic). |
| **D7** | First-wins dictionaries; `invalidRuntimeConfiguration` diagnostic; no trap on duplicate IDs. |
| **D8** | `.gate` → `.heldGate` (decode migrates `"gate"`); documented as threshold-held activation, not permission gate. |
| **D9** | Document replace → release-all; context change → release inactive scopes; armed→dryRun/edit → release-all; panic/MIDI disable → release-all **with** release emissions applied by host. |

### Final held/release lifecycle

```text
press  → acquire held entry (snapshot releaseActions) → emit activation
hold   → physical key owned by held table
release edge / document / context / mode / panic
       → remove hold → emit snapshotted releaseActions (never re-prove fire gates)
```

### Performance modes

| Mode | Behavior |
|------|----------|
| `edit` | Skip evaluation |
| `dryRun` | Full evaluation; `shouldExecute = false` (activation + release) |
| `armed` | Executable when live-supported |

### Files

- `Sources/AuroraModel/AMEModels.swift` — `releaseActions`, `heldGate`
- `Sources/AuroraEngine/AME/*` — runtime, held, diagnostics
- `Sources/AuroraMIDI/HostTime+MIDI.swift` — legacy seconds helper
- `Sources/Aurora/ControlActionRouter.swift` — ingress HostTime, dual-path, apply release batches
- `Tests/AuroraEngineTests/AMERuntimePhaseDTests.swift`
- `Tests/AuroraMIDITests/HostTimeLegacySecondsTests.swift`

### Explicit non-goals (still deferred)

| Item | Phase |
|------|-------|
| Stateful sequences (advance/reset/random/RNG) | E |
| Dedicated AME window / Learn UX | F |
| MusicalEngine quantize schedule bridge | G |
| Generalized AuroraAction executor (all cases) | later (D4 Option A) |
| Real cross-mapping permission gate | later |

---

## Re-acceptance checklist

- [x] Ingress monotonic timestamp survives into AME
- [x] Held release not blocked by debounce/burst/timing/scope
- [x] Momentary/whileHeld/heldGate have outward release actions
- [x] `releaseAllHeld` returns/applies deactivation emissions
- [x] Toggle ON/OFF semantics
- [x] Gate renamed/documented as `heldGate`
- [x] Unsupported actions explicit (not silent success)
- [x] Value transform inMin/inMax work
- [x] Concurrent debounce single-fire
- [x] Duplicate IDs cannot trap runtime
- [x] Full suite green (679)
- [x] This checkpoint updated

---

## STOP

**Do not start Phase E** until human acceptance of this Phase D closeout.
