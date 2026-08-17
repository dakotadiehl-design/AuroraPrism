# Aurora AME + Musical Engine
## Phase C Closeout Acceptance + Phase D Pass 1 Deep Code Review Fixes

**Review date:** 2026-08-16  
**Reviewed archive:** `Aurora_PhaseCCloseout_PhaseD_Pass1.zip`  
**Scope:** Verify the Phase C remediation, then deeply review the Phase D AME Core implementation against the approved AME/Musical Engine specifications and existing Phase A–C contracts.  

## Disposition

- **Phase C: ACCEPTED.** The previously identified MIDI Clock acquisition, source-switch, phase-alignment, freewheel, and fallback-tempo defects have been materially corrected in code and covered by dedicated tests.
- **Phase D: NOT YET ACCEPTED.** The architecture is promising, but several core runtime semantics are incomplete or unsafe, especially held/release behavior and ingress timestamp preservation.
- **STOP before Phase E.** Do not begin stateful sequences/random modes until this Phase D closeout lands and the full macOS suite is green.

---

# 1. Executive Summary

Phase D is a strong first implementation of the AME evaluation pipeline. The separation between `AuroraMIDI`, `AuroraEngine`, `AuroraModel`, and `AuroraMusical` remains healthy. The headless runtime is testable, the normalized event model is clean, typed `AuroraAction` is preserved, inheritance and scope are represented explicitly, and the ownership transition away from legacy MIDI is moving in the right direction.

However, the current runtime has four issues that should be considered **Phase D blockers**:

1. **The original MIDI ingress timestamp is discarded at the `ControlActionRouter` → AME boundary.** `ameNormalized(from:)` defaults to `HostTime.now()` instead of reconstructing the already-monotonic `MIDIEvent.timestamp`. This violates the Phase A ingress timestamp contract and makes AME latency/debounce/burst behavior dependent on callback processing time rather than actual packet arrival time.
2. **Held releases pass through scope, timing, enabled-state, debounce, and burst-suppression gates before release.** A Note Off can therefore be suppressed after the corresponding Note On successfully acquired a hold, leaving a stuck held state.
3. **`momentary` / `whileHeld` / current `gate` behavior has no outward release action.** Note Off only removes an internal held-table entry. If Note On emitted `.blind`, `.blackout`, a temporary override, etc., Note Off does not undo it. This contradicts the approved behavior contract: “Note On activates, Note Off releases.”
4. **The public AME action surface is larger than the live executor surface.** AME can mark many `AuroraAction` cases executable, while `ControlActionRouter` silently declines to execute anything that cannot bridge to `ShowAction`. This creates “successful” AME emissions that are live no-ops.

There are also important P1 hardening items: rate-limit concurrency is not actually serializable, malformed duplicate IDs can still trap runtime dictionaries, `AMEValueTransform.inMin/inMax` algebraically do not affect scaling, and the current `.gate` implementation does not match the documented “permit another behavior” semantic.

These are fixable without redesigning the AME architecture.

---

# 2. Phase C Closeout Review

## Status: ACCEPTED

The Phase C remediation addresses the previous blockers in actual implementation rather than only in checkpoint language.

### Verified improvements

- External authority is not taken merely because one `F8` arrives; usable external authority requires estimator lock.
- Acquisition has a timeout path for a stray pulse.
- `ClockEstimator.resetForNewSource()` clears source-specific history so source B does not inherit source A’s tempo/stability evidence.
- Stability evidence is cleared on freewheel/loss and invalid return intervals.
- MIDI Start resets phase origin.
- SPP calls `alignPhase(to:)`, keeping estimator pulse phase consistent with canonical quarter-note position.
- Preferred fallback restores a retained internal/song/project tempo baseline instead of continuing indefinitely at the last external tempo.
- Preferred fallback can keep internal authority while an external candidate acquires.
- First external authority acquisition can release scheduler work held for timing availability.
- Freewheel age is measured after the dropout threshold, not from the last pulse itself.
- SPP capability is surfaced dynamically after accepted SPP.
- Source admission remains in the Musical Engine, not only in the MIDI adapter.

### Phase C note

There are a couple of harmless compiler warnings around presently immutable `fireNow` / `canceled` locals in `receiveClockPulse`. These are cleanup only and do not block acceptance.

**Phase C may be marked accepted in its checkpoint.**

