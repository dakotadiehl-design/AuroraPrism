# Aurora AME + Musical Engine
## Phase A Deep Code Review — Required Closeout Before Phase B

**Review target:** `Aurora_AME_MusicEngine_A1(1).zip`  
**Checkpoint reviewed:** `docs/design/CHECKPOINT_AME_PHASE_A_CONTRACTS.md`  
**Primary design references:**
- `AME and Music Engine/Aurora_AME_and_Musical_Engine_Deep_Feature_Spec.md`
- `AME and Music Engine/Aurora_AME_Musical_Engine_Plan_Review_Amendments.md`

**Disposition:** **Phase A is architecturally promising but is not yet approved for Phase B.**

The implementation gets many important architectural decisions right: `AuroraMusical` is a separate module, System Real-Time and System Common MIDI are correctly distinguished, interleaved real-time parsing is substantially improved, SPP is modeled, song sections are first-class objects, timing state is separated from show context, AME ownership claims exist, and `ame.json` is integrated into schema v4 persistence.

However, the deep review found several contract-level issues that should be corrected **before Phase B creates runtime code against these APIs**. The most important are the incomplete metrical-beat model, lossy/stringly action persistence, incomplete monotonic timestamp semantics, and safety holes around compound actions.

---

# 1. Review / Build Verification

The Linux review environment cannot build the full Aurora package because the `AuroraMIDI` target links Apple `CoreMIDI`. That is expected for this environment and is not treated as an Aurora failure.

The two foundational targets that can be built independently were verified successfully:

```text
swift build --target AuroraMusical
PASS

swift build --target AuroraModel
PASS
```

The supplied checkpoint reports the full macOS suite at **554 tests, 0 failures**. This review accepts that report but also identifies missing tests below.

---

# 2. Severity Summary

## P0 — Must fix before Phase B

1. **Metrical-beat / compound-meter contract is incomplete.**
2. **`AuroraAction` persistence is lossy for compound actions and AME uses unsafe parallel string arrays despite having a typed action model.**
3. **Safety-critical classification is not recursive, allowing a compound action containing panic/blackout/stop to appear non-safety-critical.**
4. **The promised monotonic MIDI ingress timestamp contract is not actually established end-to-end.**

## P1 — Strongly fix before Phase B

5. Replace remaining stringly-typed AME/timing contract fields with typed enums/structures.
6. Expand AME structural validation substantially before these persisted models harden.
7. Resolve sequence lifecycle/state-scope ambiguity.
8. Correct timing-source capability semantics, especially MIDI Clock vs SPP.
9. Define and enforce numeric invariants for meter, duration, tempo, transforms, and positions.
10. Define deterministic inheritance/override invariants at the model level.

## P2 — Closeout hardening / tests

11. Expand Phase A tests to exercise the failure modes below.
12. Add `ame.json` to the explicit current-schema missing-file regression test.
13. Clarify temporary Phase A APIs that must not become permanent runtime contracts.

---

# 3. P0-1 — Metrical Beat Model Is Incomplete

### Files

- `Sources/AuroraMusical/MusicalTypes.swift`
- `Sources/AuroraMusical/MusicalState.swift`
- `Sources/AuroraMusical/MusicalSchedulerContracts.swift`

### Current implementation

The model correctly distinguishes:

- quarter-note position,
- meter,
- note-grid durations,
- and a `BeatUnit` enum.

However, `MusicalTimingState` stores only:

```swift
public var meter: Meter?
public var barBeat: BarBeatPosition?
```

and `Meter` contains only numerator/denominator.

`BeatUnit` exists, but it is not associated with the active meter/timing state and there is no beat grouping representation.

At the same time, the scheduler contract already exposes:

```swift
case nextMetricalBeat
```

### Why this is a blocker

The reviewed amendments explicitly required Aurora not to assume:

```text
1 beat == 1 quarter note
```

For example, `6/8` can be represented as six denominator units, but the common musical pulse is two dotted-quarter beats. From only:

```text
Meter(numerator: 6, denominator: 8)
```

Phase B cannot know what `nextMetricalBeat` means.

This also affects:

- `BarBeatPosition.beatIndexInBar`
- `BarBeatPosition.beatPhase`
- bar/beat diagnostics
- future effect synchronization
- show-control position reporting
- quantization in 6/8, 9/8, 12/8 and irregular meters

### Required correction

Introduce an explicit metrical structure before implementing the scheduler. One acceptable design is:

```swift
public struct MusicalMeter: Codable, Equatable, Sendable, Hashable {
    public var numerator: Int
    public var denominator: Int
    public var beatUnit: BeatUnit
    public var beatGrouping: [Int]?
}
```

or equivalent separate values in timing state.

Examples:

```text
4/4  -> quarter-note beat unit, grouping [1,1,1,1] or implicit simple meter
6/8  -> dotted-quarter beat unit, grouping [3,3]
9/8  -> dotted-quarter beat unit, grouping [3,3,3]
12/8 -> dotted-quarter beat unit, grouping [3,3,3,3]
7/8  -> explicit grouping such as [2,2,3], [3,2,2], etc.
```

Do not infer a compound-meter pulse from the numerator alone in a way that prevents an explicit user/project override.

### Acceptance tests

Add tests proving at minimum:

- 4/4 quarter-note metrical beats
- 3/4 quarter-note metrical beats
- 6/8 dotted-quarter metrical beats
- 12/8 dotted-quarter metrical beats
- 7/8 explicit grouping
- next metrical beat differs from next quarter note in 6/8
- bar position remains correct across these meters

**Do not begin Phase B scheduler math until this contract is corrected.**

---

# 4. P0-2 — AME Action Persistence Is Stringly, Parallel, and Compound Actions Are Lossy

### Files

- `Sources/AuroraModel/AuroraAction.swift`
- `Sources/AuroraModel/AMEModels.swift`
- `Sources/AuroraModel/SongSection.swift`
- `Sources/AuroraMusical/MusicalSchedulerContracts.swift`

### Current implementation

A first-class `AuroraAction` now exists in `AuroraModel`, which is excellent.

Despite that, AME persists actions using parallel arrays:

```swift
public var actionKeys: [String]
public var actionParameters: [String]
```

The same pattern exists in:

- `AMEMapping`
- `AMESequenceStep`
- `SongSection.onEnter...`
- `SongSection.onExit...`

The scheduler similarly stores:

```swift
public var actionStorageKey: String
public var actionParameter: String?
```

Most importantly, `AuroraAction.compound` is not losslessly persisted:

```swift
case .compound(let actions):
    return "\(actions.count)"
```

and decoding does this:

```swift
case "compound":
    return .compound([])
```

Therefore:

```text
compound([A, B, C])
```

round-trips as:

```text
compound([])
```

This violates the core requirement that compound actions use the same first-class Aurora action architecture.

### Additional problem: parallel array corruption

Parallel `actionKeys` / `actionParameters` arrays can become different lengths or lose positional meaning. A no-parameter action followed by a parameterized action needs placeholder semantics that are currently not modeled.

This makes malformed state representable by construction.

### Required correction

Because `AuroraAction` already lives in `AuroraModel`, AME model objects should store typed actions directly unless Grok can demonstrate a concrete dependency-cycle reason not to.

Preferred form:

```swift
public var actions: [AuroraAction]
```

Likewise:

```swift
SongSection.onEnterActions: [AuroraAction]
SongSection.onExitActions: [AuroraAction]
AMESequenceStep.actions: [AuroraAction]
```

For cross-module scheduler work, do **not** fall back to an opaque string merely because the scheduler lives in `AuroraMusical`. If `AuroraMusical` must remain independent from `AuroraModel`, introduce a typed scheduler command/token owned by `AuroraMusical` and let the integration layer map Aurora actions to tokens. The reviewed amendments explicitly called for typed scheduled work, not persisted string key/parameter pairs becoming the permanent scheduler ABI.

### Compound encoding

Implement fully recursive, lossless `Codable` support for:

```swift
case compound([AuroraAction])
```

A tagged enum representation is preferable to flattening associated values into a single string.

If backward compatibility with existing storage keys is needed, preserve a decoder for old representations, but **schema v4 should not knowingly persist lossy compound actions**.

### Acceptance tests

Add:

- round-trip every `AuroraAction` case
- round-trip nested compound actions
- round-trip compound containing parameterized actions
- AME mapping with mixed parameterless + parameterized actions
- section enter/exit typed-action round-trip
- sequence-step typed-action round-trip

---

# 5. P0-3 — Safety Classification Fails for Compound Actions

### File

`Sources/AuroraModel/AuroraAction.swift`

### Current implementation

`isSafetyCritical` marks direct actions such as:

```swift
.panic
.blackout
.stop
.clearOverrides
```

as safety-critical.

But:

```swift
.compound([.panic, ...])
```

falls through the default branch and returns `false`.

### Why this matters

The amendments explicitly require safety actions to bypass quantization and never wait for the next beat/bar.

Without recursive classification, a compound action containing `.panic`, `.blackout`, or `.stop` can be treated as ordinary creative work and become quantized.

That is a real show-safety semantic bug.

### Required correction

Make compound safety classification recursive:

```swift
case .compound(let actions):
    return actions.contains(where: \ .isSafetyCritical)
```

(use valid Swift key-path syntax in implementation).

Also decide and document whether other actions should be classified as safety/transport-critical, especially:

- `setTransportStop`
- `freeze` / `freezeOff`
- `blind` operations

They do not necessarily all need the same classification, but it must be intentional.

### Validation implication

The AME validator must inspect the decoded typed action, recursively, when checking `safety_quantized`.

Do not perform this check from a storage key with `parameter: nil`.

### Acceptance tests

- direct panic is safety-critical
- compound containing panic is safety-critical
- nested compound containing blackout is safety-critical
- compound of only decorative actions is not safety-critical
- quantization validator rejects a nested safety action

---

# 6. P0-4 — Monotonic Timestamp Contract Is Not Actually Established

### Files

- `Sources/AuroraMIDI/MIDIIngressEvent.swift`
- `Sources/AuroraMIDI/MIDIMessageParser.swift`
- `Sources/AuroraMIDI/MIDIInputManager.swift`
- `Sources/AuroraMusical/TimingProvider.swift`

### Required design contract

The reviewed amendments explicitly require:

> Every normalized MIDI ingress event should carry a monotonic timestamp.

and specifically recommend preserving/normalizing useful CoreMIDI packet timestamps.

### Current implementation

The timestamp type is an unqualified:

```swift
TimeInterval
```

The legacy parser path generates it using:

```swift
Date().timeIntervalSince1970
```

which is **wall-clock time, not a monotonic clock**.

More importantly, `MIDIInputManager.handlePacketList` currently ignores each `MIDIPacket.timeStamp` and invokes:

```swift
parser.parse(bytes:sourceID:)
```

which discards realtime/common ingress and stamps channel messages later with wall-clock time.

The new `parseIngress` API accepts a timestamp but the actual CoreMIDI input path does not yet provide one.

### Why this should be fixed in Phase A

Phase C will build clock phase estimation on this foundation. If the timestamp domain is vague now, Phase C will either:

- build timing math on wall-clock values,
- duplicate timestamp conversion logic,
- or require an avoidable API refactor after Phase B.

### Required correction

Define an explicit monotonic host-time abstraction now.

Examples:

```swift
public struct MIDIIngressTimestamp: Equatable, Sendable, Hashable {
    public let monotonicNanoseconds: UInt64
}
```

or another clearly documented monotonic representation.

Likewise, Musical Engine timing APIs should use a named monotonic host-time type rather than ambiguous wall-clock `TimeInterval` if practical.

Then:

1. Convert CoreMIDI `MIDITimeStamp` into the canonical monotonic domain.
2. Preserve packet timestamps through parsing.
3. Ensure RTP-MIDI ingress can normalize into the same local monotonic domain later.
4. Keep wall-clock dates only for diagnostics/log presentation, not timing math.
5. Ensure event-to-action latency can be measured from the same time base.

The actual Phase C MIDI Clock provider may remain deferred, but the **timestamp representation and ingress plumbing contract should land now**.

### Acceptance tests

- packet timestamp propagates to all events parsed from that packet
- timestamp does not depend on system wall-clock changes
- pending MIDI message completed by a later packet has an explicitly defined timestamp policy
- realtime event retains the packet timestamp in which its status byte arrived
- latency IDs/timestamps can be carried forward without conversion ambiguity

