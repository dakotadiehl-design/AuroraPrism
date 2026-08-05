# Aurora Post-Remediation Deep Code Review
## Backend Hardening and UI Readiness Plan

**Repository reviewed:** `Aurora_post_codereview`  
**Review date:** 2026-08-05  
**Review scope:** Full repository after Grok's remediation of the prior P0-P3 review, with special attention to live-show reliability and the upcoming Aurora UI redesign.  
**Platform note:** Aurora is a macOS-native Swift application. This review intentionally treats Linux-only failures caused by Apple frameworks such as CoreMIDI and Network as environment limitations rather than Aurora defects.

---

# 1. Executive Summary

The remediation pass materially improved Aurora. The original foundation remains strong, and several of the highest-risk defects from the first review were correctly addressed. In particular, the repository now contains meaningful fixes for package replacement/rollback, dirty-state tracking, unsaved-change prompts, stale-universe blackout, cue-only state preservation, MIDI source identity, remote PIN/auth behavior, presets, palette compatibility checks, diagnostics scaffolding, and removal of the old root `.id(revision)` refresh workaround.

This review does **not** recommend a rewrite.

However, the second pass exposed deeper issues that should be fixed before the visual UI redesign becomes the main development focus. The most important are:

1. The new dirty-generation algorithm can still falsely report a modified project as clean after undo + branch edits.
2. A real Save As to a new `.aurora` package does not preserve the original package's `media/` or `layouts/` directories.
3. Nearly every project mutation reloads the lighting engine, and the reload path resets playback. A harmless live edit can therefore alter or drop the current stage look.
4. 16-bit coarse/fine fixture channels are merged incorrectly, which will break precise pan/tilt and other 16-bit attributes.
5. Several model fields and product promises are still inert or incomplete, including `fadeOut`, cue looping, parts of Song Mode, persistent effects, output routing hints, and some fixture-personality metadata.
6. MIDI Note On velocity is discarded by the generic programmer-attribute action path. This directly conflicts with Aurora's goal of mapping drum-note velocity to lighting intensity or other parameters.
7. The action-routing layer has begun to fragment across MIDI, OSC, remote control, keyboard/UI, and Song Mode. This should be unified before the redesigned Settings and Perform interfaces are built.
8. Project validation is both too narrow and currently executed on the engine hot path. It needs to become a cached project-level service.
9. `AppModel` is still a large application-wide coordinator and manual global invalidation remains. This is the most important architecture item to address specifically for the UI redesign.
10. The engine should compile project data into an immutable runtime representation rather than repeatedly performing linear model lookups at 40 Hz.

The recommended approach is:

- Fix all **P0** items before serious show use or UI implementation.
- Fix the **UI Gate** subset of P1 before building the new Aurora interface.
- Begin the visual redesign once the UI-facing state architecture and product semantics are stable.
- Continue P2/P3 hardening in parallel with UI work where appropriate.

---

# 2. Overall Assessment

| Area | Current assessment | Direction |
|---|---|---|
| Repository/module structure | Strong | Preserve |
| Model separation | Good, with several semantic gaps | Harden |
| Project persistence | Much improved, but still has two serious edge cases | Fix before UI |
| Cue/playback engine | Good core, but live-edit reset and inert cue semantics remain | Fix before UI |
| Fixture/DMX compilation | Needs important correctness work for 16-bit and personality metadata | Fix before UI |
| MIDI architecture | Much improved | Finish value semantics and hotplug state |
| Art-Net/sACN output | Functional architecture, needs routing/health/sequence hardening | Fix before live beta |
| Remote/web control | Useful foundation, still has lifecycle and binding gaps | Harden |
| Song Mode | Functional skeleton, not yet complete enough to design final UI around | Finish semantics |
| Effects | Useful runtime engine, persistence/order model incomplete | Finish semantics |
| Diagnostics | Good start, insufficiently integrated | Expand during UI work |
| UI state architecture | Still prototype-quality | Refactor before visual redesign |
| Existing visual UI | Intentionally temporary | Replace |
| Test discipline | Good and improving | Preserve and expand |

### Bottom line

Aurora has moved from "promising architecture" to "credible lighting application core." The next job is not to add another pile of features. The next job is to make the existing feature model internally truthful and stable enough that the redesigned interface can expose it confidently.

A professional UI must never offer controls that are dead, ambiguous, stale, or wired to different execution paths depending on where the user clicked.

---

# 3. What the Previous Remediation Successfully Fixed

The following items from the first audit are substantially improved and should generally be preserved rather than reworked again.

## 3.1 Package save replacement and rollback

`ProjectPackage.save` now writes to a temporary package and preserves an existing destination package through a backup/rollback path rather than deleting the live package first.

This is a major improvement over the original implementation.

**Remaining caveats:** true Save As preservation and crash/power-loss recovery are covered later in this review.

## 3.2 Media/layout preservation during normal save

When saving back to an existing package, `media/` and `layouts/` are copied into the newly constructed package.

This protects embedded assets during ordinary Save operations.

## 3.3 Dirty-state save points and unsaved-change guards

The repository now has explicit saved-generation state and prompts around New/Open/Quit.

The product behavior is much safer than before.

**Remaining caveat:** the generation algorithm has a branch-collision flaw described in P0-1.

## 3.4 Stale universe blackout/reconciliation

The engine/output transition path now addresses the old problem where universes belonging to the previous show could continue transmitting stale values after opening a new project.

This is an important live-show safety improvement.

## 3.5 Cue-only preservation

The prior cue-only problem was addressed so unstored attributes do not simply collapse to fixture defaults when progressing through a cue list.

This better matches the intended stage-state behavior.

## 3.6 MIDI hot-path and source identity work

MIDI has moved significantly closer to the intended architecture:

- raw CoreMIDI handling remains isolated,
- source identity is carried through the event path,
- live MIDI actions no longer need to originate from the UI,
- client/context cleanup was improved.

The remaining MIDI issues are narrower and are listed below.

## 3.7 Remote authentication defaults

The former `0000` default PIN was replaced with a generated value, and failed-auth rate limiting/token cleanup behavior improved.

This is materially safer for a LAN-facing operator interface.

## 3.8 Palette type compatibility and presets

Palette resolution now has stronger compatibility checking, and presets are no longer merely an unimplemented model concept. There is real UI/model behavior present.

The semantics still need refinement before the new visual preset/palette shelf is built.

## 3.9 Global `.id(revision)` workspace reconstruction removed

The old pattern of rebuilding the entire workspace through `.id(appModel.revision)` is gone.

That was the correct direction.

The replacement still relies too heavily on global/manual invalidation, but this is now an architecture cleanup rather than an emergency workaround.

## 3.10 Diagnostics scaffolding

A `DiagnosticsStore` now exists, giving us somewhere to build the production diagnostics experience envisioned for Aurora.

It needs broader subsystem integration before it becomes genuinely useful.

---

# 4. Priority Definitions

This review uses the same severity philosophy as the previous audit.

## P0: Correctness / data safety / stage safety

A defect that can:

- silently lose user work,
- corrupt or omit project data,
- make the stage output incorrect,
- unexpectedly reset a running show,
- or create a serious false sense that data is safely saved.

These should be fixed before the UI redesign begins.

## P1: UI readiness / serious beta blockers

A defect or architectural gap that is unlikely to corrupt a project immediately but would make the upcoming UI misleading, brittle, difficult to implement, or unsafe for serious rehearsal/live use.

The **UI Gate** subset of P1 should be fixed before implementing the new Aurora visual design.

## P2: Hardening and maintainability

Important work that improves scale, diagnostics, networking robustness, concurrency correctness, and long-term maintainability. Much of this can proceed in parallel with UI development after the UI Gate is clear.

## P3: Production/roadmap items

Items that should exist before a polished production release or specific hardware deployment, but which do not need to block the first UI implementation pass.

---

