# Aurora Final Backend Review Before UI Mode

> **STATUS: HISTORICAL / COMPLETED (2026-08-05)**  
> All UI-GATE and PRE-UI items from this document were implemented on `main`.  
> Do **not** treat this file as an active backlog.  
> Authoritative current memory: `docs/PROJECT_HANDOFF.md` + `docs/UI_BACKEND_CONTRACT.md`.

## Post-Review-2 Backend Gate and UI Readiness Audit

**Repository reviewed:** `Aurora_postreview2.zip`  
**Reviewed HEAD:** `17c8d37` (`P2/P3: complete hardening — MIDI, output, remote, package, ENTTEC`)  
**Review goal:** Determine what, if anything, should still be corrected before Aurora enters the major UI/UX redesign.

---

# 1. Executive Summary

Aurora is now in substantially better condition than it was during either of the prior deep reviews.

The second remediation pass successfully addressed nearly all of the previously identified architectural blockers:

- dirty/save-point identity is now graph-safe rather than depth-based;
- Save As preserves package media/layout assets;
- ordinary project edits no longer destructively reset playback;
- the engine now uses a compiled show representation;
- 16-bit coarse/fine output is actually encoded as a 16-bit value;
- required package files fail load instead of silently becoming empty arrays;
- cue `fadeOut` and loop semantics now execute;
- fixture home/highlight/inversion/wheel behavior has been substantially developed;
- effects are persistent model objects with explicit ordering;
- fixture selection order is preserved;
- MIDI value/velocity can drive scalar actions;
- MIDI mappings can produce more than one action;
- output routing exists as a real model/runtime concept;
- project validation is cached outside the 40 Hz frame path;
- groups have an authoritative membership model;
- deterministic palette/preset recording rules exist;
- Song Mode now produces a dedicated performance snapshot;
- `AppModel` has been split into focused controllers;
- a shared `PerformanceSnapshot` exists for the future Mac Perform UI and remote surfaces;
- output health, frame percentiles, remote session expiration, package recovery, and several other hardening items are present.

This is no longer a repository I would describe as needing another broad backend phase.

**My recommendation is to fix the small set of issues in Sections 3 and 4, verify the listed macOS tests, and then begin UI mode.**

There is no justification for a rewrite.

---

# 2. Review Scope and Limits

I inspected the repository structure, commit history, production Swift, tests, package format, handoff documentation, controller split, engine/runtime representation, cue playback, programmer, effects, MIDI, OSC, RTP-MIDI, output routing, Art-Net, sACN, ENTTEC abstraction, remote control, diagnostics, persistence, workspace state, and existing UI plumbing.

I also attempted `swift test` in the review environment.

The model and diagnostics modules began compiling successfully. The complete package then stopped for the expected platform reason:

```text
error: no such module 'Network'
error: no such module 'CoreMIDI'
```

Those are Apple frameworks and this review environment is Linux. I do **not** count those failures as Aurora defects.

One minor compiler warning was observed:

```text
ProjectValidator.swift: variable 'hash2' was never mutated
```

That is cosmetic and included later as cleanup only.

Full build/test truth remains the macOS/Xcode build Grok is currently preparing.

---

# 3. Fix Before UI Mode

These are the findings I would resolve before committing the new Aurora UI architecture to production code.

They are not another giant remediation program. They are integration defects and API-contract issues that will become harder to notice once a richer UI is built around them.

---

## UI-GATE-1: MIDI live-status callback is installed and then overwritten

**Priority:** P1 / UI Gate  
**Area:** MIDI, diagnostics, UI observation  
**Files:**

- `Sources/Aurora/Controllers/InputController.swift`
- `Sources/Aurora/AppModel.swift`
- `Sources/Aurora/ControlActionRouter.swift`

### Finding

`InputController.startMIDI(...)` installs a `ControlActionRouter` UI notification callback:

```swift
router.setUINotify { [weak self] action, summary in
    Task { @MainActor in
        self?.appendMIDILog(summary)
        self?.lastMIDIEvent = summary
        self?.midiStatus = "MIDI: ..."
        ...
    }
}
```

This is around `InputController.swift:32`.

Immediately afterward, `AppModel.init` calls:

```swift
showControl.setUINotify { ... }
```

around `AppModel.swift:141`.

`ShowControlController.setUINotify` ultimately calls the **same** single-slot `ControlActionRouter.setUINotify(...)` API.

Therefore the second callback replaces the first one.

### Impact

The lighting action itself can still execute correctly, but normal live MIDI can stop updating:

- `midiLog`
- `lastMIDIEvent`
- the detailed MIDI status line
- future MIDI activity indicators

MIDI Learn uses a different path, so this can be easy to miss during development.

The planned UI will make this especially visible because Aurora intends to have quiet but trustworthy MIDI status indicators and diagnostic views.

### Required fix

Do not model UI observation as one replaceable callback.

Good options:

