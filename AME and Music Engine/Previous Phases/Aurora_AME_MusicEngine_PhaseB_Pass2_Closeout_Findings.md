# Aurora AME + Musical Engine — Phase B Pass 2 Closeout Findings

**Review target:** `Aurora_AMEPhaseB_Pass2.zip`  
**Review date:** 2026-08-16  
**Phase:** B — Musical Engine Core, post-review Pass 2  
**Disposition:** **VERY CLOSE, BUT NOT YET CLEARED FOR PHASE C**  
**Required action:** Address the blockers below, add the regression tests, rerun the complete macOS suite, update the Phase B checkpoint, then **STOP** for final human acceptance before Phase C.

---

## 1. Executive summary

Pass 2 is a meaningful improvement and closes most of the first Phase B review correctly.

Confirmed-good changes include:

- strict `.externalMIDI` no longer leaves the internal source authoritative;
- `.externalPreferredFallback` now has coherent fallback state;
- internal `tick()` authority is based on `activeSourceID`, not a policy OR-condition;
- safety actions scheduled through `MusicalEngine.schedule()` fire synchronously and bypass the queue;
- stop-time scheduling failure policy is now per-action;
- cancellation returns the removed payload;
- scheduling target resolution + enqueue is linearized under the engine lock;
- stale song metadata is restored to project defaults when the next song omits it;
- timing sink carries source ID and `HostTime`;
- SPP reposition/provenance is atomic;
- internal timing uses an anchor-based monotonic timeline and no longer drops long stalls;
- meter/duration/position decoding validates invariants;
- timeline diagnostics are bounded;
- `VirtualHostClock` no longer wraps;
- `AuroraMusical` still builds cleanly in isolation.

Local review verification:

```text
swift build --target AuroraMusical
Build complete.
```

The supplied checkpoint reports **610 tests / 0 failures** on macOS. That full result cannot be independently rerun in this Linux review environment because the complete Aurora package reaches macOS-only frameworks.

The remaining findings are smaller than the first review, but two still violate core contracts and should be fixed before Phase C adds an external clock source.

---

# 2. P0 — Public scheduler access can bypass the safety-immediate invariant

## Problem

`MusicalEngine` currently exposes:

```swift
public let scheduler: MusicalScheduler
```

and `MusicalScheduler.enqueue(...)` is public.

Pass 2 correctly makes this safe path synchronous:

```swift
engine.schedule(safetyAction)
```

but the API still permits a caller to bypass the engine entirely:

```swift
let panic = ScheduledMusicalAction.panicBypass()
engine.scheduler.enqueue(
    panic,
    targetPosition: .must(128),
    hold: false
)
```

`MusicalScheduler.enqueue` currently accepts safety work as long as capacity is available. Because `harvestDue` checks `targetPosition` before the action's `.immediate` boundary, the safety action above can remain queued until musical position 128.

That means the statement:

> safety / panic can never be delayed by scheduling

is true only when every caller voluntarily uses the preferred API.

Safety invariants need to be impossible to bypass through public production API.

## Required fix

Prefer **encapsulation**:

```swift
private let scheduler: MusicalScheduler
```

or at most module-internal:

```swift
let scheduler: MusicalScheduler
```

Expose narrow engine surfaces instead:

```swift
public var pendingScheduledCount: Int
public func pendingScheduleSnapshotForDiagnostics() -> ... // only if genuinely needed
public func cancelScheduled(id: UUID) -> ScheduledMusicalAction?
public func cancelAllScheduled() -> [ScheduledMusicalAction]
```

Tests can use `@testable import AuroraMusical` if scheduler inspection is needed.

Also harden `MusicalScheduler.enqueue` itself so a safety-critical action cannot be queued behind a musical target. Since the scheduler cannot itself deliver the action, the safest standalone contract is:

```text
if action.isSafetyCritical => rejectedInvalid
```

and document that all safety delivery goes through `MusicalEngine.schedule()`.

This gives defense in depth if the scheduler is later reused elsewhere.

## Mandatory tests

- Direct scheduler enqueue of `.panicBypass` cannot produce a pending entry.
- Direct scheduler enqueue of a safety token cannot produce a pending entry.
- `MusicalEngine.schedule(panic)` still fires synchronously.
- Queue-full state cannot prevent `MusicalEngine.schedule(panic)` from firing.

