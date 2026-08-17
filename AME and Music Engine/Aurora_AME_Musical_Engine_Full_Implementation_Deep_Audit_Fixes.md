# Aurora AME + Musical Engine — Full Implementation Deep Audit & Required Fixes

**Audit target:** `Aurora_AMEMusicEngine_FinalPhases.zip`  
**Date:** 2026-08-16  
**Scope:** Entire Advanced MIDI Engine (AME) + Musical Engine stack, Phases A–I, including models, persistence, validation, MIDI ingress, timing authority, clock estimator, scheduler, AME runtime, sequences, quantization, song/section integration, dedicated AME UX, reliability tests, and host integration.

## Executive disposition

The implementation contains a **strong architectural core**, and the earlier Phase A–E closeout work is largely preserved. However, the current archive should **not** be considered “full AME + Musical Engine complete” yet.

There are two different categories of remaining work:

1. **Runtime correctness / live-show blockers** — defects that can make configured behavior fail, disappear, fire late, apply the wrong value, or leave held state stranded.
2. **Incomplete phases disguised as narrowed closeouts** — especially Phase F (editor/Learn UX), Phase H (real song/section integration), and Phase I (hardware/reliability acceptance).

### Current recommendation

- **Phases A–E:** architecture accepted, subject to cross-phase integration fixes below.
- **Phase F:** **NOT complete** relative to the approved feature spec. Current code is a read-only AFK shell.
- **Phase G:** runtime concept is present, but contains critical integration bugs.
- **Phase H:** transition helper exists, but actual product integration is incomplete.
- **Phase I:** deterministic smoke tests exist, but the approved hardware/reliability gate was explicitly skipped.
- **Overall:** **STOP before calling the AME/Musical Engine track complete.** Apply P0/P1 fixes, complete Phase F/H product wiring, then perform the actual Phase I hardware/soak gate.

---

# P0 — Must fix before live smoke testing

## P0-1 — MIDI Clock is not wired into the running application at all

### Evidence

`MIDIInputManager` correctly exposes full ingress through:

```swift
setIngressHandler(_ handler: ([MIDIIngressEvent]) -> Void)
```

and `MIDIClockTimingAdapter` correctly converts System Real-Time / SPP ingress into `MusicalTimingSink` calls.

However, the application wiring in `Sources/Aurora/Controllers/InputController.swift` only installs:

```swift
midi.setHandler { events in ... router.handleMIDIEvents(events) }
```

There is **no call anywhere in production Sources** to:

```swift
midi.setIngressHandler(...)
MIDIClockTimingAdapter(...)
```

`MIDIClockTimingAdapter` is referenced only by tests and its own source file.

### Impact

The Phase C MIDI Clock implementation works in unit tests but is not connected to live CoreMIDI ingress. In the actual app:

- F8 Timing Clock never reaches `MusicalEngine`.
- Start / Stop / Continue never reach `MusicalEngine`.
- SPP never reaches `MusicalEngine`.
- External MIDI timing can never become authority in normal product use.

This makes Phase C and the external-timing portions of Phases G/H functionally disconnected from Aurora.

### Required fix

Create one long-lived `MIDIClockTimingAdapter` owned by the input/show-control layer and wire full ingress independently of channel-voice routing.

Preferred ownership:

```swift
InputController
  MIDIInputManager
  MIDIClockTimingAdapter -> ShowControlController.musicalEngine
```

During `startMIDI(...)`:

```swift
midi.setIngressHandler { [weak clockAdapter] ingress in
    clockAdapter?.handle(ingress: ingress)
}
```

Do **not** route timing through the ordinary `MIDIEvent` handler because MIDI Learn currently short-circuits that handler. Clock must continue while Learn is armed.

### Mandatory tests

- Product-level integration harness: `MIDIInputManager` synthetic ingress -> adapter -> real `MusicalEngine`.
- F8 stream locks external timing through the same handler topology used in the app.
- Start/Stop/Continue and SPP work while MIDI Learn is armed.
- Dense channel MIDI + interleaved F8 both reach their respective consumers.

---

## P0-2 — Persisted timing policy / source / freewheel settings are never applied to MusicalEngine

### Evidence

`MusicalEngineProjectSettings` persists:

- `timingPolicy`
- `selectedExternalSourceBindingID`
- `defaultTempoBPM`
- `defaultMeter`
- `freewheelSeconds`

But `ShowControlController.applyMusicalProjectDefaults` only applies:

```swift
musicalEngine.setProjectDefaults(tempoBPM: settings.defaultTempoBPM, meter: meter)
```

No production caller invokes:

```swift
musicalEngine.setTimingPolicy(...)
musicalEngine.selectExternalTimingSource(...)
```

and the configured `freewheelSeconds` is not applied to the clock estimator/runtime.

### Impact

A project can save “External MIDI” or “External Preferred Fallback” and an external source binding, but reopening/loading the project leaves the engine using its runtime defaults. The UI can therefore display persisted configuration that the live engine is not honoring.

### Required fix

Implement one explicit project-settings application function that atomically applies all Musical Engine settings:

```text
project AME musical settings
  -> canonical TimingSourcePolicy
  -> resolved stable CoreMIDI source ID
  -> MusicalEngine.selected source
  -> freewheel/dropout configuration
  -> project tempo/meter defaults
```

Resolve `selectedExternalSourceBindingID` through `AMEProjectDocument.sourceBindings` to the same canonical source ID string emitted by `MIDIInputManager`.

Do not use display names as the primary identity when a CoreMIDI UniqueID is available.

### Mandatory tests

- Save externalMIDI + binding -> load -> MusicalEngine policy/source match.
- Save preferredFallback -> load -> internal owns timing until selected source locks.
- Save internalOnly -> external F8 is ignored.
- Project freewheel value changes estimator loss/fallback behavior.

---

## P0-3 — CoreMIDI source binding comparison is currently incompatible with the source IDs MIDIInputManager emits

### Evidence

`MIDIInputManager.stableSourceID(for:)` emits CoreMIDI UniqueID as:

```swift
"uid:\(unique)"
```

But `AMEMatchEngine.sourceMatchesBinding` checks:

```swift
sourceID == String(uid)
```

rather than:

```swift
sourceID == "uid:\(uid)"
```

### Impact

Any AME trigger with a source binding using `lastCoreMIDIUniqueID` will fail to match real CoreMIDI events.

This is especially serious because stable UniqueID is the preferred binding mechanism.

### Required fix

Create one canonical source-ID formatter shared by AuroraMIDI and AME binding resolution. Do not duplicate string formatting rules.

Example:

```swift
public enum MIDISourceIdentity {
    public static func coreMIDIUniqueID(_ id: Int32) -> String { "uid:\(id)" }
}
```

Use it for both ingress generation and binding matching.

### Mandatory tests

- Real-format source ID `uid:12345` matches binding `lastCoreMIDIUniqueID = 12345`.
- `uid:12345` does not match `12346`.
- Name fallback is only used when stable UID is absent.
- Duplicate endpoint names do not defeat UID matching.

---

## P0-4 — `holdUntilTimingAvailable` currently DROPS the AME action instead of holding it

### Evidence

`MusicalEngine.schedule()` correctly supports held scheduling:

```swift
case .holdUntilTimingAvailable:
    scheduler.enqueue(action, targetPosition: nil, hold: true)
```

But `AMERuntime.makeEmissions()` prevents the action from reaching that scheduler when timing is unavailable:

```swift
case .holdUntilTimingAvailable:
    include = false
    diagKind = .quantizeHeld
```

The host only schedules actual emissions. Therefore no emission -> no token -> no scheduler held entry.

### Impact

A mapping configured as:

```text
Quantize: Next Beat
Failure: Hold Until Timing Available
```

fires while clock is unavailable and simply disappears. It will never fire when timing returns.

### Required fix

Do not implement scheduler hold semantics inside AMERuntime by deleting the emission.

For `.holdUntilTimingAvailable`:

- emit the action with `executeImmediately = false`;
- preserve the requested boundary + failure policy;
- let `MusicalEngine.schedule()` place it into its held queue.

Diagnostics may still say `quantizeHeld`, but the action must actually exist downstream.

Recommended separation:

```text
AMERuntime decides semantic intent
MusicalEngine scheduler decides temporal availability/failure behavior
```

### Mandatory tests

End-to-end, not bridge-only:

1. Musical time unavailable.
2. AME event with nextBeat + holdUntilTimingAvailable.
3. Verify no immediate live action.
4. Verify MusicalEngine pending/held count increases.
5. Restore usable timing.
6. Verify action is re-resolved to the requested boundary and fires once.
7. Verify token registry returns to baseline count.

---

## P0-5 — Internal musical scheduling is driven by a 4 Hz UI/status timer

### Evidence

Production calls to `tickMusicalEngine()` occur only from:

- `ShowControlController.statusTimer`: every **0.25 s**
- `AMEEngineWindowRoot`: every **0.25 s** while that window is open

`MusicalEngine.tick()` is what advances internal-anchor state and calls:

```swift
scheduler.harvestDue(at: pos)
```

### Impact