1. Make `ControlActionRouter` support multiple observers/subscriptions.
2. Have one owner install a composite notification callback that performs both responsibilities.
3. Better: keep the real-time router free of UI concepts and publish a bounded, thread-safe control-event stream that UI/diagnostics can subscribe to.

For the immediate fix, a composited callback is sufficient.

### Regression tests

Add an integration-level test where one MIDI Note event:

1. fires the mapped show action;
2. updates the live MIDI status/log observer;
3. updates any show-control presentation observer;
4. proves registering the second consumer does not unregister the first.

### UI rule

The new MIDI status UI should consume a focused observable MIDI/controller state, not infer activity from engine state.

---

## UI-GATE-2: OSC and remote GO paths still cross MainActor before live engine dispatch

**Priority:** P1 / live-performance gate  
**Area:** OSC, remote/iPad control, latency isolation  
**Files:**

- `Sources/Aurora/Controllers/InputController.swift`
- `Sources/Aurora/AppModel.swift`
- `Sources/Aurora/Controllers/RemoteController.swift`

### Finding

The prior review explicitly called for live OSC and remote transport actions to avoid waiting on `MainActor`.

That is not yet true.

### OSC

`InputController.setOSCEnabled(...)` receives the OSC event and immediately does:

```swift
Task { @MainActor in
    onAction(action, value)
}
```

around `InputController.swift:84`.

The `onAction` closure then eventually reaches `ControlActionRouter` from the main actor.

### Remote

`AppModel.setRemoteEnabled(...)` creates:

```swift
let action: @Sendable (RemoteShowAction) -> Void = { [weak self] action in
    Task { @MainActor in
        self?.performRemote(action)
    }
}
```

around `AppModel.swift:431`.

`performRemote` then dispatches GO/BACK/STOP/fire actions through the otherwise thread-safe `ControlActionRouter`.

That means the router itself is capable of avoiding UI scheduling latency, but the remote path waits for the UI actor before it gets there.

### Why this matters

The iPad/web remote is intended to be a live-performance control surface.

A busy SwiftUI main thread should never be able to delay:

```text
remote GO -> cue engine
OSC trigger -> cue engine
```

The same principle already correctly exists for CoreMIDI.

### Required architecture

Split live action execution from presentation updates.

Conceptually:

```text
Remote/OSC network callback
        |
        +--> ControlActionRouter.dispatch(...)   [immediate, non-MainActor]
        |
        +--> Task @MainActor                     [status/log/UI only]
```

Song navigation may still need a clearly synchronized state path because `SongDirector` is MainActor today. Transport and programmer actions should not.

### Regression/performance tests

Add tests or an instrumented harness proving:

- remote GO does not require MainActor execution before `engine.go()`;
- OSC GO does not require MainActor execution before `engine.go()`;
- UI/log notification can occur afterward;
- a deliberately blocked MainActor does not materially delay a live non-UI control action.

This is important before the iPad Perform interface becomes a primary workflow.

---

## UI-GATE-3: Universe routing default currently means "send everywhere"

**Priority:** P1 / stage-safety and Settings contract  
**Area:** DMX output routing  
**Files:**

- `Sources/AuroraModel/Universe.swift`
- `Sources/AuroraOutput/OutputManager.swift`
- `Sources/Aurora/Controllers/OutputController.swift`

### Finding

A new `Universe` defaults to:

```swift
protocolHint: .none
```

But `OutputManager.driver(_:accepts:)` interprets `.none` as:

```swift
case .none:
    return true
```

and additionally allows any driver whose own protocol is `.none` to receive everything.

So when both Art-Net and sACN are enabled, a universe whose route remains the default `.none` is currently eligible to be transmitted by **both network protocols**.

### Why this is dangerous

The word `none` reads like "not routed" while the runtime semantics are "route to all drivers."

That is exactly the kind of semantic mismatch that becomes dangerous once we build a polished Settings/Output Routing UI.

A user could reasonably believe a universe is disabled or unassigned while Aurora is transmitting it on multiple protocols.

### Required decision

Make the enum semantics explicit before the UI exposes them.

Recommended model:

```text
none      = no physical output
local     = local DMX driver
artNet    = Art-Net
sACN      = sACN
all/auto  = explicit separate concept, only if actually desired
```

If "all active protocols" is intentionally useful, name it something such as `.all` or `.mirror`.

Do not overload `.none` to mean "everything."

### Migration consideration

Existing schema-v1 projects may contain `.none` because it was the default.

Decide whether migration should treat old `.none` as:

- local/offline safe default, or
- legacy mirror behavior.

For live safety I recommend **no physical output** until the user chooses a route.

### Tests

Test all combinations:

```text
route none   -> no physical driver
route local  -> local only
route artNet -> Art-Net only
route sACN   -> sACN only
explicit mirror/all -> all, if supported
```

The Null/Mock test driver behavior can remain special as long as it does not redefine production routing semantics.

---

## UI-GATE-4: Performance and remote active-channel counts are wrong for multi-universe shows