---

# 3. P0-D1 — Preserve the Real MIDI Ingress Timestamp End-to-End

**Severity:** P0  
**Files:**
- `Sources/Aurora/ControlActionRouter.swift`
- `Sources/AuroraMIDI/MIDIEvent.swift`
- `Sources/AuroraMIDI/HostTime+MIDI.swift`
- `Sources/AuroraEngine/AME/AMENormalizedEvent.swift`

## Current behavior

`MIDIEvent.timestamp` is already documented and populated as **monotonic seconds**, originating from CoreMIDI packet `HostTime`.

But:

```swift
static func ameNormalized(from event: MIDIEvent, hostTime: HostTime? = nil) -> AMENormalizedEvent? {
    let ht = hostTime ?? HostTime.now()
    ...
}
```

`handleMIDIEvents` calls:

```swift
Self.ameNormalized(from: event)
```

so every AME event is re-timestamped at AME conversion time.

## Why this matters

The approved Phase A contract explicitly required:

> Do not assign timestamps later in AME evaluation.

The ingress time is used for:

- end-to-end latency IDs/measurement,
- debounce,
- burst suppression,
- deterministic ordering,
- future event coalescing policy,
- future quantization diagnostics,
- correlation with Musical Engine state.

If the callback is delayed, or a packet contains multiple events, `HostTime.now()` measures **processing latency**, not arrival time.

## Required fix

Convert the already-monotonic `MIDIEvent.timestamp` back to `HostTime` exactly once at the AME adapter boundary.

Recommended helper:

```swift
public extension HostTime {
    static func fromLegacyMonotonicSeconds(_ seconds: TimeInterval) -> HostTime? {
        guard seconds.isFinite, seconds >= 0 else { return nil }
        let ns = seconds * 1_000_000_000.0
        guard ns <= Double(UInt64.max) else { return nil }
        return HostTime(nanoseconds: UInt64(ns.rounded()))
    }
}
```

Then:

```swift
let ht = hostTime
    ?? HostTime.fromLegacyMonotonicSeconds(event.timestamp)
    ?? HostTime.now() // defensive only, diagnostic-worthy
```

Even better, in a later cleanup, make `MIDIEvent` carry `HostTime` directly and retain `timestamp` only as a compatibility projection. That is not mandatory for this closeout if too invasive.

## Mandatory tests

- Construct a `MIDIEvent` with a known monotonic timestamp and verify `AMENormalizedEvent.hostTime` preserves it.
- Two MIDI events with distinct ingress timestamps processed in one batch must retain distinct AME times.
- Debounce must use ingress timestamps, not the time the router happened to process the batch.
- Latency correlation diagnostics must report the ingress `HostTime`.

---

# 4. P0-D2 — Release Edges Must Never Be Blocked by Fire-Time Preconditions

**Severity:** P0 / stuck-output safety  
**File:** `Sources/AuroraEngine/AME/AMERuntime.swift`

## Current pipeline problem

For a held mapping, the release Note Off becomes a candidate, but then passes through all of these before `evaluateBehavior()` can release the held identity:

1. active scope,
2. inheritance suppression,
3. enabled check,
4. timing requirement,
5. burst suppression,
6. debounce,
7. transform evaluation,
8. behavior evaluation/release.

This allows a valid Note Off to be discarded even though the matching Note On previously acquired a held state.

### Concrete failure examples

#### Debounce trap

- Mapping: `.whileHeld`, debounce = 500 ms.
- Note On at t=0 → hold acquired, action fired, `lastFireSeconds` set.
- Musician releases button/note at t=100 ms.
- Note Off matches release path.
- `rateLimitDecision` suppresses it because 100 ms < 500 ms.
- `held.release(identity)` never runs.
- Gate remains internally held.

#### Timing-loss trap

- `.whileHeld` mapping requires `.externalSyncLocked`.
- Note On arrives while clock is locked and acquires the hold.
- MIDI Clock drops out.
- Note Off arrives while unlocked.
- `timingRequirementFailed` returns before release.
- Held state sticks.

#### Section-change trap

- Section-scoped hold acquired in Section A.
- Section changes to B while the physical button/note is still down.
- Note Off arrives.
- Mapping scope is now inactive, so the held identity is never released.

#### Disable/edit trap

- Hold is acquired.
- Mapping is disabled or removed while held.
- Subsequent release may not traverse the mapping at all.

