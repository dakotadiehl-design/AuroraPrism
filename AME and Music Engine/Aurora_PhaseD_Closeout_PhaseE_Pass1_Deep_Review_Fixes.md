# Aurora AME + Musical Engine
## Phase D Closeout Verification + Phase E Pass 1 Deep Code Review Fixes

**Review date:** 2026-08-16  
**Reviewed archive:** `Aurora_PhaseDCloseout_PhaseEPass1.zip`  
**Disposition:**

- **Phase D:** architecture and most closeout fixes are sound, but **two performance-mode/document-transition unwind defects remain and must be corrected**.
- **Phase E:** sequence engine is a strong first pass, but **not accepted for Phase F yet**. Several runtime semantics need correction before a visual editor or later quantization work is layered on top.
- **STOP before Phase F** until the P0/P1 items and mandatory regression tests below are closed.

---

# 1. Executive Summary

The Phase D closeout work substantially improved the AME core and preserved the intended architecture. The following previously reviewed behaviors are present in the code and appear correct:

- ingress monotonic timestamps survive into AME;
- physical held-control release occurs before normal fire-time gates;
- held controls snapshot their release actions at acquire time;
- release-all/document/context paths can produce outward deactivation emissions;
- toggle ON/OFF uses activation/release actions;
- unsupported generalized `AuroraAction` values are explicitly diagnosed rather than silently forged into a different action;
- value transforms use `inMin`/`inMax` as a real input window;
- AME processing is serialized under the runtime lock;
- duplicate runtime IDs use first-wins indexing rather than trapping;
- `gate` has been renamed/migrated to the more accurate `heldGate` concept.

However, the final Phase D implementation still contains a live-state transition bug: leaving `armed` removes held/toggle state but marks the generated release emissions as non-executable, so the host receives an unwind batch that it then refuses to apply. A related document-replace path does the inverse in dry-run mode and can mark simulated release actions executable.

Phase E also has several contract-level issues. Most important:

1. `fireThenAdvance` and `advanceThenFire` are currently behaviorally identical.
2. `onSongStart` / `onSectionEntry` resets also fire on song/section **exit to nil**, not only entry/start.
3. dry-run mutates the same held/toggle/sequence state later used by armed mode.
4. sequence reset semantics are incomplete when reset policy and state scope differ, especially `.onSongStart` + `.perSection`.
5. `.advanceSequence` currently **fires a step** rather than merely advancing state, despite being modeled separately from `.fireSequenceStep`.
6. malformed `fireSequenceStep` indices silently clamp to another real step instead of being rejected/diagnosed.
7. random/shuffle RNG is shared globally across all sequences/scopes, causing unrelated sequences to perturb one another's future random order.
8. the standalone sequence state table is publicly `@unchecked Sendable` even though its own documentation says it relies on `AMERuntime`'s external lock.

These are closeout-level fixes. The sequence architecture does **not** need to be discarded.

---

# 2. Build / Test Environment Note

I attempted the relevant Swift test/build paths in the review environment.

The package begins compiling the Phase E code successfully, but the complete build cannot finish on this Linux host because Aurora's output target imports Apple's `Network` framework:

```text
Sources/AuroraOutput/ArtNetOutputDriver.swift:3:8: error: no such module 'Network'
```

This is an environment limitation, not evidence of a macOS failure.

During compilation, the new AME/sequence sources themselves progressed through compile successfully before the Apple-framework dependency stopped the package. The archive checkpoint reports:

```text
700 tests, 0 failures
```

Grok must rerun the **full macOS suite** after the fixes below. Do not reduce that gate to isolated Phase E tests only.

---

# 3. Phase D Closeout Verification

## What is accepted from Phase D

The closeout implementation correctly addresses the major Pass 1 findings in these areas:

### D-A. Held release bypasses fire-time gates

`AMERuntime.process(...)` performs the physical release check before normal mapping evaluation:

```swift
if isPhysicalReleaseEdge(normalized) {
    let released = releaseMatchingHoldsUnlocked(...)
    ...
}
```

That is the correct architecture. A physical Note Off must not be blocked by debounce, timing availability, scope changes, or the mapping's current enablement.

### D-B. Release actions are snapshotted

`AMEHeldEntry` stores:

```swift
public var releaseActions: [AuroraAction]
```

and the entry snapshots those actions on acquire. This preserves the previously approved rule that release/unwind must not have to re-prove the original fire conditions after document/context changes.

### D-C. Unsupported generalized actions are explicit

