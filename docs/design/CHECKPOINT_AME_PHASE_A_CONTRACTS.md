# Checkpoint — AME / Musical Engine Phase A (Contracts)

**Date:** 2026-08-15  
**Status:** **COMPLETE — STOP before Phase B**  
**Plan:** Advanced MIDI Engine + Musical Engine (amended)  
**Spec:** `AME and Music Engine/Aurora_AME_and_Musical_Engine_Deep_Feature_Spec.md`  
**Amendments:** `AME and Music Engine/Aurora_AME_Musical_Engine_Plan_Review_Amendments.md`

---

## What shipped (Phase A only)

### Module: `AuroraMusical` (new)

- Dedicated SPM target — **no CoreMIDI**
- `MusicalTimingState` vs `ShowMusicalContext` composition → `MusicalState`
- Transport / sync / policy / fallback enums
- Clock vs grid vs meter types (`Meter`, `MusicalGridUnit`, `QuarterNotePosition`, `BarBeatPosition`, …)
- Field provenance (`MusicalValueProvenance`)
- `MusicalTimelineEvent` discontinuity contract
- `TimingProvider` protocol (continuous sources only)
- `TapTempoEstimator` (not a continuous provider)
- `ScheduledMusicalAction` + `ScheduleEnqueueResult` (typed; reject-newest contract)
- Stub `MusicalEngine` for wiring / context set

### MIDI ingress (`AuroraMIDI`)

- `MIDIIngressEvent`: channel voice | **system realtime** | **system common**
- SPP is **system common**, not realtime
- `MIDIStreamParser.parseIngress` emits interleaved realtime immediately
- Note On velocity 0 → Note Off normalization
- Monotonic ingress timestamps on all events
- Legacy `parse` still returns channel-voice only (compat)

### Model / package (schema **v4**)

- `SongSection`, safe default **Main** (no silent label→section rewrite)
- `SongSectionMigrationHelper.proposeSections` (opt-in helper only)
- `AMEProjectDocument` + triggers/groups/mappings/sets/sequences/bindings/settings
- `AMEMapping` ownership claims (`claimsLegacyMappingID` / `claimsLegacyRuleID`)
- `AuroraAction` expanded storage model (+ ShowAction bridge in AuroraMIDI)
- `AMEConfigurationValidator` skeleton
- `ame.json` in package; load optional for schema &lt; 4
- Migration v3→v4: ensure Main section per song

### Tests

- `AuroraMusicalTests`
- `MIDIIngressParserPhaseATests` (interleave matrix, SPP, vel0)
- `AMEPhaseAModelTests` (migration, ownership, package, validator)
- Full suite: **554 tests, 0 failures**

### Tooling

- `Package.swift` products/deps updated
- `project.yml` + `xcodegen generate` for app product

---

## Explicit non-goals (still deferred)

- Musical Engine runtime clock / scheduler firing (Phase B)
- MIDI Clock provider adapter (Phase C)
- AME evaluation runtime (Phase D)
- Dedicated MIDI Engine window (Phase F)
- Effects Engine

---

## Exit criteria checklist

| Criterion | Status |
|-----------|--------|
| Old projects load | Yes (schema 1–3 migrate to 4) |
| No behavior change for existing MIDI map users | Yes (legacy path unchanged) |
| Parser interleave + SPP tests green | Yes |
| AuroraMusical compiles / tests green | Yes |
| Full suite green | 554 pass |

---

## STOP (superseded)

Initial Phase A contracts landed here. **Deep code review closeout** completed in:

→ **`docs/design/CHECKPOINT_AME_PHASE_A_CLOSEOUT.md`**

**Do not start Phase B** until the closeout re-acceptance gate is accepted.