**Priority:** P1 / presentation truthfulness  
**Area:** PerformanceSnapshot, remote state  
**Files:**

- `Sources/Aurora/Controllers/PerformanceSnapshot.swift`
- `Sources/Aurora/Controllers/RemoteController.swift`
- `Sources/AuroraRemote/RemoteMessages.swift`

### Finding

`PerformanceSnapshot.build(...)` calculates active channels from:

```swift
let levels = engineSnap.universeLevels.values.first ?? []
```

around `PerformanceSnapshot.swift:53`.

That is dictionary iteration order, not a defined universe.

The remote snapshot instead hard-codes:

```swift
let levels = engineSnap.universeLevels[1] ?? []
```

around `RemoteController.swift:105`.

Therefore the Mac and remote can report different counts, and both undercount a multi-universe show.

### Why fix before UI

`PerformanceSnapshot` is explicitly the contract intended for the new Perform UI.

If we build the new status chrome against a field whose meaning is already wrong, the visual redesign bakes the mistake into multiple clients.

### Required fix

Either:

1. define `activeChannelCount` as total active channels across all universes:

```swift
engineSnap.universeLevels.values
    .reduce(0) { $0 + $1.filter { $0 > 0 }.count }
```

or, preferably,

2. make the snapshot richer:

```text
activeChannelCountTotal
activeUniverseCount
perUniverseActivity: [UniverseNumber: ChannelActivity]
```

The Perform header can display the total while Diagnostics/Universe Monitor can display detail.

### Tests

Use at least two universes with active channels in both and assert Mac/remote presentation agrees.

---

## UI-GATE-5: MIDI stream parser preserves running status but not incomplete messages across packet boundaries

**Priority:** P1 / live MIDI reliability  
**Area:** CoreMIDI parser  
**Files:**

- `Sources/AuroraMIDI/MIDIMessageParser.swift`
- `Sources/AuroraMIDI/MIDIInputManager.swift`

### Finding

`MIDIStreamParser` correctly preserves the running-status byte.

However, it does **not** preserve incomplete channel-message data bytes.

For example, if one callback supplies:

```text
90 3C
```

(status = Note On, note = 60, velocity not yet present)

then the parser hits:

```swift
guard i + 1 < bytes.count else { return events }
```

and returns.

The partial note number is discarded.

If the next packet is:

```text
64
```

running status is known, but `64` is now interpreted as a new first data byte. The original Note On cannot be reconstructed.

The same issue exists for Note Off and CC.

### Required fix

The stream parser should preserve both:

- running status;
- pending data bytes for the current message.

A small state machine is preferable to reparsing concatenated arrays.

Conceptually:

```text
status
expectedDataByteCount
pendingDataBytes
```

Realtime system messages (`F8` etc.) must be allowed to interleave without destroying the pending channel message.

### Tests

Add boundary tests for:

- status + first data byte in packet A, final data byte in packet B;
- running-status message split after first data byte;
- realtime MIDI clock byte interleaved inside an incomplete channel message;
- multiple messages with arbitrary callback chunk boundaries.

This matters for drum-trigger reliability.

---

## UI-GATE-6: Song "automatic" progression is presentation state only

**Priority:** P1 / truthful UI contract  
**Area:** Song Mode  
**Files:**

- `Sources/Aurora/SongDirector.swift`

### Finding

`SongProgressionMode` defines:

```swift
case manual
case automatic
```

and `SongDirector` exposes:

```swift
func setProgressionMode(_ mode: SongProgressionMode)
```

But `progressionMode` currently changes only snapshot state.

No code observes playback completion/follow state and advances the song entry automatically.

### Why this matters now

The new Song/Perform UI is likely to expose Manual vs Automatic progression if it sees this domain contract.

At the moment that would create a control that can say "Automatic" without actually changing behavior.

This violates the rule established in the previous review:

> Do not build beautiful controls around model fields whose runtime semantics do nothing.

### Required decision

Before the UI spec, choose one:

**Option A, recommended for initial UI:**

Remove/hide `.automatic` from the usable contract until automatic progression has a precise design.

**Option B:**

Define and implement automatic Song entry completion semantics.

This needs real answers for:

- When is a cue entry considered complete?
- When is a cue-list entry considered complete?
- Do cue follows advance within the cue list before the song entry advances?
- Does a manual GO cancel/pause automatic progression?
- How are infinite loops handled?
- Does automatic mode advance songs or only entries?

Do not guess these behaviors in the UI layer.

---

## UI-GATE-7: Autosave performs full package I/O synchronously on MainActor

**Priority:** P1 for live-operation UX, P2 for pure persistence  
**Area:** autosave, media-heavy projects, control responsiveness  
**Files:**

- `Sources/Aurora/Controllers/AutosaveController.swift`
- `Sources/Aurora/AppModel.swift`
- `Sources/Aurora/Controllers/ProjectController.swift`
- `Sources/AuroraModel/ProjectPackage.swift`

### Finding

