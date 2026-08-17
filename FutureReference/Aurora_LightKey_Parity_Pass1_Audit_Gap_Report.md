# Aurora LightKey-Parity Pass 1 Audit
## Gap Report and Required Remediation Before Final Pre-Hardware Review

**Audit target:** `Aurora_LightKeyParityPass1.zip`  
**Date:** 2026-08-13  
**Purpose:** Evaluate the first implementation pass against the approved Aurora LightKey-parity roadmap, its amendments, and the companion 2D Stage Designer / Advanced MIDI specification.  
**Primary rule:** A feature is not considered implemented merely because a model, panel, enum, or placeholder exists. The roadmap's observable acceptance criteria define completion.

---

# 1. Executive Verdict

## PARITY PASS 1: NOT COMPLETE

Aurora has gained useful foundations in this pass, but it has **not reached the approved pre-smoke-test LightKey-parity gate**.

The current `UIDesignReferences/Lightkey_Parity_Matrix.md` is directionally honest in marking several items Partial/Missing, but even that matrix is optimistic in some important places.

The strongest pattern in this pass is:

> **Model/scaffold created → feature labeled Partial → operator workflow and acceptance gate still missing.**

That is acceptable for an implementation wave, but it is **not acceptable as the final parity implementation**.

The largest blockers are:

1. **2D Stage Preview is architecturally divergent from live playback output and the editor is incomplete.**
2. **Fixture Profile Editor is completely missing.**
3. **Multi-cell/pixel fixtures have a model/footprint foundation but are not compiled/programmed/effected/previewed as cells.**
4. **Advanced MIDI is mostly unimplemented. `MIDIRule` exists as an unused/unpersisted model scaffold.**
5. **Outbound MIDI feedback is absent.**
6. **Unified External Control diagnostics are absent.**
7. **Portable Aurora Library / cross-show asset import-export is absent.**
8. **Programmer still does not provide practical Beam, Shutter/Strobe, or generic/raw parameter control.**
9. **Effects are still a narrow pulse/chase/wave/rainbow baseline and do not satisfy the required practical effect families/controls.**
10. **Patch workflow remains incomplete for a parity gate.**
11. **Output diagnostics exist only partially; fixture/channel semantic attribution and surfaced fixture-health workflow remain incomplete.**
12. **Cue workflow is improved but still lacks several parity requirements such as reorder/duplicate/full timing metadata editing.**
13. **Web remote still lacks required Master/Blackout baseline.**
14. **Custom keyboard shortcuts are explicitly not implemented.**
15. **Formal Wave 9 parity verification has not occurred and cannot pass in the current state.**

## Recommendation

Do **not** move directly from this pass into the final top-to-bottom pre-hardware code review as though parity implementation is finished.

Instead:

> **Run a focused Parity Completion Pass using this document as the task list.**

Once every P0 parity line is PASS or explicitly accepted/deferred according to the approved roadmap, then perform the final exhaustive code review and controlled hardware smoke test.

---

# 2. Sources of Truth Used for This Audit

The implementation was audited against:

```text
FutureReference/
  Aurora_Lightkey_Parity_Pre_Smoke_Test_Roadmap.md
  Aurora_Lightkey_Parity_Plan_Review_Amendments.md
  Aurora_2D_Stage_Designer_and_Advanced_MIDI_Engine_Spec.md

UIDesignReferences/
  Lightkey_Parity_Matrix.md

Current Aurora source and tests
```

The roadmap, amendments, and companion specification take precedence over implementation comments such as:

```text
"baseline"
"foundation"
"P0-A"
"parity"
```

A source-code comment claiming a requirement does not satisfy that requirement.

---

# 3. Corrected Parity Matrix

The following matrix reflects the audited implementation rather than intended ownership.

| ID | Requirement | Audited Status | Key Reason |
|---|---|---:|---|
| P0-A | 2D Stage Designer / Live Preview | **FAIL / Partial foundation** | Preview omits real playback path; editor missing major tools |
| P0-B | Fixture Profile Editor | **FAIL / Missing** | No editor UI or user fixture library workflow |
| P0-B+ | Generic/raw fixture parameters | **FAIL / Partial model only** | Model exists; no profile editor and no practical Programmer UI |
| A1 / P0 pixel | Multi-cell fixtures | **FAIL / Partial model only** | Footprint model exists; no runtime cell expansion/selection/programming/effects/preview |
| P0-C | Patch / rig management | **PARTIAL** | Repatch/clone/report exist; renumber/bulk create/profile reassignment/import/export file workflow incomplete |
| P0-D | Programmer completeness | **PARTIAL** | Intensity/color/position strong; Beam/Strobe/Generic absent |
| P0-E | Palettes/presets + portable library | **PARTIAL** | Local palette/look workflow exists; no search/hierarchy/portable library |
| P0-F | Cue lists/playback | **PARTIAL+** | Core playback good; authoring lacks reorder/duplicate/full timing/follow editing |
| P0-G | Effects baseline | **PARTIAL** | Only pulse/chase/wave/rainbow; missing practical controls/families |
| P0-H | Song Mode | **PARTIAL+** | Baseline exists; limited target types and no advanced MIDI context pipeline |
| P0-I | Global live controls | **PARTIAL+** | Master/Blackout/Freeze/Blind/Panic exist; Clear Overrides/MIDI disable UX incomplete; Master semantics need RGB+dimmer audit |
| P0-J | Advanced MIDI | **FAIL / foundation only** | No rule runtime, behaviors, envelopes, expressive MIDI, feedback, drum profiles, safety engine |
| P0-K | Unified External Control | **FAIL / Missing** | No unified event/action monitor |
| P0-L | Output diagnostics | **PARTIAL** | Basic health + raw universe monitor; semantic attribution/recovery visibility incomplete |
| P0-L+ | Fixture health | **FAIL / dead-end foundation** | `FixtureHealth` exists but is not wired to operator UI |
| P0-M | Persistence/recovery | **PARTIAL+** | Existing project persistence strong; advanced MIDI/library assets not persisted because they do not exist in project model |
| A5 | Preview↔Output parity tests | **FAIL** | Existing test does not exercise actual authoritative live preview path |
| A6 / Wave 9 | Formal parity verification | **FAIL / Not run** | Current matrix contains Partial/Missing items |
| P1-A amended | Pixel/matrix practical support | **FAIL** | Model footprint only |
| P1-B | Custom keyboard shortcuts | **FAIL / Missing** | Settings explicitly says not implemented |
| P1-C | OSC completeness | **PARTIAL** | UDP dispatch exists; monitor/mapping/docs/discovery incomplete |
| P1-D | Web Remote baseline | **PARTIAL** | Current/Next/GO/Back/Stop exist; required Master/Blackout absent |

