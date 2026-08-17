# Aurora AME + Musical Engine — Code Review Pass 2 Closeout Fixes

**Review target:** `Aurora_AMEMusicEngine_CodeReviewPass2.zip`  
**Review date:** 2026-08-16  
**Disposition:** **HOLD Wave 6 hardware acceptance until the P0 items below are closed and the macOS suite is green.**

This is a closeout review of the integrated AME + Musical Engine after the second remediation pass. The previous Waves 1–5 fixes are largely present and correct. The remaining findings are mostly integration/idempotency and product-truthfulness problems, not architectural redesigns.

---

## Executive disposition

### What is now healthy

The following prior review items are implemented correctly enough to preserve:

- CoreMIDI full-ingress timing reaches `MIDIClockTimingAdapter` independently of channel-voice Learn.
- RTP-MIDI rides the same CoreMIDI source path, so network MIDI timing can reach the same ingress adapter.
- `MusicalEngineRuntimeDriver` owns high-resolution ticking independently of the 250 ms presentation timer.
- Immediate and quantized AME emissions now converge on `executeAuroraAction(...)`.
- Host callbacks for song / section actions are installed from `ShowControlController`.
- Song transitions use `setShowContext(...)` rather than overwriting Musical Engine project defaults.
- Scheduled payloads preserve control value, selection snapshot, ingress HostTime, mapping ID, and latency ID.
- Source-owned held controls and toggles unwind on device disconnect.
- Mapping-set / section-local activation is present.
- AME editor mutations are command-backed and therefore participate in document undo/redo.
- The archive checkpoint reports **740 tests / 0 failures** on macOS.

### Remaining gate

Do **not** begin Wave 6 hardware acceptance yet. Fix P0-1 through P0-3 first. P1 items should also be closed before declaring the AME/Musical Engine software track production-complete.

---

# P0 — Must fix before Wave 6

## P0-1 — Re-applying an unchanged project can destroy live Musical Engine timing authority and resolve queued work incorrectly

### Severity

**P0 / live-show timing correctness**

### Files

- `Sources/Aurora/AppModel.swift`
- `Sources/Aurora/Controllers/ShowControlController.swift`
- `Sources/AuroraMusical/MusicalEngine.swift`
- `Sources/Aurora/ControlActionRouter.swift`
- `Sources/AuroraEngine/AME/AMERuntime.swift`

### Current flow

Every document command triggers:

```swift
// AppModel.swift
document.onProjectModified = { ...
    self.applyProjectUpdate()
    ...
}
```

which calls:

```swift
showControl.applyProjectUpdate(...)
```

and that always calls:

```swift
applyMusicalEngineFromProject(project, availableSources: lastMIDIInventory)
```

That function always calls, even when values are unchanged:

```swift
musicalEngine.setProjectDefaults(...)
musicalEngine.setClockEstimatorConfig(...)
musicalEngine.setTimingPolicy(policy)
...
musicalEngine.selectExternalTimingSource(sourceID)
```

`MusicalEngine.setTimingPolicy(...)` is **not idempotent**. It unconditionally rebuilds timing-source authority.

For `.externalMIDI`, it does this on every call:

```swift
_state.timing.activeSourceID = nil
_state.timing.activeSourceCapabilities = .init()
_state.timing.sourceHealth = .unavailable
_state.timing.sync = .unlocked
anchorHostTime = nil
```

It then compares old authority vs new authority and can run:

```swift
let resolution = scheduler.timingBecameUnavailable()
```

Therefore a totally unrelated document change can apply `cancel`, `executeImmediately`, or `holdUntilTimingAvailable` to already accepted quantized work.

### Concrete failure example

1. Project uses strict external MIDI Clock.
2. External source is locked and transport is running.
3. A drum hit schedules an action for the next bar with `.cancel` on timing loss.
4. User renames a cue, edits an AME label, patches a fixture, or performs any document command.
5. `onProjectModified` re-applies the same Musical Engine settings.
6. `setTimingPolicy(.externalMIDI)` clears active authority.
7. Scheduler sees timing become unavailable.
8. The pending next-bar action is canceled even though the MIDI clock never stopped.
9. The next F8 may reacquire authority, but the scheduled action is already gone.