`AMELiveActionSupport.isPhaseDLiveSupported(...)` and `AMEActionEmission.isLiveSupported` prevent AME from pretending unsupported actions executed. This is a good interim boundary until the generalized Aurora Action executor exists.

### D-D. Runtime duplicate IDs are defensive

The first-wins indexes in `AMERuntime.process(...)` avoid the former `Dictionary(uniqueKeysWithValues:)` trap class.

### D-E. Ingress time is preserved

The Phase D timestamp bridge is now based on the original ingress monotonic timestamp rather than substituting wall-clock/current processing time.

These pieces should remain.

---

# 4. P0 — Phase D Live Unwind on Mode Change Is Still Non-Executable

**Files:**

- `Sources/AuroraEngine/AME/AMERuntime.swift`
- `Sources/Aurora/ControlActionRouter.swift`
- `Tests/AuroraEngineTests/AMERuntimePhaseDTests.swift`

## Current behavior

`setPerformanceMode(...)` does this when leaving armed:

```swift
if old == .armed && newMode != .armed {
    return releaseAllHeld(reason: .modeChange, shouldExecute: false)
}
```

The router correctly receives and applies the returned batch:

```swift
let batch = ameRuntime.setPerformanceMode(newValue)
applyAMEReleaseBatch(batch)
```

but `applyAMEEmissions(...)` intentionally skips any emission whose `shouldExecute == false`.

Therefore:

```text
armed
  Note On -> .blind executes live
  switch mode to dryRun/edit
  runtime removes held entry
  runtime emits .blindOff with shouldExecute=false
  router discards it
  live blind can remain ON
```

This violates the Phase D closeout requirement that **armed → dryRun/edit must unwind live output**.

## Required fix

Release execution authority must be derived from the state that created the hold, not simply the destination mode.

At minimum:

```swift
let wasArmed = old == .armed
...
if wasArmed && newMode != .armed {
    return releaseAllHeld(reason: .modeChange, shouldExecute: true)
}
```

Better still, snapshot whether each held/toggle entry was acquired in an executing/armed context so release behavior is self-describing.

### Important API cleanup

`AMERuntime.performanceMode` currently has a public setter that calls `setPerformanceMode(...)` and discards the returned release batch:

```swift
set {
    _ = setPerformanceMode(newValue)
}
```

That setter is unsafe because a caller can silently throw away required outward deactivation emissions.

**Make `performanceMode` read-only publicly** and require state changes to use the batch-returning API, or otherwise redesign the setter so release emissions cannot be lost.

Preferred:

```swift
public var performanceMode: AMEPerformanceMode {
    lock.lock(); defer { lock.unlock() }
    return mode
}

@discardableResult
public func setPerformanceMode(_ newMode: AMEPerformanceMode) -> AMEHeldReleaseBatch
```

## Mandatory regression tests

- armed `whileHeld .blind` → change to dryRun → returned `.blindOff` has `shouldExecute == true`;
- armed toggle ON → change to edit → toggle release action is executable;
- public mode API cannot silently discard a required live release batch;
- dry-run-created holds do **not** produce executable OFF actions merely because mode changes.

---

# 5. P0 — `updateDocument` Can Execute Dry-Run Release Actions

**Files:**

- `Sources/AuroraEngine/AME/AMERuntime.swift`
- `Sources/Aurora/ControlActionRouter.swift`

## Current behavior

`updateDocument(...)` currently begins with:

```swift
let batch = releaseAllHeld(reason: .documentChange, shouldExecute: true)
```

This is unconditional.

A hold or toggle created while AME is in `dryRun` never activated live output, but replacing the document can return its release action as executable. The router then applies the batch.

Example:

```text
dryRun
  Note On simulates .blind       // shouldExecute=false, live blind unchanged
  document reload
  releaseAllHeld(... true)
  .blindOff becomes executable   // can affect real live state despite dry-run origin
```

## Required fix

Document-change unwind must preserve the execution provenance of the state being unwound.

Minimum acceptable closeout:

```swift
let shouldExecute = performanceMode == .armed
let batch = releaseAllHeld(reason: .documentChange, shouldExecute: shouldExecute)
```

More robust design: each held/toggle entry snapshots whether its activation was live-executed, and release execution follows that snapshot.

This same provenance concept will become increasingly useful as AME acquires simulation, UI preview, and remote-control paths.

## Mandatory tests

