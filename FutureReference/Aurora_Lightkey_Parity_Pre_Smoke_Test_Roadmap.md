# Aurora: Lightkey-Parity Pre-Smoke-Test Implementation Roadmap

**Status:** Planning directive\
**Audience:** Grok Plan Mode / Aurora development\
**Date:** 2026-08-13\
**Objective:** Reach practical Lightkey-class functional completeness
before Aurora enters smoke testing.

> **Grok instruction:** Review the current Aurora repository, existing
> architecture/design documentation, and the companion
> `Aurora_2D_Stage_Designer_and_Advanced_MIDI_Engine_Spec(1).md` before
> proposing implementation. This document defines product scope and
> priority, not exact code ownership. Reconcile every item against the
> repository and produce a repo-aware, dependency-ordered implementation
> plan. **Do not begin coding unless explicitly instructed.**

------------------------------------------------------------------------

## 1. Why This Roadmap Exists

Aurora has reached the point where smoke testing should exercise a real
lighting-control product rather than expose predictable missing
subsystems one at a time.

The pre-smoke-test target is therefore:

> **Aurora must be capable of performing the practical core workflows
> expected from Lightkey-class lighting software before broad smoke
> testing begins.**

This does **not** mean cloning Lightkey pixel-for-pixel or reproducing
every peripheral integration. It means that a user accustomed to
Lightkey should be able to perform the normal professional workflow in
Aurora without discovering a major missing piece:

1.  Create/open a show.
2.  Define or import fixtures.
3.  Patch fixtures and universes.
4.  Arrange/select fixtures and groups.
5.  Program fixture parameters semantically.
6.  Create and reuse palettes/presets.
7.  Build cues, sequences, effects, and songs.
8.  Visualize the live rig.
9.  Control playback safely during a show.
10. Control Aurora externally with MIDI and other supported inputs.
11. Diagnose control/output problems.
12. Save, reopen, export, and reuse work reliably.

Aurora should reach this baseline **without sacrificing its
differentiators**: Song Mode, richer MIDI performance control, semantic
fixture architecture, spatial awareness, performer-oriented workflows,
and future AI integration.

------------------------------------------------------------------------

# Part I: Non-Negotiable Architecture

## 2. Preserve One Authoritative Lighting System

All new features must respect Aurora's existing engine authority.

``` text
UI / MIDI / OSC / Remote / Keyboard / Future Inputs
                         |
                         v
                ControlActionRouter
                         |
                         v
              LightingEngine / Session
                         |
                         v
                  Resolved State
                  /           \
                 v             v
          OutputManager    Presentation
          /    |    \       Snapshots
         v     v     v          |
       DMX  Art-Net sACN        v
                            2D Preview
```

Do not create:

-   Preview-owned lighting state
-   MIDI-to-DMX shortcuts
-   SwiftUI-owned output state
-   A second cue/effect engine for visualization
-   Fixture semantics reconstructed from DMX bytes when semantic
    resolved state already exists
-   Independent remote-control state that can disagree with the engine

Every input should ultimately affect the same authoritative show state,
and every output/preview surface should observe that state.

## 3. Preserve Compatibility

Before changing persisted models or existing behavior:

-   Inventory current schema versions and migrations.
-   Preserve existing show files wherever practical.
-   Preserve existing simple MIDI mappings.
-   Preserve current fixture IDs and references.
-   Preserve undo/redo expectations.
-   Preserve existing engine/output tests.
-   Add explicit migrations when persisted models change.
-   Avoid broad rewrites unless repository evidence proves they are
    necessary.

------------------------------------------------------------------------

# Part II: Definition of "Ready for Smoke Testing"

## 4. Smoke-Test Entry Gate

Aurora is **not ready for broad smoke testing** merely because the
application launches and current implemented features work.

The smoke-test gate should require the following functional areas to
exist at a usable baseline:

-   [ ] Project/show lifecycle
-   [ ] Fixture library and user fixture profile creation
-   [ ] Fixture patching and universe management
-   [ ] Fixture/group selection
-   [ ] Programmer
-   [ ] Palettes/presets
-   [ ] Cue lists and playback
-   [ ] Effects
-   [ ] Song Mode baseline
-   [ ] 2D Stage Designer / Live Preview
-   [ ] Global live safety/output controls
-   [ ] Advanced MIDI baseline, including feedback
-   [ ] External-control diagnostics
-   [ ] Output routing and diagnostics
-   [ ] Reusable/importable/exportable programming assets
-   [ ] Persistence/migrations/reopen reliability
-   [ ] Undo/redo for destructive editing workflows
-   [ ] Sufficient test coverage for all above systems

