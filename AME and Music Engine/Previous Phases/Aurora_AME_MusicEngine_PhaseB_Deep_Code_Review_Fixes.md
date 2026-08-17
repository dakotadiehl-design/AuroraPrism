# Aurora AME + Musical Engine — Phase B Deep Code Review Fixes

**Review target:** `Aurora_AMEMusicEngine_PhaseB(1).zip`  
**Review date:** 2026-08-16  
**Phase:** B — Musical Engine Core  
**Disposition:** **NOT YET ACCEPTED FOR PHASE C**  
**Required action:** Close the findings below, run the complete macOS test suite, update the Phase B checkpoint, then **STOP** for human review before beginning Phase C.

---

# 1. Executive Summary

Phase B is directionally strong and preserves the major architectural decisions established in Phase A:

- `AuroraMusical` remains independent of CoreMIDI.
- The engine uses a monotonic `HostClock` abstraction.
- `MusicalMeter` now carries explicit beat grouping and compound/asymmetric meter math is centralized.
- Tap tempo is an estimator feeding internal tempo rather than pretending to be a continuous timing provider.
- The scheduler uses typed commands and stable cancellation IDs.
- Safety classification is derived from the scheduled command rather than a free-standing mutable Boolean.
- Timeline discontinuity events exist.
- Show context remains separate from timing state.
- The scheduler rejects newest decorative work rather than silently dropping previously accepted events.
- The future Effects consumer seam is visible in the API.

The implementation is therefore **not a redesign candidate**. The overall shape should be preserved.

However, several runtime-state semantics are not yet safe enough to become the substrate for Phase C. Two are particularly serious:

1. Selecting strict external MIDI timing can leave the internal source active, so the internal clock continues advancing even though policy says external MIDI.
2. `.immediate` / safety work is not necessarily immediate while transport is running; it can sit in the scheduler until the next `tick()`.

A third major issue is that pending quantized actions do not actually honor their individual `QuantizationFailurePolicy` when timing stops or becomes unavailable. The current `stopTransport(cancelPending:)` path applies a global cancel/keep decision instead.

These should be corrected before any MIDI Clock PLL/provider work lands, because Phase C will multiply the number of source-loss, transport, and re-lock transitions hitting these paths.

---

# 2. Verification Performed

The review covered the Phase B runtime and its immediate integration contracts, including:

- `Sources/AuroraMusical/MusicalEngine.swift`
- `Sources/AuroraMusical/MusicalScheduler.swift`
- `Sources/AuroraMusical/MusicalSchedulerContracts.swift`
- `Sources/AuroraMusical/MusicalBoundaryMath.swift`
- `Sources/AuroraMusical/MusicalTypes.swift`
- `Sources/AuroraMusical/MusicalState.swift`
- `Sources/AuroraMusical/TimingProvider.swift`
- `Sources/AuroraMusical/MusicalTimelineEvent.swift`
- `Sources/AuroraMusical/HostClock.swift`
- `Sources/AuroraEngine/AuroraActionTokenRegistry.swift`
- `Sources/AuroraEngine/MusicalMeterBridge.swift`
- `Tests/AuroraMusicalTests/MusicalEnginePhaseBTests.swift`
- Phase A closeout contracts and the AME/Musical Engine planning amendments
- `docs/design/CHECKPOINT_AME_PHASE_B_MUSICAL_ENGINE.md`

Local verification in the review environment:

```text
swift build --target AuroraMusical
```

completed successfully.

A complete `swift test` cannot be executed in this Linux review environment because the full package contains macOS-only dependencies such as `CoreMIDI` and `Network`. The archive's Phase B checkpoint reports **593 tests / 0 failures** on macOS; that result must be rerun after the fixes below and should remain the release gate.

Compiler warnings observed in the reviewed Phase B code also include:

```text
MusicalScheduler.swift: unused `safetyCap`
MusicalEngine.swift: `events` in setShowContext is never mutated
```

These are not blockers by themselves, but should be removed during closeout.

---

# 3. P0 — Strict External Timing Policy Can Continue Running the Internal Clock

## Problem

`MusicalEngine.setTimingPolicy(_:)` changes sync/health/fallback state for `.externalMIDI` and `.externalPreferredFallback`, but it does not clear or replace the existing active source.

At initialization:

```swift
_state.timing.activeSourceID = Self.internalSourceID
_state.timing.selectedSourceID = Self.internalSourceID
```

For external policies, the current implementation does roughly:

```swift
case .externalMIDI, .externalPreferredFallback:
    _state.timing.sync = .unlocked
    _state.timing.sourceHealth = .unavailable
    _state.timing.fallback = ...
```

but leaves `activeSourceID == "internal"`.

Then `tick()` decides whether internal time is authoritative using:

```swift
let usingInternal = _state.timing.activeSourceID == Self.internalSourceID
    || _state.timing.timingPolicy == .internalOnly
```

Therefore this sequence is possible:

```text
engine starts under internal timing
transport running
setTimingPolicy(.externalMIDI)
no external clock present
activeSourceID is still "internal"
tick() continues advancing quarter-note position
```

This violates the meaning of strict external timing and creates a dangerous foundation for Phase C.

It also means `setTimingPolicy(.externalMIDI)` may fail to emit `.sourceChanged`, because the old and new active source IDs are both still `"internal"`.

## Required fix

Define and enforce explicit state invariants for each policy before Phase C.

Recommended Phase B behavior:

### `.internalOnly`

```text
selectedSourceID = internal
activeSourceID = internal
activeSourceCapabilities = .internalSource
sourceHealth = healthy
fallback = notApplicable
sync = internalRunning when transport running, otherwise unlocked
internal tick advancement = allowed
```

### `.externalMIDI`

Before an external provider has been selected/locked:

```text
selectedSourceID = nil or explicitly selected external provider ID when available
activeSourceID = nil
activeSourceCapabilities = empty / unavailable capabilities
sourceHealth = unavailable
fallback = notApplicable
sync = unlocked/acquiring as appropriate
internal tick advancement = NOT allowed
```

Phase C can then populate the selected/active external source when the adapter/provider is actually available.

### `.externalPreferredFallback`

Do not silently represent fallback as merely `armed` while also leaving the internal source active without saying so.

Choose one explicit model and test it:

**Option A — before first external lock, fallback is actually active**

```text
activeSourceID = internal
fallback = active
sync = fallback
```

or:

**Option B — wait for external and do not advance until Phase C activates fallback**

```text
activeSourceID = nil
fallback = armed
```

Either can be defensible, but the fields must agree with one another. The current state (`activeSourceID=internal`, `fallback=armed`, `sourceHealth=unavailable`) describes contradictory authority.

## Also simplify `tick()` authority

Avoid using policy as an `OR` escape hatch:

```swift
activeSourceID == internal || policy == internalOnly
```

Prefer a single authoritative state test such as:

```swift
let usingInternal = _state.timing.activeSourceID == Self.internalSourceID
```

Then make `setTimingPolicy` responsible for putting the state into a coherent configuration.

This avoids future situations where policy says one thing and active source says another.

## Mandatory tests

Add tests equivalent to:

```text
start internal @120 BPM
advance 0.5s => position advances
switch to externalMIDI with no provider
advance/tick 1.0s => position DOES NOT advance
activeSourceID != internal
sourceChanged emitted internal -> nil/external
```

Also test external-preferred fallback according to the chosen explicit semantics.

**Severity: P0**

---

# 4. P0 — Immediate and Safety Actions Can Be Delayed Until the Next Tick

## Problem

The Phase A contract is explicit:

> Safety actions cannot be delayed by beat quantization.

Phase B's checkpoint also claims:

> Panic / safety immediate

Construction correctly forces safety actions to `.immediate`, but runtime scheduling does not always execute an immediate action immediately.

Current `schedule(_:)` behavior:

```swift
if action.targetBoundary.isImmediate {
    if transport == .stopped {
        ... executeImmediately can deliver directly ...
    }
    return scheduler.enqueue(action, targetPosition: position ?? .must(0), hold: false)
}
```

When transport is **running**, even `.panicBypass` is enqueued with the current musical position.

It does not fire until a subsequent call to:

```swift
scheduler.harvestDue(at: pos)
```

which currently happens from `tick()` or selected transport paths.

So:

```text
transport running
schedule(panicBypass)
no tick for 10/20/50 ms
panic is delayed by that amount
```

If the run loop stalls, the delay can be much larger.

That is not an acceptable emergency-control contract.

## Required fix

Define `.immediate` as a wall-clock/API semantic, not merely "target musical position equals now."

For safety work:

```text
schedule safety action
=> fire synchronously through the fire-delivery contract immediately
=> do not place it behind the musical scheduler queue
=> do not require transport
=> do not require a future tick
=> do not reject it because decorative queue capacity is full
```

For non-safety `.immediate` work, the cleanest semantic is also direct execution. If there is a product reason to queue non-safety immediate work for ordering, document and test that separately, but **safety must bypass**.

A useful pattern:

```swift
if action.isSafetyCritical {
    deliverFires([action])
    return .accepted(action.id)
}

if action.targetBoundary.isImmediate {
    switch action.failurePolicy {
       ...
    }
}
```

Do not make safety delivery depend on scheduler capacity.

## Mandatory tests

Add:

```text
transport running
schedule panic
fire handler count == 1 before schedule() returns
scheduler.pendingCount unchanged
```

Also:

```text
scheduler decorative queue filled to capacity
schedule panic
panic still fires immediately
```