---

# 4. P0-A BLOCKER — Stage Preview Does Not Observe the Actual Resolved Playback Path

This is the most important Stage finding.

## Current path

`Sources/Aurora/AppModel.swift` builds the Stage preview approximately as:

```text
Engine current frame snapshot
        ↓
throw away semantic playback state
        ↓
ActiveLook()          <-- EMPTY PLAYBACK LOOK
        ↓
effects.apply(...)
        ↓
programmer.apply(...)
        ↓
GlobalShowControl.applyToLook(...)
        ↓
StagePreviewBuilder
```

The relevant code explicitly starts with:

```swift
let playbackLook = ActiveLook()
```

This is **not** the actual engine-resolved playback look.

The real engine frame path in `LightingEngine.processFrame()` is:

```text
playback.look(at:)
or manual look
        ↓
effects
        ↓
programmer
        ↓
global show controls
        ↓
DMX merge
        ↓
Freeze handling
        ↓
physical output
```

Therefore the current Stage preview can diverge from the actual show.

## Concrete consequences

### Cue playback

A cue running in `PlaybackController` can change the physical DMX output while the Stage preview omits that cue because it starts from `ActiveLook()`.

### Cue transitions

Fade interpolation from the playback engine is not represented through the same semantic authority.

### Freeze

Physical output holds `frozenLevels`.

The Stage preview rebuilds a fresh semantic look and merely receives:

```text
freeze = true
```

It does not consume the actual frozen semantic presentation.

The preview can therefore display live changes underneath a Freeze state while the physical output remains held.

### Manual look

The engine supports `manualLook`.

The Stage reconstruction does not use the engine's actual manual/playback resolved semantic look.

### Future MIDI behaviors

Any behavior affecting a layer other than the current simple Programmer path can diverge from Stage.

---

# 5. Required Stage Architecture Fix

The engine needs a semantic resolved presentation snapshot produced from the **same frame evaluation** that produces DMX.

Do not reconstruct the frame in `AppModel`.

Recommended conceptual architecture:

```text
Playback / Manual Look
        ↓
Effects
        ↓
Programmer
        ↓
Global Show Controls
        ↓
Freeze semantic presentation
        ↓
RESOLVED SEMANTIC FRAME
        ├───────────────┐
        ↓               ↓
DMX Merge         StagePreviewSnapshot
        ↓               ↓
Output            Stage UI
```

Possible structure:

```swift
struct ResolvedShowSnapshot {
    var frameIndex: UInt64
    var timestamp: TimeInterval
    var look: ActiveLook
    var playback: PlaybackSnapshot
    var global: GlobalShowControlState
}
```

Names/ownership should follow current Aurora conventions.

The important requirement is:

> **Stage Preview must consume the engine's authoritative resolved semantic frame, not re-run a similar-looking pipeline from the app layer.**

---

# 6. Existing Stage "Parity Test" Is Not a True Parity Test

`Tests/AuroraEngineTests/StagePreviewParityTests.swift` currently:

1. sets Programmer values,
2. steps the engine,
3. inspects DMX,
4. manually rebuilds an ActiveLook from the Programmer,
5. passes that reconstructed look into `StagePreviewBuilder`.

This proves only that:

```text
Programmer value
```

can produce both expected DMX and expected preview values under a narrow case.

It does **not** prove that Stage Preview observes the actual engine frame.

## Required A5 tests

Add tests covering the real presentation path:

```text
Cue playback
Cue fade transition
Effect
Programmer
MIDI-driven action/behavior
Master
Blackout
Freeze
Manual jump
```

For a known fixture state, assert that:

```text
same authoritative resolved semantic state
        ↓
Preview state
        +
DMX state
```

remain consistent.

Freeze needs a dedicated test proving Stage holds the same appearance as physical output.

---

# 7. P0-A — Stage Designer UI Is Far Below the Approved Acceptance Gate

The current `StagePanel` is a useful proof of concept, but it is not the required designer.

## Present

- persisted `StageLayout`
- fixture X/Y
- rotation/scale fields in model
- Edit/Live mode
- simple drag placement
- grid
- snap-to-grid during drag
- labels
- basic scenic rectangles
- basic zoom scale / fit state
- Live-mode pan
- fixture selection
- live intensity/color circles
- dominant color background
- preview pan/tilt values exist in snapshot