Items explicitly deferred in this roadmap are **not** smoke-test
blockers.

------------------------------------------------------------------------

# Part III: P0 Features --- Must Exist Before Smoke Testing

## 5. P0-A: 2D Stage Designer and Live Preview

Implement the companion **2D Stage Designer / Live Preview
specification** as a first-class Aurora workspace.

Required baseline:

-   Persisted stage layout
-   Fixture X/Y placement, rotation, and presentation scale
-   Fixture symbols by broad fixture category
-   Edit and Live modes
-   Dragging and multi-selection
-   Align/distribute
-   Grid/snap
-   Zoom/pan/fit
-   Labels
-   Basic scenic objects and regions
-   Bidirectional synchronization with Aurora fixture/group selection
-   Read-only semantic preview snapshot derived from resolved engine
    state
-   Live intensity/color representation
-   Moving-fixture orientation where semantic data exists
-   Basic beam visualization
-   Dominant background color derived from resolved live output
-   Temporal smoothing of dominant background
-   Layout persistence
-   Preview throttling independent from physical output timing

### Architectural requirement

A MIDI accent, Programmer change, cue transition, effect, master change,
or override must appear automatically in the preview because the preview
observes **resolved output state**.

There must be no source-specific preview path.

### Acceptance gate

A user can disconnect all physical fixtures, play a show inside Aurora,
and obtain a useful schematic representation of what the rig is doing.

------------------------------------------------------------------------

## 6. P0-B: User Fixture Profile Editor

Aurora's internal fixture/personality model is not sufficient by itself.
Users need to create and repair fixture definitions without editing
source code.

Build a first-class **Fixture Profile Editor**.

### Required model/editor capabilities

-   Manufacturer
-   Model
-   Fixture category
-   Mode name
-   Channel footprint
-   Coarse/fine channel relationships
-   Semantic parameter/attribute assignment
-   Default values
-   Highlight values
-   DMX ranges/functions
-   Color emitters
-   Color wheels and slots
-   Gobo wheels and slots
-   Pan/tilt ranges
-   Beam-related attributes where supported
-   Strobe/shutter ranges
-   Fixture mode variants
-   Validation for overlaps, gaps, invalid ranges, and malformed
    definitions

### Required workflow

``` text
Create/Open Profile
       |
       v
Define Fixture + Mode
       |
       v
Define Channels / Functions
       |
       v
Validate
       |
       v
Test Against Fixture
       |
       v
Save to User Library
```

### Live testing

Where safely possible, provide a profile-editor test mode that allows
the operator to exercise a selected semantic parameter/range against a
patched fixture.

The test path must still pass through controlled Aurora output
authority.

### Import direction

Plan adapters for common external fixture-definition formats where
feasible. At minimum, the architecture should not prevent future:

-   GDTF
-   Open Fixture Library-derived import
-   Other legally/technically practical fixture profile importers

Do not make every importer a P0 blocker if the editor and Aurora-native
profile library are usable.

------------------------------------------------------------------------

## 7. P0-C: Fixture Patch and Rig Management Completion

Patching must feel like mature production software, not an engineering
database editor.

Required:

-   Multi-universe patching
-   Arbitrary/clear universe labels
-   Address assignment
-   Automatic next-address assistance
-   Collision detection
-   Footprint validation
-   Bulk fixture creation
-   Duplicate fixture
-   Batch editing
-   Search/filter/sort
-   Fixture renumbering
-   Repatching
-   Profile/mode reassignment with explicit conflict handling
-   Group creation/editing
-   Fixture favorites or equivalent fast-access workflow
-   Universe/output routing visibility
-   Patch diagnostics
-   Atomic undo for patch operations

### Import/export/reporting

Add:

-   CSV/TSV fixture patch import where practical
-   CSV/TSV fixture patch export
-   Human-readable patch report
-   Printable/exportable patch sheet

A lighting operator should be able to hand the patch information to
another technician without opening Aurora.

------------------------------------------------------------------------

