# Aurora AME + Musical Engine
# Phase B Closeout Acceptance + Phase C Deep Code Review Fixes

**Review target:** `Aurora_AMEMusicEngine_PhaseC_pass1.zip`  
**Review date:** 2026-08-16  
**Scope:** Verify Phase B Pass 2 closeout, then deeply review Phase C External MIDI Timing before Phase D.  
**Disposition:** **Phase B ACCEPTED. Phase C NOT YET ACCEPTED. STOP before Phase D.**

---

# 1. Executive Summary

The Phase B closeout work is substantially correct and may be considered accepted. The previously reported Phase B blockers are now addressed in the implementation, not merely in tests or checkpoint prose:

- `MusicalScheduler` is private behind `MusicalEngine`.
- Safety actions cannot be queued in `MusicalScheduler`.
- Safety actions fire synchronously through `MusicalEngine.schedule()`.
- Non-safety `.immediate` actions fire synchronously even while stopped / without timing authority.
- Timing-policy transitions apply per-action quantization failure policy.
- Canceled actions are surfaced for action-token cleanup.
- Project-default tempo changes reanchor the running internal timeline.
- Timing ingress is source-aware and unselected sources are rejected.
- Duplicate schedule IDs are rejected.

**Phase B status: ACCEPTED.**

Phase C is a promising first implementation and preserves the correct architecture:

- `AuroraMusical` remains CoreMIDI-independent.
- `MIDIClockTimingAdapter` cleanly bridges decoded MIDI timing into `MusicalTimingSink`.
- CoreMIDI monotonic timestamps are preserved.
- Clock / Start / Stop / Continue / SPP remain distinct from AME channel-voice events.
- External timing is represented as a provider/source, not as the Musical Engine itself.
- MIDI Clock does not own meter or show context.
- Freewheel and strict/preferred-fallback policy concepts are present.

However, Phase C currently has several runtime-state bugs that can produce incorrect or frozen musical time under real hardware conditions. These should be corrected before Phase D begins, because AME runtime quantization will depend directly on this timing state.

The most important Phase C blockers are:

1. **A single external MIDI Clock pulse can steal timing authority from preferred internal fallback and freeze the timeline indefinitely.**
2. **Clock-estimator lock history survives dropout/loss and selected-source changes, allowing false instant re-lock and cross-device estimator contamination.**
3. **MIDI Start and SPP do not align the clock estimator's pulse phase with canonical musical position, allowing `quarterNotePhase` to disagree with `quarterNotePosition`.**
4. **Preferred fallback returns to the internal source ID but continues at the last external MIDI tempo instead of restoring the configured internal/song tempo.**
5. **Changing selected external sources does not atomically retire/reset the old source authority.**
6. **Held scheduled work is not reliably released when external timing becomes newly usable for the first time.**

The fixes are localized. No broad architecture rewrite is required.

---

# 2. Build / Review Notes

The isolated `AuroraMusical` target builds successfully in the review environment.

Observed compiler warnings:

```text
MusicalEngine.swift:
variable 'fireNow' was never mutated
variable 'canceled' was never mutated
```

These warnings are not blockers, but should be cleaned during closeout.

The complete package cannot be independently executed in this Linux review environment because Aurora contains macOS-only frameworks. The repository checkpoint reports:

```text
630 tests, 0 failures
```

That macOS full-suite result should be rerun after this correction pass.

---

# 3. Phase B Closeout Verification

## 3.1 Scheduler safety bypass — CLOSED

Previously, callers could access the scheduler directly and queue safety work behind a musical target.

Current code:

```swift
private let scheduler: MusicalScheduler
```

and:

```swift
if action.isSafetyCritical {
    return .rejectedInvalid
}
```

inside `MusicalScheduler.enqueue`.

`MusicalEngine.schedule` handles safety synchronously:

```swift
if action.isSafetyCritical {
    deliverFires([action])
    return .accepted(action.id)
}
```

This correctly enforces the safety invariant at both layers.

**Status: CLOSED.**

---

## 3.2 Immediate action behavior — CLOSED

Current behavior correctly treats `.immediate` as API-immediate rather than timing-dependent:

```swift
if action.targetBoundary.isImmediate {
    deliverFires([action])
    return .accepted(action.id)
}
```

The Pass 2 tests cover stopped transport and strict-external/no-source cases.

**Status: CLOSED.**

---

## 3.3 Timing-policy authority loss and failure policies — CLOSED

`setTimingPolicy` now compares authority before/after transition and calls:

```swift
scheduler.timingBecameUnavailable()
```