## Missing or materially incomplete

### Multi-selection editing

Stage tap currently selects one fixture:

```swift
onSelectFixtures([place.fixtureID])
```

No command/shift multi-select Stage workflow exists.

### Align / distribute

Not implemented.

### Rotation editing

Rotation exists in the model but there is no practical UI for rotating selected fixtures.

### Scale editing

Scale exists in the model but no useful edit control exists.

### Scenic object authoring

The model can hold scenic objects, but the Stage UI does not provide a real add/edit/remove workflow.

### Regions

No meaningful semantic region editing or group association workflow.

### Layer ordering

`zIndex` exists but editing is absent.

### Lock/hide

Absent.

### Zoom controls

There is no proper zoom UI.

The current Fit button resets:

```text
scale = 1
pan = 0
```

rather than using the actual `fit(in:)` calculation again.

### Pan behavior

Panning exists only in Live mode and uses incremental translation math that should be reviewed for gesture correctness.

### Fixture categories/symbols

Every fixture renders as a circle.

Required broad categories are not visually represented:

```text
PAR/wash
bar
moving head
spot/profile
blinder
strobe
laser
fog
haze
generic
```

### Beam visualization

Absent.

### Moving-head orientation

Pan/tilt values are captured in `FixturePreviewState`, but the Stage panel does not render moving-head direction/beam.

### Strobe visualization

No `StrobePreviewState`; no visualization.

### Offline/error state

No fixture health integration.

### Bidirectional selection

Stage → fixture selection works in a basic single-selection form.

Fixture Browser → Stage selection highlight can work through shared selection state.

But full group/multi-select semantics are not complete.

### First-class workspace treatment

Stage is currently a left-column tool:

```text
Browser | Patch | Groups | Stage
```

The specification explicitly says:

> Do not cram the designer into a small panel. Treat it as a first-class workspace or substantial workspace surface.

This discoverability/layout choice is not acceptable for the final P0-A implementation.

---

# 8. Required P0-A Completion Definition

Do not mark Stage PASS until an operator can:

```text
Open Stage workspace
Place fixtures
Multi-select
Move
Rotate
Scale
Align
Distribute
Use grid/snap
Zoom/pan/fit
Add/edit scenic objects
Use labels/regions
Save/reopen
Switch to Live
Select fixtures/groups bidirectionally
Run cues
Run effects
Trigger MIDI accent
Observe intensity/color
Observe moving-head direction
Observe useful beams
Observe Blackout/Master/Freeze correctly
Observe smooth dominant background
```

with no physical fixtures connected.

That is the approved acceptance gate.

---

# 9. P0-B BLOCKER — Fixture Profile Editor Is Missing

There is no first-class Fixture Profile Editor.

The repository contains useful new model foundations:

```text
DMXFunctionRange
ChannelSemanticKind.generic
FixtureCellBlock
category
fixture wheels
pan/tilt metadata
```

but there is no operator workflow to create or repair fixture definitions.

This is a direct smoke-test blocker because canonical Scenario 1 requires:

> Create one missing fixture profile in Aurora.

The current implementation cannot do that.

---

# 10. Required Fixture Profile Editor

Implement a real editor covering the roadmap's required fields:

```text
Manufacturer
Model
Category
Mode name
Channel footprint
Coarse/fine pairing
Semantic assignment
Generic/raw assignment
Default
Highlight
DMX function ranges
Color emitters
Color wheels/slots
Gobo wheels/slots
Pan range
Tilt range
Beam attributes
Shutter/strobe ranges
Mode variants
```

Validation must include:

```text
overlap
gaps
invalid offsets
invalid ranges
bad fine/coarse relationships
footprint mismatch
cell block errors
wheel-slot errors
```

Required workflow:

```text
New / Open Fixture Profile
        ↓
Edit
        ↓
Validate
        ↓
Test selected parameter safely
        ↓
Save to User Fixture Library
```

The test path must still route through Aurora's controlled engine/output authority.

---

# 11. P0-B+ — Generic/Raw Parameters Are Only a Model Escape Hatch

`ChannelSemanticKind.generic` and `DMXFunctionRange` are a good foundation.

They do not satisfy the amendment by themselves.

Missing:

- Fixture Profile Editor authoring
- named generic controls in Programmer
- range/function selection
- Inspector visibility
- safe test mode
- migration/replacement path when a future semantic type is added

Required outcome:

> An unusual fixture parameter must be operable without changing Aurora source code.

That is not true today.

---

# 12. MULTI-CELL BLOCKER — FixtureCellBlock Is Not a Runtime Cell System

The amended roadmap moved practical multi-cell support into the pre-smoke baseline.

Current implementation provides:

```text
FixtureCellBlock
cellCount
channelsPerCell
calculated footprint
```

and a footprint test.

That is not sufficient.

## Critical runtime gap

`CompiledShow.compileAttributeWrites(definition:)` iterates only:

```swift
definition.channels
```

It does not expand:

```swift
definition.cellBlock
```

into runtime DMX writes.

The engine therefore understands the **footprint size** of a cell fixture for patching but does not compile the repeated cell parameters into controllable output semantics.

This is a major distinction.

Aurora can reserve 72 channels for a 24-cell RGB bar without actually knowing how to control those 72 channels as 24 cells.

---

# 13. Required Multi-Cell Completion

Implement:

- runtime expansion of repeated cell blocks
- stable cell identity
- whole-fixture selection
- individual cell selection
- per-cell semantic values
- Programmer targeting
- effect targeting
- Stage Preview representation
- Fixture Profile Editor cell authoring
- persistence
- output tests

Do not require full video/pixel mapping.

But an ordinary multi-cell batten must be modelable, patchable, selectable, programmable, effected, previewed, and output correctly.

---

# 14. P0-C — Patch / Rig Management Is Still Partial

The patch system has improved materially.

## Implemented

- multiple universes
- universe selection
- address display
- next-free-address helpers
- collision detection
- footprint validation
- clone fixture
- repatch
- atomic bulk offset repatch
- search
- sort
- issues display
- human-readable patch report
- CSV data generation
- route footer/status
- undoable command paths for several operations

## Missing / incomplete relative to parity

- fixture renumbering
- bulk fixture creation workflow
- richer batch edit
- profile/mode reassignment with explicit conflict handling
- mature group creation/editing from Patch workflow
- favorites/fast-access equivalent
- CSV/TSV patch **import**
- real file export UX for CSV/TSV
- printable/exportable patch sheet workflow
- clearer universe labeling/routing management within Patch
- full atomic batch operations for all destructive patch workflows

`PatchReport.csv()` existing in Core does not alone satisfy "operator can export patch CSV."

A usable file/export workflow must exist.

---

# 15. P0-D — Programmer Is Stronger, But Not Complete

UI-03 work significantly improved Programmer truthfulness.

## Strong

- ordered selection
- Intensity
- RGB-family color
- Position
- technical color channels for known supported attributes
- mixed state
- partial support
- Clear selection
- Clear All
- Fan
- Align
- Locate
- Highlight
- Blind
- Home
- capability-aware multi-selection

## Missing parity categories

- Beam control
- Shutter/Strobe control
- Gobo/wheel control
- generic/raw fixture parameter controls
- practical fixture-specific semantic parameter control
- clear individual-attribute removal workflow across all families
- explicit fine/coarse position editing UX
- complete capture/store flow for every claimed parameter family

A fixture whose important feature is:

```text
Gobo
Prism
Iris
Zoom
Focus
Shutter
Strobe
Macro
Generic channel function
```

cannot currently be considered fully programmable through Aurora's semantic Programmer.

Do not mark P0-D PASS until claimed fixture semantics have practical controls.

---

# 16. P0-E — Palettes/Presets Work Locally but the Library Requirement Is Missing

The local show palette/preset workflow is one of the stronger areas.

## Implemented

- intensity palette creation
- color palette creation
- position palette creation
- looks/presets
- stable UUIDs
- cue palette references
- apply
- create from Programmer
- delete with reference warning
- Record Ref to Cue
- visual tiles
- broken-reference validation

## Missing

- Beam palette authoring from actual Beam Programmer values
- richer rename/edit/duplicate workflow
- Search
- organization/grouping
- folders/nested hierarchy or equivalent
- portable cross-show Aurora Library
- import/export packages
- unresolved-target reconciliation UI

The roadmap requires reusable assets to move between shows.

There is currently no portable library architecture implementing:

```text
fixture profiles
palettes
presets/looks
effects
MIDI mappings
MIDI behaviors
device/drum profiles
```

Therefore P0-E cannot pass.

---

# 17. P0-F — Cue Playback Core Is Good; Authoring Is Still Incomplete

The playback engine is one of Aurora's stronger subsystems.

Implemented engine behavior includes:

- GO
- Back
- Fire
- fade in/out
- delay
- follow modes
- loop
- tracking/cue-only
- stable cue identity across edits
- deterministic cue playback

The UI now supports:

- list create/delete
- cue create/delete
- Record
- Update from Programmer
- Fire
- single-click select
- double-click fire

## Missing parity authoring workflow

- reorder cues
- duplicate/copy cue
- practical cue-number editing
- cue-name editing in main workflow
- fade-in editing
- fade-out editing
- delay editing
- follow mode/time editing
- loop editing
- notes/metadata editing

The model/engine having the fields is not enough.

A parity-complete operator must be able to author them.

---

# 18. P0-G — Effects Are a Baseline, Not Practical Parity Yet

Current built-in kinds:

```text
pulse
chase
wave
rainbow
```

Current durable fields:

```text
rate
size
phase
spread
attribute
ordered fixture IDs
enabled
order
```

The current Effects UI exposes mainly:

```text
kind
attribute text
rate
size
start/remove/clear
```

## Missing relative to roadmap

- proper Color effect family controls beyond Rainbow
- Position/movement effects as a first-class useful workflow
- Beam-related effects
- user-editable phase/spread
- direction
- offset
- richer start/stop/edit existing workflow
- reusable effect presets/library
- strong cue integration authoring
- multi-cell effect targeting
- explicit blend/precedence controls beyond fixed apply order
- capability-aware effect creation

A generic text field containing `"pan"` plus a sine wave is not yet a polished movement-effect workflow.

---

# 19. P0-H — Song Mode Is a Good Baseline but Not Full Parity Integration

Song Mode correctly remains an orchestration layer over cue playback.

Strong areas:

- persisted Song
- ordered entries
- labels that can represent Intro/Verse/Chorus/etc.
- cue/cue-list references
- current/next
- manual progression
- stable cursor reconciliation
- Perform presentation

Gaps:

- Song entry target types are limited to cue/cue-list
- direct look/behavior association from the roadmap is not implemented
- MIDI contextual rules do not actually consume Song/Section because the advanced rule engine is not implemented
- automatic progression remains intentionally deferred/unimplemented, which is acceptable if not claimed

P0-H can become PASS when the advanced MIDI context hook is real and the final chosen Song baseline is explicitly documented.

---

# 20. P0-I — Global Live Controls Are Mostly Real, With Remaining Gaps

Implemented engine/UI controls include:

```text
Master Intensity
Blackout
Freeze
Blind
Panic
MIDI performance state in engine
```

Freeze semantics are documented and tested for dimmer behavior.

## Missing / incomplete

### Clear Overrides

The roadmap explicitly requires:

```text
CLEAR OVERRIDES
```

There is no clear first-class global control with defined semantics separate from Panic.

### MIDI Performance Enable/Disable UI

Engine/action support exists, but Perform UI does not visibly expose this as a normal global show control.

### Safe Look

Optional according to the approved roadmap if architecture is not ready, so it may remain accepted deferred.

---

# 21. P0-I — Audit Master Intensity With RGB + Dedicated Dimmer Fixtures

This is a parity/safety correctness item worth testing before hardware.

`GlobalShowControl.applyToLook()` currently considers both:

```text
intensity/dimmer
and
colorR/colorG/colorB/etc.
```

to be "intensity-like."

For a fixture that has both:

```text
RGB channels
+
master dimmer channel
```

Master may scale both the RGB emitter levels and the fixture dimmer.

Depending on the fixture's physical semantics, this can effectively apply Master twice to apparent brightness.

Existing tests use a one-channel dimmer and do not cover:

```text
RGB + dimmer
RGBW + dimmer
color-only fixture
```

Before declaring P0-I PASS, define and test the intended master model:

- preserve chromatic ratios,
- avoid double attenuation where a true intensity/dimmer semantic exists,
- still scale color-only additive fixtures appropriately.

This should be verified before tomorrow's real-light test.

---

# 22. P0-J BLOCKER — Advanced MIDI Performance Engine Is Not Implemented

This is the other largest parity gap.

The repository now contains:

```swift
struct MIDIRule
```

but `MIDIRule` is not meaningfully integrated.

Search of the runtime implementation shows no rule-engine use outside the type itself.

It is also not persisted in `ShowProject`.

Current show persistence still stores:

```text
midiMappings
```

not advanced rules/behaviors/device profiles/feedback profiles.

---

# 23. MIDI Event Baseline Is Still Too Narrow

`MIDIEvent` currently supports:

```text
Note On
Note Off
Control Change
Program Change
```

Missing required rich events include:

- Pitch Bend
- Channel Pressure / Aftertouch
- Poly Pressure
- richer expressive event representation
- future-friendly normalized metadata path

Timestamp is also not preserved on `MIDIEvent`.

This does not satisfy the companion Advanced MIDI specification.

---

# 24. MIDIRule Is a Scaffold, Not an Engine

The current `MIDIRule` type has:

- priority
- device
- channel
- message type
- data ranges
- action keys
- action parameters
- optional song-section string

But missing runtime systems include:

- rule resolver
- context evaluation
- priority arbitration
- reusable Behavior model
- safety constraints
- blending
- envelopes
- modulation
- concurrent behavior lifetime
- behavior cancellation
- persisted rule/behavior storage

Do not mark Advanced MIDI Partial-complete merely because this struct exists.

---

# 25. Missing Advanced MIDI Behavior Features

Required but absent:

```text
Reusable behaviors
AHDR/ADSR envelopes
velocity scaling semantics beyond simple scalar action
continuous modulation
smoothing
deadband
input range mapping
relative encoder modes
absolute encoder modes
Pitch Bend
Aftertouch
multiple behavior blending
maximum concurrent behaviors
behavior lifecycle
```

One-to-many `MIDIMapping` actions and Note velocity scalar are useful foundations but are not the Advanced MIDI engine.

---

# 26. Drum-Aware MIDI Is Missing

Required baseline includes:

- device/drum profile
- semantic drum roles
- hardware-note abstraction
- song-context mapping
- reusable drum behaviors

None of these exist as functional persisted systems.

The canonical Electronic Drums smoke scenario cannot be performed.

---

# 27. MIDI Safety Layer Is Missing

Required safety:

```text
rate limiting
debounce
flood protection
stuck-note handling
disconnect handling
maximum behavior concurrency
strobe constraints
panic/reset
global performance MIDI disable
```

Panic and global MIDI enable exist at the show-control layer.

The rest is not an Advanced MIDI safety engine.

Given Aurora's intended drum-triggered lighting use, flood/rate/concurrency controls are not optional polish.

---

# 28. MIDI Feedback Is Completely Missing

No outbound CoreMIDI feedback path was found.

Missing required capabilities:

```text
Note/velocity output
CC output
LED state
14-bit feedback
encoder rings
motorized controls
device feedback profiles
feedback loop prevention
feedback import/export
reconnect/replay state
```

Canonical MIDI Feedback Scenario 7 cannot be performed.

P0-J cannot pass without this.

---

# 29. MIDI Monitor Is Not the Required Monitor

Current `InputController` maintains a small string log.

`MIDIMappingsPanel` shows simple mappings.

The roadmap requires at minimum:

```text
Timestamp
Source
Channel
Type
Note/CC
Value/velocity
Matched mapping/rule
Triggered action/behavior
Result/error
```

Current string summaries do not provide that structured diagnostic chain.