### Important timestamp policy question to resolve

For a channel message split across packets, define whether the normalized message timestamp is:

- status-byte packet time,
- first-data-byte packet time,
- or completion/final-data-byte packet time.

For low-latency trigger semantics, **completion/final-byte time is generally the most defensible ingress timestamp**, while retaining first-byte time separately only if diagnostics need it. Pick one rule and test it.

---

# 7. P1-1 — Remove Remaining Stringly-Typed Contract Fields

### File

`Sources/AuroraModel/AMEModels.swift`

### Current fields

```swift
AMETriggerDefinition.messageType: String
AMEMapping.quantizeBoundary: String?
MusicalEngineProjectSettings.timingPolicy: String
```

There is also a duplicated AME-side quantization failure enum while `AuroraMusical` has its own equivalent type.

### Risks

These allow persisted values such as:

```text
"noteonn"
"nextBarr"
"externlMIDI"
```

that compile and save successfully but fail later at runtime.

This is exactly the type of bug the Phase A contracts are supposed to prevent.

### Required correction

Replace with persisted enums / tagged types where module boundaries permit.

Recommended concepts:

```swift
enum AMEMIDIMessageType: String, Codable { ... }

enum AMEQuantizationBoundary: Codable { ... }

enum MusicalTimingPolicyStorage: String, Codable { ... }
```

If the model deliberately avoids depending on `AuroraMusical`, use a model-side persisted representation with an explicit conversion layer. Do not use arbitrary strings as the public contract.

The same principle applies to action storage as described above.

---

# 8. P1-2 — Configuration Validator Is Too Shallow for the Persisted v4 Graph

### File

`Sources/AuroraModel/AMEConfigurationValidator.swift`

The validator is a good start and correctly checks several broken references, empty sequences, invalid weighted-random weights, impossible transform input ranges, and sync-required/internal-only conflicts.

However, schema v4 now persists a fairly rich reference graph. The validator should catch more corruption **before performance mode**.

### Add validation for at least

#### Identity / duplicate IDs

- duplicate trigger IDs
- duplicate group IDs
- duplicate mapping IDs
- duplicate mapping-set IDs
- duplicate sequence IDs
- duplicate source-binding IDs
- duplicate song-section IDs

#### Trigger validity

- neither `triggerID` nor `triggerGroupID` selected
- both `triggerID` and `triggerGroupID` selected when semantics require exactly one
- channel outside valid MIDI range 0...15
- data values outside 0...127 where applicable
- min > max
- message-type incompatible fields
- invalid/unknown message type eliminated by typed model

#### Mapping inheritance

- missing `disablesParentID`
- self override
- self disable
- override/disable cycles
- one mapping attempting to both override and disable the same parent
- duplicate/ambiguous children overriding the same parent at the same effective scope/priority
- illegal parent/child scope direction

#### Legacy ownership

- multiple AME mappings claiming the same legacy mapping ID
- multiple AME mappings claiming the same legacy rule ID
- optional: claim ID does not exist in the project legacy collection

#### Mapping sets / section references

- section `mappingSetIDs` referencing missing sets
- section `localMappingIDs` referencing missing mappings
- local mapping does not actually have matching section scope
- mapping set duplicate IDs / duplicate mapping membership if not intentional

#### Sequence validity

- `initialIndex` outside steps array
- non-finite / non-positive weighted random weights
- duplicate step IDs
- section `sequenceIDsOnEnter` referencing missing sequences
- sequence reset/state-scope contradictions
- broken actions inside sequence steps

#### Actions

Validate references in:

- mapping actions
- sequence-step actions
- section on-enter actions
- section on-exit actions
- recursively inside compound actions

Reference checks should include all currently resolvable action types, including:

- cue
- preset
- palette
- song
- section
- MIDI behavior
- sequence
- effects when the referenced object exists in the model

#### Musical settings

- BPM finite and > 0
- freewheel duration finite and >= 0
- valid meter numerator/denominator
- selected source binding exists
- external policy with no external source selected/configured

#### Transforms

- all values finite
- input range valid
- dead zone valid
- threshold valid for intended domain

### Determinism