For internal timing, quantized AME actions can fire up to roughly **250 ms late**.

Examples:

- At 120 BPM, an eighth note is 250 ms. A “next eighth” action can be almost one full eighth late.
- At 120 BPM, a sixteenth is 125 ms. A 250 ms harvesting interval can miss the intended subdivision by two sixteenths.
- Opening the AME window adds another independent 4 Hz tick source, meaning merely opening a diagnostics window can alter scheduling cadence.

This violates the core requirement for musically precise timing.

### Required fix

Musical scheduling must have a dedicated non-UI runtime driver.

Preferred architecture:

```text
MusicalEngine
  -> dedicated high-resolution scheduling driver / one-shot deadline timer
  -> no dependency on SwiftUI refresh timers
```

Options, in preference order:

1. **Dynamic next-deadline scheduling** using monotonic host time and a `DispatchSourceTimer` / appropriate macOS real-time-capable timer. Re-arm for the next pending musical deadline. Keep small leeway.
2. Dedicated high-frequency engine loop (e.g. 1–5 ms target cadence), if dynamic deadlines are too invasive.
3. Integrate into an existing non-UI engine render scheduler only if its cadence and jitter are proven adequate.

Do not use `Timer` on the main run loop for performance-critical firing.

The 4 Hz timers may remain for **presentation refresh only**.

### Acceptance target

Define and test an execution-jitter budget. Recommended initial goal:

- scheduler dispatch target error <= ~5 ms under normal system load;
- no dependency on whether AME window is open;
- no MainActor dependency for live firing.

### Mandatory tests

- Internal 120 BPM next-sixteenth fires near intended host-time boundary, not at next 250 ms poll.
- Same result whether AME window is open or closed.
- Dense scheduled actions do not accumulate one-tick latency.
- Timing-loss detection is not delayed by UI polling cadence.

---

## P0-6 — Quantized parameterized actions lose their control value at fire time

### Evidence

`AMEActionEmission` contains:

```swift
controlValue: Double
```

but `AuroraActionTokenRegistry` stores only:

```swift
action: AuroraAction
isSafetyCritical: Bool
```

When a quantized action fires, `ControlActionRouter.handleScheduledFire` resolves only the `AuroraAction` and calls:

```swift
applyLive(... control: nil ...)
```

`applyLive` then derives:

```swift
scalar = 0
```

when control is absent.

### Impact

A quantized continuous/velocity mapping can execute with the wrong value.

Examples:

```text
CC -> masterIntensity = 0.75 -> quantize next beat
```

At the boundary, the scheduled path calls `.masterIntensity` with no scalar, so it applies **0.0**.

Likewise:

```text
Velocity -> programmerAttribute("Intensity")
```

can write 0 instead of the transformed velocity.

### Required fix

The scheduled payload token must preserve the evaluated action context, not only the action enum.

Introduce a payload record similar to:

```swift
struct AuroraScheduledActionPayload: Sendable {
    let action: AuroraAction
    let controlValue: Double?
    let latencyID: UUID
    let ingressHostTime: HostTime
    let mappingID: UUID?
    let targetFixtureIDs: [UUID]? // see P0-7
}
```

The token registry resolves this payload at fire time.

### Mandatory tests

- Quantized `masterIntensity` 0.75 fires as 0.75.
- Quantized programmer attribute preserves transformed velocity.
- Quantized CC at 0.0, 0.5, 1.0 preserves exact scalar.
- Latency correlation survives schedule -> fire.

---

## P0-7 — Quantized actions use fire-time selection, not event-time target context

### Evidence

At AME evaluation time, `ControlActionRouter` has `selection` / `orderedSelection`.

For immediate actions these are passed directly to `applyLive`.

For quantized actions, only the action enum is tokenized. At fire time, `handleScheduledFire` re-reads the **current** selection from router state.

### Impact

Example:

1. Snare hit schedules a next-beat programmer intensity action intended for fixtures A+B.
2. User changes programmer selection to fixtures C+D before the boundary.
3. Scheduled action fires against C+D.

This makes a delayed action semantically mutate after it was accepted.

### Required fix

Define and lock quantized target semantics.

Recommended: AME evaluation snapshots the target context needed by the action. A scheduled command should mean “execute the decision that was made at ingress,” not “reinterpret it against unrelated UI state later.”

Store ordered fixture targets in the scheduled payload for selection-relative actions.

If a particular action is intentionally fire-time-contextual, make that explicit per action type rather than accidental.

### Mandatory tests

- Schedule programmer action on A+B; change selection to C+D; fire -> A+B affected.
- Cue/absolute-ID actions remain unaffected by selection changes.