For `.externalPreferredFallback`, the same unnecessary reapply can flap authority to internal fallback until the next external pulse.

For internal timing, repeated `setProjectDefaults(...)` can also re-anchor the internal clock on unrelated edits.

### Required correction

Make runtime configuration application **idempotent and diff-based**.

Preferred belt-and-suspenders solution:

#### A. MusicalEngine setters should no-op on semantically unchanged values

At minimum:

```swift
public func setTimingPolicy(_ policy: TimingSourcePolicy) {
    lock.lock()
    if _state.timing.timingPolicy == policy {
        lock.unlock()
        return
    }
    ...
}
```

Also avoid unnecessary re-anchors in `setProjectDefaults` when tempo/meter are identical.

`setClockEstimatorConfig` should avoid mutating/resetting anything when config is unchanged.

#### B. Host should diff project musical settings before applying

Keep a last-applied configuration snapshot in `ShowControlController`, for example:

```swift
struct AppliedMusicalProjectConfig: Equatable {
    var tempo: Double
    var meter: MusicalMeter
    var freewheelSeconds: Double
    var timingPolicy: TimingSourcePolicy
    var selectedSourceID: String?
}
```

Only call the corresponding engine setter when that field actually changed.

Do not treat every `ShowProject` mutation as a Musical Engine reconfiguration.

### Closely related AME problem

`ShowControlController.applyProjectUpdate(...)` also always executes:

```swift
controlRouter.updateMappings(project.midiMappings, project: project)
```

and `ControlActionRouter.updateMappings(...)` always calls:

```swift
let batch = ameRuntime.updateDocument(project.ame)
```

`AMERuntime.updateDocument(...)` intentionally releases all live/sim held state and clears ephemeral state.

That means **any unrelated project edit** currently looks to AME like an AME document replacement.

Examples:

- rename a cue while a fogger hold is active → AME releases the hold;
- edit a stage placement while a momentary control is active → AME releases it;
- type one character into an AME mapping name → the command causes a full runtime document replacement and ephemeral-state clear.

Safety-first release on a *real AME document replacement* is good. Doing it for every project mutation is not.

### Required AME correction

Diff the AME portion independently:

```swift
if oldAME != project.ame {
    controlRouter.updateAMEConfiguration(project.ame)
}
```

and do not call `AMERuntime.updateDocument(...)` for unrelated project changes.

Legacy MIDI mappings can likewise be diffed separately from AME configuration.

If an AME edit occurs while armed, retain the existing conservative release-on-document-change behavior unless a more granular safe mutation model is deliberately implemented later.

### Mandatory tests

Add macOS/integration tests that prove:

- [ ] With strict external timing locked, an unrelated project command does **not** change active source, sync state, or selected source.
- [ ] A pending `.cancel` quantized action survives an unrelated project edit.
- [ ] A pending `.holdUntilTimingAvailable` action is not spuriously moved into held state by an unrelated edit.
- [ ] A pending `.executeImmediately` action does not fire because a cue name changed.
- [ ] External preferred fallback does not flap to internal on an unrelated project command.
- [ ] Internal timing position does not jump/re-anchor materially on unrelated project mutations.
- [ ] A live AME hold survives an unrelated non-AME project edit.
- [ ] A deliberate AME document replacement still releases live held/toggle state safely.

---

## P0-2 — AME still advertises several actions as live-supported even though the executor intentionally does nothing

### Severity

**P0 / correctness and operator trust**

### Files

- `Sources/AuroraEngine/AME/AMEDiagnostics.swift`
- `Sources/Aurora/AuroraActionExecutor.swift`
- `Sources/Aurora/ControlActionRouter.swift`
- optional action-specific subsystems needed for actual implementation

### Current mismatch

`AMELiveActionSupport.isLiveSupported(...)` returns `true` for:

```swift
.advanceSequence
.fireSequenceStep
.triggerEffect
.setEffectRate
.setEffectDepth
.firePreset
.firePalette
.fireLook
.runBehavior
```

But `AuroraActionExecutor.supportLevel(...)` calls these only `supportedWithLimitations`, and `execute(...)` deliberately returns `.partial` without performing the action for several of them.

The router then does:

```swift
let outcome = executeAuroraAction(...)
if outcome != .unsupported {
    any = true
}
```

So `.partial` counts as AME having fired.

