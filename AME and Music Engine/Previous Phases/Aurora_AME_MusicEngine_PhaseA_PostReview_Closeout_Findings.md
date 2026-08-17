# Aurora AME + Musical Engine — Phase A Post-Review Closeout Findings

**Review target:** `Aurora_AME_MusicEngine_PostReview.zip`  
**Prior directive:** `Aurora_AME_MusicEngine_PhaseA_Deep_Code_Review_Fixes.md`  
**Disposition:** **Phase A is NOT yet accepted. Do not begin Phase B.**  
**Scope of this pass:** Verify the post-review remediation against the Phase A re-acceptance gate and identify only issues that should be corrected before Phase B.

---

## Executive summary

The post-review implementation corrected the majority of the original findings successfully:

- `AuroraMusical` remains separate from CoreMIDI.
- `MusicalTimingState` and `ShowMusicalContext` remain properly separated.
- AME mappings, sequence steps, and section lifecycle actions now use typed `[AuroraAction]`.
- `AuroraAction.compound` now has structured recursive encoding.
- `isSafetyCritical` is recursive.
- scheduler contracts use UUID action tokens rather than string action keys.
- MIDI ingress now carries monotonic host time derived from CoreMIDI packet timestamps.
- SPP remains System Common and MIDI real-time interleaving behavior remains correct.
- MIDI Clock capabilities no longer falsely claim song-position output.
- `ame.json` is included in the current-schema required-file regression test.
- sequence state scope/reset semantics and the AME typed enums are substantially improved.

However, the closeout introduced or left several contract-level issues that should be resolved **before the Phase B runtime is built on these APIs**.

The two most important are:

1. **The rich metrical structure is not persisted by Aurora's project/song model.** A saved 6/8 or asymmetric-meter song loses the information required to reproduce its metrical pulse after reload.
2. **`ScheduledMusicalAction` allows callers to lie about safety.** `panicBypass` can currently be constructed as non-safety-critical and/or quantized, and token commands carry a free Boolean disconnected from the resolved `AuroraAction`.

There is also a validator crash path on duplicate mapping IDs and incomplete inheritance-scope validation.

This is a significantly smaller correction pass than the original review. Do not redesign the system; close the specific contracts below, add the specified regression tests, update the checkpoint, then STOP again.

---

# P0 — Must fix before Phase B

## P0-1 — Persisted song/project meter still loses metrical grouping

### Files

- `Sources/AuroraMusical/MusicalTypes.swift`
- `Sources/AuroraModel/Song.swift`
- `Sources/AuroraModel/AMEModels.swift`
- `Sources/AuroraModel/SchemaMigration.swift` / package migration as required
- related tests

### Current problem

`AuroraMusical.MusicalMeter` now contains:

- numerator
- denominator
- `beatUnit`
- `beatGrouping`

That fixes the in-memory timing contract.

But persisted show metadata still stores only:

```swift
Song.defaultMeterNumerator
Song.defaultMeterDenominator
```

and:

```swift
MusicalEngineProjectSettings.defaultMeterNumerator
MusicalEngineProjectSettings.defaultMeterDenominator
```

This means the saved model cannot distinguish, for example:

- 6/8 felt as `[3,3]`
- 6/8 intentionally treated as six eighth-note pulses
- 7/8 `[2,2,3]`
- 7/8 `[3,2,2]`
- 7/8 `[2,3,2]`

After save/load, Phase B would have to guess the metrical pulse from numerator/denominator, recreating the original ambiguity that the first review required us to eliminate.

### Required correction

Persist the **full metrical structure** as part of song/project musical metadata.

Do not create a hidden second source of truth.

A reasonable solution is one of:

1. Move/share the canonical meter value type at a dependency layer usable by both `AuroraModel` and `AuroraMusical`, **or**
2. Introduce an explicit persisted meter value in `AuroraModel` containing at minimum numerator, denominator, and grouping, with a single well-tested conversion to/from `MusicalMeter`.

Do **not** retain only the numerator/denominator pair as the canonical persisted representation.

If a separate persisted representation is unavoidable because of module layering, name it explicitly as storage/domain data rather than pretending it is another independent meter semantic.

### Migration/default behavior

Existing projects containing only numerator/denominator need deterministic migration defaults. Suggested policy:

- 4/4 → `[1,1,1,1]`
- 3/4 → `[1,1,1]`
- 6/8 → `[3,3]`
- 9/8 → `[3,3,3]`
- 12/8 → `[3,3,3,3]`
- meters whose grouping cannot be safely inferred should require an explicit default rule or preserve an "unspecified grouping" state that the UI/runtime must resolve rather than silently inventing one.