- dryRun hold → document replace → release emission exists for diagnostics but is non-executable;
- armed hold → document replace → release emission is executable;
- edit mode cannot produce a live release from nonexistent simulated state.

---

# 6. P0 — Dry-Run State Must Not Poison Armed State

**Files:**

- `Sources/AuroraEngine/AME/AMERuntime.swift`
- `Sources/AuroraEngine/AME/AMEHeldState.swift`
- `Sources/AuroraEngine/AME/AMESequenceRuntime.swift`
- Phase D and Phase E tests

## Current behavior

`dryRun` performs full evaluation using the **same** runtime tables as armed mode:

- held table;
- toggle table;
- sequence state table;
- debounce/rate-limit state.

The Phase E test explicitly codifies shared sequence mutation:

```swift
func testDryRunStillAdvancesSequenceState()
```

A simple failure case is:

```text
1. AME is dryRun.
2. User hits sequence trigger twice while testing.
3. Sequence advances from step 0 -> step 2 in the shared table.
4. User arms AME.
5. First live hit fires step 2 instead of the intended starting/live state.
```

A held mapping has the same class of failure:

```text
dryRun Note On -> held entry acquired
switch to armed
live Note On -> "already held" -> activation suppressed
```

A dry-run toggle can likewise enter armed mode already logically ON.

This is dangerous for live show control.

## Required behavior

Dry run may simulate stateful behavior for diagnostics, but **simulation state must not silently become live state**.

### Preferred architecture

Maintain separate ephemeral state domains:

```text
live/armed state
simulation/dryRun state
```

At minimum separate:

- held entries;
- toggles;
- sequence cursors/shuffle bags/RNG state;
- debounce/burst state.

### Acceptable smaller closeout if full separation is too invasive

On any `dryRun/edit -> armed` transition:

1. discard all non-live simulated held/toggle state without executing releases;
2. reset/restore sequence state to a documented armed baseline;
3. clear simulation debounce/burst history;
4. ensure no simulated state can suppress the first armed event.

If this smaller option is chosen, document that re-arming begins a fresh AME ephemeral state session. Do **not** silently preserve the dry-run cursor.

## Mandatory tests

- dryRun sequence hits do not change first armed step;
- dryRun held Note On does not block first armed Note On;
- dryRun toggle ON does not cause first armed trigger to behave as toggle OFF;
- dryRun debounce/burst history does not suppress the first valid armed event.

---

# 7. P0 — `fireThenAdvance` and `advanceThenFire` Are Currently Identical

**Files:**

- `Sources/AuroraEngine/AME/AMESequenceRuntime.swift`
- `Tests/AuroraEngineTests/AMESequencePhaseETests.swift`
- `docs/design/CHECKPOINT_AME_PHASE_E_SEQUENCES.md`

## Current behavior

The two public trigger policies are intended to have distinct semantics:

```swift
case fireThenAdvance
case advanceThenFire
```

The approved planning amendment explicitly retained both policies and defined the default:

```text
initialIndex = 0
policy = fireThenAdvance
First hit fires Step 0, then prepares Step 1.
```

But the current implementation makes both policies produce the same observable sequence.

### `fireThenAdvance`

Initial state:

```swift
cursor = initialIndex
```

First trigger:

```text
fire initialIndex
advance cursor
```

### `advanceThenFire`

Initial state:

```swift
cursor = nil
```

First trigger implementation:

```swift
let start = clamped(sequence.initialIndex, count: count)
state.cursor = start
return start
```

So the first trigger also fires `initialIndex`.

The existing test confirms the equivalence:

```swift
// First hit fires initialIndex (0); subsequent advance-then-fire
XCTAssertEqual(idx, [0, 1, 2, 0])
```

That means the user-visible policy selector would currently be a switch attached to nothing.

## Required fix

Give `advanceThenFire` genuinely distinct semantics.

Recommended model:

### `fireThenAdvance`

```text
initial cursor = initialIndex
trigger 1: fire initialIndex; advance
trigger 2: fire next; advance
```

### `advanceThenFire`

```text
initial cursor = initialIndex
trigger 1: advance according to mode; fire resulting step
trigger 2: advance; fire resulting step
```

Example, advance mode, `initialIndex = 0`:

```text
fireThenAdvance:  0, 1, 2, 0 ...
advanceThenFire:  1, 2, 0, 1 ...
```

Example, reverse mode, `initialIndex = 3`:

```text
fireThenAdvance:  3, 2, 1, 0 ...
advanceThenFire:  2, 1, 0, 3 ...
```

