# Checkpoint — Phase C: External MIDI Timing

**Date:** 2026-08-16  
**Status:** **ACCEPTED** (human review 2026-08-16 — Phase C closeout in Phase D Pass 1 review)  
**Reviews:**
- Phase B Pass 2 (accepted)
- `Aurora_AME_MusicEngine_PhaseBCloseout_PhaseC_Deep_Review_Fixes.md`
- `Aurora_PhaseC_Closeout_PhaseD_Pass1_Deep_Review_Fixes.md` (Phase C ACCEPTED)

**Suite at Phase C closeout:** 639+ tests green; later suite counts supersede.

---

## Phase B

**ACCEPTED** (Pass 2 contracts closed; not reopened).

---

## Phase C review closeout

| Finding | Fix |
|---------|-----|
| P0 one pulse steals authority | External becomes **active only when estimator locks**; preferred keeps internal while acquiring |
| P0 false re-lock after loss | `consecutiveStable` cleared on freewheel/loss; invalid gap interval resets stability; acquisition timeout for stray pulse |
| P0 source A→B contamination | `selectExternalTimingSource` full `resetForNewSource()` + authority transition |
| P0 Start/SPP phase skew | `resetPhaseForStart` / `alignPhase(to:)`; phase forced to match position |
| P0 fallback keeps external BPM | `InternalTimingBaseline` restored on preferred fallback |
| P0/P1 select source atomic | Strict → active nil + failure policies; preferred → internal fallback while B acquires |
| P1 held on first lock | Authority `false→true` releases held work |
| P1 freewheel duration | Measured **after** dropout threshold (`age - dropoutAfter`) |
| P1 SPP capability | `suppliesSongPosition` set on accepted SPP; reset on source change |
| P1 diagnostics | Pulse age + jitter EMA on tick/pulse |

### Key semantics (preferred fallback)

```text
selected = external device
candidate = acquiring (estimator)
active = internal
→ lock threshold met
active = external, sync = locked
→ dropout → freewheel (last external BPM)
→ freewheelSeconds → lost → active = internal, tempo = internal baseline
```

### Files

- `Sources/AuroraMusical/ClockEstimator.swift`
- `Sources/AuroraMusical/MusicalEngine.swift`
- Tests: `MusicalEnginePhaseCReviewFixesTests.swift` (+ updated Phase C tests)

---

## STOP (superseded)

Phase C is **ACCEPTED**. Phase D implementation + closeout: see `CHECKPOINT_AME_PHASE_D_AFK.md`.