## Required semantic rule

**Once a held identity has been acquired, the physical release edge owns the right to release that identity regardless of fire-time eligibility.**

A release should not require:

- current scope still active,
- timing still available,
- mapping still enabled,
- debounce/burst window elapsed,
- transform threshold still passing.

These conditions govern **acquisition/fire**, not **release**.

## Recommended implementation

Introduce an explicit early held-release path before candidate fire filtering.

Conceptually:

```text
normalize
→ identify release identities that are currently held
→ release them first / generate release emissions
→ separately evaluate normal fire candidates
```

The held table already has mapping/source/channel/data1 identity. Add efficient lookup if needed.

Do not make Note Off blindly release unrelated mappings. It must still match the acquired identity, including source/channel/note/controller and mapping.

## Configuration transitions

Also ensure these operations deterministically release invalidated holds:

- `updateDocument()` when a held mapping disappears or becomes disabled,
- show-context transition when a section/song-scoped held mapping ceases to be active,
- performance mode changes to edit/disabled if live held output cannot remain valid,
- project close,
- source disconnect,
- panic / MIDI performance disable (already partially wired).

A conservative Phase D closeout is acceptable: release all held state on document/context replacement if selective reconciliation is too much machinery right now. Correctness beats preserving a hold across an edit.

## Mandatory tests

- Note Off within debounce window still releases hold.
- Note Off within burst suppression window still releases hold.
- Note Off after timing requirement becomes false releases hold.
- Note Off after section changes releases or is proactively released on transition.
- Disabling/removing a held mapping releases it deterministically.
- Note Off from another source/channel/note does **not** release the hold.

---

# 5. P0-D3 — Momentary / While-Held Must Emit a Real Release Action

**Severity:** P0 / behavior contract incomplete  
**Files:**
- `Sources/AuroraModel/AMEModels.swift`
- `Sources/AuroraEngine/AME/AMEHeldState.swift`
- `Sources/AuroraEngine/AME/AMERuntime.swift`
- `Sources/AuroraEngine/AME/AMEDiagnostics.swift`
- persistence/validator/tests as required

## Current behavior

On a Note On:

```swift
held.acquire(...)
return .fire
```

On Note Off:

```swift
held.release(identity)
return .releaseOnly
```

Then runtime explicitly says:

```swift
// Phase D: no automatic reverse actions on release
continue
```

That means `.momentary`, `.whileHeld`, and current `.gate` are only **internally** momentary. The live Aurora action fired on press remains whatever state that action created.

Example from the approved specification:

```text
Note On  -> crowd blinders active
Note Off -> release crowd blinders
```

With the current runtime, mapping `actions: [.blind]` produces `.blind` on Note On and **nothing** on Note Off.

## Required model semantics

The mapping model needs a first-class way to describe what happens on release/off.

Recommended clean option:

```swift
public struct AMEMapping {
    ...
    public var actions: [AuroraAction]          // activation / on-edge
    public var releaseActions: [AuroraAction]   // release / off-edge
}
```

Default `releaseActions = []` for migration compatibility.

For known paired actions, the UI can eventually offer convenience autofill:

- `.blind` → `.blindOff`
- `.blackout` → `.blackoutOff`
- `.freeze` → `.freezeOff`

But the runtime should **not guess** arbitrary inverse actions. Many actions have no mathematical inverse.

The held entry may need to snapshot the resolved release actions at acquisition time so a later document edit cannot prevent the release of what was actually activated.

Suggested held entry additions:

```swift
public struct AMEHeldEntry {
    ...
    public var releaseActions: [AuroraAction]
    public var activationLatencyID: UUID?
}
```

Then `releaseAllHeld()` can return enough information for the live integration layer to execute the corresponding releases during disconnect/panic/disable.

## Important distinction

`releaseAllHeld()` currently only clears memory. Once held mappings can create persistent lighting state, “release all” must also give the host the release emissions to execute, not merely entries to discard.

Consider changing to something like:

```swift
public func releaseAllHeld(...) -> [AMEActionEmission]
```

or return a richer result containing released entries + release emissions.

## Toggle also needs explicit semantics

Current `.toggle` flips an internal Boolean and emits actions only when toggled on. It emits nothing on the off transition.

That means:

```text
actions = [.blackout]
```