If Grok believes a different definition is preferable, it must still satisfy one non-negotiable condition:

> **The two enum values must have distinct, documented, testable behavior.**

Do not keep two persisted/user-visible policies that are behaviorally synonymous.

## Mandatory tests

- same sequence + same initialIndex, `fireThenAdvance` and `advanceThenFire` yield different first-step behavior;
- advance mode;
- reverse mode;
- ping-pong mode;
- loop and non-loop boundary behavior;
- diagnostics report fired step and resulting next state correctly for both policies.

---

# 8. P0 — Reset-on-Entry Policies Also Fire on Exit-to-Nil

**File:** `Sources/AuroraEngine/AME/AMERuntime.swift`

## Current behavior

Context transition detection is currently:

```swift
let songChanged = previous.activeSongID != context.activeSongID
let sectionChanged = previous.activeSectionID != context.activeSectionID
```

and then:

```swift
if songChanged {
    for seq in doc.sequences where seq.resetPolicy == .onSongStart {
        sequences.reset(... context: context)
    }
}

if sectionChanged {
    for seq in doc.sequences where seq.resetPolicy == .onSectionEntry {
        sequences.reset(... context: context)
    }
}
```

This treats **leaving** a context as entering/starting one.

Examples:

```text
Song A -> nil
```

causes every `.onSongStart` sequence to reset using a `song:nil` state key.

Likewise:

```text
Section Intro -> nil
```

causes `.onSectionEntry` resets even though no section was entered.

For `.sequenceGlobal` or `.perSong` state this can also reset real existing sequence state at the moment a section is merely exited.

## Required fix

Distinguish transition events explicitly.

Suggested semantics:

```swift
let enteredSong = context.activeSongID != nil
    && previous.activeSongID != context.activeSongID

let enteredSection = context.activeSectionID != nil
    && previous.activeSectionID != context.activeSectionID
```

Then:

```text
nil -> A     = entry/start
A -> B       = entry/start of B
A -> nil     = exit only, no on-entry reset
A -> A       = no transition
```

Do not create/reset synthetic `song:nil` or `section:nil` sequence state as a side effect of context exit.

## Mandatory tests

- section A → nil does not fire `.onSectionEntry` reset;
- nil → section A does;
- section A → section B does;
- song A → nil does not fire `.onSongStart` reset;
- nil → song A does;
- song A → song B does;
- global state is not accidentally reset by an exit-only transition.

---

# 9. P1 — Reset Policy × State Scope Semantics Are Incomplete

**Files:**

- `Sources/AuroraEngine/AME/AMESequenceRuntime.swift`
- `Sources/AuroraEngine/AME/AMERuntime.swift`
- `Sources/AuroraModel/AMEModels.swift`

Phase A deliberately modeled **reset policy** and **state scope** as independent concepts:

```swift
resetPolicy: onSectionEntry / onSongStart / manual / never
stateScope: sequenceGlobal / perSong / perSection
```

That is powerful, but Phase E must define every meaningful combination.

## Problem example

Consider:

```text
stateScope = perSection
resetPolicy = onSongStart
```

The table may retain state for several sections of Song A:

```text
section:A1 -> cursor 2
section:A2 -> cursor 4
section:A3 -> cursor 1
```

When Song A starts again, current `reset(sequence:context:)` resets only **one key derived from the current context**. If the song starts with A1 active, A2/A3's old per-section states remain stored. Later entering A2 resumes stale state despite the sequence being configured `onSongStart`.

The same issue can appear whenever a reset event logically applies to a broader domain than the selected state key.

## Required fix

Lock explicit semantics for the cross-product.

Recommended rules:

### `sequenceGlobal`

- `onSongStart`: reset the single global instance on each actual song start.
- `onSectionEntry`: reset the single global instance on each actual section entry.

### `perSong`

- `onSongStart`: reset the instance for the entered song.
- `onSectionEntry`: reset the current song's instance on each section entry.

### `perSection`

- `onSectionEntry`: reset the entered section instance.
- `onSongStart`: reset **all stored section instances belonging to the entered song**, not just whichever section happens to be active at the moment.

To implement the last rule robustly, the state key should probably stop hiding context inside an opaque String and preserve structured context identity, e.g.:

```swift
struct AMESequenceStateKey {
    let sequenceID: UUID
    let scope: Scope

    enum Scope: Hashable {
        case global
        case song(UUID)
        case section(songID: UUID?, sectionID: UUID)
    }
}
```