# 5. P0 Findings

# P0-1: Dirty-State Generation Can Collide After Undo + Branching

**Files:**

- `Sources/AuroraCore/DocumentSession.swift`
- `Sources/AuroraCore/UndoStack.swift`

`DocumentSession` currently tracks:

- `documentGeneration`
- `savedGeneration`
- `isDirty = documentGeneration != savedGeneration`

The idea is reasonable, but the generation number is reusable after undo.

## Failure example

1. Edit A -> generation 1
2. Edit B -> generation 2
3. Edit C -> generation 3
4. Save -> `savedGeneration = 3`
5. Undo twice -> generation 1
6. Make a new branch edit -> generation 2
7. Make another branch edit -> generation 3

The current project contents are **not** the saved contents, but:

```text
current generation = 3
saved generation   = 3
```

Aurora can therefore report the document as clean and allow New/Open/Quit without protecting the new edits.

## Coalescing complication

Command coalescing can also cross a save point. If a rename command before Save and another rename after Save coalesce into one undo item, the exact saved state may no longer exist as a reachable undo-stack position.

## Required fix

Do not use a reusable integer depth as the identity of document content.

Recommended approaches:

### Option A: Unique state identity

Each committed document state receives a monotonically unique revision token that is **never restored/reused** merely because the user undoes.

Track the current state token separately from undo depth.

### Option B: Save-point identity tied to undo graph

Represent save state as an immutable node/branch identity in the undo history.

Whichever implementation is chosen, **do not coalesce commands across a saved-state boundary.**

## Required regression tests

- save -> undo -> branch until same numerical depth -> must remain dirty
- save -> coalescible edit -> another coalescible edit -> undo must be able to return exactly to saved state
- save -> undo -> redo -> clean only when actual saved state is restored
- save -> edit -> undo -> clean
- save -> edit -> undo -> branch edit -> dirty

---

# P0-2: True Save As Loses Source Package Media and Layouts

**Files:**

- `Sources/AuroraModel/ProjectPackage.swift`
- `Sources/Aurora/AppModel.swift`
- package save tests

The new save implementation preserves `media/` and `layouts/` by copying them from an **existing destination package**.

That works for ordinary Save.

It does not correctly implement a genuine Save As.

## Failure example

Current project:

```text
My Show.aurora/
    project.json
    media/
        intro.wav
    layouts/
        programming.json
```

User chooses:

```text
Save As -> My Show Backup.aurora
```

The new destination does not yet exist, so `ProjectPackage.save` has no destination package from which to copy `media/` or `layouts/`.

The resulting copy can therefore omit those source-package assets.

The existing regression test for Save As currently prepares/copies the destination first, which does not reproduce the actual UI workflow.

## Required fix

Make source package preservation explicit.

Example API concept:

```swift
ProjectPackage.save(
    project,
    to: destinationURL,
    preservingAssetsFrom: currentDocumentURL
)
```

or provide a dedicated:

```swift
ProjectPackage.saveAs(
    project,
    from: sourceURL,
    to: destinationURL
)
```

`AppModel.saveShowAs()` should pass the currently opened package as the asset source.

## Required tests

- true Save As to a path that does not exist
- source has files in `media/` and nested subdirectories
- source has files in `layouts/`
- destination receives all files byte-for-byte
- source and destination remain independent afterward

---

# P0-3: Ordinary Project Mutations Reset Active Playback

**Files:**

- `Sources/Aurora/AppModel.swift`
- `Sources/AuroraEngine/LightingEngine.swift`
- `Sources/AuroraEngine/PlaybackController.swift`
- application event wiring

This is the most important live-show defect found in the second review.

`AppModel` reacts to `.projectModified` by reloading the engine.

The engine's project load path reloads `PlaybackController`, and `PlaybackController.load(...)` resets runtime playback state such as the active index/phase/current look.

That means project editing and engine reset are currently coupled.

## Why this becomes dangerous during UI redesign

The current prototype UI does not generate a huge volume of rich inline editing.

The planned Aurora UI will.

Examples of edits that should **not** unexpectedly reset the running stage:

- rename a palette
- change a MIDI mapping
- edit a note/annotation
- rename a fixture/group
- adjust a project preference unrelated to output
- update a palette used by future cues
- edit a cue that is not currently active
- modify workspace/layout state

A richer UI will make these operations fast and frequent. If all of them go through "project changed -> reload engine -> reset playback," Aurora will be unsafe to edit during rehearsal or performance.

## Required architectural change

Separate:

```text
Load a completely different show
```

from:

```text
The current show model changed
```

Recommended engine APIs:

```text
loadProject(...)
    destructive runtime reset
    used for New/Open/explicit show replacement

updateProject(...)
    updates immutable show/model snapshot
    preserves active playback context where valid

updateCue(...)
updatePalette(...)
updatePatch(...)
    optional specialized invalidation paths later
```

The exact API can differ, but the semantics must be explicit.

For model edits that affect the current look, Aurora should safely re-resolve the relevant data without blanking or returning the stage to idle/default.

## Required tests

While a cue is live:

- rename project -> DMX output unchanged
- change MIDI mapping -> DMX output unchanged
- rename palette -> DMX output unchanged if semantics unchanged
- change unrelated cue -> active look unchanged
- edit palette referenced by active cue -> behavior explicitly tested and documented
- Open different project -> old universes safely blackout and runtime resets

---

# P0-4: 16-Bit Coarse/Fine Fixture Channels Are Compiled Incorrectly

**Files:**

- `Sources/AuroraEngine/MergeStub.swift`
- `Sources/AuroraModel/FixtureDefinition.swift`
- `Sources/AuroraFixtureLib/Resources/Seed/generic-moving-head-16ch.json`

Aurora's fixture model already represents coarse/fine channels, and the moving-head seed personality contains pairs such as:

```text
Pan       -> coarse
Pan Fine  -> fine
Tilt      -> coarse
Tilt Fine -> fine
```

However, the merger currently converts the same normalized attribute independently to an 8-bit DMX value for each matching channel.

For a 16-bit value, that is incorrect.

## Example

For normalized pan around `0.5`, a 16-bit representation is approximately:

```text
0x8000
```

so DMX should be approximately:

```text
coarse = 128
fine   = 0
```

The current logic can instead produce approximately:

```text
coarse = 128
fine   = 128
```

which represents a different 16-bit position.

Moving heads will therefore have incorrect fine positioning.

## Required fix

Compile fixture channels into an explicit channel-write plan.

For 16-bit attributes:

1. Clamp normalized value to 0...1.
2. Convert to a 16-bit integer.
3. Write the high byte to coarse.
4. Write the low byte to fine.

Do not rely indefinitely on matching free-form attribute strings to infer pair relationships. The fixture model should eventually provide an explicit coarse/fine relationship or compiled pairing validation.

## Required tests

For pan and tilt:

- 0.0
- 0.5
- 1.0
- several arbitrary fractional values
- inverted pan/tilt after P1-2 is implemented

Assert exact coarse/fine bytes.

---

# P0-5: Missing Core Package Files Can Silently Load as Empty Collections

**File:** `Sources/AuroraModel/ProjectPackage.swift`

The package reader's array helper treats a missing JSON collection file as an empty array.

Forward compatibility is useful, but known files belonging to the current schema should not all be optional.

## Failure scenario

Suppose `fixtures.json` is accidentally deleted from an existing show package.

Aurora may load the show with zero fixtures instead of reporting package damage.

If the user then saves, the damaged/empty state can become the new valid package contents.

## Required fix

Define required files by schema version.

For schema v1, classify files explicitly as:

- required
- optional
- future/unknown ignored safely

Missing required files should produce a clear recoverable load error.

Do not confuse forward-compatible optional future fields/files with missing known v1 project data.

## Required tests

Delete each required v1 package file and assert load failure with a useful error.

---

# 6. P1 Findings: UI Gate and Serious Beta Blockers