This also feeds directly into P0-K.

---

# 30. P0-K BLOCKER — Unified External Control Monitor Is Missing

There is no single "why did the lights do that?" surface showing:

```text
MIDI
OSC
Web Remote
Keyboard
future sources
```

with:

```text
event
mapping/rule
action
result/error
```

`DiagnosticsPanel` summarizes subsystem health and recent console lines.

That is not the unified external-control event/action log.

Required P0-K surface should support:

- live structured event rows
- source filter
- event filter
- matched/unmatched visibility
- errors
- mapping enable/disable where applicable
- safe test/invoke
- MIDI feedback rows
- device connection state

---

# 31. P0-L — Output Diagnostics Are Useful but Incomplete

Current strengths:

- Art-Net
- sACN
- Local DMX state
- driver rows
- universe routing diagnostics
- engine frame snapshot
- raw Universe Monitor
- output aggregate health
- reconnect-related infrastructure

## DMX Output Monitor gap

`UniverseMonitorPanel` shows:

```text
channel number
raw value
```

but does not provide the required semantic attribution:

```text
Channel
Value
Fixture
Parameter
```

The amendment explicitly requested ownership attribution where known.

Aurora already has patch/compiled-show information capable of supporting this.

Add read-only attribution such as:

```text
001 255 Front Wash L Intensity
002 128 Front Wash L Red
```

and distinguish unused channels.

---

# 32. Fixture Health Exists in Code but Is Not a User Feature

`Sources/AuroraEngine/FixtureHealth.swift` contains a `FixtureHealth.report()` helper.

No meaningful app/UI integration was found.

Therefore the matrix should not call this implemented.

Required operator-facing workflow should expose per-fixture chain state such as:

```text
Profile
Patch
Universe
Route
Driver
Known/unknown physical state
```

without falsely claiming fixture reachability.

Useful integration locations:

- Fixture Inspector
- Diagnostics
- Patch issue detail

---

# 33. P0-M — Persistence Is Strong for Existing Systems, Incomplete for Parity Systems

Aurora's base project package/persistence work is strong.

Current schema version is now:

```text
2
```

and Stage layout plus new fixture-definition fields have migration/default behavior.

However, the parity systems that are not implemented also cannot be persisted.

Missing persisted concepts include:

```text
Advanced MIDI rules
MIDI behaviors
MIDI feedback profiles
drum/device profiles
portable library packages
stage richer editing metadata if added
cell-level programming semantics when implemented
```

Do not declare P0-M PASS until all actual P0 systems survive save/reopen/migration.

---

# 34. Canonical Complex Test Project Is Still Needed

The roadmap requires test projects exercising together:

```text
multiple universes
fixture families
groups
palettes
effects
cues
songs
stage
MIDI rules
MIDI feedback
external outputs
```

The current demo/test coverage cannot include the missing MIDI/library/profile workflows.

Create a canonical parity project once those systems exist.

It should become the standard pre-hardware regression project.

---

# 35. P1-B — Custom Keyboard Shortcuts Are Missing

The Settings UI explicitly says:

> Full shortcut customization is not implemented.

The parity roadmap classifies this P1, not P0, but it remains a visible non-parity item.

Track as:

```text
DEFERRED / ACCEPTED
```

if intentionally postponed.

Do not let it silently disappear from the Wave 9 matrix.

---

# 36. P1-C — OSC Is a Baseline, Not Complete

Current:

- UDP listener
- fixed port
- stable ShowAction dispatch

Still missing from the requested completeness target:

- structured input monitor
- mapping/action UX beyond fixed parser behavior
- clear published namespace documentation
- richer error visibility
- discovery where practical
- any justified TCP path

This can remain P1 but should be classified honestly.

---

# 37. P1-D — Web Remote Baseline Is Still Missing Required Controls

Current web remote includes:

```text
Current
Next
GO
Back
Stop
connection/auth
```

The roadmap minimum also requires:

```text
Master
Blackout
safe high-level controls
```

Master and Blackout are not present in the current web UI.

Before calling the exposed remote baseline complete, add at least the required safe show-level controls.

---

# 38. Stage Discoverability / Workspace Architecture Must Be Corrected

Even after the Stage editor is completed, it should not remain hidden as a narrow left-column utility.

The companion specification explicitly says Stage is a:

> first-class workspace or substantial workspace surface

Recommended direction:

```text
Build workspace modes / named workspace:
Programmer
Stage
Patch
Song
Diagnostics
```

or an equivalent docking-aware arrangement.

When Stage is active, the canvas should own the main central area.

Fixture Browser and Inspector may remain available around it.

A tiny left-column Stage canvas fails the product intent even if the underlying editor becomes feature-complete.

---

# 39. Corrected Pre-Smoke Canonical Scenario Status

## Scenario 1 — Build a Rig From Scratch

**FAIL**

Blocker:

```text
Create missing fixture profile in Aurora
```

Additional patch gaps remain.

## Scenario 2 — Program a Basic Show

**FAIL / PARTIAL**

Intensity/color/position and local palettes/cues work.

Missing practical Beam programming and effects completeness.

## Scenario 3 — Run the Show

**PARTIAL+**

Core GO/Back/Master/Blackout/Freeze/Blind/Panic are promising.

Need Clear Overrides and Master RGB+dimmer semantic audit.

## Scenario 4 — Stage Preview

**FAIL**

Preview does not observe actual cue playback semantic path.

Editor incomplete.

## Scenario 5 — MIDI Foot Controller