### Acceptance tests

- Save/load a song with 6/8 `[3,3]`; grouping survives exactly.
- Save/load 7/8 `[2,2,3]`; grouping survives exactly.
- Save/load 7/8 `[3,2,2]`; it remains distinct from `[2,2,3]`.
- Project default meter round-trips full structure.
- Legacy numerator/denominator-only data migrates deterministically.
- Phase B can construct the exact `MusicalMeter` from persisted metadata without guessing.

---

## P0-2 — `MusicalMeter.beatUnit` and `beatGrouping` are internally contradictory

### File

`Sources/AuroraMusical/MusicalTypes.swift`

### Current problem

`MusicalMeter` currently stores both a single `beatUnit` and `beatGrouping`, but the initializer only validates the grouping sum. It does not validate that the two representations agree.

For example, this is currently legal:

```swift
MusicalMeter(
    numerator: 6,
    denominator: 8,
    beatUnit: .dottedQuarter,
    beatGrouping: [2,2,2]
)
```

The API then reports:

```swift
quarterNotesPerMetricalBeat == 1.5
```

while:

```swift
metricalBeatLengthsInQuarterNotes == [1.0, 1.0, 1.0]
```

So the same `MusicalMeter` can provide two different answers to "how long is a metrical beat?"

The problem is even more fundamental for asymmetric meter:

```swift
sevenEight_223
```

uses:

```swift
beatUnit: .eighth
beatGrouping: [2,2,3]
```

but its actual metrical beats are quarter, quarter, dotted-quarter. There is no single `BeatUnit` that describes all three.

Phase B must not be given a timing type whose own properties disagree.

### Required correction

Choose one canonical representation for metrical beat boundaries.

**Recommended:** make `beatGrouping` the canonical source of beat lengths and remove the claim that one `BeatUnit` describes every metrical beat.

Possible designs:

- Remove `beatUnit` from `MusicalMeter` entirely and derive beat lengths from denominator + grouping.
- Or rename/redefine it as an optional **tempo/reference beat unit** that does not participate in metrical-boundary math.

If a single beat unit is retained for simple/compound uniform meters, it must be optional or derived and must not conflict with asymmetric grouping.

No public helper should provide an answer contradicted by `metricalBeatLengthsInQuarterNotes`.

### Acceptance tests

- It must be impossible to create a meter whose beat-unit API disagrees with grouping semantics.
- 6/8 `[3,3]` produces two 1.5-quarter metrical beats.
- 7/8 `[2,2,3]` produces `[1.0, 1.0, 1.5]` quarter-note beats with no contradictory singular beat duration.
- 7/8 `[3,2,2]` produces `[1.5, 1.0, 1.0]`.
- `nextMetricalBeatPosition` and `barBeat` use the same canonical beat structure.

---

## P0-3 — Scheduler safety contract is still caller-asserted rather than enforced

### Files

- `Sources/AuroraMusical/MusicalSchedulerContracts.swift`
- `Sources/AuroraEngine/AuroraActionTokenRegistry.swift`
- future Phase B enqueue bridge
- tests

### Current problem

`ScheduledMusicalAction` exposes:

```swift
command: ScheduledCommand
isSafetyCritical: Bool
```

as independent caller-provided values.

Therefore all of these are currently constructible:

```swift
ScheduledMusicalAction(
    targetBoundary: .nextBar,
    command: .panicBypass,
    isSafetyCritical: false
)
```

or a token resolving to `.panic` while the scheduled object says `false`.

This reintroduces the exact class of safety bug that recursive `AuroraAction.isSafetyCritical` was intended to eliminate.

The model validator protects persisted AME mappings, but the scheduler is a general runtime contract and will eventually receive work from other sources such as section transitions, remote control, show-control integration, and future APIs.

### Required correction

Safety must be **derived or enforced**, not a free Boolean that can disagree with the command.

At minimum:

- `.panicBypass` must always be safety-critical by construction.
- `.panicBypass` must not be allowed to wait on a musical boundary.
- the engine bridge that converts an `AuroraAction` into a scheduler token must derive safety from `AuroraAction.isSafetyCritical`.
- Phase B enqueue must reject or normalize an invalid combination rather than trusting callers.

A useful token-registration contract would carry metadata with the token, e.g. a resolved token record containing action + safety classification, so the bridge cannot accidentally separate them.

Do not make `AuroraMusical` import `AuroraModel` merely to solve this; preserve the module boundary.

### Acceptance tests