For actions such as `.firePreset`, `.firePalette`, `.fireLook`, `.runBehavior`, and effect actions, the action can therefore:

1. pass AME's live-supported gate;
2. be emitted as executable;
3. reach the executor;
4. execute no actual product behavior;
5. return `.partial`;
6. count as `ameFired == true`;
7. suppress unmatched/legacy fallback behavior;
8. produce a diagnostic that can be mistaken for a successful route.

This is a “truthfulness” bug, not merely missing polish.

### Sequence-control nuance

AME mapping actions are expanded by `AMERuntime.expandSequenceControlActions(...)`, so `.advanceSequence` and `.fireSequenceStep` can work **inside the AME mapping evaluation path**.

However the generalized executor still cannot perform those actions when they arrive from other legal `AuroraAction` contexts, such as section lifecycle actions. `SongSection.onEnterActions/onExitActions` can contain arbitrary `AuroraAction`s, so lifecycle sequence-control actions remain partial/no-op.

### Required correction

Pick one of these paths per action category:

#### Option A — implement it fully

Preferred for core AME actions:

- `.advanceSequence(UUID)`
- `.fireSequenceStep(sequenceID:stepIndex:)`

Expose deliberate runtime APIs on `AMERuntime` so the generalized executor can execute these outside the mapping-expansion path and return the step actions/result safely.

For effects/presets/palettes/looks/behaviors, wire the actual owning subsystem if those action cases are now part of the promised AME product surface.

#### Option B — mark it honestly unsupported until productized

If not implementing now:

- `AMELiveActionSupport.isLiveSupported(...)` must return `false` for the action;
- the editor should hide/disable it or show a clear “not yet executable” state;
- the executor should return `.unsupported`, not `.partial` presented as a successful AME fire;
- the router must not set `ameFired = true` for a no-op.

### Compound semantics

A compound containing supported + unsupported children may reasonably return `.partial`, but diagnostics should enumerate which children actually executed. A compound should count as live-fired only if at least one child truly executed.

### Mandatory tests

- [ ] Every `AuroraAction` case has a test asserting support level and actual side effect/no-side-effect.
- [ ] No action classified `supported` or live-supported may return without a real effect.
- [ ] Unsupported preset/palette/effect/etc action does not count as an AME live fire.
- [ ] Section onEnter/onExit `.advanceSequence` works if declared supported, or is rejected diagnostically if intentionally unsupported.
- [ ] Section onEnter/onExit `.fireSequenceStep` follows the same rule.
- [ ] Mixed compound reports true partial execution, not blanket success.

---

## P0-3 — AME Learn lifecycle is tied to the window poll and can swallow a later performance event after the window is closed

### Severity

**P0 / live-control mode lifecycle**

### Files

- `Sources/Aurora/AMEEngineWindowRoot.swift`
- `Sources/Aurora/ControlActionRouter.swift`
- `Sources/Aurora/Controllers/InputController.swift`

### Current behavior

The window owns local:

```swift
@State private var isLearning = false
```

and starts Learn with:

```swift
appModel.showControl.controlRouter.beginAMELearn(...)
```

The actual router has its own independent `ameLearnArmed` state.

There is no `.onDisappear` / window-close cancellation.

If the operator clicks **Learn MIDI** and closes the MIDI Engine window before hitting a pad/key:

1. window state disappears;
2. router remains `ameLearnArmed == true`;
3. the next future MIDI performance event enters `InputController`;
4. `router.isAMELearning` is true;
5. the event is consumed by `handleAMELearnEvents(...)`;
6. normal `router.handleMIDIEvents(...)` is skipped for that event;
7. a learn proposal is created, but the window that normally polls/commits it is closed.

Result: the first real performance hit after closing the window can be swallowed and turned into an orphan Learn proposal.

### Required correction

Learn session ownership must not depend on a SwiftUI window-local boolean.

At minimum:

- Cancel AME Learn in `AMEEngineWindowRoot.onDisappear`.
- Make UI state derive from router/session state rather than maintain an independent truth where practical.
- Decide what happens to a captured proposal if the editor closes immediately after capture: either commit before close, retain a visible pending proposal in a persistent model, or cancel/discard it explicitly.
- Ensure closing the AME window can never leave a hidden mode that intercepts the next performance event.