And a nested/registered safety action token should receive the same behavior as `panicBypass`.

**Severity: P0**

---

# 5. P0 — Pending Actions Do Not Honor Their Individual Failure Policy When Timing Stops

## Problem

The architecture intentionally introduced:

```swift
QuantizationFailurePolicy
  .cancel
  .executeImmediately
  .holdUntilTimingAvailable
```

The planning contract says failure behavior should be resolved **per mapping/action**, not via a global engine default.

However, `stopTransport(cancelPending: Bool = true)` currently does:

```swift
if cancelPending {
    scheduler.cancelNonHeld()
}
```

This means all ordinary pending work is canceled regardless of the action's own `failurePolicy`.

If `cancelPending == false`, all pending work is simply left as-is regardless of failure policy.

Neither mode implements the defined contract.

For example:

```text
Action A: nextBar + .cancel
Action B: nextBar + .executeImmediately
Action C: nextBar + .holdUntilTimingAvailable
transport stops
```

Expected semantic behavior is approximately:

```text
A => cancel
B => fire immediately
C => become held until timing is usable again
```

Current behavior is either:

```text
all three canceled
```

or:

```text
all three remain pending
```

This will become much more important once Phase C introduces clock loss, provider unlock, freewheel expiration, and fallback transitions.

## Required fix

Replace global `cancelNonHeld()` handling with a scheduler transition operation that applies each entry's policy.

Conceptual API:

```swift
public struct TimingUnavailableResolution {
    var fireImmediately: [ScheduledMusicalAction]
    var canceled: [ScheduledMusicalAction]
    var held: [ScheduledMusicalAction]
}

func timingBecameUnavailable(...) -> TimingUnavailableResolution
```

or equivalent.

For every pending entry:

### `.cancel`

Remove from queue and return/report as canceled.

### `.executeImmediately`

Remove from queue and return for immediate fire delivery.

### `.holdUntilTimingAvailable`

Keep it, set:

```text
isHeld = true
targetPosition = nil
```

Then on Start / Continue / source recovery, `releaseHeld(...)` may re-resolve the requested musical boundary against the new current position/meter.

This same transition primitive should be reusable later for:

- transport stop
- strict external source becoming unavailable
- clock loss after freewheel expires
- source changes where old absolute schedule positions are no longer meaningful

Do not wait until Phase C to invent a second failure-policy mechanism.

## Mandatory tests

Queue three actions with the three policies and verify exact behavior on stop.

Also test:

```text
holdUntilTimingAvailable
stop
continue
=> action re-resolves to the next requested boundary from resumed position
```

and:

```text
executeImmediately
stop
=> handler runs during stop transition without waiting for a tick
```

**Severity: P0**

---

# 6. P1 — Scheduler Cancellation APIs Lose the Payload Needed to Clean Up Action Tokens

## Problem

`AuroraActionTokenRegistry` explicitly documents the ephemeral token lifetime model:

> Fire / cancel / enqueue-reject / teardown must consume the token.

The current scheduler cancellation surfaces do not make that lifecycle practical:

```swift
public func cancel(id: UUID) -> Bool
public func cancelAll()
public func cancelNonHeld()
```

Once `cancel(id:)` returns only `Bool`, the caller knows a schedule ID was removed but does not receive the removed `ScheduledMusicalAction`, and therefore may not know the `auroraActionToken(UUID, ...)` that must be consumed.

`cancelAll()` and `cancelNonHeld()` are even more problematic: they remove potentially many token-bearing actions without returning anything.

This creates a straightforward registry leak once AME begins scheduling real actions.

The fire path has the same integration requirement: the fire bridge must consume the token, not merely `resolve` it.

## Required fix

Make removal APIs payload-preserving.

Recommended shapes:

```swift
@discardableResult
func cancel(id: UUID) -> ScheduledMusicalAction?

func cancelAll() -> [ScheduledMusicalAction]

func cancelNonHeld() -> [ScheduledMusicalAction]
```

Better still, once the P0 failure-policy transition API is added, have it return all removed/fired/held results explicitly.

Then the AuroraEngine integration layer can perform:

```text
removed action contains .auroraActionToken(token,...)
=> registry.consume(token)
```

For queue rejection, ensure the bridge/caller also unregisters the token created before attempting enqueue.

Consider adding a very small `AuroraEngine` scheduling bridge in a later phase, but the Phase B API must at least preserve enough information for correct cleanup.

## Mandatory tests

At minimum add Engine-level lifecycle tests proving:

```text
register ephemeral token
schedule
cancel by schedule ID
registry count returns to zero
```

and:

```text
register + enqueue rejected
registry count returns to zero
```

and:

```text
register + fire
consume token
registry count returns to zero
```

