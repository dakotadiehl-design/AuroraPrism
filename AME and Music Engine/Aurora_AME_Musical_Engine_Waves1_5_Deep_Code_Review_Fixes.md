# Aurora AME + Musical Engine — Waves 1–5 Deep Code Review Fixes

**Review target:** `Aurora_AMEMusicEngine_CodeReviewPass1.zip`  
**Review scope:** Full remediation Waves 1–5 as one production path  
**Disposition:** **Do not begin/claim Wave 6 hardware acceptance yet.** The remediation is substantially improved, but several cross-wave integration defects remain, including live-action execution and Musical Engine provenance issues that can produce incorrect or silent behavior.

---

## 1. Executive disposition

The Waves 1–5 pass contains real, worthwhile corrections. In particular, the following audit findings are now materially addressed in code:

- CoreMIDI full ingress is delivered separately from channel-voice performance/Learn traffic.
- `MIDIClockTimingAdapter` is attached in the shipping composition path.
- Canonical `uid:<CoreMIDI UniqueID>` identity exists and is used by the normal UID path.
- Project AME timing policy, selected source, freewheel configuration, tempo and meter are applied to `MusicalEngine` on project load/update.
- Musical scheduler harvesting is no longer performed by the 250 ms UI/status timer.
- `holdUntilTimingAvailable` now emits an action that can reach the Musical scheduler instead of being discarded in AME.
- Scheduled payloads preserve control value, selection snapshot, latency ID, mapping ID and ingress host time.
- Normal song navigation now calls an AME context transition path.
- Additive section mapping activation exists for scope + `localMappingIDs` + mapping-set members.
- CoreMIDI source disconnect events are surfaced to the AME host.
- A command-backed first AME UI/Learn path now exists.

However, the combined system still has **P0 live-path gaps**. Most importantly:

1. Immediate AME actions still bypass the generalized `AuroraActionExecutor` and fall back to legacy `ShowAction` conversion.
2. The generalized executor declares song/section actions supported, but its transition hook is never wired, so some actions report success while doing nothing.
3. Song transitions overwrite the Musical Engine's project-default tempo/meter baseline with song metadata, breaking later fallback semantics.
4. Source disconnect releases held gates but explicitly does **not** unwind toggles from that source.
5. Wave 5 is still mostly a browser/add shell rather than the command-backed editable AME workspace promised by the remediation plan.

These should be corrected before hardware Wave 6. Hardware testing should validate the intended product, not spend time rediscovering software-path defects.

---

# 2. P0 — Immediate AME actions still use the legacy `ShowAction` path

## Evidence

`Sources/Aurora/ControlActionRouter.swift`, `applyAMEEmissions(...)`:

```swift
// quantized path uses MusicalEngine...
...
guard let showAction = emission.action.asShowAction else {
    notify(.stop, "AME_UNSUPPORTED ...")
    continue
}
applyLive(showAction, ...)
```

By contrast, `handleScheduledFire(...)` creates an `AuroraActionExecutor` and executes the generalized action.

This means the semantics depend on whether the same action is immediate or quantized.

Examples:

```text
AME mapping → .setTempoBPM(110)
  immediate → legacy bridge cannot represent it → AME_UNSUPPORTED
  quantized  → AuroraActionExecutor → MusicalEngine.setTempoBPM(110)
```

The same split applies to song/section actions, sequence-control actions, and other generalized `AuroraAction` cases.

## Why this is a blocker

Wave 3's purpose was to eliminate the old "rich action translated backward into ShowAction" bottleneck. The shipping immediate path still contains exactly that bottleneck.

It also creates a particularly dangerous UX contract: changing only a mapping's quantize selector can change an action from "unsupported" to "works" without changing the action itself.

## Required fix

Create **one host execution path** for both immediate and scheduled AME actions.

Recommended shape:

```swift
private func executeAuroraAction(
    _ action: AuroraAction,
    controlValue: Double,
    orderedFixtureIDs: [UUID],
    selectedFixtureIDs: Set<UUID>,
    latencyID: UUID?,
    observers: [...]
) -> AuroraActionExecutionOutcome
```