---

## P0-8 — Many first-class AuroraActions remain intentionally non-executable by AME

### Evidence

`AuroraAction` includes first-class semantic actions such as:

- selectSong
- enterSection
- nextSection / previousSection
- firePreset / firePalette / fireLook
- runBehavior
- advanceSequence / resetSequence / fireSequenceStep
- tapTempo
- setTransportStart / Stop / Continue
- setTempoBPM
- triggerEffect / setEffectRate / setEffectDepth
- compound

But `AMELiveActionSupport.isPhaseDLiveSupported` still whitelists only the legacy `ShowAction`-bridgeable subset. Unsupported actions are emitted with `shouldExecute = false`.

The Phase D checkpoint explicitly called a generalized executor a deferred non-goal, but the repository now labels the overall AME/Musical Engine track complete.

### Impact

The model and validator can accept configurations that look valid and persist correctly but cannot execute in the live product.

This also undermines Phase H. A section lifecycle action such as `.setTempoBPM`, `.firePreset`, or `.enterSection` is silently ignored because `transitionAMEShowContext` only executes actions that convert through `asShowAction`.

### Required fix

Now that the A–I implementation is being considered complete, implement the generalized `AuroraAction` executor promised by the architecture.

Recommended ownership:

```text
AuroraActionExecutor (app/engine integration layer)
  - Lighting actions -> LightingEngine
  - Song/section actions -> ShowControlController / SongDirector / AME context
  - Musical actions -> MusicalEngine
  - Sequence-control actions -> AMERuntime where appropriate
  - Effect actions -> Effects engine
  - compound -> recursive ordered execution
```

Do not force everything through `ShowAction`.

`AMELiveActionSupport` should become capability/validation metadata driven by the real executor, not a historical “Phase D whitelist.”

### Safety

Compound execution must preserve recursive safety rules. A compound containing panic/blackout/etc. must not be delayed by quantization.

### Mandatory tests

Live execution tests for every `AuroraAction` case, including nested compound and section lifecycle actions.

---

## P0-9 — Actual song navigation is not wired to AME song/section context

### Evidence

`ShowControlController` defines:

```swift
func enterAMESection(songID: UUID?, sectionID: UUID?, sectionLabel: String? = nil)
```

but no production caller invokes it.

Normal song control still uses:

```swift
loadSong(...)
songNext(...)
songPrevious(...)
```

through `SongDirector`, without updating AME structural context.

### Impact

Section/song-scoped AME mappings can remain inactive because:

```swift
activeSongID == nil
activeSectionID == nil
```

Normal show navigation does not automatically:

- fire section exit/entry actions;
- release section-scoped held state;
- reset section/song sequences;
- update song tempo/meter provenance;
- activate section-local mappings.

Phase H currently provides a host API, not full product integration.

### Required fix

Define one authoritative song/section transition path and make all product navigation use it.

For example:

```text
loadSong / next song / previous song / select song
  -> resolve target first section (or explicit section)
  -> transitionAMEShowContext
  -> SongDirector / cue playback update
```

Likewise section navigation must route through `transitionAMEShowContext`.

Avoid two parallel concepts of “current song/section.”

### Mandatory tests

- Normal UI song load updates AME activeSongID.
- Next/previous song transitions fire lifecycle in deterministic order.
- Normal section navigation updates activeSectionID and reset policies.
- Section scoped mapping works without calling a special test-only host API.

---

## P0-10 — Section mapping sets and `localMappingIDs` are persisted/validated but ignored by runtime

### Evidence

`SongSection` persists:

```swift
mappingSetIDs: [UUID]
localMappingIDs: [UUID]
```

`AMEProjectDocument` persists `mappingSets`.

The validator checks references.

But `AMERuntime.process()` activates mappings only by each mapping's own:

```swift
mapping.scope
```

There is no runtime use of:

- `document.mappingSets`
- `section.mappingSetIDs`
- `section.localMappingIDs`

A repository-wide search finds mapping sets only in models and validation.

### Impact

The approved UX/spec concept:

```text
INTRO
  MIDI Mapping Set: MFN Intro
CHORUS
  MIDI Mapping Set: MFN Chorus
```

is currently data with no runtime meaning.

### Required fix

Implement effective mapping activation for the active song/section.

At minimum:

1. Project-scoped mappings are candidates globally.
2. Song-scoped mappings apply to active song.
3. Section-scoped mappings apply to active section.
4. Active section's `mappingSetIDs` activate the referenced set members.
5. Active section's `localMappingIDs` activate those explicit mappings.
6. Inheritance/override/disable resolution operates on the resulting effective mapping set deterministically.