If actual bridge execution is deliberately Phase D, add tests to the scheduler proving the canceled payload is returned intact now.

**Severity: P1**

---

# 7. P1 — `schedule(_:)` Is Not Atomic With Respect to Musical State Changes

## Problem

`MusicalEngine` advertises thread-safe mutation via one `NSLock`, but scheduling snapshots state and then releases the engine lock before resolving/enqueueing:

```swift
lock.lock()
let transport = ...
let position = ...
let meter = ...
lock.unlock()

// boundary resolution
// scheduler enqueue
```

During this gap another thread may:

- `seek`
- `startTransport`
- `stopTransport`
- `continueTransport`
- change meter
- change timing policy
- call `tick()` and advance position

The scheduled action can therefore be resolved against a timing snapshot that is no longer authoritative at the moment it is accepted.

Example:

```text
Thread A snapshots position 3.9 in 4/4 for nextBar
Thread B seeks to 20.0
Thread A enqueues target 4.0
next tick sees current position 20.x
scheduler fires action immediately as overdue
```

This may be rare in a unit test, but MIDI callbacks, UI control, timer ticks, and future show-control inputs make concurrent calls realistic.

## Required fix

Scheduling must be linearizable with timing-state mutation.

Simplest Phase B approach:

1. Hold the engine lock while reading timing state and resolving the target.
2. Enqueue into the scheduler before releasing the engine lock.
3. Do **not** call external callbacks while the engine lock is held.

Scheduler has its own lock, and `enqueue` does not callback, so this lock ordering can be made deterministic. Document lock order if nesting is used:

```text
MusicalEngine lock -> MusicalScheduler lock
```

Never acquire them in the reverse order elsewhere.

Alternative: make the engine a serial executor/actor later, but do not introduce a half-concurrency model now just before Phase C.

## Mandatory test

A deterministic race test is preferable if feasible. At minimum add a contract test around seek/schedule ordering and document the linearization point.

**Severity: P1**

---

# 8. P1 — Song Context Can Leak the Previous Song's Tempo/Meter Into a New Song

## Problem

`setShowContext(_:)` soft-applies song defaults only when a new context contains a value:

```swift
if let bpm = context.songDefaultTempoBPM, ... {
    _state.timing.tempoBPM = bpm
    _state.timing.tempoProvenance = .songMetadata
}
```

Suppose:

```text
Project default = 120 BPM
Song A default = 96 BPM
Song B default = nil
```

After activating Song A, state becomes:

```text
tempo = 96
provenance = songMetadata
```

Switch to Song B. Because B has no `songDefaultTempoBPM`, no tempo branch executes.

State remains:

```text
tempo = 96
provenance = songMetadata
```

but 96 now refers to the previous song.

The same problem exists for meter.

This is dangerous because Song Mode can silently inherit the wrong musical timing metadata.

## Required fix

The engine needs a clear hierarchy / restoration model for metadata:

```text
explicit user override (if designed to persist)
current song metadata
project default
engine default
```

When context changes from one song to another and the current field provenance is `.songMetadata`:

- If the new song supplies a valid default, apply it.
- If the new song does not supply one, fall back to the configured project/default baseline rather than keeping the old song's value.

Do not hard-code 120/4-4 as the only fallback if project musical settings already contain defaults. Provide a way for the engine to know the current project defaults.

At minimum, Phase B should not allow stale `.songMetadata` provenance to survive after the source song no longer supplies the value.

## Mandatory tests

```text
project/default 120 4/4
song A = 96 6/8
song B = no tempo / no meter
A -> B
=> tempo/meter no longer equal A metadata
=> provenance no longer falsely says songMetadata for A values
```

Also test Song A -> Song C where C has different values.

**Severity: P1**

---

# 9. P1 — MIDI Timing Sink Surface Throws Away Source Identity

## Problem

The Phase B checkpoint describes `MusicalTimingSink` as the stable sink surface for Phase C adapters:

```swift
func receiveClockPulse(at hostTime: HostTime)
func receiveTransportStart(at hostTime: HostTime)
func receiveTransportStop(at hostTime: HostTime)
func receiveTransportContinue(at hostTime: HostTime)
func receiveSongPosition(_ position: QuarterNotePosition, at hostTime: HostTime)
```

No method identifies **which timing provider/source** produced the event.

But the model already distinguishes:

```text
selectedSourceID
activeSourceID
sourceHealth
source capabilities
sourceChanged timeline events
```

Phase C is explicitly supposed to implement source selection versus active/fallback state.

Without source identity at ingress, the engine cannot independently decide whether a pulse belongs to:

- selected MIDI source A
- unselected MIDI source B
- a future show-control timing source
- a fallback provider

An adapter can pre-filter events, but then source-selection authority is pushed outside the Musical Engine and its diagnostics become harder to reason about.