If Aurora guarantees globally unique section IDs, `section(UUID)` is sufficient for identity, but retaining the owning song in the state record makes domain-wide reset straightforward and debuggable.

Alternative: validate/disallow policy/scope combinations Aurora does not intend to support. What is not acceptable is exposing all combinations while only partially implementing some of them.

## Mandatory tests

Test every supported reset-policy/state-scope combination, especially:

- `onSongStart + perSection` with two previously visited sections;
- leave/re-enter same song;
- `onSectionEntry + perSong`;
- global sequence reset on actual entry but not exit.

---

# 10. P1 — `.advanceSequence` Fires a Step Instead of Only Advancing State

**Files:**

- `Sources/AuroraModel/AuroraAction.swift`
- `Sources/AuroraEngine/AME/AMERuntime.swift`

## Current behavior

The action model distinguishes:

```swift
.advanceSequence(UUID)
.resetSequence(UUID)
.fireSequenceStep(sequenceID: UUID, stepIndex: Int)
```

But `expandSequenceControlActions(...)` implements `.advanceSequence` by calling `resolveSequenceTrigger(...)` and appending the resulting step actions:

```swift
case .advanceSequence(let id):
    let resolved = resolveSequenceTrigger(...)
    outActions.append(contentsOf: resolved.actions)
```

So `advanceSequence` effectively means:

```text
trigger/fire current-or-next sequence step AND advance state
```

That is surprising and collapses two different concepts:

- mutate sequence state;
- execute sequence contents.

It also makes the action name misleading for future Conductor/show-management integrations.

## Required fix

Define the control actions precisely before Phase F exposes them in UI.

Recommended:

### `.advanceSequence(id)`

Advance sequence state **without firing step actions**.

### `.fireSequenceStep(id,index)`

Fire the requested step actions **without implicitly changing cursor** unless explicitly documented otherwise.

### normal mapping `sequenceID`

Perform the configured trigger policy: choose/fire step and update state.

If Aurora also needs an explicit first-class action meaning "trigger this sequence exactly as though its MIDI trigger fired", introduce a clearly named action such as:

```swift
.triggerSequence(UUID)
```

rather than overloading `advanceSequence`.

## Mandatory tests

- `.advanceSequence` changes cursor but emits no sequence step actions;
- `.fireSequenceStep` emits actions but leaves cursor unchanged;
- normal sequence trigger fires and advances according to trigger policy;
- compound control actions preserve deterministic ordering.

---

# 11. P1 — `fireSequenceStep` Silently Clamps Invalid Indices

**Files:**

- `Sources/AuroraEngine/AME/AMERuntime.swift`
- `Sources/AuroraModel/AMEConfigurationValidator.swift`

## Current behavior

```swift
let idx = min(max(0, stepIndex), seq.steps.count - 1)
outActions.append(contentsOf: seq.steps[idx].actions)
```

A corrupted or stale action requesting step `999` does not fail. It fires the sequence's **last real step**.

That is dangerous because malformed configuration is converted into a plausible but wrong lighting action.

Example:

```text
requested: fireSequenceStep(Intro, 999)
actual:    fires last Intro step
```

For live-show software, reject/diagnose is safer than "nearest valid action" for semantic references.

## Required fix

### Validation

`AMEConfigurationValidator` must validate both:

- referenced sequence exists;
- `stepIndex` is inside that specific sequence's bounds.

The validator currently only checks sequence existence.

### Runtime defense

Even after validation, runtime must defend malformed documents:

```swift
guard stepIndex >= 0, stepIndex < seq.steps.count else {
    diagnostic(.sequenceInvalidStep)
    emit nothing
    break
}
```

Do not clamp to a different step.

## Mandatory tests

- negative step index → diagnostic, no actions;
- index == count → diagnostic, no actions;
- huge positive index → diagnostic, no actions;
- valid index fires exactly that step.

---

# 12. P1 — Random/Shuffle RNG Is Globally Coupled Across Sequences and Scopes

**File:** `Sources/AuroraEngine/AME/AMESequenceRuntime.swift`

## Current design

`AMESequenceStateTable` owns one RNG:

```swift
private var rng: AMESeededRNG
```

Every random, weighted-random, and shuffle-bag sequence consumes from that single stream.

This means unrelated sequence activity changes another sequence's future random behavior.

Example:

```text
seed = 42

Run A alone:
A hit -> A choice 1
A hit -> A choice 3

Run A with unrelated sequence B interleaved:
A hit -> A choice 1
B hit -> consumes global RNG
A hit -> A choice may now be different
```