Define whether membership is additive or acts as an enable mask. Document it and test it.

### Mandatory tests

- Mapping in inactive section's mapping set does not fire.
- Enter section activates its mapping set.
- `localMappingIDs` work.
- Missing/disabled mapping set diagnostics are clear.
- Inheritance across project/song/section + mapping-set activation is deterministic.

---

## P0-11 — MIDI source disconnect can strand held AME state

### Evidence

`MIDIInputManager.reconcileSources()` knows exactly which source was removed, but only exposes an inventory **count** callback.

`InputController` updates health on inventory changes but does not notify AMERuntime that a source disappeared.

Held identities include source identity, but there is no source-disconnect release path in production wiring.

### Impact

If a device sends Note On to activate a while-held blinder/fogger/override and is unplugged before Note Off, the held state may remain active indefinitely until some unrelated global release path occurs.

This is explicitly one of the Phase I reliability cases the approved plan required.

### Required fix

Expose source lifecycle events from MIDIInputManager:

```swift
sourceConnected(id)
sourceDisconnected(id)
```

Add AMERuntime API to release held/toggle state owned by one source, returning executable deactivation emissions for live state.

On disconnect:

```text
MIDIInputManager
 -> ControlActionRouter / AMERuntime.releaseHeld(sourceID:)
 -> execute snapshotted release actions immediately
```

Do not release holds belonging to unrelated devices.

### Mandatory tests

- Device A hold + Device B hold; disconnect A -> only A unwinds.
- Disconnect after dry-run does not emit live OFF.
- Disconnect while armed emits live release exactly once.
- Reconnect starts with clean physical-held ownership.

---

# P1 — Required before declaring implementation complete

## P1-1 — Phase F is a read-only diagnostics shell, not the specified AME editor

### Evidence

The checkpoint itself says:

> `Status: COMPLETE (AFK shell)`

and explicitly lists as non-goals:

- full visual mapping editor / drag-wire graph;
- Learn arming UX inside AME window;
- inspector-driven mapping creation/edit commands.

`AMEEnginePanel` confirms this. It can:

- browse triggers/mappings/sequences;
- select a mapping;
- view read-only details;
- change performance mode;
- view diagnostics.

It cannot actually create/edit the AME graph.

### Original Phase F contract

The approved spec says Phase F is:

> Window, sidebar/context browser, **visual mapping editor, Inspector, Learn, live monitor.**

### Required fix

Complete Phase F as an actual editor.

Required minimum UX:

- Create/delete/duplicate trigger.
- Create/delete/duplicate mapping.
- Create/delete/duplicate sequence.
- Edit mapping scope, trigger/group, behavior, transform, actions, release actions, sequence, timing requirement, quantization boundary/failure policy, debounce/burst, inheritance/disable relation.
- Edit sequence steps/actions/weights/mode/reset/scope/trigger policy.
- Edit source binding.
- Visual WHEN -> CONDITIONS -> DO representation.
- Prominent AME MIDI Learn flow.
- Live highlight of matched trigger, mapping, sequence step.
- Validation issue navigation to affected item.
- Undo/redo through Aurora's command/document session architecture.

Do not mutate the project object directly from SwiftUI. Add proper `AuroraCore` commands for AME edits.

---

## P1-2 — MIDI Learn still creates legacy MIDIMapping, not AME triggers/mappings

### Evidence

`InputController.handleMIDILearnOnly` uses existing `MIDILearnSession` and then:

```swift
AddMIDIMappingCommand(mapping: learned.mapping)
```

This populates the legacy MIDI system.

There is no AME-specific Learn workflow.

### Impact

The flagship AME onboarding flow from the feature spec is absent. Users cannot click Learn in the AME window, hit a drum/pedal, and have Aurora create an AME trigger/mapping.

### Required fix

Add `AMELearnSession` (or extend learn architecture cleanly) that captures a normalized channel event and creates/updates:

- `MIDISourceBinding` when appropriate;
- `AMETriggerDefinition`;
- optionally `AMEMapping` seeded with the learned trigger;
- friendly drum-note naming where possible.

Keep legacy Learn available for legacy mappings during migration.

Clock ingress must remain active during learning (see P0-1).

---

## P1-3 — Scheduled payload loses end-to-end latency/provenance metadata

### Evidence

`AMEActionEmission` has:

- `latencyID`
- `mappingID`
- `ingressHostTime`
- `controlValue`

but `AuroraActionTokenRecord` stores only action + safety.

At quantized fire, diagnostics cannot correlate the final execution back to ingress latency ID or calculate actual scheduling latency.