## Required fix

Before Phase C depends on this protocol, decide on one of these designs:

### Preferred: source-aware sink

```swift
func receiveClockPulse(from sourceID: String, at hostTime: HostTime)
func receiveTransportStart(from sourceID: String, at hostTime: HostTime)
...
```

Use a lightweight typed source identifier if preferred.

### Alternative: provider-bound sink/session

Register a `TimingProvider` and hand it a bound sink object whose source identity is fixed by construction.

Either design is fine. What should be avoided is a supposedly multi-provider engine receiving anonymous timing events.

## Mandatory tests

Phase B can add contract-only tests. Phase C will add behavior tests showing pulses from an unselected source cannot take authority.

**Severity: P1**

---

# 10. P1 — Timing Sink Host Timestamps Are Currently Ignored for Transport and SPP

## Problem

The source-aware timing methods accept `HostTime`, but the implementation discards it:

```swift
public func receiveTransportStart(at hostTime: HostTime) {
    _ = hostTime
    startTransport()
}
```

`startTransport()` then anchors:

```swift
lastTickHostTime = clock.now()
```

The same pattern exists for Stop, Continue, and Song Position.

For CoreMIDI ingress, the timestamp attached to the packet is the actual event time. Calling `clock.now()` later introduces callback/scheduling latency into the timing origin.

Phase C's phase estimator will care about this difference.

## Required fix

Do not discard event timestamps at the Musical Engine boundary.

Create internal transport/seek helpers that accept the authoritative event time:

```swift
startTransport(at hostTime: HostTime, provenance: ...)
continueTransport(at hostTime: HostTime, ...)
stopTransport(at hostTime: HostTime, ...)
seek(to:, at hostTime:, provenance: ...)
```

UI/manual calls can pass `clock.now()`.

Provider calls must preserve the provider/ingress timestamp.

Even if the Phase B internal clock does not yet use external pulses, the API should not erase the timing data Phase C needs.

**Severity: P1**

---

# 11. P1 — `receiveSongPosition` Emits an Intermediate State With the Wrong Provenance

## Problem

Current SPP path:

```swift
seek(to: position)
lock.lock()
_state.timing.positionProvenance = .midiSongPosition
...
notifyState(...)
```

`seek(to:)` itself:

1. mutates position
2. refreshes bar/beat
3. appends `.positionJumped`
4. notifies state observers
5. notifies timeline observers

Then `receiveSongPosition` takes the lock again and updates provenance, causing a second state notification.

Consumers can observe:

```text
new SPP position + stale/old provenance
```

followed immediately by:

```text
same position + midiSongPosition provenance
```

That is unnecessary and makes state snapshots non-atomic.

## Required fix

Introduce a single internal reposition operation that sets:

```text
position
phase
barBeat
positionProvenance
host timestamp / timing anchor as appropriate
positionJumped event
```

under one mutation transaction, then emits one coherent state snapshot and one timeline discontinuity.

Manual `seek` can call it with `.user` or `.showControl`; SPP can call it with `.midiSongPosition`.

## Mandatory test

Register a state observer, call SPP receive, and assert that every snapshot containing the new position also contains the correct `.midiSongPosition` provenance.

**Severity: P1**

---

# 12. P1 — Internal Tick Silently Discards Elapsed Time for Stalls >= 5 Seconds

## Problem

`tick()` contains:

```swift
if dt > 0, dt < 5 {
    // advance
}
lastTickHostTime = now
```

If the app stalls or the machine scheduling gap is 5 seconds or more:

```text
musical position does not advance
lastTickHostTime jumps to now
no discontinuity event
no diagnostic
no sync-state change
```

The Musical Engine has silently lost elapsed musical time.

A hard guard against huge catch-up jumps may be sensible, but silent loss is not.

## Required fix

Define an explicit internal-clock stall policy.

Reasonable options:

### Option A — continuous monotonic authority

Internal timing is derived from an anchor (`anchorHostTime`, `anchorQuarterPosition`, BPM segments), so tick frequency does not determine elapsed musical time.

This is the most robust long-term model.

### Option B — bounded integration with explicit discontinuity

If `dt` exceeds a safety threshold:

- do not silently pretend no time passed;
- emit a diagnostic/timeline discontinuity;
- intentionally re-anchor;
- document whether Aurora jumps forward or freezes/restarts phase.

For a live musical clock, Option A is preferable because tick cadence should determine **notification resolution**, not the underlying musical timeline.

Also consider tempo changes: an anchor-based model must re-anchor when BPM changes so old elapsed time is not recomputed at the new BPM.

## Mandatory tests

```text
run internal @120 BPM
large clock advance > threshold
call tick
=> behavior is explicit and tested
=> never silently changes host anchor while pretending musical time did not move
```

**Severity: P1**

---