**PARTIAL**

Simple Learn/mapping can work.

Required Monitor depth/reconnect verification still incomplete.

## Scenario 6 — Electronic Drums

**FAIL**

No drum profile, semantic role, envelope behavior, contextual rule engine, or safety engine.

## Scenario 7 — MIDI Feedback

**FAIL**

Outbound feedback missing.

## Scenario 8 — Network / Physical Output

**PARTIAL+**

Good protocol foundations.

Diagnostics/attribution/device-status experience still needs closure.

## Scenario 9 — Reuse Assets

**FAIL**

Portable Aurora Library/import-export system missing.

## Scenario 10 — Failure Recovery

**PARTIAL**

Strong base validation/recovery exists.

Missing fixture-editor/library/MIDI-rule/device-profile failure paths prevent full scenario execution.

---

# 40. Mandatory Parity Completion Order

Do not simply continue adding unrelated features.

Use a dependency-ordered completion program.

---

## Wave P1 — Fix Stage Authoritative-State Architecture

Before beautifying Stage further:

1. Introduce authoritative semantic resolved frame/snapshot in engine.
2. Make physical DMX and Stage derive from that frame.
3. Make Freeze semantic presentation correct.
4. Replace AppModel's reconstructed empty-playback Stage path.
5. Add true parity tests for cue/effect/programmer/master/blackout/freeze.
6. Make Stage a first-class substantial workspace.

This is foundational.

---

## Wave P2 — Complete Fixture Architecture

1. Build Fixture Profile Editor.
2. Build user fixture library.
3. Expose generic/raw parameters.
4. Expand multi-cell definitions into compiled runtime channels.
5. Add cell identity/selection.
6. Add cell Programmer support.
7. Add cell effect targeting.
8. Add cell Stage representation.
9. Add validation/tests.
10. Add safe live profile testing.

Do not move to "parity complete" without this.

---

## Wave P3 — Finish Patch / Programmer / Palette / Cue / Effects Gaps

### Patch

- renumber
- bulk create
- profile/mode reassignment
- import
- file export
- printable patch sheet

### Programmer

- Beam
- Shutter/Strobe
- Gobo/Wheel
- generic/raw parameters
- fine position UX
- clear individual attribute

### Palettes

- Beam creation/use
- rename/edit/duplicate
- search
- hierarchy

### Cue

- reorder
- duplicate
- full cue property editing

### Effects

- real intensity/color/movement/beam families
- phase/spread UI
- direction
- offset
- reusable effect presets
- cue authoring
- multi-cell targeting

---

## Wave P4 — Build Portable Aurora Library

Implement import/export for:

```text
fixture profiles
palettes
looks
effects
MIDI mappings
MIDI behaviors
device/drum profiles
```

Required:

- stable IDs/semantics
- dependency manifest
- target/reference reconciliation
- broken/unresolved target reporting
- no silent corruption

---

## Wave P5 — Implement Advanced MIDI Properly

1. Expand rich MIDI event model:
   - timestamp
   - pitch bend
   - channel pressure
   - poly pressure
2. Persist `MIDIRule`.
3. Build contextual rule resolver.
4. Build reusable Behavior model.
5. Build envelopes.
6. Build velocity scaling.
7. Build CC modulation.
8. Build smoothing/deadband/range mapping.
9. Build encoder modes where practical.
10. Build behavior blending.
11. Build drum/device profiles.
12. Build semantic drum roles.
13. Build song/section context.
14. Build safety controls.
15. Build structured MIDI monitor.

Simple mappings must remain simple.

---

## Wave P6 — MIDI Feedback + Unified External Control

1. CoreMIDI output/destination support.
2. Note/velocity feedback.
3. CC feedback.
4. controller LEDs.
5. feedback profiles.
6. loop prevention.
7. reconnect state replay.
8. 14-bit/encoder support where practical.
9. unified event/action log for MIDI/OSC/Web/Keyboard.
10. mapping/action result/error logging.
11. safe test/invoke.

---

## Wave P7 — Operational Diagnostics Completion

1. semantic DMX channel attribution.
2. surface `FixtureHealth`.
3. fixture/profile/patch/route/driver chain diagnostics.
4. output reconnect/failure UX.
5. finish Web Remote Master/Blackout.
6. close chosen OSC P1 scope.

---

## Wave P8 — Persistence + Canonical Test Project

1. bump schema for newly persisted systems.
2. migrations.
3. round-trip all parity systems.
4. canonical complex parity project.
5. broken-reference tests.
6. missing-device/profile tests.
7. large-show tests.
8. undo/redo verification.

---

## Wave P9 — Formal LightKey-Parity Verification

Do **not** code new product scope here.

Take every final matrix row and classify:

```text
PASS
FAIL
DEFERRED / ACCEPTED
NOT APPLICABLE
```

No `Partial`.

Any P0 line that is not PASS blocks the gate unless explicitly amended/accepted by the project owner.

Produce:

```text
AURORA LIGHTKEY-PARITY GATE: PASSED
```

only when true.

---

# 41. Rules for Grok During Parity Completion

1. Do not count a model type as a completed user feature.
2. Do not count a hidden or inaccessible panel as satisfying a workspace acceptance gate.
3. Do not mark a requirement PASS from comments or filenames.
4. Trace every feature:
   ```text
   Model → Runtime → Control authority → UI → Persistence → Tests
   ```