produces ON, no-op, ON, no-op...

and:

```text
actions = [.toggleBlackout]
```

produces a state change only every *other* input event, which is unintuitive double-toggle behavior.

Use the same model concept for toggle off behavior, e.g. `releaseActions` / `offActions`, or define separate `activationActions` and `deactivationActions` clearly.

### Preferred naming

If this model is still early enough, consider:

```swift
activationActions: [AuroraAction]
deactivationActions: [AuroraAction]
```

instead of `actions` + `releaseActions`.

If migration churn matters, keep `actions` and add `releaseActions`.

## Mandatory tests

- `.whileHeld` fires activation actions on Note On and release actions on Note Off.
- `.momentary` same.
- release-all generates/returns the release actions required to unwind every live hold.
- `.toggle` emits activation on first qualifying edge and deactivation on second.
- nested/compound release actions preserve recursive safety classification.
- dry-run reports activation/deactivation but executes neither.

---

# 6. P0-D4 — Do Not Silently Drop “Executable” AuroraActions

**Severity:** P0/P1 depending on chosen Phase D boundary  
**Files:**
- `Sources/Aurora/ControlActionRouter.swift`
- `Sources/AuroraMIDI/AuroraAction+ShowAction.swift`
- AME validator/diagnostics

## Current behavior

`AMERuntime` emits typed `AuroraAction` and sets `shouldExecute = true` in armed mode.

`ControlActionRouter` then does:

```swift
if let showAction = emission.action.asShowAction {
    applyLive(...)
} else {
    notify(.go, "AME_UNBRIDGED ...")
}
```

So actions such as these can be considered executable by AME but are discarded by the live path:

- `selectSong`
- `enterSection`
- `nextSection` / `previousSection`
- `firePreset`
- `firePalette`
- `fireLook`
- `runBehavior`
- sequence actions
- `tapTempo`
- transport actions
- `setTempoBPM`
- effect actions

Some are legitimately scheduled for later phase integration. The problem is **silent semantic success**: the AME runtime and diagnostics say the mapping emitted an executable action, while live Aurora does nothing.

Also, observer notification fakes `.go` for unbridged actions:

```swift
notify(.go, "AME_UNBRIDGED ...")
```

which makes the observer API semantically misleading.

## Required closeout choice

Choose one of these explicitly:

### Option A — General AuroraAction executor now (preferred architecture)

Create an application-layer executor/dispatcher protocol capable of accepting any `AuroraAction` and routing it to the owning subsystem.

```swift
protocol AuroraActionExecuting: Sendable {
    func execute(_ action: AuroraAction, context: AuroraActionExecutionContext)
}
```

`ControlActionRouter` should not be the permanent place that converts the generalized model back down into a legacy `ShowAction` subset.

Subsystem handlers can initially return `.unsupportedInCurrentPhase` for genuinely deferred actions.

### Option B — Explicitly constrain Phase D supported actions

If full generalized execution is intentionally later, then:

- validator must warn/error for AME mappings using actions unsupported by the Phase D live executor,
- emission result must identify unsupported execution rather than `shouldExecute=true`,
- diagnostics must say `unsupportedAction`, not “armed emission”,
- observer API must not forge `.go`.

Do not let a user configure an AME mapping that appears armed and successful but is operationally a no-op.

## Mandatory tests

- Every `AuroraAction` case accepted by Phase D either executes through a defined handler or returns an explicit unsupported result.
- No `shouldExecute=true` emission disappears without an execution outcome/diagnostic.
- Unbridged action observers do not receive fake `.go` semantics.

---

# 7. P1-D5 — `AMEValueTransform.inMin/inMax` Currently Cancel Out Algebraically

**Severity:** P1  
**File:** `Sources/AuroraEngine/AME/AMERuntime.swift`

## Current formula

```swift
let inValue = t.inMin + raw * (t.inMax - t.inMin)
var unit = (inValue - t.inMin) / (t.inMax - t.inMin)
```

Substitute the first into the second:

```text
unit = raw
```

Therefore changing `inMin` and `inMax` does **not change the scaling curve at all**. They only alter the units used by dead-zone and threshold logic.

Given the model defaults of `0...127`, these fields clearly appear intended to describe an input-domain window.

## Recommended semantics

Convert normalized MIDI back to the canonical MIDI input domain first:

```swift
let midiValue = raw * 127.0
let unit = (midiValue - t.inMin) / (t.inMax - t.inMin)
```

Then define clearly whether values outside `[inMin, inMax]`:

- clamp to 0/1, or
- reject.

Clamping is likely friendlier for continuous controls; threshold remains the tool for explicit rejection.

Dead-zone semantics should also be documented as either:

- input-unit radius, or
- normalized fraction.

The current model strongly suggests input units.

## Mandatory tests

- `inMin=32, inMax=96`: MIDI 32 → output min, MIDI 64 → midpoint, MIDI 96 → output max.
- Values below/above range follow the documented clamp/reject policy.
- invert operates after normalization.
- dead zone and threshold operate in documented units.

---

# 8. P1-D6 — AMERuntime Is Thread-Safe but Debounce/Burst Evaluation Is Not Serializable

**Severity:** P1; can become P0 with multiple simultaneous MIDI sources  
**File:** `Sources/AuroraEngine/AME/AMERuntime.swift`

The class claims:

```swift
/// Process one normalized performance event. Thread-safe.
```

Individual state tables are locked, but the **check → evaluate → mark** sequence is not atomic.

Two threads can do:

```text
A: rateLimitDecision -> allowed
B: rateLimitDecision -> allowed
A: markFired
B: markFired
```

Both fire despite debounce/burst suppression.

CoreMIDI can present traffic from multiple endpoints/callback contexts, and future remote/simulation paths may also call AME concurrently.

## Required fix

Choose an explicit runtime serialization model.

Preferred options:

1. A dedicated serial executor/queue/actor owns AME ephemeral evaluation state, or
2. Make the relevant state transition atomic under one runtime lock.

Avoid holding a coarse lock while calling arbitrary external execution callbacks; AMERuntime currently returns results, which makes internal serialization relatively easy.

At minimum, rate-limit eligibility + reservation must be atomic before action evaluation.

## Mandatory test

A concurrency test launches two same-mapping events with ingress times inside the debounce window concurrently and proves only one is accepted.

---

# 9. P1-D7 — Runtime Must Not Trap on Malformed Duplicate IDs

**Severity:** P1 hardening  
**File:** `Sources/AuroraEngine/AME/AMERuntime.swift`

Phase A correctly changed validator dictionaries to “first wins” so malformed duplicate IDs produce diagnostics instead of crashing.

Phase D reintroduces unconditional dictionaries:

```swift
Dictionary(uniqueKeysWithValues: doc.sourceBindings.map { ... })
Dictionary(uniqueKeysWithValues: doc.triggers.map { ... })
Dictionary(uniqueKeysWithValues: doc.triggerGroups.map { ... })
Dictionary(uniqueKeysWithValues: doc.sequences.map { ... })
```

If corrupted or programmatically constructed data bypasses validation, runtime can trap.

Validation is important, but a live show-control runtime should not crash because a malformed document slipped through.

## Required fix

Use defensive first-wins/last-wins construction with diagnostics, or require a validated immutable runtime configuration type produced by a throwing compiler step.

Preferred long-term pattern:

```text
AMEProjectDocument
   ↓ validate/compile
AMECompiledConfiguration
   ↓ runtime
AMERuntime
```

A compiled configuration can pre-index IDs once instead of rebuilding dictionaries on every MIDI event.

For this closeout, safe dictionary construction is enough. Precompilation is a strong optimization recommendation but not mandatory.

## Mandatory test

Malformed duplicate trigger/sequence/source-binding IDs must not crash `process()`.

---

# 10. P1-D8 — `.gate` Does Not Implement the Documented Gate Semantic

**Severity:** P1 architectural clarity  
**Files:** `AMEModels.swift`, `AMERuntime.swift`, spec/checkpoint comments

The approved spec describes Gate as:

> event/value controls whether another behavior is permitted

The current runtime treats `.gate` identically to `.momentary` / `.whileHeld`: high/Note On acquires a held identity and fires the mapping’s own actions; low/Note Off clears the held identity.

That is a useful behavior, but it is a **held trigger**, not a gate that controls permission for another behavior/mapping.

## Required decision

Before Phase E adds more state on top, lock terminology and semantics.

Either:

### A. Implement real gating

Add an explicit target/condition relationship, such as a gate state key consumed by other mappings.

or

### B. Rename the present behavior