## 8. P0-D: Programmer Completeness

The Programmer must provide practical semantic control of the fixture
capabilities Aurora claims to support.

Required categories:

-   Intensity
-   Color
-   Position
-   Beam
-   Shutter/strobe
-   Fixture-specific semantic parameters

Required workflows:

-   Select fixture(s)/group(s)
-   Modify parameters
-   See changed/active values clearly
-   Clear individual attributes
-   Clear fixture changes
-   Clear Programmer
-   Capture/store into palette/preset/cue
-   Update existing programming
-   Respect selection authority
-   Preserve semantic values rather than forcing users into raw DMX

### Required operational helpers

-   Locate / Highlight
-   Blind programming
-   Clear visual distinction between live and blind work
-   Fine/coarse position control
-   Sensible handling of heterogeneous fixture selections

------------------------------------------------------------------------

## 9. P0-E: Palettes, Presets, and Reusable Library

Aurora's palette/preset system should be one of its strongest
programming tools.

Required:

-   Intensity palettes/presets
-   Color palettes/presets
-   Position palettes/presets
-   Beam palettes/presets
-   All-parameter looks where appropriate
-   Stable IDs/references
-   Update-once propagation to referencing cues
-   Visual tiles
-   Search
-   Organization/grouping
-   Nested groups/folders or equivalent hierarchy
-   Rename/duplicate/delete with reference safety
-   Clear indication of broken/missing references

### Portable Aurora Library

Introduce or formally plan an **Aurora Library** for reusable assets
across shows.

Initial portable asset types should include:

-   Fixture profiles
-   Palettes/presets
-   Looks
-   Effects
-   MIDI mappings/configurations
-   MIDI behaviors
-   Device/drum profiles

Import/export must preserve stable semantics and report unresolved
fixture/target references rather than silently producing incorrect
output.

Future semantic rig adaptation can build on this foundation, but
automatic rig adaptation is not required for the initial parity gate.

------------------------------------------------------------------------

## 10. P0-F: Cue Lists, Playback, and Transitions

Required baseline:

-   Create/edit/delete/reorder cues
-   Cue naming/numbering
-   Current/Next state
-   GO
-   Back
-   Jump/fire cue
-   Double-click-to-fire where consistent with approved Aurora UX
-   Fade up/down
-   Delay
-   Follow/wait timing
-   Cue update
-   Cue copy/duplicate
-   Cue notes/metadata where useful
-   Clear active/next indication
-   Predictable behavior when manually jumping through a list
-   Persistence and migration tests

Playback must remain deterministic.

------------------------------------------------------------------------

## 11. P0-G: Effects Engine Baseline

Required practical effect families:

-   Intensity chases/pulses
-   Color effects
-   Position/movement effects
-   Beam-related effects where supported
-   Fixture/group targeting
-   Speed/rate
-   Size/depth
-   Phase/spread
-   Direction
-   Offset
-   Start/stop
-   Reusable effect presets
-   Cue integration

Effects must blend according to explicit engine precedence rules rather
than incidental code execution order.

------------------------------------------------------------------------

## 12. P0-H: Song Mode Baseline

Song Mode is an Aurora differentiator and must be functional before
smoke testing if it is visible as a core product surface.

Required baseline:

-   Song object
-   Ordered song sections
-   Section names such as Intro/Verse/Chorus/Solo/Bridge/Outro
-   Association/reference to cues, cue lists, looks, or behaviors
    according to current architecture
-   Current song/section state
-   Next/previous section
-   GO/performance progression
-   Reusable cue/palette references rather than unnecessary duplication
-   Clear current/next presentation
-   Persistence
-   MIDI context hooks

Do not require AI song analysis, audio beat detection, or automatic
choreography.

------------------------------------------------------------------------

## 13. P0-I: Global Live Controls and Safety

Formalize a **Global Show Control Layer**.

At minimum:

``` text
MASTER INTENSITY
BLACKOUT
FREEZE
BLIND
CLEAR OVERRIDES
MIDI PERFORMANCE ENABLE/DISABLE
PANIC / RESET
```

### Master Intensity

Must scale appropriate live intensity globally without destructively
rewriting cue/programmer values.

### Blackout

Must provide an immediate, deterministic show-level blackout with
obvious active indication.

### Freeze