### Required fix

Fold these fields into the scheduled payload record proposed under P0-6.

Add diagnostics for:

```text
ingress host time
AME decision time
scheduled target
actual fire host time
error/jitter
latency ID
mapping ID
```

This becomes extremely valuable during hardware Phase I testing.

---

## P1-4 — Phase H lifecycle silently ignores unsupported section actions

Even before generalized executor completion, `transitionAMEShowContext` currently does:

```swift
if let show = action.asShowAction { ... }
```

with no explicit diagnostic in the `else` branch.

That regresses the Phase D rule that unsupported actions must never look like silent success.

### Required fix

Generalized executor solves this. Until then, lifecycle execution must emit an explicit unsupported-action diagnostic for every action it cannot execute.

---

## P1-5 — Musical Engine is always started during ShowControlController initialization

`ShowControlController.init` calls:

```swift
musicalEngine.startTransport()
```

before project timing policy/source configuration is applied.

This makes transport-running a product bootstrap side effect rather than a deliberate timing state.

### Required fix

After P0-2, configure MusicalEngine from project first and define intended startup transport semantics:

- internal-only: likely start internal transport if Aurora's product model expects always-running musical time;
- strict external: do not pretend transport is running until Start/Continue or explicit product policy says so;
- preferred fallback: explicitly define whether internal fallback starts automatically.

Lock this in tests.

---

## P1-6 — Duplicate tick producers must be removed after scheduler driver exists

`AMEEngineWindowRoot` currently calls `tickMusicalEngine()` solely to refresh UI. Once a dedicated runtime driver is added, the AME window must never drive the musical clock/scheduler.

Use state observation or presentation polling only.

Opening/closing a window must have zero effect on timing behavior.

---

## P1-7 — Phase I checkpoint contradicts the approved reliability plan

### Evidence

Current Phase I checkpoint says:

> `COMPLETE (deterministic suite smoke)`

and explicitly makes these non-goals:

- Real CoreMIDI device matrix / soak farms
- Multi-hour stability harness

But the approved Phase I plan explicitly requires real-device testing for:

### MIDI Clock

- stable hardware clock
- RTP-MIDI clock
- clock + dense notes
- dropout
- reconnect
- Start/Stop/Continue
- SPP + Continue
- tempo changes

### Drum performance

- snare rolls
- simultaneous kick/snare
- tom fills
- choke/note-off where available
- velocity extremes
- repeated Note On without Note Off
- Note On velocity 0
- multi-device same note/channel collision

### Long run

- representative rehearsal/show duration
- bounded diagnostics
- no increasing latency
- no sequence drift
- no stuck held state
- no queue growth

### Required fix

Do not mark Phase I accepted until this matrix is actually performed on macOS with representative hardware and RTP-MIDI.

Create a human-readable smoke-test checklist + results document and record:

- device names/source IDs;
- timing source;
- BPM range;
- dropout/reconnect outcomes;
- scheduler jitter metrics;
- token/scheduler/diagnostic counts before/after long run;
- held-state cleanup results.

This is not optional for software whose entire purpose is live-show control.

---

## P1-8 — Cross-system tests are thinner than the approved acceptance matrix

Current `AMEPhaseFGHTests` mainly validates:

- bridge enum conversion;
- one `.go` scheduling flow;
- section plan ordering;
- one sequence reset;
- 16-hit deterministic sequence smoke;
- timing-loss `.cancel`.

Add true cross-system tests for:

- external MIDI clock + section-scoped drum sequence;
- holdUntilTimingAvailable end-to-end;
- quantized velocity/CC payload preservation;
- quantized action across tempo changes;
- transport stop with pending work for all three failure policies;
- source switch with queued AME work;
- song transition during held controls;
- section mapping-set activation;
- source disconnect while held;
- AME simulation parity with real normalized ingress.

---

# P2 — Hardening / quality fixes

## P2-1 — Remove stale “Phase D” capability naming after generalized executor lands

Names/comments such as:

```swift
AMELiveActionSupport.isPhaseDLiveSupported
"Unsupported in Phase D live executor"
```

are now misleading in a supposedly final A–I implementation.

Replace with durable capability language.

---

## P2-2 — Compiler warnings in touched AME/Musical code

Linux compilation reached the platform boundaries and surfaced warnings including:

- `MusicalEngine.receiveClockPulse`: `fireNow` / `canceled` declared `var` but never mutated.
- `AMEConfigurationValidator`: unused pattern values in scope ancestry matching.

Clean these during closeout.

---

## P2-3 — Make source identity a first-class shared concept