Both:

- `applyAMEEmissions(...)` immediate branch
- `handleScheduledFire(...)`

must call that same function/executor.

`ShowAction` should remain only as compatibility/notification representation for actions that naturally have one. It must not be the execution gate.

### Mandatory tests

Add integration tests proving that each action behaves identically except for fire time when immediate vs quantized:

- `.setTempoBPM`
- `.tapTempo` (where deterministic test clock permits)
- `.setTransportStart` / stop / continue
- `.selectSong`
- `.enterSection`
- `.programmerAttribute`
- `.masterIntensity`
- `.resetSequence`
- nested `.compound`

---

# 3. P0 — `AuroraActionExecutor` overstates support; song/section hook is never wired

## Evidence

`Sources/Aurora/AuroraActionExecutor.swift` declares these supported:

```swift
.selectSong, .enterSection, .nextSection, .previousSection
```

Execution does:

```swift
case .selectSong(let id):
    sectionTransition?(id, ..., nil)

case .enterSection(let id):
    sectionTransition?(songID, id, label)
```

but there is no assignment to `sectionTransition` anywhere in `Sources` or `Tests`.

Therefore optional chaining silently does nothing while the method subsequently returns `.executed`.

For next/previous section:

```swift
sectionTransition?(nil, nil, nil)
return .partial
```

Even if the hook were wired, `(nil,nil,nil)` is not a meaningful "next section" request and can clear AME context if interpreted literally.

## Impact

An AME rule can be configured to select a song or enter a section, monitor/diagnostics can make it look accepted, but the actual product navigation does not happen.

This is worse than explicit unsupported behavior because it is a **false positive execution result**.

## Required architecture

Do not give the executor a single ambiguous `sectionTransition(UUID?,UUID?,String?)` callback.

Give it explicit host navigation capabilities, for example:

```swift
public struct AuroraActionHostCallbacks: @unchecked Sendable {
    var selectSong: (UUID) -> AuroraActionExecutionOutcome
    var enterSection: (UUID) -> AuroraActionExecutionOutcome
    var nextSection: () -> AuroraActionExecutionOutcome
    var previousSection: () -> AuroraActionExecutionOutcome
}
```

The callbacks must route through the same authoritative product navigation path used by the UI so that:

- `SongDirector` cursor changes,
- the lighting/cue song state changes,
- AME context transitions,
- section exit/reset/enter actions,
- Musical show context,

all stay synchronized.

### Important threading constraint

AME MIDI can originate off MainActor. If the authoritative navigation API is MainActor-bound, bridge deliberately and safely. Do not silently execute only the AME context portion on a background queue while leaving `SongDirector` behind.

### Required outcome contract

`AuroraActionExecutor.isSupported(action)` must mean **the current host can really perform the action**.

Prefer instance capability:

```swift
executor.supportLevel(for: action)
```

rather than a static list that cannot know whether required host hooks are installed.

### Mandatory tests

- `.selectSong(id)` changes actual SongDirector/current song **and** AME context.
- `.enterSection(id)` changes active section and applies exit/reset/enter lifecycle exactly once.
- `.nextSection` and `.previousSection` navigate actual neighboring sections.
- Missing callback returns `.unsupported`, never `.executed`.
- Immediate and quantized versions converge on identical final navigation state.

---

# 4. P0 — Song transitions corrupt Musical Engine project-default provenance

## Evidence

`Sources/Aurora/Controllers/ShowControlController.swift::applyMusicalEngineFromProject(...)` correctly establishes project defaults from:

```swift
project.ame.musicalSettings.defaultTempoBPM
project.ame.musicalSettings.defaultMeter
```

But `Sources/Aurora/ControlActionRouter.swift::transitionAMEShowContext(...)` later does this whenever the song changes:

```swift
let defaults = AMESectionTransition.musicalDefaults(forSongID: songID, project: proj)
let bpm = defaults.tempoBPM ?? 120
if let meter = defaults.meter ... {
    me.setProjectDefaults(tempoBPM: bpm, meter: musical)
} else {
    me.setProjectDefaults(tempoBPM: bpm, meter: .fourFour)
}
me.setShowContext(
    ShowMusicalContext(
        ...
        songDefaultTempoBPM: defaults.tempoBPM,
        songDefaultMeter: ...
    )
)
```

This overwrites the true project baseline with song metadata before calling the Musical Engine's own song-metadata layering API.

`MusicalEngine.setShowContext(...)` already contains the correct logic:

- song metadata becomes the internal baseline while in that song;
- when a later song omits tempo/meter, it falls back to stored project defaults.

The host currently destroys those stored project defaults.

## Failure example

```text
Project default: 96 BPM
Song A default: 110 BPM
Song B default: nil

Load project -> project baseline 96
Enter Song A -> host calls setProjectDefaults(110) [wrong]
Enter Song B -> host calls setProjectDefaults(120) [wrong]
Result: 120 BPM rather than project 96 BPM
```

Meter has the same issue, with hard-coded `.fourFour` replacing the configured project meter.

## Required fix

In `transitionAMEShowContext(...)`:

**Remove song-derived calls to `setProjectDefaults`.**

Only call:

```swift
me.setShowContext(
    ShowMusicalContext(
        activeSongID: songID,
        activeSectionID: sectionID,
        songDefaultTempoBPM: defaults.tempoBPM,
        songDefaultMeter: ...
    )
)
```

`setProjectDefaults(...)` should be driven only when project-level settings genuinely change/load.

If project settings change while a song is active, update project defaults, then reapply/retain show context so provenance remains correct.

### Mandatory tests

1. Project 96, Song A 110, Song B nil → A=110, B=96.
2. Project 7/8 `[2,2,3]`, Song A 4/4, Song B nil → B restores project 7/8 grouping.
3. External MIDI at 120 → dropout/freewheel → fallback while Song A active uses Song A baseline.
4. Then switch to Song B with no override → fallback uses project baseline, not 120/hard-coded 120.
5. Reset song/no active song restores project baseline.

---

# 5. P0 — Source disconnect does not unwind source-owned toggle state

## Evidence

`Sources/AuroraEngine/AME/AMERuntime.swift::releaseHeld(forSourceID:)` correctly releases held identities whose `identity.sourceID` matches the unplugged source.

But it explicitly says:

```swift
// Toggles are mapping-scoped (not source-scoped); leave them unless we track source later.
```

The Wave 4 remediation requirement was to prevent a disconnected device from stranding **held/toggle live state**.

`AMEHeldStateTable.ToggleTable.OnRecord` currently contains only:

```swift
releaseActions
wasLiveExecuted
```

and cannot identify which physical source turned the toggle on.

## Why this matters

A MIDI button can toggle a blinder/override/freeze-like state ON and then be unplugged. Aurora's physical source lifecycle arrives correctly, but the toggle state remains ON because it cannot be attributed to the disconnected device.

The software has solved the disconnect problem for while-held controls but not toggle controls.

## Required fix

Snapshot source provenance into toggle ON records.

Recommended record:

```swift
struct OnRecord {
    var sourceID: String
    var channel: UInt8
    var data1: UInt8?
    var releaseActions: [AuroraAction]
    var wasLiveExecuted: Bool
    var activationLatencyID: UUID?
}
```

Add:

```swift
ToggleTable.release(forSourceID:) -> [(UUID, OnRecord)]
```

Then `AMERuntime.releaseHeld(forSourceID:)` should return one release batch containing:

- held entries from that source,
- toggle OFF release actions from that source,
- no state owned by other devices.

### Mandatory tests

- A toggles blind ON; unplug A → blindOff emitted once.
- A and B have independent mappings toggled ON; unplug A → only A unwinds.
- dry-run toggle never emits live OFF on disconnect.
- reconnect starts clean.
- repeated disconnect notification is idempotent.