Must hold current resolved stage output while preventing subsequent
playback/effect/control changes from altering physical output until
released.

Define carefully what happens to internal timeline/state while frozen
and what occurs on release.

### Blind

Must allow programming/editing without changing live output.

### Panic / Reset

Must safely clear temporary performance behaviors, stuck MIDI state,
temporary overrides, and other transient control conditions according to
documented rules.

### Safe Look

If Aurora already has sufficient architecture for a configurable Safe
Look, include it in planning. Otherwise preserve the concept for the
next safety increment rather than blocking the initial parity gate.

------------------------------------------------------------------------

## 14. P0-J: Advanced MIDI Performance Engine

Implement the companion **Advanced MIDI Engine specification**, but
include the additional parity requirement of **outbound
MIDI/control-surface feedback**.

### Input baseline

Preserve:

-   Endpoint/source
-   Channel
-   Message type
-   Note
-   Velocity
-   CC
-   Program Change
-   Pitch Bend
-   Channel pressure/aftertouch
-   Poly pressure where supported
-   Note-on/off
-   Timestamp

### Rules and behaviors

Required:

-   Simple Input → Action mapping
-   Contextual rules
-   Reusable behaviors
-   Priority
-   Safety constraints
-   Multiple actions per event
-   Velocity scaling
-   AHDR/ADSR-style time envelopes as selected during repo-aware
    planning
-   Continuous CC modulation
-   Input smoothing/deadband/ranges
-   Relative/absolute encoder support where practical
-   Pitch bend/aftertouch integration
-   Explicit behavior blending semantics

### MIDI Learn

Simple mappings must remain simple.

``` text
Press Learn
   |
   v
Receive MIDI
   |
   v
Identify Source / Channel / Event
   |
   v
Choose Action or Behavior
   |
   v
Save
```

Advanced conditions should be available without forcing them on basic
foot-controller mappings.

### MIDI Monitor

Display at minimum:

-   Timestamp
-   Source
-   Channel
-   Type
-   Note/CC
-   Value/velocity
-   Matched mapping/rule
-   Triggered action/behavior
-   Result/error

### Control-surface feedback

Aurora must support outbound MIDI feedback so controllers can represent
application state.

Examples:

``` text
Cue active        -> Button LED on
Cue inactive      -> Button LED dim/off
Master intensity  -> Motor fader / LED ring
Effect speed      -> Encoder ring
Song section      -> Pad color/state
Blackout active   -> Blackout button feedback
```

Plan for:

-   Note/velocity feedback
-   CC feedback
-   Controller LED state
-   14-bit values where supported/appropriate
-   Encoders/jog wheels
-   Motorized controls where protocol behavior permits
-   Feedback-loop prevention
-   Device-specific feedback profiles
-   Import/export of controller mappings/configurations

### Drum-aware features

Implement according to the companion spec:

-   Device/drum profiles
-   Semantic drum roles
-   Hardware-note abstraction
-   Song-context mappings
-   Reusable performance behaviors

**Performance Energy** may be implemented late in P0 or immediately
after parity if core MIDI functionality is otherwise complete. It must
not delay foundational reliability.

### MIDI safety

Required:

-   Rate limiting
-   Debounce
-   Flood protection
-   Stuck-note handling
-   Disconnect handling
-   Maximum behavior concurrency
-   Strobe constraints
-   Panic/reset
-   Global performance-MIDI disable

------------------------------------------------------------------------

## 15. P0-K: Unified External Control and Diagnostics

Aurora should provide one coherent place to understand what external
control is doing.

Create an **External Control** workspace/panel or equivalent
architecture covering supported sources such as:

-   MIDI
-   OSC
-   Web Remote
-   Keyboard
-   Future DMX-In
-   Future additional controllers

### Unified event/action log

Conceptual presentation:

``` text
TIME       SOURCE       EVENT          MAPPING          RESULT
----------------------------------------------------------------
20:14:01   TD-17        Note 38 v117   Snare Accent     Fired
20:14:03   FCB1010      CC 12 = 127    GO               Cue 24
20:14:05   OSC Client   /aurora/go     Remote GO        Cue 25
20:14:07   iPad         Blackout       Global Control   Active
```

Required capabilities:

-   Live log
-   Search/filter
-   Matched mapping visibility
-   Unmatched-event visibility
-   Errors
-   Enable/disable mappings
-   Test/invoke mapped actions where safe
-   MIDI feedback log
-   Device connection status

