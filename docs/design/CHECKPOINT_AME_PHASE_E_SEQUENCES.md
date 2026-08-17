# Checkpoint — Phase E: Sequences (closeout)

**Date:** 2026-08-16  
**Status:** **CLOSEOUT COMPLETE — STOP before Phase F**  
**Reviews:** `Aurora_PhaseD_Closeout_PhaseE_Pass1_Deep_Review_Fixes.md`  
**Suite:** **710 tests, 0 failures**

---

## Phase D residual fixes (landed with this closeout)

| Issue | Fix |
|-------|-----|
| armed→dryRun/edit non-executable releases | `setPerformanceMode` releases **live** domain with `shouldExecute=true` |
| `performanceMode` setter discarded batch | **Read-only** property; use `setPerformanceMode` |
| dryRun document replace executed OFF | Releases use `wasLiveExecuted` provenance |
| dryRun poisoned armed state | **Dual domains** (live vs simulation) for held/toggle/sequence/rate-limit |

---

## Phase E closeout semantics

### Trigger policies (distinct)

| Policy | `initialIndex=0`, advance mode |
|--------|--------------------------------|
| `fireThenAdvance` | 0, 1, 2, 0… |
| `advanceThenFire` | 1, 2, 0, 1… |

### Context resets (entry only)

- `nil → A` / `A → B` = entry/start → apply reset policy  
- `A → nil` = exit only → **no** on-entry reset  

### Reset × state scope

| | onSongStart | onSectionEntry |
|--|-------------|----------------|
| **global** | reset single global | reset single global |
| **perSong** | reset entered song key | reset current song key |
| **perSection** | reset **all** section keys for that song | reset entered section key |

Structured keys: `global` / `song(UUID)` / `section(songID?, sectionID)`.

### Control actions

| Action | Behavior |
|--------|----------|
| `advanceSequence` | Advance cursor **only** (no step actions) |
| `fireSequenceStep` | Fire step actions; **cursor unchanged**; OOB → diagnostic, no clamp |
| mapping `sequenceID` | Full trigger policy fire + advance |

### RNG

Per `AMESequenceStateKey` substream from base seed + key identity. Unrelated sequences do not perturb each other. Reset reseeds that instance.

### Dry-run isolation

Separate simulation domain; arming purges sim state without executing releases.

### Loop=false

**Clamp/re-fire terminal** (documented): not one-shot exhaustion.

### Reverse default

`initialIndex` is authoritative. `AMESequenceDefaults.suggestedInitialIndex(mode:stepCount:)` suggests last step for reverse editors.

### Sequence table

`AMESequenceStateTable` is **internal** (not public Sendable).

### Validator

- `fireSequenceStep` bounds  
- nested sequence-control inside sequence steps **disallowed**  
- reverse-at-zero info warning  

---

## STOP

**Do not start Phase F** until human acceptance.