# 13. P1 — Synthesized `Codable` Bypasses Several Phase A Validation Invariants

## Problem

Several domain structs have validating initializers but synthesized `Decodable` implementations.

Examples include:

```swift
MusicalMeter
MusicalDuration
QuarterNotePosition
BarBeatPosition
```

A synthesized decoder assigns stored fields directly. It does **not** call the custom validating initializer.

Therefore malformed/corrupt serialized data can create states that ordinary constructors reject.

Examples:

```text
MusicalMeter denominator = 0
beatGrouping sum != numerator
MusicalDuration count <= 0
dotted && triplet
QuarterNotePosition non-finite if decoder strategy permits it
BarBeatPosition beat index / phase outside normalized contract
```

Phase B math assumes meter invariants are true.

## Required fix

For domain types whose invariants matter to runtime math, implement custom `init(from:)` that decodes raw fields and delegates to the validated initializer.

Example:

```swift
public init(from decoder: Decoder) throws {
    ...decode...
    try self.init(
        numerator: numerator,
        denominator: denominator,
        beatGrouping: grouping
    )
}
```

Do the same for persisted `ShowMusicalMeter` if it still relies on synthesized decoding.

Choose whether invalid persisted data:

- throws and causes project validation/load failure, or
- is migrated through an explicit migration path.

Do not silently instantiate mathematically invalid meter data.

## Mandatory tests

Hand-build invalid JSON for each invariant and verify decode fails deterministically.

**Severity: P1**

---

# 14. P2 — Transport APIs Need Idempotency / State-Transition Semantics

## Problem

Current public methods allow transitions without validating prior state:

```text
start while already running => resets position to zero again
stop while already stopped => emits another stopped event
continue from initial stopped state => sets running + continued
```

Some of these may be desired for MIDI semantics, but the same methods are also the generic public engine API.

The Phase C plan specifically distinguishes MIDI Start from Continue. It is worth making the runtime contract explicit now.

## Required fix

Separate semantic commands if necessary:

```text
startFromOrigin()
continueFromCurrentPosition()
stopPreservingPosition()
```

or document valid transitions and make duplicate events idempotent where appropriate.

For MIDI Start specifically, repeated Start may intentionally reset origin, but that should be a named MIDI transport behavior rather than an accidental side effect of a generic method.

Add state-transition tests.

**Severity: P2**

---

# 15. P2 — Timeline Log Is Unbounded

## Problem

`timelineLog` grows until `drainTimelineEvents()` is called.

If the application primarily uses observers and never drains the log, every seek/start/stop/source transition remains in memory for the process lifetime.

Normal shows may not create huge volumes, but future source lock/re-lock diagnostics could.

## Required fix

Either:

- make the log a bounded diagnostic ring buffer, or
- remove the retained log if observers are the canonical event path, or
- document and enforce an owner that drains it.

A bounded ring is a useful diagnostics primitive.

**Severity: P2**

---

# 16. P2 — Clean Up Phase B Compiler Warnings and Dead Logic

Current review build exposed:

```swift
let safetyCap = ... // never used
```

in `MusicalScheduler.enqueue`, plus the unused `events` variable in `setShowContext`.

The safety enqueue branch is also harder to understand than necessary because it contains comments debating behavior that the decorative-capacity rule has already established.

Simplify it to explicit invariants:

```text
non-safety count <= decorativeCapacity
all pending count <= total capacity
safety may consume reserved plus any unused decorative capacity
```

Add table-driven tests for:

```text
all decorative slots occupied, safety reserve empty
some decorative slots unused, safety exceeds reserve into unused capacity
queue all safety
capacity 1 / reserve 0
capacity 1 / reserve 1
reserve == capacity
```

This is cleanup, but scheduler code should be boring and obvious. Live-show queues are not a good place for philosophical comments arguing with themselves. 🙂

**Severity: P2**

---

# 17. P2 — `VirtualHostClock` Should Reject Invalid/Overflowing Advances

`VirtualHostClock.advance(seconds:)` converts arbitrary `TimeInterval` to `UInt64`, and `advance(nanoseconds:)` uses wrapping addition:

```swift
_now.nanoseconds &+ nanoseconds
```

For a deterministic test clock, wraparound is surprising behavior.

Recommended:

- reject/ignore non-finite or negative seconds explicitly;
- use checked/clamped addition rather than wrapping;
- add one small test.

This is test-infrastructure hardening, not product behavior.

**Severity: P2**

---

# 18. Checkpoint Accuracy — Effects Contract Claim Should Be Narrowed Until Phase C

The Phase B checkpoint says the Effects consumer contract is covered for:

```text
tempo, phase, boundaries, transport, sync, discontinuities, schedule
```

That is fair for the **generic API seam** under the internal source.