Preferred shape:

```swift
@MainActor
final class AMELearnCoordinator: ObservableObject {
    enum State { case idle, armed, captured(AMELearnProposal) }
    ...
}
```

owned by app/show-control scope rather than view lifetime.

### Mandatory tests

- [ ] Arm AME Learn → close window → next MIDI note follows normal AME/legacy routing, not Learn capture.
- [ ] Arm → capture → close before UI poll does not strand an inaccessible proposal.
- [ ] Reopen window reflects the real Learn state.
- [ ] Legacy Learn and AME Learn still do not starve MIDI Clock ingress.

---

# P1 — Required software closeout before calling Waves 1–5 complete

## P1-1 — AME editor deliberately replaces its entire view identity every 250 ms

### Files

- `Sources/Aurora/AMEEngineWindowRoot.swift`

### Current code

The window runs:

```swift
.onReceive(Timer.publish(every: 0.25, ...)) { _ in
    pollTick &+= 1
    ...
}
.id(pollTick)
```

Changing `.id(...)` tells SwiftUI that the entire `AMEEnginePanel` is a different view identity every 250 ms.

This is an extremely risky way to refresh presentation state for an editor containing active `TextField`, `Picker`, `Form`, scroll position, focus, menus, and in-progress interaction.

Likely symptoms include:

- text field focus loss or flicker;
- interrupted typing/selection;
- menus closing;
- scroll jumps;
- unnecessary destruction/recreation of a large editor subtree;
- hard-to-reproduce editing behavior that depends on the 4 Hz timer phase.

### Required correction

Remove `.id(pollTick)` as the refresh mechanism.

Use real observable state:

- subscribe to Musical Engine state observers and publish a presentation snapshot;
- subscribe to AME monitor changes / diagnostics;
- or retain a lightweight `@State` snapshot updated by the presentation timer without changing root identity.

If a timer is temporarily retained, simply updating an actual state value referenced by the view is enough to invalidate SwiftUI rendering. Do not use identity replacement.

### Mandatory UI test/manual acceptance

- [ ] Hold focus in mapping name field for >10 seconds while timing/monitor updates stream; typing is uninterrupted.
- [ ] Open a Picker/Menu across multiple presentation refreshes; it stays open.
- [ ] Scroll position does not jump every 250 ms.

---

## P1-2 — Wave 5 editor still cannot configure several persisted/runtime AME features

### Files

- `Sources/AuroraUI/Panels/AMEEnginePanel.swift`
- `Sources/Aurora/AMEEngineWindowRoot.swift`
- `Sources/AuroraCore/Commands/AMECommands.swift`

### What the editor can now do

The editor has useful real functionality: trigger/mapping/sequence CRUD, trigger matching basics, mapping behavior/scope/quantization, basic actions, sequence steps, Learn, validation navigation, and command-backed mutations.

### Important model fields still not editable

`AMEMapping` includes:

```swift
triggerGroupID
transform
burstSuppressionMilliseconds
overrideParentID
disablesParentID
claimsLegacyMappingID
claimsLegacyRuleID
```

but the mapping inspector does not expose them.

The project also persists:

```swift
MusicalEngineProjectSettings.timingPolicy
selectedExternalSourceBindingID
defaultTempoBPM
defaultMeter
freewheelSeconds
```

but the AME window only **displays** current timing policy; there is no editor for these settings anywhere in `Sources` found by this review.

`MIDISourceBinding` is selectable from triggers, but there is no source-binding CRUD/inspector. This makes manual external-clock/source configuration dependent on already-existing data or Learn-created bindings.

Sequence editor gaps include at least:

- `initialIndex`;
- step `weight` for weighted/random modes;
- rich step action creation (currently essentially GO/Stop/clear helpers).

The generic action-list menu is also a small hard-coded subset and cannot construct many associated-value actions such as cue/song/section IDs, arbitrary `programmerAttribute`, sequence controls, preset/palette/look IDs, behavior IDs, or effect IDs/rates/depths.

### Why this is required before Wave 6

The final hardware acceptance scenario must be buildable through the shipping UI. If external MIDI Clock policy/source/freewheel and the actual AME mapping behavior cannot be configured without JSON/test fixtures, the software track is not yet ready for the stated UI + real-hardware acceptance gate.