The following are P1. Items marked **UI GATE** should be completed before Grok begins implementing the new visual Aurora interface.

---

# P1-1 [UI GATE]: Finish Cue Semantics Before Designing Cue UI

**Files:**

- `Sources/AuroraModel/Cue.swift`
- `Sources/AuroraEngine/PlaybackController.swift`
- cue editor/UI

The model exposes fields whose runtime meaning is incomplete.

## `fadeOut`

`Cue.fadeOut` is modeled and used by UI/default construction, but the playback engine does not meaningfully execute it as an independent outgoing fade semantic.

## `loop`

`Cue.loop: LoopSpec?` exists, but loop execution is not implemented by playback.

## Why this must happen before UI

The redesigned cue editor should never present attractive controls labeled Fade Out or Loop when changing them has no deterministic effect on playback.

Before designing the final Cue List / Inspector:

- define exactly what fade-in and fade-out mean for intensity vs non-intensity attributes,
- define crossfade behavior,
- define Back behavior during a transition,
- define loop count/infinite-loop behavior,
- define interaction with Follow cues,
- decide whether unsupported v1 fields should be hidden until implemented.

## Required tests

Golden tests for:

- separate incoming/outgoing fade durations
- zero-duration fade
- follow + fade
- finite loop
- loop exit
- infinite loop interruption
- Back during/after loop

---

# P1-2 [UI GATE]: Complete Fixture Personality Semantics

**Files:**

- `Sources/AuroraModel/FixtureDefinition.swift`
- `Sources/AuroraEngine/MergeStub.swift`
- `Sources/AuroraEngine/Programmer.swift`
- fixture library/importer

The fixture model contains metadata that the engine does not yet honor.

## Unused/underused fields

### `panInvert` / `tiltInvert`

These are represented in fixture definitions but are not applied in output compilation.

Expected normalized transform:

```text
inverted value = 1 - value
```

before coarse/fine encoding.

### `highlightValue`

Fixture channels contain personality-specific highlight values, but Programmer highlight behavior is largely hard-coded.

Aurora should use fixture-definition values so fixtures with unusual shutter/intensity/control behavior can highlight correctly.

### Home / Locate behavior

Locate currently relies on generic assumptions such as centered pan/tilt and open color/intensity behavior. A professional fixture system needs these values to come from capabilities/personality metadata wherever practical.

### Wheels

Wheel definitions and wheel-slot DMX values exist in the model but are not meaningfully consumed by the engine/programmer.

The final UI will want real visual gobo/color-wheel tiles. Build the semantics before rendering those controls.

## Recommended direction

Create a compiled fixture capability representation containing:

- stable attribute identifier
- family: intensity/color/position/beam/gobo/control/etc.
- DMX channel write plan
- 8/16-bit resolution
- inversion/physical mapping
- default/home value
- highlight value
- wheel slots/ranges
- optional physical units/ranges

The UI can then ask what a fixture **can do** rather than hard-coding channel strings.

---

# P1-3 [UI GATE]: Complete Song Mode Domain and Runtime Model

**Files:**

- `Sources/AuroraModel/Song.swift`
- `Sources/AuroraCore/SongDirector.swift` or corresponding director location
- `Sources/AuroraUI/Panels/SongPanel.swift`
- `Sources/Aurora/AppModel.swift`

Song Mode exists, but it is still closer to an ordered-reference navigator than the performance-oriented Song Mode envisioned in the design.

## Current gaps

- automatic progression semantics are not fully modeled/executed,
- timing information is limited,
- annotations are not deeply integrated into runtime presentation,
- document replacement can leave `SongDirector` runtime identity/index stale unless explicitly reset,
- broken targets need stronger validation,
- the runtime snapshot is too thin for the planned Perform UI.

## Required domain decisions before UI

Define:

- manual vs automatic song progression
- song section identity/name
- current entry
- next entry
- current cue/list identity
- performer annotation visibility
- optional duration/timing metadata
- behavior when an entry target is missing
- behavior when the referenced cue list changes during editing
- set-list relationship, even if full set-list editing is later

## Recommended runtime snapshot

Create an immutable presentation/runtime structure roughly capable of answering:

```text
Song
Current section
Current cue
Next section/cue
Entry index / count
Playback status
Manual/automatic mode
Performance annotation(s)
```

This becomes a clean input for both macOS Perform Mode and the web/iPad remote.

---

# P1-4 [UI GATE]: Persistent Effects and Explicit Effect Ordering

**Files:**

- `Sources/AuroraEngine/EffectInstance.swift`
- `Sources/AuroraEngine/EffectRunner.swift`
- `Sources/AuroraUI/Panels/EffectsPanel.swift`
- project model

Effects are still primarily runtime objects.

## Problems

### Effects are not durable show concepts

A live `EffectInstance` is not yet a first-class persisted project definition that cues/presets can reference cleanly.

The original architecture called for reusable, parameterized effects that can be used in cues and live programming.

### Ordering is based on UUID

`EffectRunner.snapshot()` sorts effects by UUID string to produce deterministic ordering.

That is deterministic, but it has no user or show semantics.

If two effects modify the same attribute, their result can depend on an ordering that the operator did not choose.

### Fixture phase order can be nondeterministic

`EffectsPanel` receives selection as a `Set<UUID>` and converts it into an array for effect creation.

Effects such as chase/rainbow/wave depend on fixture order. Set iteration should not define visual phase order.

## Required fix

Add first-class project objects such as:

```text
EffectDefinition
EffectReference / EffectAssignment
```

with:

- stable UUID
- name
- kind
- parameters
- explicit order/priority or combination semantics
- fixture/group targeting semantics
- stable phase order
- persistence and migration

Do not make the final Effects UI around runtime-only ephemeral instances.

---

# P1-5 [UI GATE]: Ordered Fixture Selection Must Be Defined

**File:** `Sources/AuroraCore/SelectionManager.swift`

`SelectionSnapshot.fixtureIDs` is currently a `Set<UUID>`.

A Set is sufficient for membership. It is not sufficient for all lighting operations.

Order matters for:

- fan
- align in some workflows
- chase phase
- rainbow/wave phase
- position distribution
- stage-map sequencing
- future pixel/fixture effects

The Programmer already works around this in places by sorting fixtures by address, while Effects currently use a Set-derived order.

## Required decision

Aurora should explicitly define one or more ordering concepts:

- selection order
- patch/address order
- stage-map spatial order
- group-defined order

Recommended minimum:

```text
orderedFixtureIDs: [UUID]
membership: Set<UUID>
```

Preserve the user's selection order, while allowing callers to request canonical patch/stage ordering as needed.

This is important for the future stage-map fixture-selection UI.

---

# P1-6 [UI GATE]: MIDI Note Velocity Is Lost for Parameter Mappings

**Files:**

- `Sources/Aurora/ControlActionRouter.swift`
- MIDI action resolver/tests

This directly affects one of Aurora's original differentiating use cases.

`ControlActionRouter.handleMIDIEvents` currently derives a generic value primarily from CC data. When a Note On is mapped to `.programmerAttribute`, the note velocity is not propagated as the parameter value, so the action can receive zero instead of the note's velocity.

## Desired behavior

Example:

```text
Snare Note On
velocity = 64 / 127
        ↓
Map to Intensity
        ↓
normalized value ≈ 0.504
```

This enables drum dynamics to drive lighting intensity/effect size/etc.

## Required fix

Create a generic normalized control-value abstraction:

```text
Note On      -> velocity / 127
Note Off     -> 0 where appropriate
CC           -> value / 127
Pitch Bend   -> normalized/bipolar value when supported
Aftertouch   -> normalized value when supported
```

Action definitions should specify whether they consume:

- trigger only
- scalar value
- bipolar value
- discrete parameter

## Required tests

- Note On velocity 1, 64, 127
- CC 0, 64, 127
- note trigger action ignores scalar safely
- value action receives normalized velocity