`AutosaveController` is `@MainActor` and calls `onAutosave` from a MainActor task.

The callback invokes:

```swift
ProjectController.save(...)
```

which synchronously calls:

```swift
ProjectPackage.save(...)
```

That operation:

- encodes all show JSON;
- creates a temporary package;
- copies `media/`;
- copies `layouts/`;
- validates the new package by loading it;
- swaps the package.

For small projects this is fine.

For a show containing significant media/assets, an autosave can block the main actor for a noticeable period.

The lighting engine itself has an independent scheduler, so DMX should continue. But UI, remote actions, and OSC currently depend on MainActor more than they should, making the combined effect worse.

### Recommended immediate strategy

Do not perform the full package write synchronously on MainActor.

A robust design is:

1. On MainActor, capture:
   - an immutable `ShowProject` value snapshot;
   - current document state ID;
   - destination/source URLs.
2. Perform package I/O on a utility/background task.
3. Return to MainActor.
4. Mark the document saved **only if** the current state ID still equals the snapshot state ID.
5. If edits happened during the save, leave the document dirty.

This makes autosave compatible with a responsive professional UI.

### Minimum short-term alternative

If asynchronous package save is deliberately deferred, disable periodic autosave while in Perform Mode and document that limitation.

I prefer the asynchronous implementation before broad beta use.

### Tests

Add a test around save-point identity:

```text
snapshot state A -> background save begins
user edits -> state B
save A completes
result: package contains A, document remains dirty at B
```

Then the next autosave captures B.

---

# 4. Strongly Recommended Before or During the First UI Implementation Pass

These findings are less likely to break a show immediately, but resolving their semantics now will make the UI specification cleaner.

---

## PRE-UI-1: ProjectValidator still misses several identity and routing invariants

**Priority:** P2, but inexpensive and high-value before Inspector/Diagnostics work  
**File:** `Sources/AuroraModel/ProjectValidator.swift`

### Current duplicate checks

The validator currently checks duplicate IDs for:

- fixtures;
- universes;
- groups;
- palettes.

It does not appear to check duplicate IDs for all other stable-ID model entities, including at least:

- fixture definitions;
- presets;
- cue lists;
- cues across lists;
- songs;
- song entries;
- MIDI mappings;
- effects.

### More important: duplicate universe numbers

Output buffers and routing are keyed by **universe number**, while project identity also has UUIDs.

`AddUniverseCommand` prevents duplicate UUIDs but does not reject duplicate `Universe.number` values.

Two different Universe UUIDs with the same number can therefore collide in:

```text
OutputManager buffers
route map
engine frame universeLevels
network output
```

That is a real integrity problem.

### Required validator additions

At minimum validate:

- unique universe numbers;
- universe number valid for the chosen output protocol where relevant;
- channelCount > 0 and reasonable;
- duplicate IDs for every first-class entity;
- duplicate cue IDs even across cue lists;
- duplicate effect order values, or explicitly define tie behavior;
- wheel slot duplicate indices/invalid DMX values if fixture definitions are embedded/imported;
- fixture-definition channel offsets are unique and within `channelCount`;
- at most one coarse/fine pair per semantic attribute unless explicitly supported.

### Command-side protection

Do not rely only on diagnostics.

`AddUniverseCommand` should reject duplicate universe numbers immediately.

Validation is the safety net for imported/corrupt files.

---

## PRE-UI-2: Application frame-rate preference does not change the engine frame rate

**Priority:** P2 / Settings UI contract  
**Files:**

- `Sources/Aurora/Controllers/AppSettingsStore.swift`
- `Sources/Aurora/AppModel.swift`
- `Sources/AuroraModel/ProjectPreferences.swift`

### Finding

`AppSettingsStore` has:

```swift
preferredFrameRateHz
```

At startup `AppModel` uses it only to call:

```swift
engine.frameMetrics.setTargetPeriodMs(...)
```

That changes the **performance budget target**, not `EngineConfiguration.frameRateHz` and not the actual scheduler period.

So a future Settings UI could let the user choose 30/40/44 Hz while the engine still runs at its existing configured rate and only the diagnostics target changes.

There is also a second project-scoped `ProjectPreferences.preferredFrameRateHz` that is currently unused by the engine.

### Required decision before Settings UI

Choose one ownership model.

Recommended:

- Engine frame rate is **application/hardware preference** unless there is a compelling reason to make it show-specific.
- Keep the app-global setting.
- Remove/deprecate the project-level duplicate in the next schema migration, or clearly define it as a per-show override.
- When the app setting changes, call a real `LightingEngine.updateConfiguration(...)` path.
- Save the app setting.

Also note that `AppSettingsStore.save()` currently has no caller in the repository.

Do not build a Settings control until this contract is real.

---

## PRE-UI-3: ENTTEC support is a protocol/framing backend, not yet usable physical DMX on macOS

**Priority:** P2 before live hardware, contract decision before Output Settings UI  
**File:** `Sources/AuroraOutput/ENTTECUSBDMXProDriver.swift`