However, the planning amendment originally calls for proving a consumer can eventually work identically under Internal and MIDI Clock sources. Phase B does not and should not implement MIDI Clock; `receiveClockPulse` is intentionally a no-op.

Do not pretend the second half has been proven yet.

Update checkpoint wording to something like:

> Phase B establishes and tests the provider-agnostic consumer API under internal timing. Phase C must prove the same Effects consumer contract under external MIDI Clock without consumer-specific code changes.

Then add that exact cross-provider test to the Phase C acceptance gate.

**Severity: documentation / gate clarity**

---

# 19. What Looks Good and Should Be Preserved

Do **not** churn the following parts merely because this is a review pass.

## 19.1 `AuroraMusical` separation

Keep CoreMIDI out of this module. MIDI timing adapters belong at the boundary.

## 19.2 Explicit metrical grouping

This is now a strong foundation:

```text
4/4  [1,1,1,1]
6/8  [3,3]
7/8  [2,2,3] / [3,2,2] / etc.
```

`MusicalMeterMath.nextMetricalBeatPosition` correctly treats asymmetric beat lengths as first-class.

## 19.3 Typed scheduled commands

Keep:

```swift
ScheduledCommand.auroraActionToken(...)
ScheduledCommand.panicBypass
```

Do not regress to string action keys or arbitrary closure scheduling.

## 19.4 Safety normalization in `ScheduledMusicalAction`

The constructor/decode normalization is good defense in depth. Keep it, while fixing the runtime delivery delay described above.

## 19.5 Reject-newest queue policy

Do not switch to dropping oldest accepted work.

## 19.6 `HostClock` injection

`VirtualHostClock` is exactly the right testing seam for Phase C synthetic timing work.

## 19.7 Timeline discontinuity model

Keep semantic events separate from ordinary state snapshots. Phase C will need `.syncLost`, `.syncRecovered`, source changes, re-lock jumps, etc.

## 19.8 Timing state vs show context

Do not let MIDI Clock determine Song/Section identity. That separation remains correct.

---

# 20. Required Implementation Order

Recommended closeout order:

## B1 — Authority/source state repair

Fix:

- strict external policy leaving internal active;
- selected/active/capability/fallback invariants;
- internal tick authority;
- source-change events.

Then lock with tests.

## B2 — Immediate/safety execution

Fix direct immediate delivery and queue-capacity independence for safety actions.

Then lock with tests before changing scheduler transitions.

## B3 — Failure-policy transitions

Replace global stop cancellation with per-action:

```text
cancel / executeImmediately / holdUntilTimingAvailable
```

Make the primitive reusable for future source loss.

## B4 — Scheduler lifecycle + atomic scheduling

Return removed actions from cancellation APIs and make schedule acceptance linearizable with timing state.

## B5 — Context/provenance cleanup

Fix:

- stale song metadata on song changes;
- atomic SPP reposition/provenance;
- preservation of ingress `HostTime`.

## B6 — Phase C sink contract

Add source identity to timing ingress or a provider-bound equivalent before Phase C writes the MIDI adapter against the current anonymous interface.

## B7 — Domain decode validation / robustness

Close synthesized-Codable invariant bypasses, large-tick policy, log bound, warning cleanup.

## B8 — Tests + checkpoint

Run full macOS suite, update checkpoint, then STOP.

---

# 21. Mandatory Phase B Closeout Test Matrix

The current Phase B tests cover the happy-path core well, but the missing tests cluster around state transitions. Add at least the following.

## Timing authority

- [ ] Internal policy advances from monotonic time.
- [ ] Strict external policy with no active provider does not advance internal time.
- [ ] Switching internal -> strict external emits coherent source transition state/event.
- [ ] Switching strict external -> internal re-anchors without giant stale `dt`.
- [ ] External-preferred fallback fields agree with actual authority.

## Immediate/safety

- [ ] Panic fires before `schedule()` returns while stopped.
- [ ] Panic fires before `schedule()` returns while running.
- [ ] Safety token action fires before `schedule()` returns while running.
- [ ] Full decorative queue cannot delay/reject immediate safety work.
- [ ] Non-safety immediate behavior is explicitly tested/documented.

## Failure policies

With transport running and target in the future:

- [ ] `.cancel` is canceled when timing becomes unavailable.
- [ ] `.executeImmediately` fires immediately on transition.
- [ ] `.holdUntilTimingAvailable` becomes held.
- [ ] Held work re-resolves on Continue/Start/recovery.
- [ ] Multiple mixed-policy entries retain deterministic order.

## Token lifetime

- [ ] Cancel returns removed scheduled payload/token.
- [ ] Bulk cancel/transition returns all removed payloads.
- [ ] Queue rejection can clean ephemeral token.
- [ ] Fire path can consume ephemeral token.

## Context