If the intended product behavior is simply threshold-held activation, name it accordingly (`valueGate`, `heldGate`, etc.) and reserve `.gate` for future conditional routing.

Do not keep one enum case whose runtime meaning differs materially from the design document.

---

# 11. P1-D9 — Held State Must Reconcile with Document/Context/Mode Changes

**Severity:** P1, closely related to D2/D3  
**Files:** `AMERuntime.swift`, `ControlActionRouter.swift`

`updateDocument`, `updateShowContext`, and `performanceMode` currently replace state without reconciling active holds/toggles.

Examples:

- mapping removed while held,
- mapping disabled while held,
- section changes while section-local blind button is held,
- dry-run/edit transition while active live holds exist.

Once release actions are modeled, these transitions need deterministic unwind rules.

Recommended baseline:

- document replacement: release any held mappings no longer valid/enabled; conservative release-all acceptable in Phase D,
- context change: release holds whose scope is no longer active,
- armed → dryRun/edit: release all live held effects before changing posture,
- project close / MIDI disable / source disconnect / panic: release all with outward deactivation emissions.

Toggle state also needs a stated policy on song/section transition. Do not let project-global and section-local toggle state accidentally share one lifetime merely because both are keyed only by mapping ID.

---

# 12. P2-D10 — Performance and Determinism: Compile the AME Document Once

**Severity:** P2 now, likely P1 before hardware soak  
**File:** `AMERuntime.swift`

Every MIDI event currently reconstructs multiple dictionaries and scans all triggers/groups/mappings.

For a modest configuration this is fine, but AME’s main motivating use case is dense drum traffic plus MIDI Clock plus live UI/output work.

Consider compiling `AMEProjectDocument` on `updateDocument()` into immutable runtime indexes:

- source binding by ID,
- trigger by ID,
- triggers indexed by message type/channel/data1 where practical,
- trigger groups reverse index (trigger → groups),
- sequences by ID,
- mappings by trigger/group,
- validated inheritance suppression relationships.

Benefits:

- lower allocation pressure on MIDI callback path,
- no per-event duplicate-key traps,
- deterministic validation boundary,
- simpler Phase E sequence integration.

Not required to accept Phase D if correctness fixes above land, but worth doing before Phase I soak.

---

# 13. Diagnostics Improvements Required by the Fixes

Add diagnostic kinds for at least:

```swift
case heldReleaseEmission
case heldReleasedByContextChange
case heldReleasedByDocumentChange
case heldReleasedByModeChange
case unsupportedAction
case invalidRuntimeConfiguration
case timestampFallbackUsed
```

Do not use fake `ShowAction.go` as a carrier for non-ShowAction diagnostics.

Longer term, UI observers should receive a typed control/AME diagnostic event rather than overloading `(ShowAction, String)`.

---

# 14. Tests Missing from Phase D Pass 1

The existing `AMERuntimePhaseDTests` cover many happy-path behaviors and are useful. Add the following before acceptance.

## Held/release correctness

- [ ] Note On acquires; Note Off emits release action.
- [ ] release inside debounce window is not suppressed.
- [ ] release inside burst window is not suppressed.
- [ ] release after timing loss is not suppressed.
- [ ] release after section/context change unwinds correctly.
- [ ] release after mapping disable/removal unwinds correctly.
- [ ] disconnect/release-all returns or emits all required deactivation actions.
- [ ] wrong source/channel/note cannot release another hold.
- [ ] velocity-zero Note On reaches the exact same release semantics.

## Toggle

- [ ] first edge emits activation; second emits deactivation.
- [ ] toggle state lifetime is defined across section/song transitions.

## Timestamp

- [ ] MIDIEvent monotonic timestamp is preserved into `AMENormalizedEvent`.
- [ ] batched events retain distinct timestamps.
- [ ] debounce uses ingress timestamp.

## Value transforms

- [ ] non-default `inMin/inMax` materially affect transform result.
- [ ] edge clamps/rejections documented and tested.
- [ ] dead-zone and threshold unit semantics tested.

## Runtime safety/hardening

- [ ] duplicate IDs cannot crash runtime.
- [ ] concurrent debounce cannot double-fire.
- [ ] unsupported AuroraAction produces explicit unsupported result/diagnostic.

## Source/context

- [ ] disabled/unresolved source binding cannot match.
- [ ] two identical-name devices do not accidentally satisfy a binding when a stable unique identity is available.