Validation issue ordering should be deterministic so tests and diagnostics do not flicker.

---

# 9. P1-3 — Sequence Lifecycle / State Scope Is Ambiguous

### Files

- `Sources/AuroraModel/AMEModels.swift`
- `Sources/AuroraModel/SongSection.swift`

### Current model

Sequences have:

```swift
resetPolicy: AMESequenceResetPolicy
sharedAcrossSections: Bool
```

Sections separately have:

```swift
sequenceIDsOnEnter: [UUID]
```

with the comment:

```text
Sequence IDs that reset/arm when this section is entered.
```

### Problem

There are now two overlapping mechanisms that can control section-entry sequence behavior:

1. `sequence.resetPolicy == .onSectionEntry`
2. `section.sequenceIDsOnEnter`

It is not defined whether `sequenceIDsOnEnter`:

- merely associates a sequence with the section,
- resets it,
- arms it,
- resets only when its own policy permits,
- or overrides the sequence's reset policy.

`sharedAcrossSections: Bool` is also underspecified. Runtime state must know whether sequence state is:

- global per sequence,
- per song,
- per section,
- or per mapping/reference.

### Required correction

Define this now before Phase E runtime state is built.

Prefer explicit semantics over a Boolean, e.g.:

```swift
enum AMESequenceStateScope {
    case sequenceGlobal
    case perSong
    case perSection
}
```

or whatever semantics match the design.

Define a single source of truth for reset policy. If section membership is required, rename `sequenceIDsOnEnter` to reflect association rather than silently embedding reset behavior.

Document and test the exact section transition order already specified in the amendments:

1. old section `onExit`
2. change active section
3. resolve inheritance
4. reset/arm sequences
5. new section `onEnter`

Also define whether lifecycle actions can themselves request quantization.

---

# 10. P1-4 — MIDI Clock Capability Currently Overstates Song Position Support

### File

`Sources/AuroraMusical/MusicalTypes.swift`

### Current implementation

```swift
public static let midiClock = TimingSourceCapabilities(
    suppliesTempo: true,
    suppliesPhase: true,
    suppliesTransport: true,
    suppliesSongPosition: true,
    suppliesMeter: false
)
```

### Problem

MIDI Clock (`F8`) itself does not provide Song Position Pointer. SPP is a separate System Common message and a device/source may send clock/transport without ever sending SPP.

Therefore a generic `midiClock` capability cannot truthfully guarantee:

```swift
suppliesSongPosition: true
```

### Required correction

Capabilities should describe the actual active provider/source behavior, not the theoretical union of MIDI timing messages Aurora knows how to parse.

Options:

- make generic MIDI Clock `suppliesSongPosition = false` and let the adapter enable it when SPP is observed/configured,
- or distinguish `supportsSongPositionInput` from `currentlySuppliesSongPosition`,
- or construct capabilities per source/provider instance.

This matters for diagnostics and quantization fallback decisions.

---

# 11. P1-5 — Numeric Invariants Need to Be Defined Before Phase B Math

### Files

- `Sources/AuroraMusical/MusicalTypes.swift`
- `Sources/AuroraModel/AMEModels.swift`
- `Sources/AuroraModel/Song.swift`

Current constructors clamp a few integer values but allow many mathematically invalid or ambiguous states.

Examples:

```swift
Meter(numerator: 4, denominator: 3)
MusicalDuration(count: -2)
MusicalDuration(dotted: true, triplet: true)
QuarterNotePosition(quarters: .nan)
defaultTempoBPM = -120
freewheelSeconds = -1
AMEValueTransform(deadZone: -5)
```

### Required correction

Define invariants now so Phase B does not have to defend against arbitrary invalid domain values at every calculation.

At minimum:

- meter numerator > 0
- denominator restricted to supported musical denominators (normally powers of two)
- BPM finite and within a sane supported range
- musical duration count finite and > 0
- define whether dotted + triplet simultaneously is legal; if not, make it unrepresentable
- quarter-note positions finite
- phases finite and normalized to `[0, 1)` rather than allowing exactly `1` unless `1` has an explicit meaning
- freewheel duration finite and >= 0
- transforms finite with valid ranges
- sequence weights finite