---

# P1-7 [UI GATE]: MIDI Mapping Resolver Only Returns One Matching Action

**File:** `Sources/AuroraMIDI/MIDIActionResolver.swift`

`match(...)` returns the first matching mapping.

That prevents one physical input from intentionally driving multiple Aurora actions.

Possible real-world examples:

```text
Kick drum
  -> pulse front wash
  -> trigger audience blinder effect at reduced value
  -> log/telemetry event
```

This may or may not be a v1 UX requirement, but the architecture should decide intentionally before the redesigned MIDI Settings UI is built.

## Recommended direction

Resolve to an ordered list of mappings/actions, with explicit priority/order.

If Aurora intentionally wants one-to-one mapping in v1, enforce/document that in the model and UI rather than relying on "first array match wins."

---

# P1-8 [UI GATE]: `MIDIMapping.data2` Has No Defined Runtime Meaning

**File:** `Sources/AuroraModel/MIDIMapping.swift`

`data2` is persisted in the mapping model but not meaningfully used by the matching logic.

Before the final MIDI-mapping editor is built, either:

1. define it as a value/velocity filter/range concept and implement it, or
2. remove/deprecate it from the v1 model/UI.

Do not expose a field whose semantics are ambiguous.

---

# P1-9 [UI GATE]: Unify All Show-Control Actions Before Building Settings and Perform Mode

**Files:**

- `Sources/Aurora/ControlActionRouter.swift`
- `Sources/AuroraMIDI/ShowAction.swift`
- `Sources/AuroraRemote/RemoteMessages.swift`
- `Sources/Aurora/AppModel.swift`
- OSC handling
- Song Director

Aurora now has multiple paths capable of asking the show to do something:

- MIDI
- OSC
- remote TCP/web
- keyboard
- main UI
- Song Mode
- future plugins/data sources

These paths are beginning to duplicate action semantics.

## Concrete current bug: cue-index context

Several `fireCueIndex` paths refer to `project.cueLists.first` rather than the list currently loaded/active in playback.

If Song Mode has loaded another list, cue-index control can target the wrong list or fail.

## Required architecture

Create one typed show-control/action dispatcher.

Conceptually:

```text
MIDI ─┐
OSC ──┤
Web ──┤
Keys ─┤
UI ───┤ -> ShowActionDispatcher -> Engine / Song Director
Plugin┘
```

The action layer should define:

- stable action ID
- user-visible name
- category
- parameter schema
- real-time-safe vs main-thread-required behavior
- target/reference fields
- validation

Likely action categories:

```text
Playback
Song
Programmer
Palette
Preset
Effect
Fixture/Group
Output/Safety
Diagnostics/Utility
```

## Why this is a UI Gate

The redesigned Settings screen for MIDI/OSC/plugins should be populated from this action catalog rather than having each settings panel invent its own list of actions.

The same action dispatcher should power the giant GO button in Perform Mode and the iPad/web remote.

---

# P1-10 [UI GATE]: Universe Output Routing Model Is Not Actually Used

**Files:**

- `Sources/AuroraModel/Universe.swift`
- `Sources/AuroraOutput/OutputManager.swift`
- Art-Net/sACN drivers

`Universe.protocolHint` exists but the output manager currently fans universe data to all active drivers rather than routing according to the project's intended protocol/output mapping.

If both Art-Net and sACN are enabled, Aurora can transmit a universe through both even when the project intends one route.

## Required fix

Implement an explicit output-routing model before designing the final Output Settings UI.

Do not necessarily lock Aurora to one protocol per universe forever. A future-friendly model could allow:

```text
Universe 1
  -> ENTTEC USB Pro

Universe 2
  -> Art-Net / interface en0 / target x

Universe 3
  -> sACN multicast

Universe 4
  -> Art-Net + sACN redundant/mirror route
```

A single `protocolHint` may eventually be too restrictive. Consider a first-class `OutputRoute` model with stable IDs.

## Required tests

- only configured driver receives a universe
- mirrored route intentionally sends to multiple outputs
- disabled route transmits nothing
- opening a new project reconciles/blackouts routes safely

---

# P1-11 [UI GATE]: Project Validation Must Become Comprehensive and Leave the Engine Hot Path

**Files:**

- `Sources/AuroraModel/ResolutionIssue.swift`
- `Sources/AuroraEngine/LightingEngine.swift`
- project loading/editing paths

`ShowProject.validateReferences()` currently checks only a narrow subset of project integrity, while the engine invokes project validation as part of frame/snapshot processing.

## Problems

### Validation coverage is too narrow

A complete project validator should detect at least:

- duplicate stable IDs
- missing fixture definition references
- missing universe references
- invalid fixture addresses/footprints
- patch overlap/conflict
- missing group members
- missing cue fixture IDs
- missing/incompatible palette references
- preset palette/reference issues
- missing Song targets
- invalid MIDI action targets
- invalid output routes
- invalid effect references
- schema/model invariant violations

### Validation is in the real-time path

Scanning project cues/references repeatedly at engine/snapshot frequency is unnecessary and becomes increasingly expensive as shows grow.

Issue IDs are also generated in ways that can make the same logical issue look new repeatedly.

## Required architecture

Create a `ProjectValidator` service.

Run it:

- after load,
- after relevant document mutations,
- optionally on a debounced background queue,
- before save/export when appropriate.

Cache the resulting immutable validation snapshot.

The engine should consume only the validated/compiled project state and report **runtime-specific** issues separately.

Use stable issue identity derived from entity/reference/type rather than random identity every frame.

This service will feed the redesigned Diagnostics/Issues panel and Inspector warnings.

---

# P1-12 [UI GATE]: Split Runtime Project Compilation From Editable Project Model

**Files:**

- `Sources/AuroraEngine/MergeStub.swift`
- `Sources/AuroraEngine/LightingEngine.swift`
- project lookup helpers

The engine currently works directly against the editable `ShowProject` and repeatedly performs lookups such as definition-by-ID and universe-by-ID while rendering frames.

These helpers generally perform linear searches.

At 40 Hz and thousands of fixtures, this is not the architecture we want to carry into production.

## Recommended design

Compile the editable project into an immutable `EngineShowState` / `CompiledShow` when the project or relevant structural state changes.

It should contain structures such as:

```text
universeByID
fixtureByID
compiled fixture patch records
compiled channel write plans
8/16-bit attribute mappings
home/default/highlight values
palette-resolved or resolver-ready indexes
fixture/group indexes
output route lookup
```

Then the engine frame loop works over compact arrays/dictionaries without repeatedly traversing Codable/project objects.

This is also the cleanest place to solve:

- 16-bit channel pairs
- inversion
- wheel/capability mapping
- address bounds
- output routing lookup

## Required performance test

Restore the original design target:

```text
2,000 fixtures
500 cues
multiple universes
multiple fixture definitions
continuous MIDI
active programmer/effects
```

Measure:

- frame duration mean
- p95
- p99
- maximum
- missed frame periods / overruns
- jitter

The current 200-fixture smoke test is not representative of the stated production target.

---

# P1-13 [UI GATE]: Resolve Group Membership's Two Sources of Truth

**Files:**

- `Sources/AuroraModel/Group.swift`
- `Sources/AuroraModel/PatchedFixture.swift`
- group commands

Group membership is represented in both:

```text
Group.fixtureIds
```

and

```text
PatchedFixture.groupIds
```

The command paths do not consistently update both.

This creates divergent model state.

The redesigned Fixture Browser and Inspector will make group membership much more visible and editable, so this must have one authoritative representation.

## Recommendation

Prefer one source of truth.

For example:

```text
Group.fixtureIDs
```

is authoritative, and fixture membership is derived/indexed as needed.

If bidirectional persisted references are retained, every mutation must update the invariant transactionally and validation must detect divergence.