This subsystem should become Aurora's "why did the lights do that?"
window.

------------------------------------------------------------------------

## 16. P0-L: Output Configuration and Diagnostics

Required:

-   ENTTEC/serial DMX output according to Aurora's supported hardware
    scope
-   Art-Net
-   sACN if currently claimed as supported
-   Universe routing
-   Enable/disable output
-   Output status
-   Device/node status where obtainable
-   Clear errors
-   Universe-level diagnostics
-   Current output inspection
-   No silent failure
-   Reconnect/recovery behavior
-   Safe behavior when an output endpoint disappears

A show-control application must distinguish:

``` text
Engine is healthy
Output protocol is enabled
Destination is reachable/available
Frames are being transmitted
```

where the underlying protocol/hardware permits those distinctions.

------------------------------------------------------------------------

## 17. P0-M: Persistence, Recovery, and Project Integrity

Before smoke testing:

-   New project
-   Open
-   Save
-   Save As / duplicate workflow as appropriate
-   Reopen
-   Schema migration
-   Autosave/recovery strategy where already planned
-   Missing fixture/profile handling
-   Missing external device handling
-   Broken-reference reporting
-   Deterministic stable IDs
-   Project validation
-   Non-destructive handling of unknown future fields if current
    architecture supports it

Create test projects that exercise:

-   Multiple universes
-   Multiple fixture families
-   Groups
-   Palettes
-   Effects
-   Cue lists
-   Song Mode
-   Stage layout
-   MIDI rules
-   MIDI feedback
-   External outputs

These should become canonical smoke-test fixtures.

------------------------------------------------------------------------

# Part IV: P1 Features --- Strongly Desired Before Smoke Testing

## 18. P1-A: Parameterized Pixel / Matrix Fixtures

Support fixtures whose cell count can vary without requiring a separate
hard-coded profile for every possible length.

Concept:

``` text
Generic RGBW Pixel Bar
Cells: 24
Channels per Cell: 4
Calculated Footprint: 96
```

Plan:

-   Cell model
-   Repeated channel blocks
-   Patch footprint calculation
-   Per-cell semantic state
-   Whole-fixture and cell selection
-   Preview representation
-   Future pixel-mapping compatibility

If implementation risk is large, establish the data model and
fixture-editor representation before smoke testing and schedule advanced
pixel programming immediately afterward.

------------------------------------------------------------------------

## 19. P1-B: Custom Keyboard Shortcuts

Provide configurable keyboard mappings for important show actions,
including conflict detection and safe defaults.

At minimum support:

-   GO
-   Back
-   Blackout
-   Freeze
-   Clear
-   Programmer actions
-   Workspace navigation
-   Selected playback controls

Do not override critical macOS conventions casually.

------------------------------------------------------------------------

## 20. P1-C: OSC Completeness

If OSC is part of Aurora's exposed feature set, ensure it has:

-   Clear address namespace
-   UDP baseline
-   TCP if justified by current architecture/product target
-   Input monitor
-   Mapping/action integration
-   Error visibility
-   Discovery where practical
-   Documentation of message formats
-   Stable action semantics shared with MIDI/remote control

Bonjour discovery is useful but not a smoke-test blocker if direct
configuration is solid.

------------------------------------------------------------------------

## 21. P1-D: Web Remote Baseline

Because Aurora explicitly intends an iPad/mic-stand remote workflow, the
baseline remote should be usable before smoke testing if the feature is
currently exposed.

Minimum useful surface:

-   Current song
-   Current cue/section
-   Next cue/section
-   GO
-   Back
-   Master
-   Blackout
-   Safe high-level controls
-   Connection status

Remote actions must route through the same control authority as local
actions.

Do not expose dangerous fixture-level programming remotely until
authentication, authorization, and UX are appropriate.

------------------------------------------------------------------------

# Part V: Explicitly Deferred / Not Required for Initial Parity Gate

## 22. Features That Should Not Delay Smoke Testing

These may be valuable, but they are not required to reach the practical
Lightkey-class baseline targeted by this roadmap:

-   Philips Hue integration
-   USB joystick control
-   User-configurable multitouch gesture system
-   macOS Shortcuts integration
-   Full DMX-In control
-   Full 3D visualization
-   Photometric/ray-traced preview
-   CAD import
-   Performer/camera tracking
-   AI Show Designer
-   AI photo/video song-profile generation
-   MIDI 2.0 / UMP
-   Ableton-style timeline sync
-   Audio beat detection
-   Automatic choreography
-   Cloud services
-   Full semantic "Adapt Show to New Rig"
-   Advanced spatial effects
-   Lighting DNA / advanced AI features

The architecture should avoid unnecessarily blocking these future
capabilities.

------------------------------------------------------------------------

# Part VI: Dependency-Ordered Implementation Program

## 23. Recommended Program Structure

Grok should validate this ordering against the actual repository.

### Wave 0 --- Repository Audit and Parity Matrix

**No production code.**

Produce:

1.  Current subsystem inventory.
2.  Current implemented vs partial vs missing status.
3.  Exact type/module ownership.
4.  Current persistence schema/migrations.
5.  Current test coverage.
6.  Current UI workspace structure.
7.  Existing MIDI architecture.
8.  Existing output architecture.
9.  Existing fixture/personality architecture.
10. Existing selection/programmer/cue/effect architecture.
11. A Lightkey-parity matrix mapping every roadmap requirement to:

-   Complete
-   Partial
-   Missing
-   Intentionally deferred

12. Dependency graph.
13. Proposed PR sequence.
14. Risk register.

**STOP after the plan.**

### Wave 1 --- Foundation Gaps

Likely work:

-   Missing persisted-model foundations
-   Fixture-profile editor model support
-   Portable library foundations
-   Stage-layout persistence
-   Rich MIDI event/rule model
-   Global show-control semantics
-   External-control event/log model

Do not build elaborate UI until ownership and persistence are correct.

### Wave 2 --- Fixture / Patch / Library Completion

Implement:

-   Fixture Profile Editor
-   Rig/patch workflow completion
-   Import/export/reporting
-   Palette/preset library portability
-   Pixel/matrix foundation if feasible

### Wave 3 --- Programmer / Playback / Effects / Song Completion

Close any parity gaps in:

-   Programmer
-   Blind/Locate/Highlight
-   Palettes/presets
-   Cue lists
-   Effects
-   Song Mode
-   Global live controls

### Wave 4 --- 2D Stage Designer

Follow the companion specification:

1.  Stage model
2.  Preview snapshot
3.  Basic canvas
4.  Edit tools
5.  Live rendering
6.  Dominant background
7.  Beam/mover improvements
8.  Scenic regions
9.  Performance tuning

### Wave 5 --- Advanced MIDI Core

Follow the companion specification:

1.  Rich event normalization
2.  Rules/context
3.  Behaviors
4.  Envelopes/scaling
5.  CC/expressive controls
6.  Multiple actions
7.  Drum profiles
8.  Safety
9.  Monitor

### Wave 6 --- MIDI Feedback / Unified External Control

Implement:

-   Outbound feedback
-   Device feedback profiles
-   14-bit/encoder considerations
-   Import/export controller mappings
-   Unified external-control monitor
-   Action testing
-   Error/logging UX

### Wave 7 --- Output / Remote / Operational Hardening

Close gaps in:

-   DMX hardware
-   Art-Net
-   sACN
-   Routing
-   Output diagnostics
-   Web remote
-   OSC
-   Device disconnect/reconnect behavior

### Wave 8 --- Pre-Smoke-Test Hardening

No major new feature work unless a blocker is discovered.

Focus on:

-   Persistence round trips
-   Migration tests
-   Undo/redo
-   Error handling
-   Broken references
-   Performance
-   Main-thread violations
-   Frame-loop protection
-   Resource cleanup
-   Device connect/disconnect
-   Empty states
-   Large-show behavior
-   UI state restoration
-   Crash recovery where supported
-   Accessibility/keyboard sanity
-   Canonical test projects

------------------------------------------------------------------------

# Part VII: Grok Plan Mode Deliverable

## 24. Required Output From Grok

When this roadmap is supplied to Grok Plan Mode, Grok must produce a
**repo-aware implementation plan**, not a generic restatement of this
document.

For every proposed phase/PR, provide:

### A. Scope

-   User-visible capability
-   Exact requirements satisfied
-   Explicit non-goals

### B. Repository Touchpoints