when necessary, then separately delivers immediate actions and canceled payloads.

This satisfies the Phase B contract.

**Status: CLOSED.**

---

## 3.4 Canceled action payload cleanup — CLOSED

The engine now exposes:

```swift
setScheduleCancelHandler(...)
```

and `cancelScheduled` / `cancelAllScheduled` return and deliver removed payloads.

This gives the integration layer enough information to release ephemeral action tokens.

**Status: CLOSED.**

---

## 3.5 Project-default tempo reanchor — CLOSED

`setProjectDefaults` now reanchors when project-default tempo is authoritative and internal timing is running.

The regression test verifies actual quarter-note advancement at the new BPM.

**Status: CLOSED.**

---

## 3.6 Source admission — CLOSED as a Phase B contract

`acceptsTimingEventLocked(from:)` now explicitly enforces timing-policy source admission.

Unselected external sources cannot manipulate Start/Stop/SPP or clock state.

Phase C exposes additional source-transition concerns discussed later, but the original Phase B admission problem is closed.

**Status: CLOSED.**

---

## 3.7 Duplicate scheduled IDs — CLOSED

`MusicalScheduler.enqueue` rejects duplicate IDs.

**Status: CLOSED.**

---

# 4. Phase B Disposition

**Phase B may now be marked ACCEPTED.**

The Phase B checkpoint language is consistent with the implementation.

Do not reopen Phase B unless Phase C remediation requires an intentional contract change.

---

# 5. P0 — External Source Must Not Take Authority on One Lone Clock Pulse

**Severity:** P0 / Phase C blocker  
**Files:** `ClockEstimator.swift`, `MusicalEngine.swift`, Phase C tests

## Current behavior

In `receiveClockPulse`, the selected source becomes active immediately upon the first accepted pulse:

```swift
if _state.timing.selectedSourceID == sourceID {
    if _state.timing.activeSourceID != sourceID {
        _state.timing.activeSourceID = sourceID
        ...
    }
}
```

This happens before the estimator has established a valid interval or lock.

In preferred-fallback mode, that means the first `F8` causes Aurora to abandon the healthy internal fallback.

Now consider only one pulse arriving.

`ClockEstimator` has:

```swift
lastPulseHostTime != nil
lastIntervalSeconds == nil
tempoBPM == nil
sync == .acquiring
```

Later `evaluateDropout` attempts to derive an expected interval:

```swift
if let bpm = tempoBPM ...
else if let li = lastIntervalSeconds ...
else {
    return
}
```

With only one pulse, both estimates are unavailable, so dropout evaluation returns forever.

The result is a serious live-show failure mode:

```text
preferred fallback running internally
    ↓
one stray F8 arrives
    ↓
external becomes active
    ↓
no second clock pulse
    ↓
no interval exists
    ↓
dropout can never be declared
    ↓
internal fallback never resumes
    ↓
Aurora musical timeline freezes indefinitely
```

A noisy/disconnected USB MIDI interface or device that emits a stray clock byte can therefore stop musical progression.

## Required correction

Separate **external candidate acquisition** from **active timing authority**.

For `externalPreferredFallback`:

- internal timing should remain active while the selected external source is merely acquiring;
- collect pulse history in the estimator;
- only hand timing authority to external when the source meets an explicit usability/lock threshold;
- perform the source transition atomically;
- keep musical position continuous across the handoff.

For strict `externalMIDI`:

- no internal fallback is required;
- the selected source may be shown as acquiring;
- but canonical `activeSourceID` should mean actual timing authority, not merely "a byte arrived";
- alternatively, if acquiring is intentionally considered active authority, the estimator **must** have a bounded acquisition timeout even when only one pulse was received.

Preferred design:

```text
selectedSourceID = external device
candidate estimator = acquiring
activeSourceID = internal (preferred fallback) or nil (strict external)

when estimator becomes locked / explicitly usable:
    activeSourceID = selected external
    sourceHealth = healthy
    sync = locked
    sourceChanged event
    handoff canonical position without discontinuity
```

## Mandatory tests

Add tests for:

1. preferred fallback + exactly one F8 → internal remains authoritative;
2. preferred fallback + two/three unstable pulses → internal remains authoritative;
3. preferred fallback + stable lock → external takes authority once;
4. strict external + one pulse → never claims healthy/locked timing;
5. acquisition that never completes eventually times out/reset cleanly;
6. a stray F8 must not permanently freeze position.

---

# 6. P0 — Clock Estimator Must Reset Stability on Dropout/Loss and Source Replacement