One source is simpler and safer.

---

# P1-14 [UI GATE]: Palette/Preset Recording Semantics Need to Be Deterministic

**Files:**

- Programmer/palette/preset application code
- palette/preset panels

When creating a palette from programmer data, code paths can effectively select the first value from dictionary-like storage.

If selected fixtures hold different colors/values, "first" can be arbitrary.

The upcoming palette shelf will make recording/applying palettes a central workflow, so this needs explicit semantics.

## Define before UI

When recording a palette from multiple fixtures:

- must all selected fixtures have the same value?
- does Aurora record a per-fixture palette?
- does it use the active/primary fixture?
- does the UI show "Mixed" and require a choice?
- are color/position palettes universal or fixture-family scoped?

Likewise, applying a preset currently can encounter resolution issues that are not strongly surfaced to the operator.

A preset should never report a simple success while silently skipping incompatible/missing content.

## Recommendation

Build a proper Record dialog/state model that can report:

```text
Common values
Mixed values
Referenced palettes
Literal values
Compatible fixture families
Warnings
```

This will map naturally into the visual UI later.

---

# P1-15 [UI GATE]: Build the UI-Facing State Architecture Before Visual Implementation

**Files:**

- `Sources/Aurora/AppModel.swift`
- `Sources/AuroraUI/*`
- `WorkspacePanelContext`
- selection/document/engine state

`AppModel` is now roughly 800 lines and owns or coordinates an unusually broad set of responsibilities:

- document lifecycle
- save/open dialogs
- project session
- fixture library
- engine
- output manager and driver configuration
- MIDI
- control actions
- RTP-MIDI
- OSC
- Song Mode
- plugins
- diagnostics
- remote servers
- status polling
- logs/settings

It is becoming the exact God object we predicted in the first review.

The current UI also still depends on manual/global invalidation patterns. `bump()` increments an `@Published revision` and also manually sends `objectWillChange`, producing redundant broad invalidation.

`DocumentSession` and `SelectionManager` are not themselves clean observable presentation stores, so panels rely heavily on the root model to make SwiftUI notice changes.

## This should be addressed before implementing the pretty UI

Do **not** rebuild the new interface around one giant `AppModel` environmental dependency.

Recommended composition:

### `ProjectController` / `DocumentStore`

Owns:

- current project/session
- URL
- save/open/new
- dirty/save state
- project validation snapshot

### `ShowControlController`

Owns:

- engine transport
- current/next playback presentation state
- action dispatch
- programmer runtime control

### `InputController`

Owns:

- CoreMIDI
- RTP-MIDI
- OSC
- mapping state/presentation

### `OutputController`

Owns:

- drivers
- routes
- device/network configuration
- output health

### `RemoteController`

Owns:

- web/TCP remote lifecycle
- client/session state
- remote settings

### `DiagnosticsController`

Owns:

- subsystem events
- performance metrics
- project issues
- export/report state

### `AppSettingsStore`

Owns truly application-global preferences.

### `WorkspaceController`

Owns:

- Build/Perform workspace selection
- panel visibility/layout
- named workspace layouts
- inspector state
- UI-only selection/presentation state where appropriate

`AppModel` can remain as a thin composition root if useful.

## Observation model

Use granular observable stores/presentation snapshots rather than a global revision counter.

Views should update because the state they consume changed, not because "something in Aurora changed."

This is the single most important architecture prerequisite for the upcoming UI redesign.

---

# 7. P2 Findings: Hardening That Can Continue During UI Work

# P2-1: MIDI Hotplug Reconciliation Is Incomplete

**File:** CoreMIDI input manager

Refreshing sources updates the visible source list, but stale connected endpoint/source-ID bookkeeping can remain when devices disappear.

Potential consequences:

- stale connected count
- failure to reconnect correctly
- endpoint-reference reuse confusion

Implement a true inventory reconciliation:

```text
removed endpoints -> disconnect + remove state
new endpoints     -> connect + create state
existing          -> retain/update metadata
```

Prefer testable endpoint-inventory abstraction around CoreMIDI.

---

# P2-2: MIDI Running Status Should Survive Packet Boundaries

The MIDI message parser keeps running status locally per parse call, while CoreMIDI packet lists can split byte streams in ways that make parser state across packets relevant.

Use parser state per source/stream, or explicitly guarantee and test the assumptions being made.

---

# P2-3: Art-Net/sACN Sequence Counters Should Be Per Universe/Stream

Art-Net and sACN drivers currently maintain a single sequence counter per driver.

With interleaved multiple universes, each receiver can observe gaps because unrelated universe packets consume sequence values.

Use per-universe counters:

```text
[UniverseID/number: UInt8]
```

For sACN, also consider persisting a stable CID per Aurora installation instead of generating a new source identity on each driver construction.

---

# P2-4: Output Driver Thread-Safety Needs a Swift 6 Audit

Several driver objects are marked `@unchecked Sendable` while mutable fields such as `isRunning`, configuration, socket/listener state, and error state can be read/written across UI and engine/output threads.

`@unchecked Sendable` should represent a proven synchronization strategy, not a promise to the compiler.

Recommended options:

- lock-protected driver state,
- actor-owned lifecycle/configuration with a real-time-safe send endpoint,
- or OutputManager-owned synchronized lifecycle state.

Enable stricter concurrency checking in CI when feasible.

---

# P2-5: Output Reconfiguration Errors Are Still Suppressed

Some Art-Net/sACN update/restart paths use `try?`.

A configuration screen can therefore claim an output is enabled while socket/startup actually failed.

Return structured failure and publish it through output health/diagnostics.

The future UI's quiet status indicators must mean something trustworthy.

---

# P2-6: Add First-Class Output Health Snapshots

Before finalizing the small status dots envisioned for Aurora, define an output status model that can distinguish:

```text
Disabled
Starting
Ready
Degraded
Failed
Disconnected
```

Useful fields:

- driver ID/name
- configured route(s)
- interface/target
- last successful send time
- last error
- sent/dropped packet count
- active universes
- driver state transition timestamp

The UI should not equate "configured/enabled" with "healthy."

---

# P2-7: DMX Buffer Resize/Short-Frame Semantics Need Tightening

Existing universe buffers are not always resized when logical channel count changes, and writing a shorter level array can leave stale values in a longer buffer.

For standard DMX output, the simplest rule is likely:

```text
Universe size = 512 channels
```

with explicit validation and full-frame clearing/update behavior.

If variable channel counts are retained internally, buffer resize and tail clearing must be deterministic.

---

# P2-8: Save Replacement Still Has a Power-Loss Window

The new backup/temporary-package save strategy correctly rolls back on thrown errors.

It cannot roll back if the process or machine dies between moving the old package to backup and moving the new package into place.

That can leave:

```text
Show.aurora.bak
Show.aurora.tmp
```

with no `Show.aurora` at the expected path.

Improve with either:

- platform-supported coordinated/atomic replacement (`replaceItemAt` where suitable), and/or
- startup/open recovery detection for orphan temp/backup packages.

For a live-performance application, recovery UX is worth implementing.

---

# P2-9: Add Schema Migration Infrastructure Before UI-Driven Model Expansion

Aurora is still schema version 1 with no meaningful migration pipeline.

The UI redesign is likely to introduce persistent model additions such as:

- persistent effects
- output routes
- richer Song data
- named workspaces
- new settings scopes
- expanded fixture capability metadata

Do not wait until several released schemas exist before building migration support.

Recommended pattern:

```text
read raw v1
 -> migrate v1 to v2
 -> validate v2
 -> load current domain model
```

Maintain golden old-version package fixtures in tests.

Never overwrite the only copy of an older project during migration without recoverability.

---

# P2-10: Patch/Fixture Arithmetic Should Not Use Trapping UInt16 Math

Fixture end-address and related calculations use unsigned integer arithmetic that can overflow if a malformed/imported personality contains an absurd channel count.