The same coupling exists across `perSong` and `perSection` state instances.

This weakens two intended properties:

- state scopes behave independently;
- deterministic reproduction/debugging of one sequence does not depend on unrelated sequence traffic.

## Required fix

Prefer RNG state per `AMESequenceStateKey` (or deterministic substream per key), derived from:

```text
base show seed + sequenceID + scope discriminator
```

Possible design:

```swift
struct AMESequenceRuntimeState {
    ...
    var rngState: UInt64
}
```

or maintain:

```swift
[AMESequenceStateKey: AMESeededRNG]
```

A reset policy must explicitly define whether it resets the random stream for that instance. For reproducible "reset sequence" behavior, I recommend **yes**: reset should return a random/shuffle sequence to its deterministic starting stream for that key.

If product intent is instead "reset cursor/bag but continue randomness", document and test that intentionally. Do not leave it as accidental global coupling.

## Mandatory tests

- with the same seed, Sequence A produces the same choices whether or not unrelated Sequence B fires between A events;
- two section-scoped instances do not consume one another's RNG stream;
- reset behavior for random/weighted/shuffle is deterministic and documented;
- shuffle-bag still avoids immediate repeat across reshuffle when looping.

---

# 13. P1 — `AMESequenceStateTable` Is Public `@unchecked Sendable` but Not Thread-Safe

**File:** `Sources/AuroraEngine/AME/AMESequenceRuntime.swift`

The class says:

```swift
/// Thread-safety owned by `AMERuntime` lock.
public final class AMESequenceStateTable: @unchecked Sendable
```

but the class and its mutating methods are public.

That combination advertises cross-concurrency safety to callers while relying on a lock the class itself does not own and external callers cannot be required to hold.

Methods such as:

```swift
setSeed
clear
reset
trigger
removeStates
pruneRemovedSequences
```

mutate dictionaries/RNG without internal synchronization.

## Required fix

Choose one:

### Preferred

Make the table an internal implementation detail of `AuroraEngine` and expose only safe snapshot/control methods through `AMERuntime`.

```swift
final class AMESequenceStateTable { ... }
```

No `public`, no misleading `@unchecked Sendable` contract.

### Alternative

Give it an internal lock/actor isolation and make its public Sendable claim genuinely true.

Do not keep a public `@unchecked Sendable` mutable type whose correctness depends on undocumented external serialization.

---

# 14. P1 — Reverse Mode Default Starting Semantics Need a Locked Contract

**Files:**

- `Sources/AuroraModel/AMEModels.swift`
- `Sources/AuroraEngine/AME/AMESequenceRuntime.swift`
- Phase E tests/checkpoint

The feature spec illustrates reverse as:

```text
4 -> 3 -> 2 -> 1 -> 4
```

but `AMETriggeredSequence.initialIndex` defaults to `0` for every mode.

Therefore a newly created reverse sequence using defaults behaves approximately:

```text
0 -> last -> last-1 -> ...
```

unless the caller/UI remembers to set `initialIndex = steps.count - 1`.

The current test hides this by explicitly specifying `initialIndex: 3`.

This is not necessarily a runtime bug if `initialIndex` is intentionally fully user-defined, but **Phase F cannot build the editor until the default creation semantics are explicit**.

## Required decision

Either:

1. reverse defaults to the final step when no explicit initial index is provided; or
2. reverse always starts at the configured `initialIndex`, and UI creation explicitly initializes new reverse sequences to `lastIndex` to match the feature description.

Add a test for the chosen product behavior.

---

# 15. P1 — Non-Looping Sequence Terminal Semantics Need to Be Finalized Before UI

The Phase E checkpoint currently states:

```text
loop=false clamps at ends
```

and the test expects:

```text
0, 1, 1, 1
```

for a two-step non-looping advance sequence.

This means `loop=false` does **not** mean "play once and finish". It means "stop advancing, but continue firing the terminal step forever".

That may be intentional, but it is a potentially surprising live-control contract.

Similarly, non-looping ping-pong can clamp at an endpoint rather than representing a clearly exhausted sequence.

Before Phase F exposes a `Loop` toggle, lock one of these semantics:

### Option A — current clamp/re-fire

```text
loop=false => cursor stops at endpoint; every future trigger re-fires endpoint
```

If retained, document this explicitly in the UI/spec.

### Option B — one-shot exhaustion