**Severity:** P0 / Phase C blocker  
**Files:** `ClockEstimator.swift`, `MusicalEngine.swift`

## Current behavior

When a stable clock locks, `consecutiveStable` can grow well beyond `lockPulseCount`.

On freewheel/loss, that counter is not reset.

When a pulse eventually returns after a long gap, this code only modifies `consecutiveStable` if the new interval produces a valid MIDI BPM:

```swift
let instantBPM = 60.0 / (interval * 24.0)
if MusicalNumeric.isValidBPM(instantBPM) {
    ...
}
```

For a long dropout, the apparent BPM will usually be below the valid range. In that case the old `consecutiveStable` survives untouched.

Then:

```swift
case .unlocked, .lost, .freewheeling:
    sync = .acquiring
    if consecutiveStable >= config.lockPulseCount {
        sync = .locked
    }
```

So the **first pulse after a long clock loss can immediately restore `.locked`** using stability evidence from before the outage.

That is false lock.

## Cross-source contamination

`selectExternalTimingSource` currently only changes the selected ID.

It does **not** reset `clockEstimator`.

Therefore:

```text
Device A @ 120 BPM locks estimator
select Device B
Device B's first pulses enter estimator containing A history
```

Tempo EMA, interval history, pulse phase, stable count, and lock state can all leak between physical sources.

This violates the source-authority model.

## Required correction

Define explicit estimator lifecycle operations. For example:

```swift
mutating func resetForNewSource()
mutating func beginReacquisitionPreservingFreewheelTempo()
```

The exact API is flexible, but the semantics must be explicit.

### On selected source change

Perform a **full estimator reset**:

- pulse count / pulse phase reset or explicitly re-aligned;
- consecutive stability reset;
- interval history reset;
- lock state reset;
- EMA tempo history reset unless intentionally seeded from a documented source-independent estimate.

No A→B contamination.

### On dropout/loss

Do not allow pre-dropout stability count to qualify the returning source for lock.

At minimum:

```text
consecutiveStable = 0
```

before reacquisition.

Preserving the last tempo solely for the freewheel period is reasonable, but it must not count as new lock evidence.

### Invalid return interval

If the first interval after a gap is unusable/invalid, explicitly reset acquisition stability rather than doing nothing.

## Mandatory tests

- lock at 120 → lose for several seconds → first pulse does **not** relock;
- lock → lose → requires `lockPulseCount` stable new pulses to relock;
- source A locks at 120 → select source B at 90 → B must acquire independently;
- source A's `pulsesReceived`/phase/EMA must not leak into B diagnostics/state;
- rapid A→B→A switching must remain deterministic.

---

# 7. P0 — MIDI Start and SPP Must Align Pulse Phase with Canonical Position

**Severity:** P0 / correctness blocker  
**Files:** `ClockEstimator.swift`, `MusicalEngine.swift`

## Current inconsistency

`ClockEstimator` tracks an internal `pulseInQuarter` and publishes:

```swift
quarterPhaseFromPulses = Double(pulseInQuarter) / 24.0
```

`MusicalEngine.receiveClockPulse` advances canonical position:

```swift
let newQ = cur + 1.0 / 24.0
applyPositionLocked(.must(newQ), provenance: .midiClock)
```

`applyPositionLocked` correctly derives quarter phase from the fractional quarter-note position.

But immediately afterward the engine overwrites that phase with the estimator phase:

```swift
_state.timing.quarterNotePhase = clockEstimator.quarterPhaseFromPulses
```

The estimator's pulse counter is not reset/aligned by MIDI Start or SPP.

## Example: MIDI Start after arbitrary prior clock history

Assume the estimator previously has:

```text
pulseInQuarter = 17
```

MIDI Start resets canonical position to 0.

Next F8:

```text
canonical position = 1/24 quarter ≈ 0.04167
canonical phase should be 0.04167
estimator pulse phase becomes 18/24 = 0.75
```

Aurora can therefore publish:

```text
quarterNotePosition = 0.04167
quarterNotePhase = 0.75
```

Those two fields describe different places in musical time.

## SPP has the same problem

SPP positions are in sixteenth-note units, i.e. quarter phases can be:

```text
0.00, 0.25, 0.50, 0.75
```

The estimator pulse phase must align to that new position, otherwise the next clock pulse overwrites the correctly repositioned phase with stale pulse-count phase.

## Required correction

Give the estimator an explicit phase-alignment operation, for example:

```swift
mutating func resetPhaseForStart()
mutating func alignPhase(to quarterNotePosition: QuarterNotePosition)
```

### MIDI Start

Start must establish phase zero at musical origin according to the chosen MIDI semantics.