- [ ] Song A metadata -> Song B metadata applies B.
- [ ] Song A metadata -> Song B with nil metadata does not retain A falsely.
- [ ] User override semantics across song changes are explicitly tested.
- [ ] Meter follows the same provenance rules as tempo.

## SPP / discontinuity

- [ ] SPP state observer never sees new position with stale provenance.
- [ ] SPP emits exactly one coherent position-jump discontinuity.
- [ ] SPP host timestamp is preserved into the internal timing transition contract.

## Concurrency / ordering

- [ ] Schedule linearization is documented/tested around seek/tick.
- [ ] Fire callbacks occur outside engine/scheduler locks.
- [ ] Observer callbacks remain outside locks and may safely call back into engine APIs.

## Internal-clock stalls

- [ ] Large tick gap has defined behavior.
- [ ] No silent loss of elapsed time + host re-anchor.

## Decode invariants

- [ ] Invalid `MusicalMeter` JSON fails decode.
- [ ] Invalid `MusicalDuration` JSON fails decode.
- [ ] Invalid persisted `ShowMusicalMeter` fails or explicitly migrates.

## Meter / boundaries (retain existing coverage)

- [ ] 4/4 next metrical beat.
- [ ] 6/8 dotted-quarter metrical beat.
- [ ] 7/8 `[2,2,3]` boundaries.
- [ ] 7/8 `[3,2,2]` differs as expected.
- [ ] next grid quarter remains distinct from next metrical beat.
- [ ] next bar works across compound/asymmetric meter.

---

# 22. Phase B Re-Acceptance Gate

Phase B may be marked complete only when all of the following are true:

- [ ] `.externalMIDI` cannot accidentally leave internal timing authoritative.
- [ ] Timing policy, selected source, active source, source health, sync, capabilities, and fallback state are mutually coherent.
- [ ] Safety actions execute immediately even while transport is running.
- [ ] Safety execution is independent of scheduler decorative capacity.
- [ ] Pending work honors each action's `QuantizationFailurePolicy` when timing stops/becomes unavailable.
- [ ] Held actions re-resolve correctly when timing returns.
- [ ] Scheduler cancellation/removal preserves payloads needed for token cleanup.
- [ ] Scheduling is linearizable with seek/tick/transport changes.
- [ ] Switching songs cannot retain stale previous-song tempo/meter under `.songMetadata` provenance.
- [ ] Timing ingress preserves source identity or uses an equivalent provider-bound design.
- [ ] Timing ingress does not discard authoritative `HostTime` timestamps.
- [ ] SPP reposition + provenance is one coherent state mutation.
- [ ] Large internal tick gaps have an explicit tested policy.
- [ ] Runtime-critical musical value types validate on decode.
- [ ] Phase B compiler warnings introduced by this work are removed.
- [ ] Full macOS suite is green.
- [ ] `CHECKPOINT_AME_PHASE_B_MUSICAL_ENGINE.md` is updated accurately.
- [ ] Phase C has **not** begun.

Then STOP for human acceptance.

---

# 23. Suggested Updated Phase B Checkpoint Summary

After fixes, the checkpoint should be able to say something close to:

```text
Phase B COMPLETE — Musical Engine Core

- Internal monotonic timing with defined long-gap behavior
- Coherent timing-policy/source authority state
- Explicit compound/asymmetric metrical boundaries
- Tap-tempo estimator feeding internal timing
- Typed quantized scheduler with stable IDs
- Immediate safety bypass independent of scheduler capacity
- Per-action quantization failure behavior on timing loss/stop
- Payload-preserving cancellation for integration/token cleanup
- Atomic scheduling relative to timing-state transitions
- Coherent song/project tempo+meter provenance
- Timeline discontinuity events
- Provider/source-aware Phase C timing ingress contract
- Provider timestamps preserved end-to-end at Musical Engine boundary
- Generic Effects-consumer contract proven under internal timing
- Phase C must prove the same consumer contract under MIDI Clock
```

---

# 24. Final Review Disposition

**Phase B architecture:** GOOD  
**Phase B implementation quality:** PROMISING  
**Phase B runtime-state semantics:** NEEDS CLOSEOUT  
**Permission to begin Phase C:** **NO — not yet**

The important point is that the implementation does not need to be torn apart. The clock math, meter model, typed scheduler direction, monotonic time seam, and module boundaries are all worth keeping.

The remaining work is to make the engine's state transitions tell the truth and make scheduling semantics hold under live-show conditions, not only under happy-path test cadence.

Once these findings are closed, Phase C can add MIDI Clock on top of a much firmer base instead of becoming the place where source authority, queue behavior, and transport semantics all get debugged simultaneously.

**STOP after Phase B closeout and full test pass. Do not begin the MIDI Clock PLL/provider until this checkpoint is reviewed again.**