Project files/imports are untrusted input.

Perform address arithmetic in `Int`, validate boundaries, then convert to DMX types.

For standard universes enforce:

```text
1 <= start address <= 512
1 <= footprint <= 512
end address <= 512
```

unless Aurora intentionally supports a different protocol model.

---

# P2-11: Remote Bind Policy Is Declared but Not Enforced

**Files:** remote host/session/server configuration

A `RemoteBindPolicy` exists, but it is not wired strongly enough into listener/interface behavior.

The remote server can therefore still listen more broadly than the configuration model implies.

Implement the policy rather than merely storing it.

Default should favor local/private-network operation unless the operator explicitly chooses otherwise.

Apply similar thought to OSC input.

---

# P2-12: Web Remote Sessions Can Accumulate Until `maxClients` Is Reached

HTTP `/api/hello` creates client/session records, but ordinary web refresh/reconnect behavior does not have a sufficiently strong session-expiry/reuse/logout model.

Repeated browser reloads can consume client slots until the server refuses additional clients.

Implement:

- `lastSeen`
- session/token expiry
- client ID reuse/reconnect
- explicit logout where useful
- inactive-client reclamation

Test many browser reconnects/reloads.

---

# P2-13: Remote Parsers Need Pre-Delimiter Buffer Limits

HTTP header size limits are applied after the header terminator is found.

A malicious/broken client can keep sending bytes without `\r\n\r\n`, growing the receive buffer.

The TCP newline protocol has a similar pre-delimiter issue.

Enforce maximum accumulated buffer size **before** delimiter discovery and disconnect abusive clients.

---

# P2-14: Remote Startup Should Be Transactional

Remote enablement starts multiple services. If one listener succeeds and the next fails, Aurora can be left partially enabled.

Start remote services transactionally:

1. attempt each component,
2. if any component fails, stop all newly started components,
3. publish a single accurate failure state.

Also distinguish "listener object created" from actual Network.framework `.ready` status.

---

# P2-15: OSC and Remote Live Actions Still Depend on MainActor

MIDI received a better real-time path, but OSC and remote show actions still route through `Task { @MainActor ... }` in important places.

GO/fire/programmer live actions should enter the same real-time-safe `ShowActionDispatcher` as MIDI.

MainActor should only receive presentation/log/document-edit consequences.

This will matter for the new Perform Mode and iPad/web interface.

---

# P2-16: Remote Snapshot Is Still First-Cue-List / Universe-1 Centric

Remote presentation logic still makes assumptions such as:

- Universe 1 for activity summary
- first cue list for cue-name resolution

Those assumptions fail when Song Mode loads a different list or a project uses multiple universes.

Build remote/performance snapshots from stable IDs supplied by engine runtime state.

Recommended fields for the shared Perform snapshot:

```text
show ID/name
song ID/title
song entry/section
active cue list ID/name
current cue ID/number/name
next cue ID/number/name
transition state/progress
engine health
output health summary
MIDI/control health
active universe summary
warnings
```

This snapshot can power both macOS Perform Mode and the remote UI.

---

# P2-17: Diagnostics Store Needs Real Subsystem Integration

The diagnostics store currently receives mainly app-level messages.

Inject or bridge diagnostics from:

- project loading/saving/migration
- project validator
- engine overruns
- MIDI connect/disconnect/parser issues
- RTP-MIDI
- OSC
- output driver start/send failures
- remote auth/client/server events
- plugin/data-source events later

Use structured event codes/categories rather than only human-readable strings.

This will support:

- Diagnostics panel
- Show Report
- log export
- troubleshooting filters

---

# P2-18: Performance Metrics Need Percentiles and Overrun Counts

Mean and lifetime maximum are useful but insufficient for deterministic show-control analysis.

Track a bounded moving window and expose:

- mean
- p95
- p99
- max
- frame period target
- overrun count
- consecutive overrun count
- jitter
- control/MIDI queue depth where possible

This should ultimately feed the Show Diagnostics report envisioned earlier.

---

# P2-19: Avoid Per-Frame Full-Buffer Allocation Once Compiled Engine State Exists

`MergeStub` creates fresh universe arrays and OutputManager copies them into DMX buffers.

At small shows this is acceptable.

After correctness work, profile and consider:

- reusable frame buffers
- precompiled channel writers
- copy-on-publish only for monitor snapshots

Do not optimize prematurely, but do benchmark at the 2,000-fixture target.

---

# P2-20: Remove Remaining Silent `try?` UI Operations

Several panels still suppress command/application errors.

The redesigned UI should use one error-presentation strategy:

```text
command executor
   -> success
   -> recoverable warning/toast
   -> validation issue
   -> blocking error sheet only when truly necessary
```

Silent failure is especially dangerous in live software because the operator may think a configuration change took effect.

---

# P2-21: Project `modifiedAt` Should Have One Ownership Rule

The package writer updates metadata on the copy being written, while the in-memory session project does not necessarily receive the same timestamp.

Choose one owner:

- document/session updates metadata before save, or
- save returns the canonical written metadata/project state.

Avoid persisted metadata silently diverging from in-memory state.

---

# P2-22: Dead/Unused Preference Audit

Before the Settings redesign, audit every persisted preference/model field and prove it affects runtime behavior.

Examples currently needing attention include:

- preferred engine frame rate
- output protocol hint/routing
- default fade-out vs actual playback semantics
- workspace layout identifiers
- other fields introduced ahead of implementation

Rule for the new UI:

> If a setting appears on screen, it must have a tested effect or be explicitly labeled unavailable/coming later.

---

# 8. P3 Findings: Production and Roadmap

# P3-1: ENTTEC USB DMX Pro / Physical Local DMX Driver Is Still Needed

Aurora's architecture includes `.local` output intent, but a physical local DMX path such as the ENTTEC DMX USB Pro is not yet implemented.

This is not a code-review regression, but it is a practical requirement before Aurora can fully replace the user's current LightKey setup for Haywire.

Implement as an `OutputDriver`, not as engine special-case logic.

Test:

- connect/disconnect
- device enumeration
- missing device
- mid-show USB unplug/replug
- long-run output
- universe/channel correctness

---

# P3-2: Real Art-Net/sACN Hardware Validation

Static/unit tests cannot substitute for network-lighting hardware tests.

Before live beta, validate:

- multiple universes
- broadcast/unicast/multicast behavior as applicable
- node startup order
- node reboot
- Mac interface changes
- Wi-Fi/Ethernet coexistence
- unplug/replug
- duplicate send routing
- packet sequence behavior
- hours-long continuous operation

---

# P3-3: Proper macOS App/Document Packaging and Recovery

Aurora remains structurally closer to an SPM executable than the final polished document application described in the original system design.

During the UI/productization phase, consider:

- proper Xcode `.app` target
- UTType for `.aurora`
- Finder/Open Recent integration
- autosave/recovery strategy
- document package coordination
- app sandbox/notarization implications if distribution is planned

Whether to use `NSDocument`, SwiftUI document infrastructure, or a custom document controller should be decided intentionally based on Aurora's live-engine lifecycle needs.

---

# P3-4: Dynamic Plugin Runtime Can Remain Later

The plugin/data-source concept is strategically valuable, but dynamic third-party dylib loading should still wait until the internal APIs have stabilized.

Before runtime plugins, first create clean internal protocols for:

- data sources
- events
- actions
- output drivers
- fixture importers
- effect generators
- settings descriptors
- diagnostics

The plugin SDK should expose those stable abstractions, not Aurora internals.

---

# 9. Specific UI-Readiness Architecture Recommendations

This section is intentionally more prescriptive because the next major project phase is the UI redesign.

---

# 9.1 Preserve the Product Principle: Complexity Available, Not Constantly Visible

The backend should support the UI hierarchy already chosen for Aurora:

```text
Workspace
    Things used while programming or performing

Inspector
    Context-sensitive editing of current selection

Settings
    Occasional configuration such as MIDI mappings, network/output, plugins

Diagnostics
    Health, warnings, logs, validation and performance information
```

Do not let backend ownership force every subsystem into the main workspace.

---

# 9.2 Make Build Mode and Perform Mode Separate Presentation States

The application core can be shared, but presentation state should clearly distinguish:

## Build / Programming

- dense information
- fixture selection
- programmer
- palettes/presets
- cues
- patch
- effects
- Inspector
- keyboard-driven workflows

## Perform

- current song/section
- current cue
- next cue
- large GO
- Back/Stop/Blackout as appropriate
- output/MIDI/engine health
- warnings
- touch-friendly targets
- editing locked or strongly restricted

Do not implement Perform Mode as merely "hide a few panels from WorkspaceView."

Give it its own presentation model backed by the same ShowControlController.

---

# 9.3 Build One Shared `PerformanceSnapshot`

macOS Perform Mode and the web/iPad interface should consume the same semantic snapshot.

This prevents two UIs from disagreeing about what is current/next.

Example:

```swift
struct PerformanceSnapshot {
    let projectName: String
    let song: SongSummary?
    let section: String?
    let cueList: CueListSummary?
    let currentCue: CueSummary?
    let nextCue: CueSummary?
    let transition: TransitionSummary
    let engineHealth: HealthState
    let outputHealth: [OutputHealth]
    let inputHealth: [InputHealth]
    let warnings: [OperatorWarning]
}
```

Exact types can differ.

The important idea is semantic separation from raw engine buffers.

---

# 9.4 Build a Central Attribute/Capability Registry

The prototype UI often works with strings such as:

```text
intensity
colorR
colorG
pan
tilt
```

The redesigned Programmer should not be hard-coded around ad hoc string comparisons.

Create stable attribute descriptors:

```text
Attribute ID
Display name
Family
Value type
Normalized/raw range
Physical units/range
Color component semantics
Wheel/capability semantics
8/16-bit mapping
Home/highlight behavior
```

This enables the UI to dynamically show only controls relevant to selected fixtures and gives plugins/mappings the same vocabulary.

---

# 9.5 Build an Action Catalog for MIDI/OSC/Remote/Plugins

The Settings -> MIDI Mapping UI should be data-driven.

Example descriptors:

```text
Action: Playback / GO
Input type: Trigger
Realtime safe: Yes

Action: Programmer / Set Intensity
Input type: Normalized scalar
Realtime safe: Yes
Parameters: fixture/group target

Action: Song / Next Entry
Input type: Trigger
Realtime safe: Yes
```

The same catalog will later make plugin/data-source automation much easier.

---

# 9.6 Define Settings Scope Explicitly

Before creating the polished Settings window, classify settings into:

## Application-global

Likely examples:

- appearance
- default workspace
- CoreMIDI device preferences
- RTP-MIDI host defaults
- logging preferences
- general app behavior

## Project/show-scoped

Likely examples:

- MIDI mappings used by the show
- output/universe routes
- cue defaults
- song/set data
- project remote-control policy if desired

## Workspace-local

Likely examples:

- panel sizes/visibility
- Inspector tab
- Build vs Perform layout
- selected monitor view

Avoid accidentally embedding personal UI layout into a show file unless that is explicitly desired.

---

# 9.7 Named Workspaces Should Replace the Current Prototype Layout Assumption

The approved UI concept benefits from named workspace modes such as:

```text
Programming
Patch
Cue Editing
Effects
Diagnostics
Perform
Custom 1
Custom 2
```

Persist panel IDs/geometry/visibility independently from core show logic.

The current `workspaceLayoutId` is not enough by itself and appears underused.

---

# 9.8 Keep Engine Frames Out of General SwiftUI State

Do not publish 512-byte universe arrays through a giant global ObservableObject at engine rate.

Instead:

- publish lightweight semantic playback state for general UI,
- provide a dedicated Universe Monitor stream for detailed channel data,
- throttle/copy detailed data only when the monitor is visible,
- publish diagnostics/performance separately.

This keeps the future UI smooth without coupling SwiftUI redraw cadence to DMX frame cadence.

---

# 9.9 Design Status Dots Around Verified Health, Not Configuration

The visual concept includes quiet status indicators such as:

```text
ENGINE   DMX   MIDI   NETWORK
```

Backend status APIs must support real meaning.

Example:

```text
Green  = verified operational
Yellow = degraded/reconnecting/warning
Red    = failed/offline when expected
Gray   = disabled/not configured
```

Do not make "driver object exists" turn the DMX dot green.

---

# 9.10 Do Not Put MIDI Mappings in the Main Workspace

Preserve the LightKey-inspired behavior the product owner explicitly prefers.

MIDI mappings, RTP-MIDI sessions, output network configuration, remote access, plugins, and similar occasional configuration belong in Settings or focused configuration sheets/popovers.

The main workspace should expose status and fast access, not the entire configuration matrix.

---

# 10. Recommended Fix Order

## Stage A: Clear P0

Do these before starting the UI redesign:

1. Dirty-state branch/save-point identity
2. True Save As asset/layout preservation
3. Preserve active playback across normal project edits
4. Correct 16-bit coarse/fine output
5. Required project-package file enforcement

After Stage A, run the entire macOS test suite and add explicit regression coverage for every item.

---

## Stage B: UI Gate Domain Semantics

Before visual implementation, complete:

1. Cue fade-out/loop semantics
2. Fixture capability/inversion/highlight/wheel semantics
3. Song Mode runtime/domain completion
4. Persistent effects + explicit ordering
5. Ordered fixture selection
6. MIDI velocity/value semantics
7. MIDI one-vs-many mapping decision
8. MIDI `data2` semantics
9. Unified ShowActionDispatcher + action catalog
10. Output routing model
11. ProjectValidator service/cached validation
12. Compiled engine show state
13. Group membership single source of truth
14. Palette/preset recording semantics

These are the contracts the new UI will display.

---

## Stage C: UI State Architecture

Then refactor presentation ownership:

1. Thin `AppModel` into composition root
2. Project/Document store
3. ShowControl/Performance store
4. Input controller
5. Output controller
6. Remote controller
7. Diagnostics controller
8. Workspace controller
9. Settings scope/store
10. Remove manual revision/bump invalidation
11. Create shared `PerformanceSnapshot`
12. Create dedicated monitor streams

At the end of Stage C, Aurora is ready for the visual design implementation.

---

## Stage D: Begin Aurora UI Redesign

Only now implement the approved visual direction:

- dark charcoal professional macOS workspace
- restrained Aurora cyan/violet accents
- Fixture/Group Browser on left
- large central Programmer
- visual palette/preset shelves
- context Inspector on right
- Cue List / Song controls
- stage/output visualization
- quiet verified status indicators
- Settings for configuration complexity
- separate Build and Perform modes
- shared web/iPad performance model

The UI should consume the stable APIs above instead of reaching directly into engine/output/MIDI internals.

---

## Stage E: Parallel P2/P3 Hardening

Continue:

- network remote lifecycle/security
- CoreMIDI hotplug/running status
- output concurrency/health/sequence
- diagnostics integration
- performance metrics
- migration framework
- autosave/recovery
- ENTTEC driver
- physical Art-Net/sACN testing
- plugin SDK groundwork

---

# 11. Regression Test Plan to Add Now

At minimum, create dedicated tests for the following.

## Document/Persistence

- dirty state branch collision
- coalescing across save boundary prohibited
- true Save As preserves source media/layouts
- missing required package file fails load
- backup/temp recovery behavior
- schema v1 golden package remains loadable

## Engine/Playback

- project metadata edit does not reset active cue
- MIDI-mapping edit does not reset active cue
- inactive cue edit does not reset stage
- palette edit of active cue has documented behavior
- fadeOut semantics
- loop semantics
- Song Mode list switch and current/next identity