The first subsequent clock pulse should produce canonical position and phase that agree.

### SPP

SPP must align estimator pulse phase to the SPP quarter-note phase.

Because one MIDI clock pulse is 1/24 quarter and SPP is 1/4 quarter, all legal SPP phases map exactly to pulse indices:

```text
0.00 → 0
0.25 → 6
0.50 → 12
0.75 → 18
```

### Invariant

Always enforce:

```swift
quarterNotePhase ≈ quarterNotePosition.quarters - floor(quarterNotePosition.quarters)
```

unless the API explicitly documents a different concept. At present both fields are clearly intended to represent the same quarter-note phase.

## Mandatory tests

- feed arbitrary clock history → MIDI Start → next pulse → phase matches position;
- SPP to 0.25-quarter phase → next pulse → phase matches position;
- SPP to 0.50 and 0.75 phases;
- Stop + SPP + Continue;
- Start after a previously locked clock;
- no observer snapshot may expose contradictory phase/position values.

---

# 8. P0 — Preferred Fallback Must Restore Configured Internal/Song Tempo

**Severity:** P0 / product-contract blocker  
**Files:** `MusicalEngine.swift`, state/config model as needed

## Required behavior from the approved design

The feature specification says, in substance:

> briefly freewheel at the last known external tempo, then fall back to the configured internal/song tempo when available.

That separation matters:

- **freewheel** = continue last external timing briefly;
- **fallback** = return to Aurora's configured internal musical timing.

## Current behavior

External pulses overwrite:

```swift
_state.timing.tempoBPM = bpm
_state.timing.tempoProvenance = .midiClock
```

When external timing is finally lost, preferred fallback does:

```swift
_state.timing.activeSourceID = internal
_state.timing.tempoProvenance = .fallback
reanchorLocked(...)
```

but it never restores an internal/song BPM.

`reanchorLocked` then uses the current state tempo, which is the last external MIDI tempo.

Example:

```text
song default = 96 BPM
external clock = 120 BPM
external cable lost
freewheel = 120 BPM (correct)
fallback source ID = internal
fallback BPM = still 120 BPM (incorrect)
```

The UI can claim "internal fallback" while the engine continues at the lost external master's tempo.

## Root architectural issue

The engine currently has only one live `tempoBPM` field plus `projectDefaultTempoBPM`.

Once MIDI Clock becomes active, the engine loses the previous effective internal timing configuration (song metadata, tap/user BPM, etc.).

Phase C needs a separate concept of **configured internal tempo** versus **currently observed active-source tempo**.

## Required correction

Maintain an internal fallback tempo/configuration independently from external estimator output.

One possible model:

```swift
private struct InternalTimingConfiguration {
    var tempoBPM: Double
    var tempoProvenance: MusicalValueProvenance
}
```

or equivalent fields.

Rules:

1. Project/song/user/tap changes update the internal timing configuration.
2. When internal timing is active, canonical state reflects that configuration.
3. When MIDI Clock is active, canonical state reflects external estimated tempo, but the internal configuration is retained.
4. During freewheel, continue last external BPM.
5. On preferred fallback activation, restore the configured internal tempo and provenance/fallback indication deliberately.
6. Song changes while externally clocked must update the *future fallback baseline* without overwriting the currently active external tempo.

Do not simply fall back to `projectDefaultTempoBPM`; song/user/tap tempo may be the correct configured internal source.

## Mandatory tests

- project 120, external 100 → fallback returns 120;
- song 96, external 120 → fallback returns 96;
- user/internal 110, external 125 → fallback returns 110;
- change song metadata while external is active → external BPM remains active, new song BPM becomes fallback baseline;
- tempo change at fallback reanchors without position discontinuity.

---

# 9. P0/P1 — Selected Source Replacement Must Be an Atomic Timing Transition

**Severity:** P0/P1  
**Files:** `MusicalEngine.swift`, `ClockEstimator.swift`

## Current behavior

`selectExternalTimingSource` does this:

```swift
_state.timing.selectedSourceID = sourceID
```

and intentionally does not change active source.

That creates contradictory states.

Example:

```text
selected = A
active = A
A is locked

selectExternalTimingSource("B")

selected = B
active = A
```

After this point:

- timing events from A are rejected because A is no longer selected;
- `tick()` can still treat A as active and freewheel/evaluate the shared estimator;
- B enters the same estimator history when pulses arrive;
- queue authority semantics are unclear;
- UI may display active A while A is explicitly no longer an allowed source.

## Required correction

Changing selected external timing source must be an explicit authority transition.