### What is good

Aurora now has:

- correct-looking USB DMX Pro packet framing abstraction;
- an `OutputDriver` implementation;
- health reporting;
- universe filtering;
- a mock transport and tests.

That is a useful backend boundary.

### What is still missing

There is no real macOS `ENTTECSerialTransport` implementation in the repository.

Therefore the application cannot yet enumerate/select/open the actual USB serial device using this driver.

### Misleading comment

The file currently says:

```text
ENTTEC DMX USB Pro / Open DMX compatible serial framing
```

USB DMX Pro framed serial protocol and ENTTEC Open DMX are not the same transport behavior.

Open DMX uses a raw FTDI-style continuous DMX stream/timing model rather than USB Pro label-6 packet framing.

Aurora should not claim Open DMX compatibility through this driver.

### Before Output Settings UI

Define the device model the UI will consume:

```text
LocalDMXDeviceDescriptor
  id
  displayName
  serialPath / hardware identifier
  deviceType
  connectionState
  supportedUniverses
```

Then implement or schedule a real macOS USB Pro transport.

The new UI can be built with the descriptor/mock layer before hardware code is complete, but it should not expose a fake "Open DMX" option.

---

## PRE-UI-4: DiagnosticsStore is still mostly an app-log mirror rather than a true subsystem event bus

**Priority:** P2  
**Area:** future Diagnostics screen  
**Files:**

- `Sources/AuroraDiagnostics/DiagnosticEvent.swift`
- `Sources/Aurora/Controllers/DiagnosticsController.swift`

### Finding

The typed diagnostics infrastructure exists and is good.

However, most calls currently enter through:

```swift
DiagnosticsController.log(...)
```

which records them as subsystem `.app`.

Output, MIDI, remote, project, resolution, and engine do not yet consistently emit typed subsystem/severity/code events into the shared store.

### Recommendation

Do not block UI mode for full coverage.

But before designing the Diagnostics screen, wire the important categories so the UI can filter real structured events rather than parse strings.

At minimum:

- output start/fail/degraded/recovered;
- MIDI connect/disconnect/parser failures;
- RTP-MIDI session changes;
- remote auth/lock/kick/start failures;
- package recovery/save failures;
- project validation warnings;
- engine frame overrun warnings.

The existing `DiagnosticsStore` is the right abstraction. Use it rather than inventing another UI log model.

---

## PRE-UI-5: Document command groups have a transient dirty-state hole

**Priority:** P2  
**Area:** command/undo correctness  
**File:** `Sources/AuroraCore/DocumentSession.swift`

### Finding

While a command group is open, individual `perform(...)` calls mutate `project` and publish `.projectModified`, but do not mint/change `documentGeneration` until `endGroup()`.

Therefore during the lifetime of an open group:

```text
project content changed
isDirty may still be false
```

Current group use is synchronous and short-lived, so practical exposure is small.

However, autosave/window-close logic should never be able to observe modified content as clean.

### Recommended fix

Track an explicit `isGroupingDirty`/provisional state or mint a provisional unique state identity on the first mutation in a group and normalize it when the group commits.

At minimum add a unit test asserting `isDirty == true` immediately after the first grouped mutation before `endGroup()`.

---

## PRE-UI-6: `nextFreeAddress` still uses potentially overflowing UInt16 arithmetic

**Priority:** P3  
**File:** `Sources/AuroraModel/ShowProject+Patch.swift`

The newer `PatchedFixture.endAddress` correctly moved risky address math through `Int`.

`nextFreeAddress(...)` still includes expressions such as:

```swift
candidate + requested - 1
end + 1
```

using `UInt16` values.

Normal DMX universes are 512 channels, so this is not a normal-show failure. Imported/corrupt extreme values can still trap.

Use `Int` throughout the allocation calculation and convert back only after validated bounds.

---

## PRE-UI-7: Package crash recovery chooses "newest" backup by UUID filename ordering

**Priority:** P3  
**File:** `Sources/AuroraModel/ProjectPackage.swift`

Crash recovery searches backup packages named with random UUID suffixes and picks:

```swift
bak.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).first
```

UUID lexical ordering is not chronological.

If multiple orphan backups exist, this can restore an arbitrary valid backup rather than the newest one.

Use file modification/creation dates or encode a sortable timestamp into backup names.

Also consider validating the destination package before deleting orphan backups when a destination already exists.

---

## PRE-UI-8: Documentation now contains stale contradictions that can mislead Grok during UI work

**Priority:** P1 process/documentation fix  
**Files:**

- `docs/PROJECT_HANDOFF.md`
- `README.md`
- prior review documents retained in repo

### Examples

`PROJECT_HANDOFF.md` correctly says Stage B/Stage C are complete, but its "Intentionally incomplete" table still says things such as:

```text
Persistent effect defs | Runtime-only
AppModel split          | Still god-object-ish
```

Those statements no longer match the current code.