Add an `isExhausted` runtime state and subsequent triggers emit nothing until reset.

For a lighting sequence editor, Option B is likely closer to what many users will infer from "Loop off", but either is valid if deliberate.

**This is a contract decision that should be made before Phase F, not after users can create saved sequences through the UI.**

---

# 16. P2 — `peekNextFireIndex` Is Misleading for Shuffle Bag

For `.shuffleBag`, `peekNextFireIndex(...)` currently returns `state.cursor`, which is the **last fired step**, even when `state.shuffleBag.first` already contains a deterministic next step.

Phase F is expected to visualize current/next sequence state, so this will become visible.

Recommended:

```swift
case .shuffleBag:
    if let next = state.shuffleBag.first { return next }
    return nil // next requires a new shuffle / RNG consumption
```

For random/weighted random, `nil` is more semantically honest than returning the last fired step as "next" unless Aurora intentionally previews and reserves the next RNG draw.

Consider renaming APIs to distinguish:

```text
lastFiredIndex
nextDeterministicFireIndex
```

instead of one best-effort field that means different things by mode.

---

# 17. P2 — Sequence Control Actions Nested Inside Sequence Steps Need a Defined Policy

`expandSequenceControlActions(...)` processes control actions in the current flattened action list, but actions returned by an `.advanceSequence(...)` resolution are appended to output rather than recursively re-expanded.

Therefore a sequence step containing another sequence-control action can behave differently depending on where that action originated.

Do not add recursive execution blindly, because self-referential sequences could recurse forever.

Before Phase F allows arbitrary actions in a sequence step, choose one:

1. **Disallow sequence-control actions inside sequence steps** via validation/UI; or
2. support nested sequence control with a deterministic bounded execution graph and cycle detection.

For the near-term closeout, validation that prevents recursive sequence-control composition is the safer choice.

---

# 18. Validation Hardening Required for Phase E

Extend `AMEConfigurationValidator` with the following checks:

- `fireSequenceStep` step index exists in the referenced sequence;
- unsupported policy/state-scope combinations, if any are intentionally disallowed;
- sequence-control cycles/nesting rules, if sequence steps may contain sequence-control actions;
- optional warning when a mapping requests quantization but a referenced sequence contains safety-critical step actions (runtime correctly bypasses quantization for safety, but configuration intent is surprising);
- chosen reverse default/initial-index semantics;
- chosen non-loop terminal semantics where validation is relevant.

Runtime must remain defensive even after validator coverage. Never assume package data is valid merely because the editor normally creates valid data.

---

# 19. Mandatory Test Additions

## Phase D transition regressions

- [ ] armed held activation → mode change → executable release emitted/applied
- [ ] armed toggle ON → mode change → executable toggle release
- [ ] dryRun held activation → document replace → non-executable release
- [ ] armed held activation → document replace → executable release
- [ ] public performance-mode API cannot discard required release batch
- [ ] dryRun state does not suppress/alter first armed event

## Trigger policy

- [ ] `fireThenAdvance` and `advanceThenFire` differ observably
- [ ] advance mode for both policies
- [ ] reverse mode for both policies
- [ ] ping-pong mode for both policies
- [ ] initialIndex != 0
- [ ] boundary behavior

## Context reset lifecycle

- [ ] song A → nil does not count as song start
- [ ] nil → song A resets onSongStart
- [ ] song A → song B resets B
- [ ] section A → nil does not count as section entry
- [ ] nil → section A resets onSectionEntry
- [ ] section A → section B resets B
- [ ] `onSongStart + perSection` resets all appropriate section instances for entered song
- [ ] `onSectionEntry + perSong` defined/tested
- [ ] sequenceGlobal policy interactions tested

## Sequence control actions

- [ ] advanceSequence advances state without firing, if recommended semantics adopted
- [ ] fireSequenceStep does not mutate cursor
- [ ] OOB fireSequenceStep is rejected rather than clamped
- [ ] missing sequence remains diagnostic/no-op
- [ ] compound ordering deterministic

## Random / weighted / shuffle

- [ ] unrelated Sequence B does not perturb Sequence A random stream
- [ ] separate section instances have independent deterministic streams
- [ ] reset RNG semantics locked and tested
- [ ] weighted selection deterministic under seed/substream
- [ ] shuffle each-once guarantee
- [ ] shuffle reshuffle immediate-repeat rule

## Mode isolation