Recommended semantics:

### Strict external

On A → B selection:

```text
selected = B
active = nil
sync = acquiring/unlocked
sourceHealth = unavailable/acquiring
reset estimator for B
apply timing-became-unavailable policies if A previously provided authority
```

Then B may become active only when it satisfies the Phase C acquisition criterion.

### External preferred/fallback

On A → B:

```text
selected = B
active = internal fallback
reset estimator for B
begin B acquisition in background
```

When B locks, hand off from internal to B.

### Clearing selected source

Define deterministic behavior:

- strict external: no external authority, active nil;
- preferred fallback: internal becomes/stays active;
- estimator resets.

## Timeline events

Emit source changes once per actual authority change. Do not imply A remains active after it has been explicitly deselected.

## Mandatory tests

- strict A locked → select B → A immediately ceases authority;
- queued timing work receives proper failure policy when A is retired;
- preferred A locked → select B → internal fallback takes authority while B acquires;
- A pulses after deselection are ignored;
- B estimator starts clean;
- clearing external selection behaves deterministically.

---

# 10. P1 — Held Quantized Work Must Release on First External Authority Acquisition

**Severity:** P1, potentially P0 for Phase D quantization correctness  
**Files:** `MusicalEngine.swift`

## Current behavior

A quantized action scheduled under strict external timing before timing exists can be held:

```swift
failurePolicy = .holdUntilTimingAvailable
```

When the external source first begins delivering pulses, the engine changes active source.

However, `releaseHeldNow` is currently set primarily for:

```swift
prevSync == .freewheeling || prevSync == .lost
    && new sync == .locked
```

That covers *recovery*, not the initial transition from no authority/acquiring → usable external authority.

Therefore held work can remain held indefinitely after the first successful external lock.

## Required correction

Centralize authority transition detection:

```text
hadUsableAuthority
    ↓ process state transition ↓
hasUsableAuthority
```

When:

```text
false → true
```

release/re-resolve held work exactly once.

This should apply regardless of how timing becomes usable:

- internal policy selected;
- preferred fallback activates;
- initial external lock;
- external re-lock;
- future provider activation.

Do not special-case each provider transition separately.

## Mandatory test

```text
strict external, no source authority
schedule next-bar action with holdUntilTimingAvailable
feed external source until lock
held action is re-resolved to the next valid boundary
pending entry is no longer held
```

---

# 11. P1 — Freewheel Duration Semantics Do Not Match the Configuration Comment

**Severity:** P1  
**File:** `ClockEstimator.swift`

Configuration says:

```swift
/// Freewheel duration at last BPM before lost.
public var freewheelSeconds: Double
```

But loss is evaluated using:

```swift
let freewheelAge = age // since last pulse
if freewheelAge >= config.freewheelSeconds {
    sync = .lost
}
```

Freewheel does not start until:

```swift
age >= dropoutAfter
```

Therefore the actual time spent in `.freewheeling` is approximately:

```text
freewheelSeconds - dropoutAfter
```

rather than `freewheelSeconds`.

At typical 120 BPM defaults this difference is small, but it becomes material with slower clocks or larger dropout multipliers.

The unused `freewheelStart` field suggests the intended implementation may originally have been to track the freewheel transition separately.

## Required correction

Choose and document one meaning.

Recommended:

```text
dropout threshold = grace period before declaring freewheel
freewheelSeconds = duration *after* entering freewheel
lost threshold = dropoutAfter + freewheelSeconds
```

or store actual `freewheelStart` at the transition host time and measure from there.

Add deterministic tests around exact threshold boundaries.

---

# 12. P1 — External Clock Capabilities Should Reflect Observed SPP

**Severity:** P1  
**Files:** `MusicalEngine.swift`, timing capabilities

Phase A intentionally fixed generic MIDI Clock capabilities to:

```text
suppliesSongPosition = false
supportsSongPositionInput = true
```

This is correct because MIDI Clock itself does not imply SPP.

Phase C now actually observes SPP, but active source capabilities remain `.midiClock`, so:

```text
supportsSongPositionInput = true
suppliesSongPosition = false
```

forever, even after the selected source has demonstrated SPP output.

The Phase A contract explicitly anticipated enabling the source-instance capability when SPP is observed/configured.

## Required correction

When accepted SPP is received from the active/selected MIDI timing source, update the source-instance capability:

```swift
activeSourceCapabilities.suppliesSongPosition = true
```

Reset that observation when changing source.

This is source-instance state, not a mutation of the static `.midiClock` capability constant.

## Tests