- It is impossible to enqueue/construct `panicBypass` as non-safety-critical.
- It is impossible for `panicBypass` to remain quantized to `nextBar`, `nextMetricalBeat`, etc.
- registering `.compound([.go, .panic])` produces safety metadata derived as `true`.
- a decorative action remains non-safety.
- Phase B's eventual queue can rely on the contract without re-inspecting arbitrary strings or trusting a caller Boolean.

---

## P0-4 — Validator can trap on the malformed duplicate-ID graph it is supposed to diagnose

### File

`Sources/AuroraModel/AMEConfigurationValidator.swift`

### Current problem

The validator correctly detects duplicate mapping IDs first, but then calls:

```swift
validateInheritance(document.mappings)
```

Inside `validateInheritance`:

```swift
let byID = Dictionary(uniqueKeysWithValues: mappings.map { ($0.id, $0) })
```

`Dictionary(uniqueKeysWithValues:)` traps when duplicate keys are present.

Therefore a document containing duplicate mapping IDs can crash validation instead of returning the already-defined `duplicate_mapping_id` diagnostic.

A validator handling possibly damaged project data must not crash on malformed input.

### Required correction

Build the lookup defensively. Examples:

- use `Dictionary(grouping:by:)`, or
- populate a dictionary manually while retaining first/last deterministically, or
- skip inheritance checks for duplicated IDs after recording the duplicate diagnostic.

The key property is: **validation of invalid data must itself be total/non-trapping.**

Audit other validator lookup construction for the same pattern.

### Acceptance tests

- Two mappings with the same UUID return `duplicate_mapping_id` and do not crash.
- Duplicate IDs combined with override/disable edges still return deterministic diagnostics.
- validator output remains deterministically sorted.

---

# P1 — Should fix in this closeout

## P1-1 — Inheritance scope rules are documented but not actually validated

### File

`Sources/AuroraModel/AMEConfigurationValidator.swift`

### Current problem

The implementation validates:

- parent exists
- no self edge
- no same-parent override+disable
- separate override/disable cycles
- ambiguous same-parent + same-priority overrides

But it does **not** enforce the documented/planned scope ancestry rules.

A section mapping can currently point at a parent in an unrelated section; a song mapping can point at a section mapping; etc.

Also the ambiguity detector groups only by parent + priority:

```swift
Dictionary(grouping: children, by: { $0.priority })
```

so two same-priority overrides in different valid sections can be falsely reported as ambiguous even though they can never be simultaneously effective.

### Required correction

Implement explicit scope relationship validation.

Rules should include:

- project parent may be overridden by song or section child.
- song parent may be overridden by a section belonging to that same song.
- same-scope override is allowed only when the scope identity is the same, if same-scope overrides are still intended.
- section A must not override/disable section B.
- song A must not override/disable song B.
- project child must not target narrower song/section parent.

Ambiguity must be evaluated in **effective scope context**, not globally by priority alone.

Because a section UUID does not itself encode its parent song, use the project song/section relationship available to `validate(document:project:)`.

### Acceptance tests

- legal project → song → section override chain passes.
- section in Song A overriding Song A parent passes.
- section in Song A overriding Song B parent fails.
- section A overriding section B fails.
- two same-priority children in mutually exclusive sections are not falsely ambiguous.
- two simultaneously effective same-scope/same-priority children overriding the same parent produce the ambiguity diagnostic.

---

## P1-2 — MIDI trigger data bytes allow 128…255

### Files

- `Sources/AuroraModel/AMEModels.swift`
- `Sources/AuroraModel/AMEConfigurationValidator.swift`

### Current problem

Trigger channel/data fields are `UInt8`, which constrains them to 0…255, but MIDI channel data bytes are 7-bit values 0…127.

The validator checks channel ≤ 15 and min ≤ max, but does not reject data values > 127.

### Required correction

Validate every MIDI 7-bit data constraint explicitly:

- `data1Min`, `data1Max` ∈ 0…127
- `data2Min`, `data2Max` ∈ 0…127

Also ensure future evaluator code never assumes `UInt8` alone means MIDI-valid.

### Acceptance tests

- 127 accepted.
- 128 rejected for each data field.
- min/max inversion remains rejected.

---

## P1-3 — Timing/debounce numeric invariants are incomplete

### Files

- `Sources/AuroraModel/AMEModels.swift`
- `Sources/AuroraModel/AMEConfigurationValidator.swift`
- `Sources/AuroraModel/Song.swift`

### Current problem

The closeout plan called for finite/range validation, but several persisted timing values remain under-validated:

- project default BPM only checks `> 0`, despite `MusicalNumeric` defining 20…400.
- song default BPM is not validated here.
- `debounceMilliseconds` can be NaN, infinity, or negative.
- `burstSuppressionMilliseconds` can be NaN, infinity, or negative.
- song meter numerator/denominator are not validated in the AME validator.

### Required correction

Define one documented product range and validate consistently at model/config boundaries.

At minimum:

- BPM finite and within the supported product range.
- debounce finite and ≥ 0.
- burst suppression finite and ≥ 0 when present.
- song musical defaults validated with the same rules as project defaults.

Do not silently clamp malformed persisted project data during validation. Return diagnostics.

---

## P1-4 — Structured `compound` decoder should not silently turn malformed tagged data into an empty action

### File

`Sources/AuroraModel/AuroraAction.swift`

### Current problem

New structured encoding writes:

```json
{ "type": "compound", "actions": [...] }
```

but tagged decoding uses:

```swift
.compound(try decodeIfPresent([AuroraAction].self, forKey: .actions) ?? [])
```

So corrupted tagged data such as:

```json
{ "type": "compound" }
```

silently becomes a valid empty compound instead of surfacing package damage.

Likewise the legacy `fromLegacy("compound", ...)` returns `.compound([])` even though the old flattened representation cannot reconstruct the children.

### Required correction

For **new tagged format**, require `actions` to be present for `type == compound`. An intentionally empty compound may encode an explicit empty array.

For unrecoverable legacy compound data, prefer an explicit decode/migration failure or migration diagnostic over silently replacing real actions with a no-op.

If the team intentionally declares pre-closeout Phase A v4 files disposable, remove misleading compatibility behavior rather than silently pretending it is lossless.

### Acceptance tests

- explicit `"actions": []` decodes as empty compound.
- missing `actions` on tagged compound fails decode.
- nested compounds remain lossless.
- legacy compound handling has documented deterministic behavior and never silently claims to preserve unavailable children.

---

## P1-5 — Action-token lifetime/ownership must be defined before Phase B queue implementation

### File

`Sources/AuroraEngine/AuroraActionTokenRegistry.swift`

### Current problem

The token registry supports register/resolve/unregister/clear but does not define whether tokens are:

- persistent per configured action,
- single-use schedule payloads,
- reused across repeated triggers,
- consumed at fire time,
- removed on cancellation/rejection.

If Phase B registers a fresh token for every trigger and only calls `resolve`, the table grows for the duration of a show.

This is not a Phase A runtime bug yet, but Phase B will immediately depend on this ownership contract.

### Required correction

Document and test one lifecycle before implementing the queue.

Recommended options:

**Persistent token model:** tokens belong to durable configured action instances and are reused, with registry rebuilt when configuration changes.

or

**Ephemeral token model:** registry exposes an atomic `consume(token)` operation and Phase B guarantees cleanup on fire, cancellation, enqueue rejection, and queue teardown.

Do not leave the lifecycle implicit.

If using ephemeral tokens, `resolve` + `unregister` as separate calls is not ideal for concurrency; provide atomic consumption.

---

# P2 — Minor hardening / cleanup

## P2-1 — HostTime portability/import clarity

`HostTime.now()` directly uses Mach symbols in `MusicalTypes.swift` without an explicit Darwin/Mach import. The supplied project is macOS-only, and the reported macOS suite is green, but the standalone SPM target currently fails to compile in this Linux review environment at those symbols.

Aurora does not need Linux product support, so this is **not a release blocker by itself**. Still, make the platform dependency explicit:

```swift
#if canImport(Darwin)
import Darwin
#endif
```

and/or isolate the platform clock primitive behind a tiny host-clock implementation.

The important property is that `AuroraMusical` remains free of CoreMIDI; a Mach/Darwin dependency is acceptable for the macOS app.

Do not switch back to wall-clock `Date` merely for portability.

---

## P2-2 — Remove accidental always-true expression in sync validation

In `AMEConfigurationValidator.swift`:

```swift
if mapping.timingRequirement == .externalSyncLocked,
   mapping.quantizeBoundary != nil || true,
   document.musicalSettings.timingPolicy == .internalOnly {
```

`mapping.quantizeBoundary != nil || true` is always true and serves no purpose.

This looks like leftover scaffolding and obscures the intended condition. Remove it and make the diagnostic rule explicit.

---

# Items verified as corrected

These should **not** be churned again unless required by one of the fixes above.

## Typed action graph

Verified:

```swift
AMEMapping.actions: [AuroraAction]
AMESequenceStep.actions: [AuroraAction]
SongSection.onEnterActions: [AuroraAction]
SongSection.onExitActions: [AuroraAction]
```

The old parallel string action arrays are gone from these contracts.

## Recursive action encoding

The new tagged `AuroraAction` encoder recursively writes compound children. Parameterized actions use structured UUID/int/double/string fields rather than one ambiguous parameter string.

## Recursive safety

`AuroraAction.isSafetyCritical` recurses through compound actions and includes panic/blackout/freeze/blind/stop/clear-overrides families.

## MIDI Clock capability semantics

Verified:

```swift
TimingSourceCapabilities.midiClock.suppliesSongPosition == false
TimingSourceCapabilities.midiClock.supportsSongPositionInput == true
```

This correctly distinguishes MIDI Clock from SPP.

## Monotonic MIDI ingress

Verified architecture:

- CoreMIDI `MIDIPacket.timeStamp` is converted to `HostTime`.
- `MIDIInputManager` calls `parseIngress` per packet.
- channel voice, real-time, and System Common carry monotonic host time.
- split channel/common messages use completion-packet time.
- Note On velocity 0 normalization remains intact.

## Required `ame.json`

`ProjectPackageRequiredFilesTests.testMissingCurrentSchemaExtensionFilesFailLoad` now includes `ame.json`.

## Sequence semantics

`AMESequenceStateScope` and `associatedSequenceIDs` are clearer than the previous Boolean/reset-list design. `resetPolicy` is documented as the reset source of truth.

---

# Mandatory tests to add in this second closeout

## Meter persistence / semantics

- [ ] project default 6/8 grouping round-trip
- [ ] song 6/8 grouping round-trip
- [ ] 7/8 `[2,2,3]` round-trip
- [ ] 7/8 `[3,2,2]` remains distinct
- [ ] no contradictory beat-unit/grouping representation
- [ ] metrical boundaries use one canonical representation

## Scheduler safety

- [ ] panicBypass cannot be non-safety
- [ ] panicBypass cannot remain quantized
- [ ] token safety derives from resolved AuroraAction at bridge
- [ ] nested compound panic is immediate/safety

## Validator robustness

- [ ] duplicate mapping IDs do not trap
- [ ] invalid cross-song/cross-section override rejected
- [ ] mutually exclusive section overrides do not false-positive as ambiguous
- [ ] MIDI data byte 128 rejected
- [ ] negative/NaN debounce rejected
- [ ] negative/NaN burst suppression rejected
- [ ] invalid song/project BPM rejected consistently

## Codable corruption behavior

- [ ] tagged compound missing `actions` fails
- [ ] explicit empty compound remains valid if desired
- [ ] legacy unrecoverable compound behavior documented/tested

---

# Re-acceptance gate — second closeout

Phase A may be accepted for Phase B only when all of the following are true:

- [ ] Full meter/grouping semantics survive project and song save/load.
- [ ] There is one non-contradictory canonical source for metrical beat lengths.
- [ ] Scheduler safety cannot disagree with command/action safety.
- [ ] Panic bypass cannot be quantized.
- [ ] Validator cannot trap on duplicate IDs.
- [ ] Inheritance parent scopes are validated against song/section ancestry.
- [ ] Ambiguity detection is scope-aware.
- [ ] MIDI trigger data values enforce 0…127.
- [ ] AME debounce/burst/BPM numeric invariants are complete.
- [ ] Malformed tagged compound actions do not silently become no-ops.
- [ ] Action-token lifetime semantics are documented and tested.
- [ ] Full macOS test suite is green.
- [ ] `CHECKPOINT_AME_PHASE_A_CLOSEOUT.md` is updated with this second closeout.
- [ ] **STOP before Phase B for human acceptance.**

---

# Suggested implementation order

```text
1. Fix canonical/persisted meter model
2. Enforce scheduler safety invariants
3. Make validator duplicate-safe
4. Implement scope-aware inheritance validation
5. Finish numeric/MIDI range validation
6. Harden compound decode behavior
7. Lock token lifetime semantics
8. Add regression tests
9. Run full macOS suite
10. Update Phase A closeout checkpoint
11. STOP
```

---

## Final review disposition

The first remediation pass was worthwhile and fixed the majority of the original architectural debt. The remaining work is now narrow.

**Do not begin Phase B yet.** The persisted-meter gap and scheduler-safety contract in particular would otherwise become foundational assumptions inside the runtime and be more expensive to unwind later.

Once this second closeout is applied and the re-acceptance gate is green, Phase A should be ready for final approval.