Prefer failable/throwing validated construction or a validator plus private/set-controlled representation where practical. Avoid silently clamping malformed persisted data into a different musical meaning without diagnostics.

---

# 12. P1-6 — Inheritance / Override Model Needs Deterministic Invariants

### File

`Sources/AuroraModel/AMEModels.swift`

The persisted model provides:

```swift
overrideParentID
disablesParentID
priority
scope
```

but Phase A does not define enough invariants to guarantee deterministic interpretation later.

Before these fields become user-authored project data, document and test:

- project -> song -> section precedence
- whether a child may override only an ancestor scope
- whether same-scope override is legal
- how `priority` interacts with inheritance
- what happens if two effective mappings override one parent
- disable vs override precedence
- cycle handling
- whether disabled mappings can still own/claim legacy IDs (recommended: ownership remains independent of enabled state, but document it)

The runtime implementation can wait until Phase D, but the persisted graph must not permit ambiguous structures without diagnostics.

---

# 13. P2-1 — Expand Phase A Tests

The current Phase A tests are useful smoke tests, but they are too small relative to the number of new persisted contracts.

Add targeted tests for the following.

## MIDI parser

- incomplete Note On split across packets with realtime interleaving in both packets
- incomplete SPP split across packets with realtime interleaving
- system common aborting a pending channel message
- channel status aborting malformed system common
- running status correctly cleared by System Common
- realtime does **not** clear running status
- `F9` / `FD` undefined realtime does not poison parsing
- Active Sensing / System Reset interleave behavior
- timestamp policy for split messages
- packet timestamp propagation

## AuroraAction

- every action case round-trips
- compound actions round-trip without loss
- nested compound actions
- safety recursion

## AME model

- malformed parallel-array state should disappear after typed action conversion
- duplicate ID validation
- inheritance cycles
- ambiguous overrides
- duplicate legacy claims
- missing `disablesParentID`
- missing mapping sets/local mappings in sections
- missing sequence lifecycle IDs
- initial sequence index range
- broken action references in mappings, sequence steps, and lifecycle actions

## Musical contracts

- compound meter beat grouping
- invalid meter rejection
- invalid duration rejection
- SPP exact conversion boundaries
- no accidental assumption that MIDI Clock supplies meter
- capability behavior when SPP is unavailable

## Persistence

- v3 -> v4 migration
- v4 round trip with nontrivial AME graph
- v4 missing `ame.json` fails load
- nested compound actions survive project save/load
- sections/mapping sets/sequences/actions preserve IDs exactly

---

# 14. P2-2 — Add `ame.json` to the Explicit Required-File Regression Test

### File

`Tests/AuroraModelTests/ProjectPackageRequiredFilesTests.swift`

`ProjectPackage.currentSchemaRequiredCollectionFiles` correctly includes `ame.json`, and load logic correctly requires it for schema >= 4.

However, the test:

```swift
testMissingCurrentSchemaExtensionFilesFailLoad()
```

iterates:

```text
stage-layout.json
midi-rules.json
midi-behaviors.json
drum-profiles.json
midi-feedback.json
effects.json
```

but omits:

```text
ame.json
```

Add it to the regression matrix. This is small but important because `ame.json` is the centerpiece of schema v4.

---

# 15. P2-3 — Keep Phase A Placeholder APIs From Becoming Accidental ABI

### File

`Sources/AuroraMusical/TimingProvider.swift`

`MusicalEngine` is explicitly described as a Phase A placeholder, which is fine.

It currently uses:

- `NSLock`
- `@unchecked Sendable`
- a drainable timeline event array
- mutable test replacement API

Do not build Phase B around these merely because they now exist publicly.

Phase B should deliberately choose the real concurrency/event-delivery model, including:

- single serialized owner / actor / dedicated queue strategy
- snapshot publication semantics
- timeline-event subscription semantics
- scheduler ownership
- provider lifecycle ownership
- deterministic test clock injection

Likewise, `TimingProvider.start()/stop()` and `MusicalTimingSink` should be reviewed against that concurrency model before becoming widely consumed.

This is not a request to prematurely implement Phase B. It is a request to treat these as scaffolding rather than immutable API.

---

# 16. Additional Observations That Are Good and Should Be Preserved