The README "Next" section still says:

```text
PR17 maps MIDI to actions; PR15 deepens color tools.
```

Those are long completed.

### Why this matters

The repository documentation is explicitly being used as agent memory for Grok.

Stale handoff instructions are therefore not harmless historical notes. They can cause the next coding session to "fix" something already fixed or design the UI against obsolete assumptions.

### Required cleanup before UI prompt

Create one current authoritative document, for example:

```text
docs/UI_BACKEND_CONTRACT.md
```

It should state:

- exact current controller ownership;
- exact live control path;
- exact project vs app vs workspace state ownership;
- current domain semantics for cue/song/effects/palette/preset;
- current output routing semantics after UI-GATE-3 is fixed;
- what is intentionally deferred;
- what the UI must not bypass.

Mark old review documents as historical/completed, not active backlog.

This will materially improve Grok's UI implementation quality.

---

# 5. UI Architecture Recommendations Based on the Current Backend

These are not backend defects. They are rules I recommend carrying into the UI specification now that I have reviewed the final controller structure.

---

## 5.1 Keep `AppModel` as composition root, but do not make it the primary UI store again

The Stage C split is real and useful.

`AppModel` is still roughly 500 lines because it provides compatibility facades and menu actions, but the important ownership has moved into:

```text
ProjectController
ShowControlController
InputController
OutputController
RemoteController
DiagnosticsController
WorkspaceController
AppSettingsStore
```

That is sufficient to begin UI work.

The new UI should bind directly to focused controllers where possible.

For example:

```text
Patch/fixture views    -> ProjectController
Programmer/transport   -> ShowControlController
MIDI settings/status   -> InputController
Output settings/status -> OutputController
Remote settings        -> RemoteController
Diagnostics            -> DiagnosticsController
Workspace mode/layout  -> WorkspaceController
```

Do not recreate the old pattern where every view observes the entire `AppModel` and then calls `notifyUI()` manually.

The current `PanelRegistry` is legacy scaffolding and can be replaced as the new workspace lands.

---

## 5.2 `PerformanceSnapshot` should become the semantic contract for Perform Mode

The idea is correct.

Before implementing the final Perform view, extend/fix it to include the information the new UI actually needs, rather than letting views reach directly into engine internals.

Recommended fields eventually include:

```text
show identity
isDirty
engine health/running
current cue ID / number / name / list
next cue ID / number / name
transition phase/progress
song / section / entry
next song entry
output aggregate health
MIDI health/activity
remote health/client count
validation/warning summary
active universe/channel summary
blackout or programmer override state
```

The Mac Perform UI and web/iPad UI should derive from the same semantic state.

---

## 5.3 Keep high-frequency monitor data separate

Do not stuff raw 40 Hz DMX arrays into the general application observation tree.

The existing snapshot throttling and dedicated Universe Monitor pattern is correct.

Use:

```text
PerformanceSnapshot -> low-rate semantic status
Monitor snapshots    -> purpose-specific throttled data
Engine tick          -> never directly drives entire SwiftUI hierarchy
```

---

## 5.4 Preserve the "complexity available, not constantly visible" principle

The backend now supports enough subsystems that the main workspace could become cluttered very quickly.

Keep these primarily in Settings/configuration surfaces:

- MIDI mappings and learn configuration;
- RTP-MIDI sessions;
- OSC configuration;
- Art-Net/sACN output configuration;
- local DMX hardware selection;
- remote server settings;
- plugin management;
- engine frame-rate/advanced settings;
- logging verbosity.

The workspace should show compact status and provide links/popovers to configure those systems.

---

## 5.5 Build and Perform remain different UX states

The backend now has a real `WorkspaceMode` and shared performance state, which is a good foundation.

Use it.

### Build mode

Dense, dockable, editable:

- fixture/group browser;
- programmer;
- palettes/presets;
- cue list;
- song editor;
- effects;
- inspector;
- patch;
- monitor/diagnostics when requested.

### Perform mode

Calm and intentionally difficult to edit accidentally:

- current song/section;
- current cue;
- next cue;
- GO/BACK/STOP;
- critical system health;
- warnings;
- optional compact programmer overrides.

The web/iPad UI should be closer to Perform Mode than Build Mode.

---

# 6. Items Verified as Successfully Fixed From the Previous Reviews

I specifically checked these because they were previously high-risk.

## Persistence and document safety

- Unique document-state IDs now prevent false-clean branch collisions.
- Save As passes the original package as the asset source when destination changes.
- Save stamps canonical `modifiedAt` and then updates in-memory metadata.
- Required schema-v1 collection files are enforced.
- Cue-list files are required and ID-checked.
- Package JSON has a file-size cap.
- Temporary package validation occurs before replacement.
- Crash-recovery scaffolding exists.

## Engine and cue playback