5. If any required link is absent, classify Partial/Fail.
6. Stage must consume authoritative engine presentation state.
7. Do not reconstruct playback semantics in SwiftUI/AppModel.
8. Do not create parallel lighting engines.
9. Multi-cell must reach actual DMX output, not just footprint math.
10. `MIDIRule` must not remain dead data.
11. Advanced MIDI must remain compatible with simple mapping/Learn.
12. MIDI feedback must avoid feedback loops.
13. External-control traffic must not destabilize engine timing.
14. Do not fake fixture reachability in health diagnostics.
15. Do not hide missing functionality behind "future" if the approved P0 roadmap requires it.
16. Preserve stable IDs and migration discipline.
17. Add tests with each wave.
18. Keep physical output timing higher priority than Stage rendering and diagnostic UI.
19. Do not begin broad smoke testing merely because the app compiles.
20. Run Wave 9 before claiming parity.

---

# 42. Required Updated Parity Matrix Format

Replace the current optimistic matrix with an evidence-based matrix containing:

| ID | Requirement | Status | Model | Runtime | UI | Persistence | Tests | Remaining Gap |
|---|---|---|---|---|---|---|---|---|

Example:

```text
P0-B Fixture Profile Editor
Status: FAIL
Model: FixtureDefinition supports fields
Runtime: N/A
UI: MISSING
Persistence: embedded fixture definitions only
Tests: fixture library tests only
Gap: editor + user library + live test
```

This makes it much harder to accidentally call scaffolding parity.

---

# 43. Required Definition of Done for Every Parity Feature

Before marking a line PASS, answer all applicable questions:

```text
Can the operator find it?
Can the operator use it?
Does it affect the authoritative engine correctly?
Does it survive save/reopen?
Does undo/redo work where editing is destructive?
Does it produce a useful error when invalid?
Does it have regression tests?
Does it work with the canonical parity project?
Does it remain safe during live output?
```

If the answer to a required question is no:

> The feature is not PASS.

---

# 44. Hardware Test Tomorrow — What Is Reasonable Right Now

This audit does **not** mean Aurora cannot touch real fixtures tomorrow.

A **targeted hardware engineering test** is reasonable for already-built output paths.

Good targets:

```text
Local DMX / ENTTEC connection
Art-Net
sACN
single-channel intensity
RGB/RGBW output
16-bit pan/tilt
Locate
Highlight
Programmer
GO / Back
fade
Blackout
Freeze
Master
basic MIDI Learn
raw Universe Monitor
```

Do **not** treat that session as:

```text
final LightKey-parity smoke test
```

because major parity subsystems are still absent.

For tomorrow, use hardware testing to validate known implemented paths and gather bugs.

The final broad smoke test should follow parity completion + final code audit.

---

# 45. Specific Hardware Safety Check Before Master Testing

Before using Master Intensity on real RGB fixtures that also have a fixture dimmer:

1. Create an RGB/RGBW + Dimmer test profile.
2. Set color channels and dimmer full.
3. Measure generated DMX at Master 100%.
4. Set Master 50%.
5. Verify Aurora does not unintentionally double-attenuate both dimmer and color channels unless that behavior is explicitly desired.
6. Verify chromatic ratios remain stable.

Add an automated test for this semantic case before relying on Master broadly.

---

# 46. Final Parity Pass 1 Verdict

## Good foundations added

This pass did valuable work:

- Stage model
- Stage preview model
- Stage UI proof of concept
- generic/raw fixture model
- multi-cell footprint model
- patch report/bulk repatch foundations
- global live-control engine
- raw DMX universe monitor
- fixture-health computation helper
- schema v2 migration
- MIDI rule scaffold
- additional diagnostics/hardening

These are worth keeping.

## But the project is not at parity

The current state is closer to:

> **Parity Architecture / Foundation Pass 1**

than:

> **LightKey-Parity Implementation Complete**

The next task is not to rewrite these foundations.

The next task is to **finish the acceptance gates built on top of them**.

---

# 47. Grok Instruction

Use this document as the authoritative remediation checklist for the next parity pass.

Do not merely update `Lightkey_Parity_Matrix.md` labels.

Implement the missing runtime/UI/persistence/test links.

When complete:

1. produce the evidence-based parity matrix,
2. run all canonical scenarios,
3. complete Wave 9,
4. stop,
5. return the full repository for final exhaustive code review.

Only after that review should Aurora enter broad real-world smoke testing as a parity-complete product.

---

# 48. Exit Gate

The next parity pass is complete only when:

```text
[ ] Stage uses real authoritative resolved semantic frame
[ ] Stage acceptance workflow passes
[ ] Fixture Profile Editor exists and is usable
[ ] User fixture library exists
[ ] generic/raw parameters are usable
[ ] multi-cell fixtures reach real compile/output/programmer/effects/preview
[ ] patch P0 workflow is complete
[ ] Programmer P0 semantic categories are complete
[ ] palette/preset portable library exists
[ ] cue P0 authoring workflow is complete
[ ] effects P0 baseline is complete
[ ] Song/MIDI context is real
[ ] global controls close remaining safety gaps
[ ] Advanced MIDI rule/behavior engine is real
[ ] outbound MIDI feedback is real
[ ] unified External Control monitor exists
[ ] DMX output monitor has semantic attribution
[ ] fixture health is surfaced
[ ] parity systems persist/migrate
[ ] canonical parity project exists
[ ] Wave 9 matrix has no unresolved P0 Partial/Missing rows
```

Then:

> **Return Aurora for final pre-hardware/release-quality deep code review.**