- plain clock source: `suppliesSongPosition == false`;
- after accepted SPP: true;
- unselected source SPP cannot alter capability;
- changing source resets observed SPP capability.

---

# 13. P1 — Phase C Acceptance Tests Need the Integration Cases Required by the Approved Plan

**Severity:** P1  
**Files:** Phase C tests, MIDI parser/adapter integration tests

The current Phase C test set covers useful basics:

- stable 120 BPM lock;
- external advancement;
- unselected source rejection;
- freewheel/fallback;
- strict loss;
- Effects consumer;
- SPP seek;
- Start/Stop/Continue;
- adapter forwarding.

However, the approved Phase C amendments specifically required:

- interleaved clock + dense performance traffic integration tests;
- tempo changes;
- source selection vs active/fallback behavior;
- re-lock/seek/discontinuity tests.

Those cases are not yet adequately represented.

## Required tests

### Dense channel-voice + clock

Feed realistic packet streams containing:

```text
F8
Note On
F8
CC
F8
Note Off
F8
running-status Note On data
...
```

across packet boundaries.

Assert:

- all timing pulses reach the timing adapter exactly once;
- all channel-voice events reach the legacy/AME path exactly once;
- running status remains correct;
- real-time bytes do not disturb channel messages;
- clock lock remains stable under dense traffic.

### Tempo step/ramp

Examples:

```text
120 BPM locked → 100 BPM
100 BPM locked → 140 BPM
small gradual tempo ramp
```

Assert no impossible BPM spikes and deterministic reacquisition/responsiveness.

### Re-lock continuity

Test:

```text
locked
→ dropout
→ freewheel
→ clock returns before fallback
→ re-lock
```

Canonical position must not jump backward and should not double-count elapsed phase.

### SPP + Continue

Test the actual MIDI sequence:

```text
Stop
SPP
Continue
Clock...
```

not only isolated SPP mutation.

### Source replacement

A → B while A is locked and while A is freewheeling.

---

# 14. P1 — Re-lock Continuity Needs an Explicit Invariant

**Severity:** P1  
**Files:** `MusicalEngine.swift`, `ClockEstimator.swift`

The original Phase C requirements explicitly include re-lock without discontinuities.

Current checkpoint says:

> full PLL phase soft-correct across re-lock deferred; basic freewheel/re-lock present

Deferring a sophisticated PLL is acceptable. Deferring the **continuity invariant** is not.

At minimum Phase C should guarantee:

1. external recovery never moves canonical quarter-note position backward;
2. a returning pulse is not counted on top of an already extrapolated interval in a way that systematically advances by an extra pulse;
3. recovery does not erase SPP-derived position;
4. freewheel → re-lock transition produces one clearly documented phase correction strategy;
5. scheduler targets do not double-fire across the correction.

A simple hard correction or bounded phase snap can be acceptable for this phase if documented and tested. Full PLL soft correction may remain deferred.

Add tests with deliberately early/late returning pulses.

---

# 15. P1/P2 — Timing Diagnostics Are Mostly Placeholders

**Severity:** P1/P2  
**Files:** `ClockEstimator.swift`, `MusicalEngine.swift`, `MusicalTimingDiagnostics`

The Phase C specification includes timing diagnostics.

Current code only writes:

```swift
lastPulseAgeMilliseconds = 0
pulsesReceived = ...
```

on a received pulse.

`estimatedJitterMilliseconds` remains `nil`, and `lastPulseAgeMilliseconds` is not updated during `tick()` as time passes.

That means diagnostics cannot presently tell the UI whether the last clock is 10 ms, 100 ms, or 1 second old.

This is not necessarily a P0 runtime blocker, but Phase C should leave a usable diagnostics contract.

Recommended minimum:

- estimator exposes a basic rolling/EMA interval deviation or jitter estimate;
- `tick()` updates pulse age from `lastPulseHostTime`;
- diagnostics reset appropriately on source changes;
- `lastError` or a structured diagnostic can indicate acquisition timeout/loss if desired.

Do not overbuild a telemetry system; just make the existing fields truthful.

---

# 16. P2 — Clean Dead/Unused Phase C State

**Severity:** P2

Current items include:

- `MusicalEngine.freewheelSeconds` assigned but not used;
- `ClockEstimator.freewheelStart` assigned/reset but not meaningfully used;
- `fireNow` / `canceled` locals in `receiveClockPulse` never mutate.

Either use these as part of the fixes above or remove them.

Compiler warnings should be zero in the touched modules at closeout.

---

# 17. Recommended Architecture for Phase C Closeout

The current design can be retained with one useful conceptual clarification:

## Selected source

What the user/configuration wants.

```text
selectedSourceID
```

## Candidate source

The selected source while the estimator is acquiring. This does not necessarily require a new public state field; it can be internal estimator state.

## Active source

The source that currently owns canonical musical time.

```text
activeSourceID
```

Under `externalPreferredFallback`, a selected external source can be **acquiring while internal remains active**.

That is a valid and important state:

```text
policy = externalPreferredFallback
selected = MIDI device A
candidate A = acquiring
active = internal
fallback = active/armed
```

Only when A reaches the usability threshold does authority hand off.

This removes the one-pulse freeze class entirely and produces clearer UI semantics later.

---

# 18. Recommended Internal Tempo Separation

To fix fallback correctly, avoid treating the canonical displayed tempo as the only source of truth.

A simple private model is sufficient:

```swift
private struct InternalTimingBaseline {
    var tempoBPM: Double
    var provenance: MusicalValueProvenance
}
```

or equivalent individual fields.

Update this baseline for:

- project default;
- song metadata;
- manual user tempo;
- tap tempo.

External MIDI tempo must **not destroy it**.

Then source transitions become explicit:

```text
internal active:
    state tempo = internal baseline

external locked:
    state tempo = estimator tempo

external freewheel:
    state tempo = last estimator tempo

fallback activates:
    state tempo = internal baseline
```

This is much safer than reconstructing the correct internal tempo during an emergency source-loss transition.

---

# 19. Estimator Lifecycle Recommendation

Do not make `reset()` the only lifecycle primitive if freewheel needs retained tempo.

Recommended conceptual operations:

```swift
resetForNewSource()
resetPhaseForStart()
alignPhase(to position: QuarterNotePosition)
beginReacquisition()
```

Possible semantics:

### `resetForNewSource`

Clear everything:

- sync
- EMA tempo
- last interval
- last pulse time
- pulse phase
- stable count
- diagnostics counters if source-local.

### `beginReacquisition`

Preserve last tempo only if needed for freewheel display/continuity, but clear:

- stable count;
- acquisition evidence;
- invalid gap interval.

### `resetPhaseForStart`

Align pulse phase with quarter origin without necessarily discarding a still-valid tempo estimate.

### `alignPhase(to:)`

Align pulse count modulo quarter to an SPP-derived position.

This prevents source lifetime, tempo estimate, transport position, and phase alignment from being conflated into one all-or-nothing reset.

---

# 20. Suggested Implementation Order

## C1 — Estimator lifecycle and acquisition safety

1. Add source/reset/reacquisition lifecycle semantics.
2. Fix stale stable-count false lock.
3. Add bounded acquisition/dropout behavior.
4. Fix freewheel duration semantics.
5. Add estimator tests independent of MusicalEngine.

## C2 — Source authority handoff

1. Do not abandon internal fallback on first pulse.
2. Define external usability threshold.
3. Make selected-source replacement atomic.
4. Centralize false→true / true→false authority transition handling.
5. Release held scheduler work on first usable external authority.

## C3 — MIDI phase/transport correctness

1. Align estimator phase on Start.
2. Align estimator phase on SPP.
3. Test Stop → SPP → Continue.
4. Add continuity invariant for re-lock.

## C4 — Internal fallback tempo baseline

1. Preserve configured internal tempo independently.
2. Make song/project/user/tap update baseline correctly.
3. Restore baseline after freewheel expiration.
4. Test song change while external active.

## C5 — Capability / diagnostics / integration tests

1. Mark source-instance SPP capability after observation.
2. Populate pulse-age diagnostics and basic jitter if keeping those fields.
3. Add dense performance + clock integration tests.
4. Add tempo-change and re-lock tests.
5. Remove dead state and warnings.

## C6 — Closeout

1. Run complete macOS suite.
2. Update `CHECKPOINT_AME_PHASE_C_MIDI_TIMING.md`.
3. Record exact test count.
4. **STOP before Phase D.**

---

# 21. Mandatory Phase C Re-Acceptance Tests

## Estimator

- [ ] stable 120 BPM lock
- [ ] stable 90 BPM lock
- [ ] invalid/long interval resets acquisition evidence
- [ ] first pulse after loss does not instant-lock
- [ ] full lock count required after loss
- [ ] source change resets estimator history
- [ ] freewheel duration means what configuration says
- [ ] acquisition timeout cannot remain infinite after one pulse

## Source authority