- Ordinary project updates call `engine.updateProject(...)` rather than destructive `load(...)`.
- `PlaybackController.updateProject(...)` preserves stage runtime state when possible.
- Cue-only resolution work from the prior pass remains present.
- `fadeOut` participates in crossfade duration.
- finite and infinite loop behavior has tests.
- effects are loaded from durable project definitions.
- the real-time engine uses `CompiledShow` rather than repeatedly walking editable model structures for output compilation.
- project validation is cached on load/update rather than recalculated at 40 Hz.

## Fixture/output semantics

- 16-bit coarse/fine channels are paired into a compiled write plan.
- normalized 16-bit values split into high/low DMX bytes.
- pan/tilt inversion is represented in the compiled write.
- fixture personality home/highlight data is compiled for programmer use.
- wheel slot application exists.
- universe reconciliation blackouts removed universes before deleting their buffers.
- DMX buffer tail/resize hardening exists.
- per-universe network sequence state exists.
- output health snapshots exist.

## MIDI/control

- source IDs are stable CoreMIDI unique IDs when available.
- per-source stream parsers exist.
- MIDI mappings support all matches rather than first-match only.
- `data2` now has explicit exact-filter semantics.
- Note velocity/CC scalar extraction exists.
- `ControlActionRouter` is thread-safe and keeps CoreMIDI live actions off MainActor.
- active cue-list context is used for `fireCueIndex`.

## Song/effects/model

- Song Mode remains an orchestration layer over the existing engine rather than a second lighting engine.
- `SongPerformanceSnapshot` now gives current/next entry state.
- effects are persistent and have explicit order.
- selection preserves explicit fixture order for phase-sensitive operations.
- Group.fixtureIds is documented/used as the authoritative membership source.
- palettes/presets are first-class model objects.

## State architecture

- focused controllers exist.
- `PerformanceSnapshot` exists.
- the old global `.id(revision)` whole-workspace rebuild is gone.
- Build/Perform mode exists as explicit workspace state.

This is why I am comfortable recommending UI mode after the small gate list above.

---

# 7. Recommended Fix Order for Grok

I would not hand Grok another giant "fix everything" prompt.

Give it this order and have it commit each cluster independently.

## Cluster A: Live-control correctness

1. Fix MIDI observer callback overwrite.
2. Move OSC live dispatch ahead of MainActor UI notification.
3. Move remote transport/programmer dispatch ahead of MainActor UI notification.
4. Add partial-message buffering to `MIDIStreamParser`.

## Cluster B: UI contract truthfulness

5. Define `.none` output route correctly and add an explicit mirror/all route only if desired.
6. Fix multi-universe `PerformanceSnapshot` and `RemoteSnapshot` activity semantics.
7. Remove/hide or implement Song automatic progression.
8. Resolve app/project frame-rate preference ownership before Settings UI.

## Cluster C: Persistence/UI responsiveness

9. Move autosave package I/O off MainActor, preserving document state-ID semantics.
10. Fix transient dirty state while command groups are open.

## Cluster D: Integrity and hardware contracts

11. Expand ProjectValidator, especially unique universe numbers and missing duplicate-ID categories.
12. Make `AddUniverseCommand` reject duplicate universe numbers.
13. Correct ENTTEC/Open DMX documentation and define the real macOS local-DMX device/transport contract.
14. Fix remaining UInt16 patch allocation arithmetic.
15. Improve orphan backup chronology.

## Cluster E: Agent memory cleanup

16. Refresh `README.md` and `PROJECT_HANDOFF.md`.
17. Add a concise authoritative UI/backend contract document.
18. Mark both older review MDs as historical/completed backlog documents.

Then stop backend work and enter UI mode.

---

# 8. Minimum Regression Matrix Before UI Branch

Run this on macOS/Xcode once Grok has created the Xcode project.

## Build

```text
Debug build succeeds
Release build succeeds
Zero Swift compiler errors
Review all Swift concurrency warnings
```

Treat new Swift 6 actor/sendability warnings seriously because Aurora has many intentionally `@unchecked Sendable` real-time/network classes.

## Model/package

- Save/open round trip.
- Save As with non-empty `media/` and `layouts/`.
- dirty state after branch/undo/redo.
- dirty state inside command group.
- background autosave completion after newer edit does not falsely mark clean.
- missing required file fails clearly.
- duplicate universe number rejected/diagnosed.

## Engine

- tracking and cue-only golden tests.
- fade in/fade out transitions.
- finite/infinite loops.
- live project edit preserves current stage look.
- 8-bit and 16-bit channel bytes.
- inversion/home/highlight.
- persistent effects and deterministic order.

## MIDI

- Note velocity drives programmer attribute.
- CC drives programmer attribute.
- one MIDI event triggers multiple mappings.
- per-source mapping identity.
- running status across callback boundaries.
- incomplete MIDI message across callback boundaries.
- live MIDI log/status observer remains active alongside show-control observer.

## Output

- local/artNet/sACN route matrix.
- `.none` means exactly the newly documented behavior.
- removed universe blackouts once before removal.
- multi-universe sequence counters.
- Art-Net packet golden.
- sACN packet golden.
- output health degraded/recovered states.