### Required correction

Add a command-backed **Project Timing / MIDI Sources** section in the AME window (or a clearly linked settings surface) supporting:

- timing policy;
- external source binding;
- project tempo;
- project meter/grouping;
- freewheel duration;
- source binding create/edit/delete/enable.

Complete the mapping inspector for runtime-significant fields:

- value transform;
- burst suppression;
- trigger groups;
- inheritance override/disable;
- legacy ownership claims (may be in an Advanced disclosure group).

Complete sequence controls:

- initial index;
- weight per step;
- generalized action editor per step.

Create a reusable typed `AuroraActionEditor` rather than adding more hard-coded menu buttons. It should expose valid parameters based on action case and use project object pickers for UUID-based actions.

### Acceptance

A user must be able to configure, without JSON/test APIs:

1. preferred external MIDI Clock source;
2. freewheel/fallback behavior;
3. a drum trigger learned from hardware;
4. a velocity transform;
5. a section-scoped mapping;
6. a weighted or ordered multi-step sequence;
7. quantization/failure policy;
8. release actions;
9. a song/section/cue/programmer action with real parameters.

---

## P1-3 — Name/hint MIDI source bindings are resolved for timing selection but not for AME performance trigger matching

### Files

- `Sources/AuroraModel/MIDISourceIdentity.swift`
- `Sources/AuroraEngine/AME/AMERuntime.swift`
- `Sources/Aurora/Controllers/ShowControlController.swift`

### Current split behavior

For Musical Engine source selection, `ShowControlController.resolveExternalSourceID(...)` uses:

```swift
MIDISourceIdentity.resolve(binding:inventory:)
```

which correctly converts a name/hint binding to a live canonical ID such as `ep:4242`.

AME trigger matching does **not** receive inventory resolution. It uses:

```swift
MIDISourceIdentity.matches(sourceID: event.sourceID, binding: binding)
```

When the binding has a stable CoreMIDI UID this works (`uid:123`).

But for a binding with no UID, `matches(...)` compares the canonical live source ID directly against display/hint text:

```swift
if sourceID == binding.endpointNameHint
if sourceID == binding.displayName
if sourceID == binding.modelHint
```

A live event source ID of `ep:4242` therefore does not match a persisted binding named `Nord Drum 3P` even though the inventory resolver can correctly establish that relationship.

Learn happens to avoid this in many cases because it may store the canonical `ep:` string as the display/hint, but imported, migrated, or manually created name bindings can fail.

### Required correction

Use the same resolved-source identity concept for AME performance matching.

Recommended approach:

- `ControlActionRouter` / AMERuntime receives a resolved binding table, e.g. `[bindingID: Set<canonicalSourceID>]`, refreshed from live MIDI inventory.
- Trigger evaluation compares `event.sourceID` to resolved canonical IDs.
- Stable UID remains strongest identity.
- Name/model/manufacturer hints are used only during inventory resolution, not on every performance event.

Do not make AMERuntime import CoreMIDI.

### Mandatory tests

- [ ] UID binding matches canonical `uid:` event.
- [ ] no-UID name binding resolved to `ep:` matches performance event.
- [ ] ambiguous duplicate-name binding does not silently match either endpoint.
- [ ] reconnect with changed endpoint ref resolves again by hints where appropriate.

---

## P1-4 — Per-keystroke commands create full runtime churn and pathological undo granularity

### Files

- `Sources/AuroraUI/Panels/AMEEnginePanel.swift`
- `Sources/Aurora/AMEEngineWindowRoot.swift`
- `Sources/AuroraCore/Commands/AMECommands.swift`

Most editor `Binding` setters immediately call `onUpdateMapping`, `onUpdateTrigger`, or `onUpdateSequence`, which immediately perform an `Upsert...Command`.

For text fields, this commonly means one document command per character.

Because `document.onProjectModified` rebuilds runtime projections, typing a mapping name can currently cause repeated engine/runtime work at human typing rate. P0-1's diffing will make that safe, but the command/undo behavior remains poor.

### Required correction

At minimum for free-form text/numeric entry:

- edit into local draft state;
- commit one command on submit/focus loss/debounce;
- preserve immediate command updates for discrete Pickers/Toggles if desired.

Undo should preferably revert a meaningful field edit, not one character at a time.