- [ ] preferred fallback remains internal during external acquisition
- [ ] one stray F8 cannot steal authority
- [ ] external becomes active only at declared usability threshold
- [ ] source A→B transition retires A immediately
- [ ] unselected A cannot mutate estimator after B selection
- [ ] strict external A→B applies timing-unavailable policies
- [ ] preferred A→B uses internal while B acquires

## Transport / phase

- [ ] MIDI Start resets/aligned phase
- [ ] first pulse after Start produces phase consistent with position
- [ ] SPP aligns estimator phase
- [ ] Stop → SPP → Continue works
- [ ] SPP provenance remains atomic
- [ ] Continue does not incorrectly reset position

## Fallback

- [ ] external loss first enters freewheel at last external BPM
- [ ] after freewheel, project baseline tempo restored
- [ ] song baseline tempo restored
- [ ] user/tap internal baseline restored
- [ ] position remains monotonic during fallback tempo switch

## Scheduler interaction

- [ ] holdUntilTimingAvailable scheduled before first external lock releases on lock
- [ ] `.cancel` and `.executeImmediately` behave on strict source loss
- [ ] held work behaves across source replacement
- [ ] no quantized action double-fires across re-lock/fallback

## MIDI integration

- [ ] dense clock + Note On/Off/CC traffic
- [ ] real-time bytes interleaved inside channel messages
- [ ] packet-boundary running status with clock
- [ ] timing and channel paths each receive events exactly once
- [ ] tempo change while dense performance traffic is active

## Re-lock

- [ ] dropout → freewheel → recovery before fallback
- [ ] returning early pulse
- [ ] returning late pulse
- [ ] no backward position jump
- [ ] no systematic extra-pulse advance

## Capabilities / diagnostics

- [ ] MIDI Clock alone does not claim SPP
- [ ] observed accepted SPP marks source-instance position capability
- [ ] source change clears observed SPP state
- [ ] pulse-age diagnostic increases between pulses
- [ ] diagnostics reset appropriately on source replacement

---

# 22. Checkpoint Corrections

Current Phase C checkpoint says:

```text
Status: COMPLETE — STOP before Phase D
```

Change this during remediation to something equivalent to:

```text
Status: POST-REVIEW CLOSEOUT IN PROGRESS — NOT ACCEPTED FOR PHASE D
```

After all findings above are closed and tests pass, update to:

```text
Status: ACCEPTED — CLEARED FOR PHASE D
```

The final checkpoint should explicitly mention:

- external acquisition does not steal fallback prematurely;
- estimator state is source-local;
- Start/SPP phase alignment;
- configured internal tempo restoration after freewheel;
- first-lock held-action release;
- dense MIDI traffic integration;
- re-lock continuity behavior.

---

# 23. What NOT to Change

Do **not** use this review as justification to redesign the good parts.

Preserve:

- `AuroraMusical` separate from CoreMIDI;
- `MusicalTimingSink` source-aware interface;
- monotonic `HostTime` path;
- typed System Real-Time vs System Common events;
- SPP as System Common;
- channel voice routed separately toward AME;
- explicit selected vs active source concepts;
- strict external vs preferred-fallback policies;
- anchor-based internal timeline;
- private scheduler boundary;
- synchronous safety actions;
- typed scheduled action tokens;
- meter owned by project/song context, not MIDI Clock;
- bounded timeline diagnostics/event ring;
- provider-agnostic consumers.

Do not begin AME rule evaluation while fixing Phase C.

---

# 24. Final Review Disposition

## Phase B

**ACCEPTED.**

The previously reported closeout issues are substantively resolved.

## Phase C

**NOT YET ACCEPTED.**

The implementation direction is good, but real hardware can currently expose source-acquisition, estimator-lifecycle, phase-alignment, and fallback-tempo failures that would directly undermine Phase D quantization.

### Permission to begin Phase D

**NO — not yet.**

Complete the Phase C closeout above, run the full macOS suite, update the Phase C checkpoint, and STOP for review.

---

# 25. Short Grok Directive

```text
Phase B is accepted. Do not redesign it.

Perform a Phase C closeout only.

Highest priority:
1. Do not let one external F8 steal preferred fallback authority.
2. Reset/reacquire ClockEstimator correctly after loss and source change.
3. Align estimator pulse phase on MIDI Start and SPP so phase == position fraction.
4. Preserve configured internal/song/user tempo separately and restore it after freewheel.
5. Make external source replacement an atomic authority transition.
6. Release held scheduler work on first successful external authority acquisition.
7. Add dense MIDI, tempo-change, SPP+Continue, and re-lock continuity tests.

Run the full macOS suite and update the Phase C checkpoint.
STOP before Phase D.
```