**Severity: P0**

---

# 3. P0 — `.immediate` actions still depend on transport/failure policy when stopped

## Problem

Pass 2 correctly fires non-safety `.immediate` work synchronously **while transport is running**:

```swift
case .running:
    deliverFires([action])
```

But when transport is stopped or paused, it does this:

```swift
case .stopped, .paused:
    switch action.failurePolicy {
    case .cancel:
        return .rejectedInvalid
    case .executeImmediately:
        deliverFires([action])
    case .holdUntilTimingAvailable:
        enqueue(... hold: true)
    }
```

The default `failurePolicy` for an action token is `.cancel`.

Therefore this perfectly valid action:

```swift
ScheduledMusicalAction.actionToken(
    token: token,
    isSafetyCritical: false,
    targetBoundary: .immediate
)
```

fires immediately when transport is running, but is rejected when transport is stopped.

That is semantically inconsistent. An `.immediate` boundary does **not require musical timing**, so `QuantizationFailurePolicy` should not participate at all.

The failure policy exists for a boundary that cannot be resolved or retained because timing is unavailable. `.immediate` has no such dependency.

## Required fix

Make `.immediate` one simple API semantic:

```swift
if action.targetBoundary.isImmediate {
    lock.unlock()
    deliverFires([action])
    return .accepted(action.id)
}
```

This applies regardless of:

- stopped / paused / running transport;
- active timing source;
- meter availability;
- quantization failure policy.

Safety should still take the earlier explicit safety bypass path, but ordinary immediate work should behave identically with respect to timing availability.

Do **not** reinterpret `.holdUntilTimingAvailable` on an `.immediate` action as “hold until transport runs”; there is no unavailable timing calculation to wait for.

## Mandatory tests

For a non-safety immediate action with default `.cancel`:

- stopped transport → fires synchronously and returns accepted;
- running transport → fires synchronously and returns accepted;
- strict external policy with no active source → fires synchronously and returns accepted;
- scheduler pending count remains unchanged in all cases.

**Severity: P0**

---

# 4. P0 — Timing can become unavailable through policy change without applying queued-action failure policies

## Problem

Pass 2 correctly applies `timingBecameUnavailable()` from `stopTransport(...)`.

However, timing can also become unavailable without transport stopping.

Example:

```text
internalOnly
transport running
position = 1.0
schedule three nextBar actions:
  A = .cancel
  B = .executeImmediately
  C = .holdUntilTimingAvailable
setTimingPolicy(.externalMIDI)
```

`setTimingPolicy(.externalMIDI)` now correctly does:

```text
activeSourceID = nil
sourceHealth = unavailable
sync = unlocked
```

but it never calls:

```swift
scheduler.timingBecameUnavailable()
```

So all three entries remain as ordinary non-held pending work with their old absolute target positions.

The engine is now in the contradictory runtime situation:

```text
transport = running
active timing source = nil
pending quantized targets = still armed against an old timing authority
```

If the user later switches back to internal timing, those stale entries may resume/fall due even though their declared failure policies should have been processed at the moment timing disappeared.

Phase C will create many more versions of this transition: source loss, unlock, timeout, freewheel expiry, selected-source replacement, etc. This invariant must be centralized before that complexity arrives.

## Required fix

Treat **loss of timing authority** as the trigger, not only transport stop.

When a transition changes the engine from usable musical timing to unavailable musical timing, atomically apply:

```swift
let resolution = scheduler.timingBecameUnavailable()
```

Then, after locks are released:

- fire `.executeImmediately` actions;
- return/report canceled payloads for token cleanup;
- retain `.holdUntilTimingAvailable` entries as held.

Recommended internal abstraction:

```swift
private func transitionTimingAuthorityLocked(...) -> TimingTransitionResult
```

or equivalent, so stop, source-loss, strict-external selection, Phase C lock loss, and fallback transitions cannot each invent subtly different queue behavior.

Likewise, when timing becomes available again, held entries should be released/re-resolved through one shared transition path.

## Important token-lifetime note

`TimingUnavailableResolution.canceled` is currently produced but `MusicalEngine.stopTransport` discards it:

```swift
let resolution = scheduler.timingBecameUnavailable()
deliverFires(resolution.fireImmediately)
// canceled / held retained for integration cleanup if needed later
```