-   Existing files/modules/types to modify
-   New files/modules/types proposed
-   Ownership boundaries
-   Why each location is correct

### C. Data Model

-   New persisted types/fields
-   Stable IDs/references
-   Schema version impact
-   Migration strategy
-   Backward compatibility

### D. Engine Integration

-   Control flow
-   Thread/actor ownership
-   Resolved-state interaction
-   Output interaction
-   Snapshot/presentation boundaries
-   Performance implications

### E. UI Integration

-   Workspace/panel location
-   Selection integration
-   Inspector integration
-   Commands/menus/shortcuts
-   Empty/error states
-   Accessibility considerations

### F. Tests

-   Unit tests
-   Integration tests
-   Persistence/migration tests
-   Engine/output tests
-   UI tests where valuable
-   Performance/stress tests where valuable

### G. Acceptance Criteria

Provide observable pass/fail criteria for the PR.

### H. Risks

-   Regression risk
-   Migration risk
-   Concurrency risk
-   Performance risk
-   Compatibility risk
-   Architectural debt risk

### I. Dependencies

Explicitly name prerequisite PRs and downstream work.

------------------------------------------------------------------------

# Part VIII: Planning Guardrails

## 25. Rules for Grok

1.  **Inspect the current repository before planning implementation
    details.**
2.  Do not assume this roadmap's conceptual type names already exist.
3.  Prefer extending current Aurora authorities over inventing parallel
    systems.
4.  Preserve `ControlActionRouter` and authoritative engine/output
    boundaries unless repository evidence justifies a change.
5.  Do not put engine logic, MIDI behavior logic, envelope execution, or
    semantic DMX decoding in SwiftUI.
6.  Do not make the 2D Preview its own lighting engine.
7.  Do not bypass engine authority for MIDI, remote, OSC, keyboard, or
    fixture-profile testing.
8.  Propose migrations before persisted-model changes.
9.  Keep PRs bounded and independently testable.
10. Preserve existing simple workflows while adding advanced capability.
11. Flag any roadmap requirement already completely implemented rather
    than rewriting it.
12. Flag any current implementation that only superficially satisfies a
    requirement.
13. Prefer deterministic behavior for live-show critical paths.
14. Treat physical output timing as higher priority than visualization
    refresh.
15. Do not allow unbounded external input to destabilize the frame loop.
16. Explicitly define precedence/blending for cues, effects, Programmer,
    MIDI behaviors, masters, overrides, Freeze, Blackout, and Blind.
17. Maintain test coverage with every phase.
18. Do not perform unrelated refactors merely because nearby code could
    be cleaner.
19. Do not implement deferred AI/3D/cloud features during parity work.
20. **Stop after producing the implementation plan. Do not code until
    explicitly authorized.**

------------------------------------------------------------------------

# Part IX: Required Pre-Smoke-Test Scenarios

## 26. Canonical Functional Scenarios

Before declaring Aurora ready for smoke testing, the implemented system
should be able to pass these scenario-level checks.

### Scenario 1 --- Build a Rig From Scratch

1.  Create a new show.
2.  Add fixture profiles from the library.
3.  Create one missing fixture profile in Aurora.
4.  Patch fixtures across multiple universes.
5.  Detect an intentional address collision.
6.  Correct the collision.
7.  Create fixture groups.
8.  Export a patch report.
9.  Save and reopen.

### Scenario 2 --- Program a Basic Show

1.  Select fixtures.
2.  Locate them.
3.  Set intensity/color/position/beam.
4.  Store palettes.
5.  Create reusable looks.
6.  Create cues referencing palettes.
7.  Update a palette.
8.  Verify referencing cues inherit the change.
9.  Build an effect.
10. Add cues/effects to a cue list.
11. Save/reopen and verify fidelity.

### Scenario 3 --- Run the Show

1.  Start playback.
2.  GO through cues.
3.  Jump backward/forward.
4.  Adjust Master.
5.  Blackout and restore.
6.  Freeze output.
7.  Change internal playback while frozen.
8.  Release Freeze according to documented semantics.
9.  Enter Blind and edit without changing live output.
10. Clear temporary overrides safely.

### Scenario 4 --- Stage Preview