---

# 6. P1 — Live support classification is not truthful

## Evidence

`Sources/AuroraEngine/AME/AMEDiagnostics.swift::AMELiveActionSupport.isLiveSupported` returns `true` for virtually every action, including the default branch:

```swift
default:
    // Preset/palette/look/behavior/effect may be partial — still allow emission for diagnostics.
    return true
```

Meanwhile `AuroraActionExecutor` returns `.partial` for:

- `.advanceSequence`
- `.fireSequenceStep`
- effects
- presets/palettes/looks/behaviors
- next/previous section

and immediate `applyAMEEmissions` currently rejects many of them through `asShowAction` anyway.

Thus `isLiveSupported` currently means neither "the host executes this" nor "the runtime should reject it."

## Required fix

Collapse capability ownership into the actual executor/host.

Do not maintain two divergent support tables:

```text
AMELiveActionSupport
AuroraActionExecutor.isSupported
```

Suggested enum:

```swift
enum AuroraActionSupportLevel {
    case supported
    case supportedWithLimitations(String)
    case unsupported(String)
}
```

AME can always produce semantic emissions. The host decides support and emits a truthful diagnostic.

At minimum, an action returning `.partial` must not be advertised as fully supported in the UI/validator.

---

# 7. P1 — Wave 5 editor is not yet the editor described by the approved remediation plan

## Current implementation

`AMEEnginePanel` / `AMEEngineWindowRoot` currently provides:

- list triggers/mappings/sequences,
- add trigger,
- add mapping,
- add sequence,
- delete mapping,
- select mapping,
- read-only mapping detail rows,
- AME Learn producing a binding+trigger+mapping,
- validation display,
- monitor display.

This is useful progress, but it does **not** yet provide the Wave 5 minimum that was approved.

Missing product operations include at least:

- edit mapping name/enabled/behavior/priority;
- choose trigger / trigger group;
- edit source binding;
- edit scope;
- edit timing requirement;
- edit quantization boundary/failure policy;
- edit transform/dead-zone/threshold;
- edit actions and release actions;
- edit debounce/burst;
- edit override/disable parent semantics;
- create/edit/delete/duplicate trigger;
- create/edit/delete/duplicate mapping;
- create/edit/delete/duplicate sequence;
- sequence step CRUD and reordering;
- sequence mode/reset/state-scope/trigger-policy editing;
- source-binding editor;
- validation issue → select affected object;
- WHEN → CONDITIONS → DO visual summary/editor;
- live highlight of last matched trigger/mapping/sequence step;
- duplicate commands requested by the plan.

The checkpoint currently calls Waves 1–5 complete while listing the full visual editor as remaining. A giant node graph may be legitimately deferred, but the **command-backed property editor** was not optional in the remediation plan.

## Required fix

Complete the inspector-driven editor before Wave 6 hardware acceptance.

A full node graph is not required. A professional inspector is sufficient if the user can construct and modify the complete AME configuration without JSON or test APIs.

### Strong recommendation

Use small document commands for every mutation rather than passing mutable bindings directly into `ShowProject`.

Add update/duplicate/reorder commands as needed. Existing Upsert commands can cover many edits, but the UI must actually invoke them.

### Acceptance scenario for Wave 5

Starting from a blank project, through the AME window only:

1. Learn a snare note.
2. Rename the trigger.
3. Bind it to the desired source.
4. Create a mapping scoped to a song section.
5. Set behavior and velocity transform.
6. Choose next-eighth quantization + hold failure policy.
7. Create a four-step sequence.
8. Populate each step with different actions.
9. Set sequence trigger/reset/state-scope policy.
10. Attach it to the mapping.
11. Add explicit release action for a held mapping.
12. Put mapping into a mapping set / section membership.
13. Undo/redo edits.
14. See validation errors navigate to the affected object.
15. Arm and see matched object highlighted in monitor/editor.

If any of those require editing `ame.json`, Wave 5 is not closed.