## Remote/OSC

- GO/BACK/STOP/fire do not depend on MainActor before engine dispatch.
- blocked-main-thread latency harness.
- remote authentication/rate limit/session expiry.
- multi-universe snapshot totals.

## Performance

- frame p95/p99 and overrun metrics.
- at least the existing scale test.
- ideally a larger 1,000 to 2,000 fixture synthetic bench on the target Mac before claiming production performance.

---

# 9. Hardware Work That Does Not Need to Block the Visual Redesign

The following can continue in parallel with UI work as long as the UI-facing contracts are defined now.

- Real Art-Net node soak test.
- Real sACN node soak test.
- Real ENTTEC USB DMX Pro serial transport and hardware test.
- Higher fixture-count performance bench.
- Native iPad app.
- TLS for remote control.
- Dynamic third-party plugin loading.
- Full GDTF support.
- Advanced timeline editor.

The visual redesign should include truthful disabled/unavailable states for capabilities that are modeled but not yet connected to physical hardware.

---

# 10. Xcode Project Review Checklist

Grok is currently creating a full Xcode project. When that lands, I recommend checking the following before the UI branch becomes the main development line.

## Preserve architecture

The Xcode project must not collapse the SPM modules.

Keep:

```text
AuroraModel
AuroraCore
AuroraEngine
AuroraOutput
AuroraMIDI
AuroraFixtureLib
AuroraDiagnostics
AuroraRemote
AuroraUI
Aurora app target
```

## App bundle

Confirm:

- real `.app` target;
- Info.plist ownership is unambiguous;
- document type for `.aurora` package is registered;
- app icon asset catalog exists;
- Aurora accent assets can be added cleanly;
- hardened runtime/signing configuration is understood;
- local-network description/Bonjour capabilities are only enabled if actually needed;
- sandbox decision is documented rather than accidental.

## Tests/schemes

Have at least:

```text
Aurora
Aurora Unit Tests
Aurora Performance Tests
```

A dedicated hardware/manual scheme can be useful later but is not required now.

## CI

A macOS CI workflow should build and run tests against the Xcode project or package on a Mac runner.

This gives future reviews a platform-authoritative result for CoreMIDI, Network.framework, AppKit, and SwiftUI.

---

# 11. Final Go/No-Go Decision

## Current state

**Conditional GO for UI mode.**

Aurora's core architecture is now healthy enough that I would begin UI design work once the P1/UI-Gate findings in this document are fixed or deliberately resolved by product decision.

I do **not** think every P2/P3 item must be completed before we start designing/rendering the UI.

I do think the following must be settled first because the UI will directly depend on them:

- MIDI observer ownership;
- non-MainActor remote/OSC live dispatch;
- output-route meaning;
- multi-universe performance snapshot meaning;
- MIDI stream completeness;
- Song automatic/manual semantics;
- frame-rate setting ownership;
- enough autosave isolation that the final UI is not designed around blocking saves;
- unique universe numbers/integrity;
- truthful local-DMX hardware capability description.

After those are settled, **stop adding backend features for a while.**

The next major deliverable should be the Aurora UI/UX specification and design system.

---

# 12. Suggested Grok Prompt

Use the following with this document:

> Treat `Aurora_Final_Backend_UI_Gate_Review.md` as the final backend readiness review before Aurora enters its UI redesign. Do not perform a broad rewrite. Preserve the existing module architecture, CompiledShow engine path, controller split, command/document model, ControlActionRouter, OutputDriver abstraction, and PerformanceSnapshot concept. Work through the UI-GATE items first in independent tested commits. Then address the inexpensive PRE-UI integrity/contract items that affect Settings, Diagnostics, Song Mode, output routing, autosave, and local DMX presentation. Do not begin visual UI redesign inside these commits. Do not add UI controls for behavior that is not implemented. After fixes, run the full macOS/Xcode test suite, update PROJECT_HANDOFF.md and README.md so they reflect the actual current code, and create a concise UI_BACKEND_CONTRACT.md describing the final observable/controller APIs the new UI should consume. Then stop and hand the repository back for UI design.

---

# 13. Closing Assessment

The overnight feature sprint initially produced a surprising amount of functionality, but the important result after two review/remediation cycles is not the raw feature count.

It is that Aurora now has a coherent architecture underneath those features.

The current repository has recognizable boundaries for:

```text
editable show model
command/undo document state
compiled engine state
playback/programmer/effects
input/control routing
output routing/drivers
remote clients
performance presentation state
UI workspace state
```

That is exactly the foundation the planned interface needs.

The remaining findings in this document are mostly cases where two good subsystems are not yet joined perfectly at their boundary. Those are much cheaper to fix now than after the new UI makes those boundaries visible everywhere.

Once they are cleaned up, I would consider the backend ready for the fun part:

**turning Aurora from a capable engineering interface into the professional lighting workstation we have been designing.**