---

# 15. Phase D Closeout Implementation Order

Recommended order:

```text
D1 preserve ingress HostTime
  → D2/D3 redesign held acquisition/release output semantics together
    → D4 make executable AuroraAction outcomes explicit
      → D5 fix transform math
        → D6 serialize rate-limit state
          → D7 defensive runtime configuration indexing
            → D8 clarify real Gate semantic
              → tests + checkpoint
                → STOP
```

Do **not** start stateful sequence advancement while held-state semantics are still changing. Phase E will otherwise bind sequence state to an unstable event lifecycle.

---

# 16. Suggested Held-State Shape

A minimal direction that preserves current architecture:

```swift
public struct AMEMapping {
    ...
    public var actions: [AuroraAction]
    public var releaseActions: [AuroraAction]
}

public struct AMEHeldEntry {
    public var identity: AMEHeldIdentity
    public var acquiredHostTime: HostTime
    public var controlValue: Double
    public var releaseActions: [AuroraAction]
    public var mappingScope: AMEMappingScope
}
```

The release decision should happen against the **held entry that was actually acquired**, not by re-proving every current mapping condition.

Conceptual event flow:

```text
Incoming event
    │
    ├─ release edge?
    │    └─ find exact held identity
    │         └─ remove hold + emit snapshotted release actions
    │
    └─ acquisition/fire path
         ├─ trigger/scope/inheritance/enabled/timing
         ├─ debounce/burst
         ├─ transform
         └─ behavior
              └─ acquire hold with release snapshot + emit activation
```

This makes release robust against timing loss, section transitions, configuration edits, and rate limiting.

---

# 17. Phase D Re-Acceptance Gate

Phase D is ready for Phase E only when all of the following are true:

- [ ] CoreMIDI-originated monotonic ingress timestamp survives into AME unchanged.
- [ ] Held release cannot be blocked by debounce, burst suppression, timing loss, or scope change.
- [ ] Momentary/while-held activation has a defined outward deactivation/release action path.
- [ ] `releaseAllHeld` can actually unwind the live effects created by held mappings.
- [ ] Toggle has defined ON and OFF output semantics.
- [ ] Gate semantics match the product definition or the enum is renamed/documented.
- [ ] Armed AME actions cannot silently disappear because they are not bridgeable to legacy `ShowAction`.
- [ ] Value transform input ranges work mathematically.
- [ ] Concurrent debounce/burst evaluation cannot double-fire.
- [ ] Malformed duplicate IDs cannot trap the live runtime.
- [ ] Full macOS test suite is green.
- [ ] `CHECKPOINT_AME_PHASE_D_AFK.md` is updated with actual final semantics and test count.

**STOP before Phase E for human review.**

---

# 18. What Should NOT Be Reworked

The following implementation choices look healthy and should be preserved unless a fix above requires a small API adjustment:

- `AuroraEngine` owns the headless AME evaluator; CoreMIDI stays in `AuroraMIDI`.
- `AMENormalizedEvent` is CoreMIDI-free.
- `AuroraAction` remains the semantic action type.
- Musical timing enters AME as a snapshot rather than AME owning the Musical Engine.
- Dry-run/edit/armed are explicit runtime postures.
- Disabled AME mappings continue to own legacy migration claims.
- Scope specificity + explicit override/disable remain separate concepts.
- Safety actions bypass quantization intent.
- Quantization execution itself remains Phase G.
- Stateful sequence advancement remains Phase E.
- AME does not write raw DMX.

---

# 19. Final Review Verdict

## Phase C

**GREEN — ACCEPTED.**

The external MIDI timing layer now has a sufficiently coherent authority lifecycle to serve later AME quantization work.

## Phase D Pass 1

**YELLOW/RED — strong architecture, but closeout required before Phase E.**

The key concern is not sequence functionality. It is the lifecycle of a real physical control:

```text
press → activate → hold → release → unwind
```

That lifecycle must be unbreakable. A drummer, foot controller, or future iPad busk button cannot leave blinders, fog, overrides, or other held effects stuck because clock vanished, a section changed, or debounce happened to be active.

Fix held/release semantics and preserve the true ingress timestamp first. Then harden action execution, transforms, and concurrency. After that, Phase D will be a solid foundation for Phase E’s stateful sequences.