---

# 8. P1 — CoreMIDI name fallback cannot work reliably with the current live source-ID shape

## Evidence

Production `MIDIInputManager.stableSourceID` emits:

```text
uid:<uniqueID>
```

or, if no CoreMIDI UID:

```text
ep:<endpointRef>
```

`applyMusicalEngineFromProject(...)` resolves a selected external source binding as:

```swift
if let uid { return "uid:<uid>" }
if endpointNameHint { return endpointNameHint }
return displayName
```

But `MIDIClockTimingAdapter` performs exact string filtering:

```swift
if let preferred, event.sourceID != preferred { continue }
```

So a binding without a stored UID but with a name hint such as `"Nord Drum 3P"` will never match live ingress ID `"ep:1234"`.

`MIDISourceIdentity.matches(...)` has the same conceptual issue for name fallback because the matcher receives only the canonical live ID string, not the endpoint's current name metadata.

## Required fix

Resolve persisted bindings against current `MIDIDeviceInfo` inventory at apply time.

The remediation plan originally described:

```text
applyMusicalEngineFromProject(project, availableSources)
```

Implement that missing resolution layer.

Suggested rules:

1. UID match first.
2. If no UID persisted, match current inventory by endpoint name/manufacturer/model hints.
3. Once resolved, use the inventory's canonical runtime `id` (`uid:` or `ep:`) for adapter/engine admission.
4. If zero or multiple candidates, mark unresolved/ambiguous rather than silently comparing display names to canonical IDs.

AME trigger binding should use the same resolver or retain enough source metadata at ingress for deterministic matching.

### Tests

- UID match.
- no UID + unique endpoint-name match resolves to `ep:*` live ID.
- duplicate names produce ambiguity, not arbitrary binding.
- endpoint reconnect with stable UID resolves again.

---

# 9. P1 — `MusicalEngineRuntimeDriver` adaptive cadence implementation does not actually adapt

## Evidence

The driver starts with:

```swift
armTimer(interval: activeIntervalSeconds)
```

After each tick it computes:

```swift
let desired = pending > 0 ? activeIntervalSeconds : idleIntervalSeconds
```

but only calls `armTimer(interval: desired)` when:

```swift
if current == nil
```

While running, `current` is the existing timer, so cadence never changes. The timer remains at the 4 ms active interval continuously.

Also:

```swift
let ns = UInt64(interval * 1_000_000_000)
...
_ = ns
```

is dead code.

## Impact

This is not a timing correctness blocker because 4 ms is the safer cadence, but it defeats the stated adaptive design and keeps a user-interactive dispatch timer waking ~250 times/sec even with no scheduled work.

## Required fix

Either:

### Option A — simplify deliberately
Keep a fixed 4 ms runtime driver and document the intentional CPU/power tradeoff for a live-show desktop app. Remove fake adaptation/dead code.

or

### Option B — implement actual adaptation
Track current interval class and re-arm only when changing active↔idle.

Do not re-create the DispatchSourceTimer every 4 ms.

Before hardware Wave 6, measure scheduler jitter and CPU impact. Reliability wins over clever timer economy.

---

# 10. P1 — Disconnect diagnostics use the wrong semantic diagnostic kind

`ControlActionRouter.handleMIDISourceDisconnected` records:

```swift
kind: .heldReleasedByDocumentChange
```

for a device disconnect.

Add a dedicated diagnostic kind such as:

```swift
.heldReleasedBySourceDisconnect
```

This matters when reviewing a live-show log after a stuck-control incident. "Document change" is materially different from "USB/RTP MIDI source vanished."

---

# 11. P1 — Section navigation is still first-section-biased

`ShowControlController.loadSong` and `syncAMEContextFromSongDirector` choose:

```swift
song.sections.sorted(by: { $0.order < $1.order }).first
```

The checkpoint itself notes "deeper SongDirector multi-section cursor" as remaining.