The review found several strong decisions that should **not** be regressed while correcting the issues above:

1. Keep `AuroraMusical` independent of CoreMIDI.
2. Keep `MusicalTimingState` separate from `ShowMusicalContext`.
3. Keep SPP as System Common, not System Real-Time.
4. Keep interleaved System Real-Time parsing immediate and non-destructive.
5. Keep Note On velocity 0 normalization.
6. Keep song sections as first-class IDs and do not silently rewrite `SongEntry.label` into sections.
7. Keep `ame.json` separated from legacy MIDI files during migration.
8. Keep mapping-identity ownership claims rather than suppressing legacy behavior by event shape.
9. Keep reject-newest queue-overflow intent for future scheduler implementation.
10. Keep safety actions conceptually outside quantization.
11. Keep tap tempo as an estimator feeding internal timing rather than pretending it is a continuous timing provider.
12. Keep source selection distinct from active/fallback source state.
13. Keep provenance as a first-class Musical Engine concept.

---

# 17. Required Phase A Closeout Order

Grok should perform remediation in roughly this order:

### A1. Fix musical time contracts

- Add beat unit/grouping to the canonical meter/timing model.
- Define numeric invariants.
- Correct capability semantics.
- Add compound-meter tests.

### A2. Fix action persistence

- Replace AME parallel key/parameter arrays with typed actions.
- Implement lossless recursive compound action coding.
- Make safety classification recursive.
- Update validator and package tests.

### A3. Fix timestamp contract

- Define canonical monotonic timestamp type/domain.
- Preserve CoreMIDI packet timestamp in ingress plumbing.
- Define split-message timestamp semantics.
- Add tests.

### A4. Harden AME model graph

- Replace stringly enum-like fields.
- Define inheritance invariants.
- Clarify sequence state/reset semantics.
- Expand validator.

### A5. Regression / closeout

Run the complete macOS suite and add the tests listed above.

Do not implement:

- internal Musical Engine runtime clock,
- scheduler firing,
- MIDI Clock provider/PLL,
- AME mapping evaluation runtime,
- dedicated AME UI.

Those remain later phases.

---

# 18. Phase A Re-Acceptance Gate

Phase A can be accepted for Phase B when all of the following are true:

- [ ] Compound meter has an explicit metrical-beat/grouping contract.
- [ ] `nextMetricalBeat` is mathematically well-defined for 4/4, 6/8, 12/8, and explicit asymmetric grouping.
- [ ] AME mappings, sequence steps, and section lifecycle actions use a safe typed representation.
- [ ] `AuroraAction.compound` is losslessly Codable.
- [ ] Safety classification recursively detects safety actions inside compound actions.
- [ ] Quantization validation recursively rejects delayed safety actions.
- [ ] MIDI ingress uses a defined monotonic time domain.
- [ ] CoreMIDI packet timestamps are preserved/normalized by the ingress contract.
- [ ] Stringly contract fields (`messageType`, `quantizeBoundary`, `timingPolicy`) are replaced or strongly wrapped.
- [ ] Sequence state scope and section-entry/reset semantics are unambiguous.
- [ ] MIDI Clock capabilities do not falsely promise SPP.
- [ ] AME validation catches ambiguous/broken inheritance and the major reference-graph failures listed above.
- [ ] `ame.json` missing-file behavior has an explicit regression test.
- [ ] New Phase A tests pass.
- [ ] Existing legacy MIDI tests still pass.
- [ ] Existing project migration/package tests still pass.
- [ ] Full macOS test suite passes with zero regressions.

---

# 19. Final Review Disposition

**Do not proceed to Phase B yet.**

This is a good Phase A first pass. The architecture is pointed in the correct direction and several difficult MIDI details were handled correctly. The remaining issues are precisely the kind that should be corrected at a contract checkpoint, before clock math, scheduler queues, phase-lock behavior, AME evaluation, and UI are built on top of them.

The primary goal of this closeout is not to expand scope. It is to make the Phase A foundation **typed, lossless, musically unambiguous, monotonic-time-safe, and difficult to misconfigure**.

Once those corrections are complete, Phase B can build on a substantially stronger foundation instead of carrying avoidable migration debt into the runtime.