Today source IDs are strings interpreted separately by:

- CoreMIDI input;
- AME source bindings;
- MIDI Clock adapter;
- Musical Engine source selection.

The `uid:` mismatch already demonstrates the risk.

Prefer one shared typed/canonical identity representation or, at minimum, one shared formatter/resolver API.

---

## P2-4 — Add observability for token/scheduler boundedness

Expose diagnostics counters (read-only):

- action token registry count;
- pending scheduler entries;
- held scheduler entries;
- AME held entries;
- AME toggle entries;
- diagnostics ring count.

Phase I long-run acceptance should prove all of these remain bounded.

---

# Important implementation notes

## Preserve these architecture wins

Do **not** redesign the following. They are good and should survive remediation:

- `AuroraMusical` remains independent of CoreMIDI/AuroraEngine.
- Musical timing and show context remain separate.
- Monotonic `HostTime` remains canonical for live timing.
- System Real-Time interleaving and SPP remain correctly parsed.
- External clock authority is not granted on one stray F8.
- Phase C estimator reset/reacquisition fixes remain.
- AME live/dry-run ephemeral domains remain isolated.
- Held release occurs before fire-path scope/debounce/timing checks.
- Release actions are snapshotted at acquisition.
- Sequence per-scope deterministic RNG streams remain.
- Sequence trigger policies remain behaviorally distinct.
- Safety actions bypass quantization.
- Musical scheduler remains encapsulated behind `MusicalEngine.schedule()`.
- `AuroraAction` structured recursive Codable remains.
- `ame.json` remains a separate package member.

---

# Recommended remediation order

## R1 — Make live timing real

1. Wire `MIDIInputManager.setIngressHandler` -> `MIDIClockTimingAdapter` -> `MusicalEngine`.
2. Apply persisted timing policy/source/freewheel settings.
3. Canonicalize source identity (`uid:` bug).
4. Add source connect/disconnect events.
5. Remove timing dependence on UI polling; add dedicated scheduling driver.

**Gate:** hardware F8 reaches live engine and internal quantized firing has measured low jitter.

## R2 — Fix Phase G semantic payloads

1. Fix `holdUntilTimingAvailable` so it reaches scheduler held queue.
2. Expand scheduled token payload to include control value, target selection, latency ID, ingress HostTime, mapping ID.
3. Ensure cancel/reject/fire consumes token exactly once.
4. Add end-to-end quantization tests.

**Gate:** all three failure policies + value-preserving quantization green.

## R3 — Finish generalized action execution

1. Add `AuroraActionExecutor` integration layer.
2. Route song/section, musical, effect, lighting, and compound actions correctly.
3. Replace historical Phase-D whitelist.
4. Ensure lifecycle actions use the same executor.

**Gate:** every AuroraAction case has a live integration test or is explicitly marked unsupported by product design.

## R4 — Finish Phase H integration

1. Route normal SongDirector navigation through authoritative AME context transitions.
2. Implement mapping-set/local-mapping activation.
3. Verify lifecycle ordering and sequence resets in actual product navigation.

**Gate:** no special test-only `enterAMESection` call is required for section-scoped mappings to function.

## R5 — Finish Phase F product UX

1. Add AME edit commands.
2. Implement trigger/mapping/sequence editors.
3. Implement AME MIDI Learn.
4. Live-highlight diagnostics/sequence state.
5. Provide validation navigation.

**Gate:** a user can create the spec's snare-driven sequence example entirely through the AME window without editing JSON or legacy MIDI mappings.

## R6 — Real Phase I acceptance

Run the hardware + RTP-MIDI + long-duration matrix from the approved plan.

**Gate:** documented results, bounded queues/state, no stuck controls, no drift, no increasing latency.

---

# Mandatory final acceptance scenario

This should be executable through the real UI and real MIDI plumbing, not a unit-test shortcut:

1. Open Aurora project.
2. Open **MIDI Engine**.
3. Click **Learn MIDI**.
4. Hit snare on a connected drum module.
5. Aurora creates a friendly Snare trigger/mapping.
6. Create a 4-step sequence of existing Aurora cues/presets.
7. Scope it to Song X / Intro section using section mapping association.
8. Set sequence reset = on section entry.
9. Set mapping quantization = next eighth; failure policy = hold until timing available.
10. Select external MIDI Clock source.
11. Send Start + MIDI Clock.
12. Enter Intro using normal Aurora song/section navigation.
13. Sequence resets.
14. Each snare hit advances exactly one step and fires on intended eighth boundary within jitter budget.
15. Change velocity/CC mapping and verify quantized scalar survives scheduling.
16. Stop clock: held policy waits, cancel policy cancels, immediate policy fires immediately.
17. Restore clock: held action fires once at resolved boundary.
18. Unplug drum device while a held mapping is active: release action unwinds immediately.
19. Reconnect device and continue without stale held/sequence/source state.
20. Leave Intro: exit lifecycle fires, section-held state unwinds, next section mapping set becomes effective.
21. AME live monitor shows ingress -> mapping -> sequence -> schedule -> actual fire correlation using one latency ID.