This means normal `songNext/songPrevious` synchronize AME to the first section, not necessarily a real section cursor. If sections are intended as runtime song structure rather than only metadata, this is insufficient for Wave 4's "authoritative context transitions" requirement.

## Required fix before final track acceptance

Define and use one authoritative `(songID, sectionID)` cursor in `SongDirector`/show control.

All paths must update it:

- load song,
- next/previous song,
- next/previous section,
- direct section selection,
- AME `.enterSection` / `.nextSection` / `.previousSection`,
- future remote/Conductor control.

The AME host should consume that cursor, not independently pick `sections.first`.

This may be completed alongside P0-3 executor navigation wiring.

---

# 12. P2 — Commands should preserve ordering on undo/removal

`RemoveAMETriggerCommand`, `RemoveAMEMappingCommand`, and `RemoveAMESequenceCommand` restore removed objects using `.append(...)` rather than their previous index.

For mappings runtime order is mostly normalized by specificity/priority/UUID, but preserving document order is still the correct command invariant, especially for editor predictability and sequences/triggers displayed in user order.

Store `removedIndex` and reinsert at `min(index, count)` on undo.

Do the same for source-binding / mapping-set delete commands when added.

---

# 13. P2 — Compiler warnings in the reviewed area should be closed before hardware acceptance

A Linux package build progressed through `AuroraModel` and `AuroraMusical`, then stopped as expected on macOS-only `CoreMIDI` / `Network` modules. During that build the reviewed code emitted warnings including:

- `MusicalEngine.receiveClockPulse`: `fireNow` and `canceled` never mutated.
- `AMEConfigurationValidator`: unused associated-value binds (`cs`, `csec`).
- several existing test closures mutate captured variables from `@Sendable` closures and are warned as Swift 6 errors-in-waiting.

The first two are trivial cleanup. The Swift 6 concurrency warnings in tests deserve a dedicated cleanup because they can become hard errors when language mode/toolchain changes.

Do not suppress them globally.

---

# 14. Required implementation order

Recommended closeout sequence:

```text
C1  Unified generalized execution path
    + truthful support/capability result

C2  Authoritative song/section action host wiring
    + real section cursor

C3  Fix Musical Engine project/song provenance layering

C4  Source disconnect toggle provenance + release

C5  Resolve source bindings against live inventory

C6  Complete inspector-based Wave 5 editor + commands

C7  Driver cleanup/adaptation + diagnostics naming + warnings

C8  Full macOS test suite + integration scenario

STOP → then Wave 6 hardware matrix
```

---

# 15. Mandatory cross-wave regression tests

The current `AMEAuditWave1to5Tests` is useful but too shallow for the claims made by the checkpoint. Add host/integration tests for the actual seams.

## Timing / source

- [ ] persisted external policy + source binding → live canonical source ID
- [ ] no-UID name binding resolves through current source inventory
- [ ] F8/Start/SPP ingress reaches MusicalEngine while legacy Learn is active
- [ ] F8/Start/SPP ingress reaches MusicalEngine while AME Learn is active
- [ ] opening/closing AME window has no effect on Musical scheduler cadence
- [ ] internal quantized action timing error within agreed target under load

## Quantization payload

- [ ] immediate vs quantized `.masterIntensity` produce same value
- [ ] immediate vs quantized `.programmerAttribute` affect same snapshotted fixtures
- [ ] holdUntilTimingAvailable enters scheduler held queue and fires once on restoration
- [ ] cancel/reject/fire consume token exactly once

## Generalized action execution

- [ ] immediate `.setTempoBPM` executes
- [ ] quantized `.setTempoBPM` executes
- [ ] immediate/quantized `.selectSong` update actual navigation + AME context
- [ ] `.enterSection`, `.nextSection`, `.previousSection` operate on authoritative cursor
- [ ] executor never returns `.executed` when required host hook is absent
- [ ] partial/unsupported action yields explicit monitor diagnostic

## Musical provenance

- [ ] project default survives songs with overrides
- [ ] song missing tempo/meter restores project values
- [ ] external fallback returns to correct song/project baseline
- [ ] custom/asymmetric project meter survives song roundtrip