## Fixture/DMX

- 16-bit coarse/fine exact bytes
- pan inversion
- tilt inversion
- highlight values from personality
- home/locate values
- wheel-slot output
- invalid fixture footprint rejected

## MIDI/Actions

- Note On velocity -> normalized parameter
- CC -> normalized parameter
- multiple matching mappings if supported
- active cue-list fire-by-index
- identical mapping behavior from MIDI/OSC/web/UI through one dispatcher
- device hotplug removal/reconnect

## Effects

- persistent round trip
- explicit ordering
- stable fixture phase order
- cue-linked effect restore after reopen

## Output

- protocol/output route filtering
- mirrored route
- multi-universe sequence counters
- driver start failure visible
- driver restart failure visible
- short buffer clears stale tail

## Remote

- bind-policy behavior
- repeated browser reload does not exhaust clients
- inactive session expiry
- oversized unterminated HTTP header is disconnected
- oversized unterminated TCP command is disconnected
- partial startup rollback
- snapshot resolves exact current list/cue/song

## Performance

- 2,000 fixtures
- multiple definitions
- multiple universes
- 500 cues
- continuous MIDI
- active effects/programmer
- p95/p99 frame metrics

---

# 12. Things I Would Explicitly Not Rewrite

The review found problems, but the following architectural choices remain good and should be preserved.

## Module separation

The existing `AuroraModel`, `AuroraCore`, `AuroraEngine`, `AuroraMIDI`, `AuroraOutput`, `AuroraFixtureLib`, `AuroraDiagnostics`, `AuroraUI`, remote/plugin modules, and app target remain a good foundation.

## OutputDriver abstraction

Keep protocol-specific/local drivers behind the output abstraction.

## Command-based document mutations

Keep commands/undo as the required path for user document mutations. Fix save-point identity rather than abandoning the pattern.

## Dedicated lighting engine

Keep playback/effects/programmer/merge/output away from SwiftUI.

## Monotonic engine clock / scheduler

Continue to keep timing independent from UI refresh.

## Sparse cue and palette/preset reference concepts

These remain the right data-model direction.

## Built-in control protocol modules

CoreMIDI/RTP-MIDI/OSC separation remains sound.

## Remote control as a client of the show-control layer

Keep remote UI outside the engine. Improve its shared action/performance snapshot interfaces.

## Diagnostics as a first-class subsystem

Expand it rather than deleting/replacing it.

---

# 13. UI Redesign Go/No-Go Checklist

I would consider Aurora ready to enter full UI implementation when all of the following are true.

## Must be YES

- [ ] Dirty state cannot falsely become clean after history branching.
- [ ] Save As preserves all package assets/layouts.
- [ ] Ordinary project edits cannot reset active playback.
- [ ] 16-bit fixture channels output correctly.
- [ ] Required package corruption is detected rather than silently interpreted as empty content.
- [ ] Cue controls exposed by UI have real runtime semantics.
- [ ] Song Mode current/next state is stable and well-defined.
- [ ] Effects intended for show programming persist and have explicit order semantics.
- [ ] Fixture selection order semantics are defined.
- [ ] MIDI Note velocity/value mappings work.
- [ ] All control surfaces use one show-action dispatcher.
- [ ] Output routing semantics are real and tested.
- [ ] Project validation is comprehensive and not performed repeatedly on the engine hot path.
- [ ] Engine uses a compiled/runtime-ready project representation for critical frame work.
- [ ] Group membership has one authoritative truth.
- [ ] Palette/preset record/apply behavior is deterministic.
- [ ] UI no longer needs a giant global manual revision bump to observe normal state.
- [ ] `AppModel` has been reduced to a composition/root role or equivalent clean ownership structure.
- [ ] A shared performance presentation snapshot exists for Mac and remote interfaces.

## Can still be in progress during UI work

- [ ] Full dynamic third-party plugin loading
- [ ] TLS for remote web control
- [ ] native iPad app
- [ ] complete GDTF coverage
- [ ] advanced timeline editor
- [ ] full production autosave/version browser
- [ ] final ENTTEC hardware integration, if UI can use mock/null/local route descriptors first
- [ ] every performance optimization beyond demonstrated target headroom

---

# 14. Suggested Grok Instruction

The following can be given to Grok together with this document:

> Treat this document as a post-remediation architecture and correctness review, not as a request for a broad rewrite. Preserve Aurora's existing modular architecture. Work in priority order. Fix and commit each logical issue independently, with regression tests. Complete all P0 items first. Then complete all findings marked UI GATE before beginning the visual UI redesign. Do not implement UI controls for model fields whose runtime semantics remain incomplete. Do not trade deterministic live-show behavior for speed of implementation. After the UI Gate is complete, stop and produce a concise handoff describing changed APIs/state ownership so the UI specification can be written against the final backend architecture.

---

# 15. Final Assessment

The post-review repository is significantly healthier than the version examined in the first audit.

The first remediation pass removed several obvious hazards. This second review is therefore more demanding: it is concerned with whether Aurora behaves correctly at boundaries that matter in a real show and whether its model/state architecture can support a sophisticated professional UI without creating a second layer of technical debt.

The answer is **yes, with another focused hardening pass**.

The core is worth keeping.

The highest-value next work is not another large feature sprint. It is to make the existing domain model truthful and deterministic:

```text
Project edits must not unexpectedly change the live stage.
Saved must really mean saved.
Fixture semantics must produce the correct bytes.
Every visible cue/effect/song control must actually work.
Every control surface must speak the same action language.
The UI must observe focused state instead of one giant application object.
```

Once those conditions are met, Aurora will be in an excellent position for the planned interface redesign.

At that point the UI work can be treated as a product-design project rather than a rescue operation around backend inconsistencies, which is exactly where we want to be.

---

# 16. Condensed Priority List

For quick reference:

## P0

1. Dirty/save-point branch collision
2. True Save As asset/layout loss
3. Project mutation resets live playback
4. Incorrect 16-bit coarse/fine DMX compilation
5. Missing core package files silently become empty collections

## P1 / UI Gate

1. Implement real fadeOut/loop semantics
2. Complete fixture inversion/highlight/home/wheel/capability semantics
3. Complete Song Mode domain/runtime state
4. Persist effects and define ordering
5. Preserve explicit fixture selection order
6. Use Note velocity/other MIDI scalar values in mappings
7. Decide/implement one-to-many MIDI mappings
8. Define/remove `MIDIMapping.data2`
9. Unify ShowActionDispatcher/action catalog
10. Implement real universe/output routing
11. Build comprehensive cached ProjectValidator
12. Compile editable project into engine runtime state
13. Remove duplicate group-membership truth
14. Define deterministic palette/preset recording/apply semantics
15. Split AppModel / create granular observable UI state

## P2

1. MIDI hotplug reconciliation
2. MIDI running-status state
3. Per-universe Art-Net/sACN sequences
4. Output-driver concurrency audit
5. Stop suppressing output restart errors
6. First-class output health
7. DMX buffer resize/tail clearing
8. Save crash-recovery window
9. Schema migration infrastructure
10. Safe patch arithmetic
11. Enforce remote bind policy
12. Web session expiry/reuse
13. Pre-delimiter remote buffer limits
14. Transactional remote startup
15. Move OSC/remote live actions off MainActor
16. Correct multi-list/multi-universe remote snapshot
17. Integrate DiagnosticsStore across subsystems
18. Add p95/p99/overrun metrics
19. Profile/reuse engine frame buffers
20. Remove silent UI `try?`
21. Normalize `modifiedAt` ownership
22. Audit dead/unused preferences before Settings UI

## P3

1. ENTTEC/local physical DMX driver
2. Real Art-Net/sACN hardware soak tests
3. Proper macOS document/app packaging + recovery/autosave
4. Dynamic plugin runtime after internal APIs stabilize