1.  Place fixtures spatially.
2.  Save/reopen the layout.
3.  Select a fixture in the Stage view and observe selection elsewhere.
4.  Fire a cue.
5.  Observe intensity/color.
6.  Run an effect.
7.  Observe live effect state.
8.  Trigger a MIDI accent.
9.  Observe the accent automatically.
10. Verify dominant background follows resolved stage color without
    distracting flicker.

### Scenario 5 --- MIDI Foot Controller

1.  Connect a MIDI controller.
2.  Learn a button for GO.
3.  Learn a button for Blackout.
4.  Verify incoming events in Monitor.
5.  Verify actions.
6.  Save/reopen.
7.  Reconnect device.
8.  Confirm mappings recover correctly.

### Scenario 6 --- Electronic Drums

1.  Load/create a drum device profile.
2.  Map snare semantically.
3.  Create a velocity-sensitive accent behavior.
4.  Add an envelope.
5.  Restrict behavior to a Song/Section.
6.  Play soft/hard hits.
7.  Verify scaling.
8.  Verify behavior in Stage Preview.
9.  Flood input intentionally within safe test bounds.
10. Verify engine remains stable.

### Scenario 7 --- MIDI Feedback

1.  Map a controller LED to cue state.
2.  Fire cue from Aurora.
3.  Verify controller state changes.
4.  Fire cue from controller.
5.  Verify no feedback loop.
6.  Change Master and verify supported feedback.
7.  Disconnect/reconnect controller.
8.  Verify recovery.

### Scenario 8 --- Network / Physical Output

1.  Configure DMX hardware.
2.  Configure Art-Net/sACN as supported.
3.  Route universes.
4.  Verify output status.
5.  Disconnect an endpoint.
6.  Observe useful diagnostic state.
7.  Reconnect.
8.  Verify recovery without restarting the show where technically
    possible.

### Scenario 9 --- Reuse Assets

1.  Export palettes/effects/MIDI mappings from Show A.
2.  Import into Show B.
3.  Resolve target differences explicitly.
4.  Verify no silent corruption.
5.  Save/reopen Show B.

### Scenario 10 --- Failure Recovery

Exercise:

-   Missing fixture definition
-   Missing MIDI device
-   Missing output device
-   Invalid patch
-   Broken library reference
-   Interrupted external connection
-   Rapid input
-   Empty project
-   Large fixture selection

Aurora should fail visibly and safely rather than mysteriously.

------------------------------------------------------------------------

# Part X: Final Readiness Review

## 27. Parity Review Before Smoke Testing

Once all planned implementation waves are complete, perform a dedicated
**Lightkey-Parity Readiness Review** before beginning general smoke
testing.

The review should answer:

### Fixture Workflow

-   Can Aurora define, patch, organize, locate, edit, and troubleshoot a
    practical rig?

### Programming

-   Can Aurora program intensity, color, position, beam, palettes,
    looks, effects, and cues efficiently?

### Playback

-   Can Aurora safely run and recover a live show?

### Visualization

-   Can the operator understand live fixture state without physical
    fixtures connected?

### External Control

-   Can MIDI and other supported controllers be learned, monitored,
    debugged, and trusted?

### MIDI Differentiation

-   Does Aurora equal basic controller functionality while clearly
    exceeding it for musical performance?

### Portability

-   Can useful programming assets move between shows?

### Diagnostics

-   When something does not work, does Aurora explain where the chain
    failed?

### Persistence

-   Does a complex show survive save/reopen/migration intact?

### Performance

-   Do UI visualization and external-control traffic remain subordinate
    to deterministic lighting output?

Only after these questions are answered satisfactorily should broad
smoke testing begin.

------------------------------------------------------------------------

# 28. Product Principle

Lightkey is the **functional floor**, not Aurora's design ceiling.

Aurora should reach the point where a Lightkey user does not lose
essential professional lighting-control capability by moving to Aurora.
From that foundation, Aurora should distinguish itself through:

-   Song-oriented show control
-   Rich performance MIDI
-   Semantic behaviors
-   Spatial stage awareness
-   Reusable programming intelligence
-   Performer-friendly remote control
-   Future AI-assisted design

The pre-smoke-test job is therefore not to chase every peripheral
checkbox.

It is to build a complete, coherent, deterministic lighting workstation
whose missing pieces no longer dominate testing.

> **First achieve professional functional completeness. Then smoke-test
> the product as a product.**