## Disconnect safety

- [ ] held gate unwinds on device disconnect
- [ ] toggle unwinds on device disconnect
- [ ] disconnect A cannot unwind B
- [ ] dry-run state cannot cause live release
- [ ] repeated disconnect is idempotent

## Mapping activation

- [ ] ordinary scoped mappings remain active with mapping sets
- [ ] local IDs add activation
- [ ] mapping-set members add activation
- [ ] inheritance/disable resolves after combined candidate set

## UI / commands

- [ ] create/edit/delete/duplicate trigger with undo/redo
- [ ] create/edit/delete/duplicate mapping with undo/redo
- [ ] create/edit/delete/duplicate sequence + steps with undo/redo
- [ ] Learn commit undo restores exact previous document state
- [ ] validation navigation selects the affected AME object

---

# 16. Full software re-acceptance scenario before Wave 6

Run this with a deterministic synthetic MIDI source in the shipping application composition path, not isolated helpers:

1. Open project configured for external-preferred timing.
2. Resolve selected source binding to canonical live ID.
3. Start on internal fallback at project/song baseline.
4. Feed MIDI Clock + Start; acquire external authority.
5. Feed dense note traffic interleaved with F8.
6. AME Learn a snare note while clock continues.
7. Use the AME UI to configure the learned mapping without JSON.
8. Scope it to active song/section.
9. Attach a four-step sequence.
10. Set next-eighth quantization.
11. Trigger with varying velocity and confirm scalar payload survives scheduling.
12. Change fixture selection before fire and confirm ingress selection snapshot is used.
13. Execute a generalized immediate action (e.g. tempo/section action).
14. Execute the same semantic action quantized.
15. Exercise cancel/immediate/hold failure policies during clock loss.
16. Restore timing and confirm held action fires once.
17. Turn ON a source-owned toggle, unplug the source, confirm OFF/unwind.
18. Change section and confirm held-state lifecycle + sequence reset + mapping activation.
19. Enter a song with tempo override; then song without override; verify project baseline restoration.
20. Undo/redo AME edits.
21. Confirm token/scheduler/held/toggle counts return to bounded baseline.

Only after this is green should Wave 6 become primarily a **hardware/RTP/soak validation exercise**.

---

# 17. Things not to redesign

Do **not** use these findings as justification to reopen working architecture:

- Keep `AuroraMusical` free of CoreMIDI and AME model imports.
- Keep full ingress separate from legacy channel-voice handling.
- Keep monotonic `HostTime`.
- Keep authority-after-lock semantics.
- Keep AME armed vs dry-run state isolation.
- Keep held release ahead of normal fire gates.
- Keep recursive safety semantics.
- Keep tokenized scheduled action payloads.
- Keep additive mapping-set activation.
- Keep AME as a distinct window.
- Do not build the full Effects Engine as part of this closeout.

The remaining work is primarily **integration truthfulness and product completion**, not foundation redesign.

---

# 18. Final gate

Waves 1–5 may be re-stamped complete when all of the following are true:

- [ ] Immediate and quantized AME actions use the same generalized executor.
- [ ] No supported action can report success while doing nothing.
- [ ] Song/section actions use authoritative product navigation.
- [ ] Project musical defaults are never overwritten by song metadata.
- [ ] Missing song tempo/meter correctly falls back to project settings.
- [ ] Disconnect unwinds both held and source-owned toggle state.
- [ ] Source binding fallback resolves against actual live inventory.
- [ ] AME inspector can create **and edit** the approved mapping/trigger/sequence configuration without JSON.
- [ ] Command undo/redo covers those edits.
- [ ] Cross-wave integration tests are green on macOS.
- [ ] Full macOS `swift test` is green.
- [ ] Checkpoint is updated honestly to describe remaining Wave 6 hardware work only.

**Disposition until then:** software remediation is close, but **Wave 6 hardware acceptance should remain HOLD**.