---

# P2 — Cleanup / observability

## P2-1 — Compiler warnings remain in the reviewed path

The Linux build progressed through `AuroraModel` and `AuroraMusical` before expected failure on macOS-only `Network`.

Warnings observed include:

- unused `cs` / `csec` bindings in `AMEConfigurationValidator.swift`;
- `fireNow` / `canceled` variables in `MusicalEngine.receiveClockPulse` never mutated.

These are not functional blockers but should be cleaned before the final hardware tag so warning output remains useful.

## P2-2 — Avoid `try?` swallowing AME editor command failures

`AMEEngineWindowRoot` currently uses `try? appModel.session.perform(...)` throughout CRUD/edit/Learn paths.

If a command fails, the UI can appear to accept an edit without any surfaced error.

Route failures through the existing document/app error presentation/logging path.

## P2-3 — Add live acceptance counters to the Wave 6 view/checklist

Before soak/hardware tests, expose or log at least:

- pending scheduled count;
- held scheduled count if separately available;
- action-token registry count;
- AME held count;
- AME toggle count;
- current external source / sync / pulse age;
- last timing discontinuity;
- AME diagnostic ring occupancy.

The point is to prove bounded state during long runs and make leaks visible without attaching a debugger.

---

# Required implementation order

```text
1. P0-1 idempotent/diffed runtime configuration
   ↓
2. P0-2 truthful action support or full implementations
   ↓
3. P0-3 Learn lifecycle ownership/window close safety
   ↓
4. P1-1 remove 4 Hz root identity replacement
   ↓
5. P1-3 canonical binding resolution for AME performance
   ↓
6. P1-2 finish runtime-significant editor/settings surfaces
   ↓
7. P1-4 edit batching / undo quality
   ↓
8. P2 cleanup + diagnostics
   ↓
9. Full macOS suite
   ↓
10. Wave 6 hardware matrix
```

---

# Regression suite additions required before Wave 6

## Configuration/idempotency

- [ ] unrelated project edit while external MIDI locked leaves authority unchanged
- [ ] unrelated edit does not invoke scheduler timing-loss failure policies
- [ ] unrelated edit does not release AME held/toggle state
- [ ] real AME document replacement still safely unwinds state
- [ ] actual policy/source/freewheel change still transitions correctly

## Execution truthfulness

- [ ] every `AuroraAction` support claim corresponds to a real side effect
- [ ] unsupported action never sets AME-fired success
- [ ] section lifecycle sequence-control behavior explicitly tested
- [ ] partial compound identifies executed vs unsupported children

## Learn/editor

- [ ] close editor while Learn armed does not swallow next performance event
- [ ] editor remains focus-stable for >10 seconds of 4 Hz monitor/timing updates
- [ ] external clock settings can be configured entirely through UI
- [ ] weighted sequence and value transform can be configured through UI
- [ ] source bindings can be managed through UI

## Source identity

- [ ] no-UID named source resolved to canonical endpoint matches AME trigger
- [ ] ambiguous names fail closed
- [ ] hotplug re-resolution works

---

# Wave 6 readiness gate

Wave 6 hardware testing may begin only when:

- [ ] P0-1 through P0-3 are fixed
- [ ] root editor identity is no longer replaced every 250 ms
- [ ] AME timing policy/source/freewheel are configurable in shipping UI
- [ ] action support is truthful (implemented or explicitly unsupported)
- [ ] AME performance source matching uses canonical resolved identities
- [ ] full macOS test suite is green
- [ ] checkpoint is updated with these closeout results

Then proceed to the real device/RTP-MIDI/long-run matrix.

---

# Reviewer disposition

**Architecture:** green.  
**Timing core:** green, subject to P0-1 host idempotency fix.  
**Quantization:** green, subject to P0-1 preventing false timing-loss transitions.  
**AME runtime:** green core; host update churn and support truthfulness need closeout.  
**AME editor:** materially improved but not yet sufficient for the final real-UI hardware acceptance scenario.  
**Wave 6:** **HOLD.**

The important theme of this review is that the engine no longer needs another redesign. The remaining work is to stop ordinary document/UI activity from masquerading as timing-source failure or AME document replacement, and to ensure the UI/executor tells the truth about what Aurora can actually do live.