- [ ] dryRun sequence simulation does not poison armed sequence cursor
- [ ] dryRun held state does not poison armed held state
- [ ] dryRun toggle state does not poison armed toggle state
- [ ] dryRun rate-limit state does not suppress first armed fire

## Full suite

- [ ] Full macOS `swift test` green
- [ ] Existing Phase A-D tests remain green
- [ ] Update `CHECKPOINT_AME_PHASE_D_AFK.md` if Phase D transition semantics changed
- [ ] Update `CHECKPOINT_AME_PHASE_E_SEQUENCES.md` with final sequence semantics

---

# 20. Recommended Implementation Order

```text
E-closeout-1
  Fix Phase D mode/document unwind provenance
  + eliminate unsafe performanceMode setter

E-closeout-2
  Separate or purge dryRun simulation state from armed state

E-closeout-3
  Correct trigger-policy semantics
  fireThenAdvance != advanceThenFire

E-closeout-4
  Correct context entry/start detection
  + lock reset-policy × state-scope semantics

E-closeout-5
  Separate sequence state-advance from step-fire operations
  + fix fireSequenceStep OOB behavior

E-closeout-6
  Isolate deterministic RNG by sequence state key

E-closeout-7
  Hide or synchronize AMESequenceStateTable
  + validator/test hardening

E-closeout-8
  Decide reverse-default + loop=false terminal semantics
  + update checkpoint/docs

FULL macOS suite
STOP
```

---

# 21. Things Not to Redesign

The following architecture is good and should survive this closeout:

- `AuroraModel` owns persisted AME/sequence definitions;
- `AuroraEngine` owns AME runtime state;
- sequence runtime state remains ephemeral rather than silently persisted;
- mapping evaluation remains serialized/deterministic;
- `sequenceID` on a mapping is the normal stateful sequence trigger path;
- seedable deterministic random behavior remains a requirement;
- trigger groups remain separate from sequence state;
- release actions remain snapshotted at acquire time;
- unsupported live actions remain explicit;
- quantized Musical Engine execution remains Phase G as planned;
- full section onEnter/onExit orchestration remains deferred as planned.

Do not turn this into a broad AME rewrite. The problems are semantic seams inside an otherwise usable structure.

---

# 22. Phase D Re-Acceptance Gate

Phase D may be finally stamped closed when:

- [ ] leaving armed executes deactivation for live-held/toggled output;
- [ ] dry-run/document transitions cannot execute releases for actions that never ran live;
- [ ] required release batches cannot be silently discarded through a public setter;
- [ ] dry-run ephemeral state cannot contaminate armed behavior;
- [ ] all Phase D regression tests remain green.

---

# 23. Phase E Re-Acceptance Gate

Phase E is ready for Phase F only when:

- [ ] `fireThenAdvance` and `advanceThenFire` have distinct documented semantics;
- [ ] reset-on-entry/start is not triggered by exit-to-nil;
- [ ] reset-policy × state-scope combinations are fully defined and tested;
- [ ] dry-run sequence state cannot alter armed sequence state;
- [ ] sequence advance vs fire semantics are explicit and correctly implemented;
- [ ] invalid `fireSequenceStep` indices do not silently fire another step;
- [ ] random/shuffle behavior is deterministic without cross-sequence RNG coupling;
- [ ] sequence state table's concurrency contract is truthful;
- [ ] reverse starting semantics are locked;
- [ ] `loop=false` terminal behavior is deliberately locked before UI exposure;
- [ ] validator covers new sequence invariants;
- [ ] full macOS suite is green;
- [ ] Phase E checkpoint is updated to reflect actual final semantics.

---

# 24. Final Review Disposition

## Phase D

**🟡 CLOSEOUT MOSTLY GOOD, TWO LIVE-STATE TRANSITION DEFECTS REMAIN**

The major Phase D architecture is accepted, but do not consider the held/release lifecycle fully closed until armed-mode exit and dry-run document replacement preserve correct execution provenance.

## Phase E

**🟡 STRONG PASS 1, CLOSEOUT REQUIRED BEFORE PHASE F**

The sequence engine has the right broad pieces:

- scoped state;
- advance/reverse/ping-pong/random/weighted/shuffle modes;
- explicit reset policies;
- deterministic seeded RNG foundation;
- mapping integration;
- diagnostics;
- first-class action contents;
- document/context lifecycle hooks.

The required changes are primarily about making the public semantics match the model and preventing simulation/context/random-state edge cases from becoming visible live-show failures.

**Do not begin Phase F until this closeout passes review.**