Canceled actions are **not retained** by the scheduler. Therefore integration cannot clean up ephemeral action tokens later unless the engine surfaces the canceled payloads now.

This was the reason the first review required payload-preserving cancellation.

Do not merely return canceled payloads inside the scheduler and then throw them away one layer higher.

Provide a cancellation/removal observer, return value, or engine-level lifecycle handler so the integration layer can consume ephemeral `AuroraActionTokenRegistry` records for:

- explicit cancel;
- policy-driven cancel on timing loss;
- bulk teardown;
- enqueue rejection.

Held actions remain pending and should **not** consume their token.

## Mandatory tests

1. Running internal clock + A/B/C as above → switch to `.externalMIDI` with no provider:
   - A removed and surfaced as canceled;
   - B fired immediately;
   - C retained as held;
   - no ordinary non-held target remains armed against old internal timing.

2. Restore internal timing:
   - C is re-resolved relative to the newly available current position;
   - C does not use its stale pre-loss target.

3. Token lifecycle integration test:
   - register ephemeral token;
   - schedule `.cancel` action;
   - cause timing loss;
   - canceled payload reaches cleanup path;
   - registry count returns to baseline.

**Severity: P0**

---

# 5. P1 — Changing project-default tempo while running leaves state BPM and actual clock rate disagreeing

## Problem

`setProjectDefaults(...)` updates the visible timing state when project defaults are currently authoritative:

```swift
if _state.timing.tempoProvenance == .projectDefault {
    _state.timing.tempoBPM = tempoBPM
}
```

but it does **not** re-anchor the running internal timeline.

Internal timing advances from:

```swift
anchorBPM
```

not directly from `_state.timing.tempoBPM`.

Example:

```text
engine starts project default = 120 BPM
start transport
setProjectDefaults(tempoBPM: 60, ...)
state.timing.tempoBPM now says 60
anchorBPM is still 120
advance host clock 1 second
tick()
position advances 2 quarter notes instead of 1
```

This is a real state/authority divergence: UI/observers report one tempo while scheduling advances at another.

## Required fix

When `setProjectDefaults` actually changes the active tempo and internal timing is authoritative, re-anchor at the same host-time snapshot:

```swift
let now = clock.now()
_state.timing.tempoBPM = tempoBPM
if _state.timing.transport == .running,
   _state.timing.activeSourceID == Self.internalSourceID {
    reanchorLocked(at: now, keepPosition: true)
}
```

Capture `clock.now()` once for the transaction if needed.

Do not re-anchor merely because the stored project default changed while a user/song/external tempo is authoritative.

## Mandatory tests

- project default 120, running → change default to 60 while `.projectDefault` provenance → after 1 second, advance exactly 1 quarter note from change point;
- same call while tempo provenance is `.user` → state tempo and anchor remain user-owned;
- same call while song tempo metadata is authoritative → current song tempo is unchanged.

**Severity: P1**

---

# 6. P1 — Source-aware timing sink still accepts transport/SPP from any source regardless of policy

## Problem

The first review required source identity to reach the Musical Engine boundary. Pass 2 added the correct API shape, which is good:

```swift
receiveTransportStart(from sourceID: String, at hostTime: HostTime)
receiveTransportStop(from sourceID: String, at hostTime: HostTime)
receiveSongPosition(... from sourceID: String, at hostTime: HostTime)
```

But the implementation currently discards `sourceID`:

```swift
_ = sourceID
```

and explicitly says:

```swift
// Phase B accepts any.
```

That means once a MIDI adapter exists, an unselected or merely connected device can:

- reset transport to origin;
- stop transport;
- continue transport;
- reposition via SPP;

even while policy is `.internalOnly`.

The purpose of carrying source identity is to let the **Musical Engine** remain the authority over selected vs active source. If admission is delegated entirely to the adapter, two adapters/providers can each believe they are allowed to drive the engine.

Phase C will implement actual clock lock and provider activation, but the admission invariant should be established before Phase C starts using this sink.

## Required fix

Add one central source-admission predicate. Conceptually:

```swift
private func acceptsTimingEventLocked(from sourceID: String) -> Bool
```

Phase B-safe semantics can be minimal:

- `.internalOnly` → reject all external sink transport/SPP events;
- `.externalMIDI` → accept only selected/active external source once one exists;
- `.externalPreferredFallback` → accept selected external source when selected; otherwise internal fallback remains authoritative;
- internal UI APIs (`startTransport`, `seek`, etc.) remain separate and are not routed through external admission.

If Phase C needs an explicit API to select/register the candidate source, add that there, but **do not leave “any source mutates state” as the base engine behavior**.

At minimum, before Phase C lands, add tests proving an unselected source cannot alter internal-only transport or SPP position.

## Mandatory tests

- `.internalOnly` + `receiveTransportStop(from: "rogue-midi")` → no state change;
- `.internalOnly` + external SPP → no position change;
- selected source A + events from B → ignored;
- selected source A + event from A → accepted once Phase C activates A.

**Severity: P1 / Phase C entry contract**

---

# 7. P2 — Scheduler should reject duplicate schedule IDs

## Problem

`ScheduledMusicalAction.id` is the cancellation identity, but `MusicalScheduler.enqueue` does not reject duplicate IDs.

Two pending entries can therefore share the same schedule ID. `cancel(id:)` removes only the first match, making cancellation and token-lifecycle reasoning ambiguous.

UUID collisions from normal creation are fantastically unlikely, but callers can supply explicit IDs, decoded work can contain IDs, and deterministic tests/replay may reuse identifiers. Since the scheduler already validates capacity on enqueue, uniqueness is cheap to enforce.

## Recommended fix

Before enqueue:

```swift
if pending.contains(where: { $0.id == action.id }) {
    return .rejectedInvalid
}
```

Add a regression test that enqueues the same schedule ID twice and verifies the second is rejected.

**Severity: P2 hardening**

---

# 8. What should remain unchanged

Do **not** redesign the Phase B architecture around these findings. Preserve:

- `AuroraMusical` separation from CoreMIDI;
- `HostClock` / `HostTime` monotonic domain;
- anchor-based internal timeline;
- explicit `MusicalMeter.beatGrouping` model;
- typed `ScheduledCommand` payloads;
- recursive safety information originating from `AuroraAction` registration;
- engine → scheduler lock ordering;
- callbacks outside engine lock;
- source-aware timing sink signatures;
- SPP atomic reposition/provenance;
- project/song metadata provenance model;
- per-action timing failure policies;
- reject-newest queue policy;
- bounded timeline diagnostics.

This is a closeout pass, not an invitation to rewrite the engine.

---

# 9. Suggested implementation order

```text
B2.1  Encapsulate/harden scheduler safety boundary
  → B2.2  Make .immediate unconditional with respect to musical timing
    → B2.3  Centralize timing-authority loss / restore queue transitions
      → B2.4  Surface canceled payloads for token cleanup
        → B2.5  Re-anchor active project-default tempo changes
          → B2.6  Lock source-admission invariant before Phase C
            → B2.7  Duplicate schedule-ID hardening + regression suite
              → full macOS test suite
                → update Phase B checkpoint
                  → STOP
```

---

# 10. Re-acceptance gate

Phase B is ready for Phase C only when all are true:

- [ ] Safety actions cannot be queued through any public production path.
- [ ] Non-safety `.immediate` fires synchronously even when transport/timing is unavailable.
- [ ] Loss of active timing authority applies each pending action's failure policy, not only transport stop.
- [ ] Policy-driven canceled actions are surfaced for ephemeral token cleanup.
- [ ] Held actions survive timing loss and are re-resolved from fresh timing on recovery.
- [ ] Changing an authoritative project-default tempo while internally running re-anchors the timeline.
- [ ] External sink events cannot mutate internal-only state or come from an unselected source.
- [ ] Duplicate schedule IDs cannot create ambiguous pending entries.
- [ ] Existing meter/boundary/safety/SPP/stall tests remain green.
- [ ] Full macOS suite is green.
- [ ] Phase B checkpoint is updated truthfully.
- [ ] **STOP before Phase C for human acceptance.**

---

# 11. Final disposition

**Pass 2 is substantially better and the Musical Engine architecture remains approved.**

The remaining work is small and focused, but the public scheduler safety bypass and timing-authority-loss behavior are important enough that Phase C should not be layered on top of them yet.

**Disposition: 🟡 Phase B Pass 2 — CLOSE, NOT YET ACCEPTED.**