If this scenario cannot be completed in the shipping app, the AME/Musical Engine implementation is not yet complete.

---

# Final re-acceptance checklist

## Live wiring

- [ ] CoreMIDI full ingress connected to MIDIClockTimingAdapter in production
- [ ] MIDI timing continues while Learn is armed
- [ ] Project timing policy is applied
- [ ] Selected external source binding resolves to live canonical source ID
- [ ] Configured freewheel is applied
- [ ] `uid:` source identity is consistent everywhere

## Scheduler / quantization

- [ ] Musical scheduler no longer depends on 250 ms UI/status polling
- [ ] Measured internal scheduling jitter meets documented target
- [ ] `holdUntilTimingAvailable` actually holds
- [ ] `.cancel` cancels
- [ ] `.executeImmediately` fires immediately
- [ ] Quantized scalar/control value preserved
- [ ] Quantized selection/target context semantics locked and tested
- [ ] Token lifecycle bounded and leak-free
- [ ] End-to-end latency/provenance preserved

## AME actions

- [ ] Generalized AuroraAction executor exists
- [ ] Every intended AuroraAction case executable
- [ ] Section lifecycle uses generalized executor
- [ ] Unsupported action never silently disappears
- [ ] Compound actions preserve order and safety

## Song / section

- [ ] Normal song load updates AME context
- [ ] Normal section navigation updates AME context
- [ ] Section mapping sets affect runtime
- [ ] `localMappingIDs` affect runtime
- [ ] Lifecycle exit/context/reset/enter order preserved
- [ ] Song tempo/meter provenance preserved

## UX

- [ ] AME window can create/edit/delete triggers
- [ ] AME window can create/edit/delete mappings
- [ ] AME window can create/edit/delete sequences/steps
- [ ] AME-specific MIDI Learn exists
- [ ] Visual WHEN -> CONDITIONS -> DO representation exists
- [ ] Live matched mapping/sequence step highlight exists
- [ ] Validation issues navigate to relevant object
- [ ] Changes participate in document undo/redo/save

## Reliability

- [ ] Source-disconnect releases held state per source
- [ ] Hardware MIDI Clock matrix completed
- [ ] RTP-MIDI clock matrix completed
- [ ] Dense notes + clock completed
- [ ] Start/Stop/Continue + SPP completed
- [ ] Dropout/reconnect completed
- [ ] Drum performance matrix completed
- [ ] Representative show-duration soak completed
- [ ] Diagnostic/token/scheduler buffers remain bounded
- [ ] No increasing latency
- [ ] No sequence drift
- [ ] No stuck held state
- [ ] Full macOS test suite green

---

# Audit environment note

A Linux `swift test` attempt was able to compile substantial portions of `AuroraModel` / `AuroraMusical` and exposed only minor warnings in those touched files before the build reached expected platform boundaries. The complete suite cannot run in this environment because the project imports macOS-only `CoreMIDI` and `Network` modules.

The repository's Phase I checkpoint reports **720 tests / 0 failures**, but that checkpoint explicitly covers deterministic/no-hardware smoke only. The fixes above require a fresh full macOS suite plus the real hardware acceptance matrix.

---

# Bottom line for Grok

This is **not a request to redesign AME or Musical Engine**. The underlying architecture is good.

The job is to close the remaining seams where otherwise-correct subsystems are not actually connected to one another, finish the product surfaces that were narrowed to “AFK shell” scope, and perform the reliability gate that was deferred.

The highest-priority failures are:

```text
1. Live MIDI Clock not wired into app
2. Persisted timing policy/source/freewheel not applied
3. Stable source-binding uid format mismatch
4. holdUntilTimingAvailable drops actions
5. Quantized scheduler driven by 250 ms UI timer
6. Quantized control value/target context lost
7. Generalized AuroraActions still not executable
8. Normal song navigation does not update AME context
9. Mapping sets/local section mappings have no runtime effect
10. Source disconnect can strand held state
11. Phase F editor/Learn is not implemented
12. Phase I hardware/soak acceptance was skipped
```

Fix those, then rerun the final acceptance scenario above before stamping the AME + Musical Engine track complete.
