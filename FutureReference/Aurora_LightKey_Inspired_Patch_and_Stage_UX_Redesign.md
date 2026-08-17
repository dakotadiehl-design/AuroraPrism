# Aurora --- LightKey-Inspired Patch & 2D Stage UX Redesign

**Target:** Aurora LightKey Parity Pass 2\
**Priority:** High --- usability correction before further parity/UI
expansion\
**Scope:** Patch / fixture-management workflow and 2D Stage Designer /
Live Preview\
**Intent:** Preserve Aurora's backend architecture and visual identity
while restructuring these workflows around the operator's task rather
than the application's internal panel structure.

------------------------------------------------------------------------

## 1. Why This Pass Exists

Aurora Pass 2 contains substantially more functionality, but the
application still does not feel as immediately understandable as
LightKey.

This is not primarily a styling problem.

The problem is the **interaction model**.

Aurora currently exposes concepts such as:

``` text
Browser
Patch
Groups
Stage
Profiles
Programmer
Inspector
```

as peer panels/tools. That maps reasonably well to the software
architecture, but it forces the lighting operator to think about
Aurora's architecture before completing ordinary lighting tasks.

The target mental model should instead be:

``` text
BUILD THE RIG
      ↓
ARRANGE THE STAGE
      ↓
DESIGN THE LOOK
      ↓
BUILD THE SHOW
      ↓
PERFORM
```

Panels remain useful implementation components, but they should appear
contextually around these jobs.

> **Do not merely polish the existing PatchPanel and StagePanel.
> Restructure their operator workflows.**

------------------------------------------------------------------------

# 2. Product Principle

Aurora should retain its own modern macOS visual identity, modular
architecture, engine model, stable IDs, and safety rules.

However, for fixture management and stage visualization, use the proven
interaction philosophy of LightKey as the UX reference.

Do **not** copy LightKey artwork, branding, source code, or
pixel-for-pixel appearance.

Do emulate the parts of its interaction model that make lighting work
immediately understandable:

-   fixtures are selected from a visual/searchable fixture library
-   quantity and mode are chosen before patching
-   fixtures are patched directly onto a visual DMX universe
-   fixture footprints are visible spatially
-   fixtures can be moved by dragging
-   Stage/Preview is a large visual workspace
-   fixtures on Stage are meaningful visual objects, not generic dots
-   Stage selection and programming cooperate
-   Live Preview communicates the actual show state

------------------------------------------------------------------------

# 3. Hard Scope Rule

This pass should change:

``` text
Patch UX
Fixture-library UX related to patching
Stage workspace placement
Stage editing UX
Stage fixture visualization
Stage live visualization
Contextual Inspector/Programmer integration
```

This pass should **not**:

-   replace the Aurora engine
-   create a second lighting-state pipeline
-   rewrite persistence without necessity
-   redesign every application screen
-   change cue semantics
-   change palette-reference semantics
-   change MIDI architecture except where Stage must reflect
    authoritative engine state
-   copy LightKey's visual assets

Preserve the backend work that is already correct.

------------------------------------------------------------------------

# PART I --- PATCH / FIXTURE MANAGEMENT REDESIGN

# 4. Current Problem

The current Patch workflow is fundamentally table-oriented:

``` text
Addr | End | Name | Personality | Ch | Issues
```

with commands such as:

``` text
Add Universe
Clone
Remove
Bulk...
Renumber
Bulk Create
Import CSV
CSV
Report
```

Those operations remain useful, but they should not be the primary
mental model for building a rig.

An operator normally thinks:

> "I have four of this fixture, in this mode, and the first one starts
> at DMX 101."

Aurora should let the operator express exactly that.

------------------------------------------------------------------------

# 5. New Patch Workspace

Patch becomes a substantial workspace rather than a narrow utility
panel.

Recommended structure:

``` text
┌───────────────────────────────────────────────────────────────────────────┐
│ PATCH                                            Universe 1     Output ✓ │
├─────────────────────────┬─────────────────────────────────────────────────┤
│ FIXTURE LIBRARY         │ DMX UNIVERSE 1                                  │
│                         │                                                 │
│ Search fixtures...      │ 001 002 003 004 005 006 007 008 009 ...       │
│                         │ ┌─────────────────────────┐                     │
│ Favorites               │ │ Front Wash L           │                     │
│ Recent                  │ │ RGBW PAR · 001–008     │                     │
│                         │ └─────────────────────────┘                     │
│ Chauvet                 │                                                 │
│   4BAR Hex              │                    ┌───────────────────────┐    │
│   LP12 Hex              │                    │ Mover 1               │    │
│   Intimidator ...       │                    │ 16ch · 101–116        │    │
│                         │                    └───────────────────────┘    │
│ Generic                 │                                                 │
│   Dimmer                │                                                 │
│   RGB                   │                                                 │
│   RGBW                  │                                                 │
├─────────────────────────┴─────────────────────────────────────────────────┤
│ Selected Profile: LP12 Hex    Mode: 8ch    Quantity: 4       [ PATCH ]  │
└───────────────────────────────────────────────────────────────────────────┘
```

The visual universe is the primary patching surface.

A secondary List view may remain available:

``` text
[ Universe Grid ] [ List ]
```

Use List for:

-   diagnostics
-   sorting
-   CSV operations
-   bulk metadata editing
-   large-rig administration
-   issue review

Default to **Universe Grid**.

------------------------------------------------------------------------

# 6. Fixture Library Workflow

The left side of Patch should provide a proper Fixture Library.

Required:

``` text
Search
Manufacturer hierarchy
Fixture/model
Mode/personality
Favorites
Recent fixtures
User fixtures
Generic fixtures
```

Selecting a fixture exposes a compact patch preparation strip:

``` text
Fixture: Chauvet LP12 Hex
Mode: 8 Channel
Quantity: 4
Name Prefix: LP
```

Changing mode immediately changes the previewed DMX footprint.

Quantity must be selected **before or during** the patch gesture.

------------------------------------------------------------------------

# 7. Primary Patch Interaction --- Drag to DMX Address

The preferred workflow is:

``` text
Choose fixture
      ↓
Choose mode
      ↓
Choose quantity
      ↓
Drag fixture/batch onto desired DMX address
      ↓
Aurora previews complete batch footprint
      ↓
Valid = commit
Invalid = reject/explain
```

Example:

``` text
LP12 Hex
Mode: 8ch
Quantity: 4

Drop at 101
```

Preview:

``` text
LP1   101–108
LP2   109–116
LP3   117–124
LP4   125–132
```

The preview must exist **before commit**.

------------------------------------------------------------------------

# 8. Drag Ghost / Validation Behavior

During drag, render ghost fixture blocks over the DMX universe.

Valid placement:

``` text
101 ┌──────── LP1 ────────┐
109 ├──────── LP2 ────────┤
117 ├──────── LP3 ────────┤
125 └──────── LP4 ────────┘
```

Invalid placement should visually indicate the conflict.

Examples:

``` text
overlap
past channel 512
invalid footprint
unavailable universe
profile/mode error
```

Do not silently auto-move a requested fixture around an overlap unless
the operator explicitly asks for "next free."

A rejected drop should explain why.

------------------------------------------------------------------------

# 9. Fast Patch Interaction

Provide a fast operation equivalent in spirit to LightKey's
first-available workflow.

Recommended:

``` text
Double-click fixture profile
```

or:

``` text
Patch at Next Free
```

Result:

-   use selected mode
-   use selected quantity
-   locate first contiguous valid range
-   preview or commit according to current UX
-   select newly patched fixtures

This should be fast enough for building a simple rig in seconds.

------------------------------------------------------------------------

# 10. Repatch Existing Fixtures by Dragging

Existing fixture blocks in the universe should be draggable.

Dragging:

``` text
Mover 1
101–116
```

to channel:

``` text
201
```

previews:

``` text
201–216
```

and commits atomically if valid.

Support dragging between universes where the model permits it.

Undo must restore the complete previous patch state.

------------------------------------------------------------------------

# 11. Universe Visualization

The universe should communicate the actual 512-channel address space
visually.

Do not make it a decorative grid.

Required:

-   channel numbers
-   fixture blocks spanning actual footprints
-   unused ranges
-   overlap/conflict states
-   selected fixture state
-   hovered/drop-target state
-   universe identity
-   protocol/output route status
-   start/end address
-   fixture name
-   mode/footprint where space allows

Zoom or density controls may be added if required for readability.

The operator should be able to glance at the universe and understand how
full it is.

------------------------------------------------------------------------

# 12. Multiple Universes

Universe selection should be obvious.

Possible treatment:

``` text
Universe 1
Universe 2
Universe 3
+
```

or a compact navigator.

Dragging a fixture to another universe should be possible where
practical.

Output protocol/routing should remain visible but secondary.

The primary task is patching, not network administration.

------------------------------------------------------------------------

# 13. Fixture Inspector During Patch

Selecting a patched fixture should open contextual Inspector content:

``` text
Name
Fixture Number
Manufacturer
Model
Mode
Universe
Address
Footprint
Group membership
Stage placement status
Profile health
Patch health
```

Editable fields should update through existing safe command/undo paths.

Do not make the operator hunt through another screen for basic fixture
identity.

------------------------------------------------------------------------

# 14. Bulk Operations Remain, But Become Secondary

Keep useful existing operations:

``` text
Bulk Create
Renumber
Clone
CSV import/export
Patch report
Batch edit
```

But move them to secondary toolbar/menu/context actions.

They are power tools, not the primary patching workflow.

------------------------------------------------------------------------

# 15. Patch Acceptance Scenario

The following must feel natural without documentation:

``` text
1. Open Patch.
2. Search for Chauvet LP12 Hex.
3. Choose the desired mode.
4. Set Quantity = 4.
5. Drag the fixture onto DMX 101.
6. See all four footprints before committing.
7. Drop.
8. Rename fixtures if desired.
9. Drag one fixture to a different address.
10. Undo.
11. Add another fixture at Next Free.
12. Save/reopen.
```

If this feels like database administration, Patch is not done.

------------------------------------------------------------------------

# PART II --- 2D STAGE DESIGNER REDESIGN

# 16. Stage Must Become a First-Class Workspace

The current arrangement:

``` text
Browser | Patch | Groups | Stage | Profiles
```

inside a narrow left column is not acceptable as the final Stage
experience.

Stage is one of Aurora's major show-building surfaces.

When Stage is selected, the **central workspace becomes Stage**.

Recommended composition:

``` text
┌───────────────────────────────────────────────────────────────────────────┐
│ AURORA             BUILD | PERFORM        Project Name          DMX ✓   │
├───────────────┬───────────────────────────────────────┬───────────────────┤
│ FIXTURES      │                                       │ INSPECTOR         │
│               │                STAGE                  │                   │
│ Front Wash L  │                                       │ Fixture           │
│ Front Wash R  │        ◉                 ◉            │ X / Y             │
│ Mover 1       │                                       │ Rotation          │
│ Mover 2       │     ════════ TRUSS ════════          │ Scale             │
│               │                                       │ Label             │
│ GROUPS        │          ◉           ◉                │ Beam              │
│ Front         │                                       │ Layer             │
│ Movers        │                                       │                   │
├───────────────┴───────────────────────────────────────┴───────────────────┤
│ EDIT | LIVE    Grid ✓  Snap ✓  Align ▾  Distribute ▾   75%   Fit       │
└───────────────────────────────────────────────────────────────────────────┘
```

The canvas should receive the majority of the available screen area.

------------------------------------------------------------------------

# 17. Stage Has Two Clear Modes

## EDIT

Purpose:

``` text
build the visual representation of the rig
```

Allow:

-   select
-   multi-select
-   marquee select
-   move
-   rotate
-   scale
-   align
-   distribute
-   snap
-   grid
-   scenic object creation/editing
-   labels
-   layer order
-   lock/hide
-   regions where supported

## LIVE

Purpose:

``` text
show what the rig is actually doing
```

Prioritize:

-   intensity
-   color
-   beam
-   movement/orientation
-   strobe
-   fixture state
-   dominant stage/background color
-   selection for programming
-   pan/zoom navigation

Editing geometry should be protected in Live mode.

------------------------------------------------------------------------

# 18. Stage Fixture Symbols Must Represent Fixture Type

Do not render every fixture as a generic circle.

Provide Aurora-native schematic symbols for broad fixture categories:

``` text
PAR / wash
bar / batten
moving head
spot / profile
blinder
strobe
laser
fog
haze
matrix / pixel fixture
generic fixture
```

These do not need photorealism.

They should be:

-   immediately recognizable
-   visually consistent
-   scalable
-   rotatable
-   readable at small size
-   appropriate for a professional lighting plot

Use the existing Aurora icon language where suitable.

------------------------------------------------------------------------

# 19. Fixture Geometry

Each placed fixture should support persisted:

``` text
X
Y
Rotation
Scale
Z/layer
Label
Lock
Visibility
```

Where useful:

``` text
beam display preference
label display preference
```

Multi-selection operations must work across these values.

------------------------------------------------------------------------

# 20. Stage Selection Must Feel Like a Graphics Application

Required:

``` text
click -> select
Command-click -> toggle selection
Shift-click -> extend selection where appropriate
drag empty canvas -> marquee selection
Command-A -> select all relevant Stage fixtures when focus is Stage
Escape -> clear selection when safe
```

Selection must remain synchronized with Aurora's central selection
model.

Do not create a second independent Stage selection authority.

------------------------------------------------------------------------

# 21. Align and Distribute

Provide obvious Edit-mode tools:

``` text
Align Left
Align Center X
Align Right
Align Top
Align Center Y
Align Bottom

Distribute Horizontally
Distribute Vertically
```

Use deterministic ordered geometry.

All actions must be undoable.

------------------------------------------------------------------------

# 22. Grid and Snap

Provide:

``` text
Show Grid
Snap to Grid
Grid spacing
```

Optional later:

``` text
snap to fixture
snap to guide
smart guides
```

Grid should aid layout without visually dominating the canvas.

------------------------------------------------------------------------

# 23. Zoom / Pan / Fit

Required:

``` text
mouse/trackpad zoom
pan
Fit Stage
Fit Selection
100%
```

Support natural macOS trackpad behavior where practical.

`Fit Stage` must actually calculate the stage bounds.

Do not implement Fit merely as:

``` text
scale = 1
pan = 0
```

unless that happens to be the correct calculated fit.

------------------------------------------------------------------------

# 24. Scenic Objects

Stage should support enough scenic structure to make the preview useful.

Required baseline:

``` text
Rectangle
Line
Text
Truss-like line/object
Image/background where architecture permits
```

Objects need:

``` text
position
size
rotation where relevant
layer
lock
visibility
label/text
```

Do not turn Aurora into CAD software.

The purpose is to create a recognizable schematic of the real stage.

------------------------------------------------------------------------

# 25. Contextual Inspector

Selecting an object changes Inspector context.

Fixture:

``` text
Fixture identity
Position
Rotation
Scale
Label
Layer
Beam display
Fixture capability summary
Patch address
```

Scenic object:

``` text
Object type
Position
Size
Rotation
Layer
Lock
Visibility
Text/style where applicable
```

Multi-selection:

``` text
Count
shared properties
mixed properties
alignment/distribution tools
```

------------------------------------------------------------------------

# PART III --- STAGE AS A LIVE LIGHTING PREVIEW

# 26. Live Preview Must Use the Authoritative Engine State

This is non-negotiable.

Do not reconstruct lighting state in `AppModel`.

Stage must observe the semantic resolved frame produced by the same
authoritative engine evaluation that ultimately generates DMX.

Conceptually:

``` text
Playback / Manual Look
        ↓
Effects
        ↓
Programmer
        ↓
Global Show Controls
        ↓
Freeze semantics
        ↓
AUTHORITATIVE RESOLVED SHOW FRAME
        ├─────────────────────┐
        ↓                     ↓
DMX Merge              Stage Preview
        ↓
Physical Output
```

Stage and DMX may transform that shared semantic state differently for
presentation/output, but they must not independently recalculate show
intent.

------------------------------------------------------------------------

# 27. Virtual Beam Visualization

Virtual beams are a major part of the desired Stage experience.

Implement useful schematic beam visualization.

## Static wash/PAR

Represent:

-   fixture orientation
-   intensity
-   color
-   approximate beam spread

## Moving head

Represent:

-   pan
-   tilt
-   intensity
-   color
-   approximate beam cone/direction
-   beam/zoom width where known

## Profile/spot

Represent useful direction and beam shape where supported.

Do not attempt physically accurate ray tracing.

The goal is:

> **At a glance, the operator should understand where a light is
> pointing and roughly what it is doing.**

------------------------------------------------------------------------

# 28. Beam Rendering Quality / Performance

Beam rendering must be efficient.

Prefer:

-   simplified geometry
-   GPU-friendly drawing where practical
-   frame throttling independent of DMX engine timing
-   graceful degradation for large rigs

Never allow Stage rendering to stall physical output.

Lighting engine/output timing has priority.

------------------------------------------------------------------------

# 29. Color and Intensity

Fixture visual state should communicate:

``` text
off
dim
bright
color
mixed emitter result
```

A fixture at 20% should not visually resemble one at 100%.

Blackout must visibly extinguish the preview.

Master must visibly affect preview intensity according to the same
semantics as output.

------------------------------------------------------------------------

# 30. Moving Fixture Orientation

For moving fixtures, Stage must visibly communicate orientation.

At minimum:

-   fixture body/symbol
-   pan/tilt-derived direction
-   beam direction

Changing Pan/Tilt in Programmer should update Stage smoothly.

Cue transitions should animate Stage orientation smoothly.

------------------------------------------------------------------------

# 31. Strobe

Where the authoritative semantic state exposes strobe/shutter behavior,
Stage should communicate it.

Do not require perfect temporal simulation.

Use a visually understandable representation without creating dangerous
or distracting UI behavior.

Respect accessibility/reduced-motion considerations where appropriate.

------------------------------------------------------------------------

# 32. Fog / Haze / Laser

Provide category-appropriate schematic state.

Fog/Haze:

-   active/off
-   output level where known

Laser:

-   active/off
-   safe schematic visualization only
-   do not imply physical safety zones unless Aurora actually models and
    validates them

------------------------------------------------------------------------

# 33. Dominant Background Color

Retain the approved LightKey-inspired behavior:

> The Stage background subtly responds to the dominant active look
> color.

Requirements:

-   smooth transition
-   restrained saturation
-   preserve fixture readability
-   never overwhelm labels/grid
-   Blackout returns toward neutral/dark
-   Freeze holds the appropriate semantic state

This should make the Stage feel alive without becoming a nightclub
wallpaper generator.

------------------------------------------------------------------------

# 34. Stage and Programmer Must Cooperate

Stage is not merely a monitor.

It is also a fixture-selection surface.

Click a moving head:

``` text
Programmer shows only relevant supported families:
Intensity
Color
Position
Gobo
Beam
Focus
Zoom
Prism
...
```

Click several PARs:

``` text
Intensity
Color
Strobe
```

Click a mixed selection:

``` text
Programmer truthfully shows:
all support
partial support
mixed values
untouched values
```

Use the existing capability-aware Programmer presentation work.

Do not duplicate it in Stage.

------------------------------------------------------------------------

# 35. Bidirectional Selection

Required:

``` text
Fixture Browser selection
        ↕
Stage selection
        ↕
Programmer
        ↕
Inspector
```

Selecting fixtures anywhere should update the shared selection model.

Selecting a Group should highlight its member fixtures on Stage.

Selecting fixtures on Stage should make them immediately programmable.

------------------------------------------------------------------------

# 36. Stage Live Acceptance Scenario

Without physical fixtures connected:

``` text
1. Open a project.
2. Enter Stage.
3. Switch to Edit.
4. Place/arrange fixtures.
5. Add a truss/rectangle/text object.
6. Multi-select fixtures.
7. Align/distribute.
8. Rotate/scale.
9. Save/reopen.
10. Switch to Live.
11. Select fixtures from Stage.
12. Set intensity/color in Programmer.
13. Observe Stage.
14. Move a moving head.
15. Observe beam direction.
16. Fire a cue.
17. Observe cue fade.
18. Run an effect.
19. Trigger a MIDI-driven change.
20. Change Master.
21. Blackout.
22. Freeze.
23. Release Freeze.
```

The Stage should remain semantically consistent with physical output
throughout.

------------------------------------------------------------------------

# PART IV --- NAVIGATION / TASK-ORIENTED UX

# 37. Reduce Panel-Architecture Exposure

Do not require the operator to reason about Aurora's internal panel
taxonomy.

Prefer major task destinations such as:

``` text
PATCH
STAGE
PROGRAM
SHOW
PERFORM
```

Names can be adjusted to fit Aurora's established terminology.

The important point is hierarchy.

Example:

``` text
BUILD

  Patch Rig
  Stage
  Program Looks
  Build Show
```

The currently relevant Browser, Groups, Palettes, Inspector, Cue List,
etc. appear around the task.

------------------------------------------------------------------------

# 38. Preserve Aurora's Modular DNA

Task-oriented UX does **not** mean abandoning modular panels.

The implementation can still be:

``` text
FixtureBrowserPanel
ProgrammerPanel
InspectorPanel
CueListPanel
StageCanvas
PatchUniverseView
FixtureLibraryView
```

The user should simply not have to understand that component graph.

Architecture is for developers.

Workflow is for operators.

------------------------------------------------------------------------

# 39. Visual Direction

Retain Aurora's approved design language:

``` text
professional dark macOS creative workstation
charcoal surfaces
restrained purple/aurora accent
excellent typography
high information density without clutter
quiet status indicators
clear hierarchy
modern native interaction
```

Reference-class feel:

``` text
LightKey workflow simplicity
+
Logic/Xcode-grade macOS polish
+
Aurora's own creative lighting identity
```

Do not make the redesign look like a generic admin dashboard.

Do not solve usability by adding more buttons.

------------------------------------------------------------------------

# 40. Progressive Disclosure

Keep ordinary workflows simple.

Primary Patch surface:

``` text
Fixture
Mode
Quantity
Universe
Address
```

Advanced fixture metadata belongs in Inspector/Profile Editor.

Primary Stage surface:

``` text
Select
Move
Arrange
Live Preview
```

Advanced geometry belongs in Inspector/toolbars.

The most common action should require the least explanation.

------------------------------------------------------------------------

# 41. Context Menus

Use context menus for secondary operations.

Patch fixture:

``` text
Rename
Duplicate
Repatch
Move to Universe
Renumber
Locate
Remove
Inspect Profile
```

Stage fixture:

``` text
Locate
Select Group
Bring Forward
Send Backward
Lock
Hide
Remove From Stage
Inspect Fixture
```

Do not put all of these permanently in the toolbar.

------------------------------------------------------------------------

# 42. Drag-and-Drop Must Be First-Class

This redesign depends heavily on drag interactions.

Implement proper:

``` text
drag preview
drop validation
snap feedback
cursor feedback
undo
keyboard modifier behavior
accessibility alternatives
```

Drag/drop must not bypass Aurora's existing command/validation
architecture.

------------------------------------------------------------------------

# PART V --- TESTING

# 43. Patch Tests

Add tests for:

``` text
batch drop at valid address
batch drop collision
batch drop beyond 512
batch drop across fixture footprint
next-free patch
repatch drag
cross-universe repatch
undo/redo
mode footprint change
quantity footprint calculation
save/reopen
```

------------------------------------------------------------------------

# 44. Stage Editing Tests

Add tests for:

``` text
fixture placement
multi-selection
move
rotation
scale
align
distribute
grid snap
scenic object persistence
layer ordering
lock
visibility
fit bounds
save/reopen
```

------------------------------------------------------------------------

# 45. Stage Semantic Parity Tests

Test the real authoritative engine path:

``` text
Programmer
Cue playback
Cue fade
Effect
MIDI-driven action
Master
Blackout
Freeze
Manual jump
```

For each applicable case:

``` text
authoritative semantic state
        ↓
Stage
        +
DMX
```

must agree.

Do not manually reconstruct an approximation inside the test.

------------------------------------------------------------------------

# 46. Performance Tests

Test:

``` text
80 fixtures
mixed fixture types
multiple moving heads
multiple beams visible
effects running
cue fade active
Stage open
Programmer interaction
```

Stage may render at a lower visual refresh rate than DMX.

The engine must remain stable and responsive.

------------------------------------------------------------------------

# PART VI --- IMPLEMENTATION ORDER

# 47. Recommended Waves

## Wave 1 --- Navigation / Workspace Restructure

-   make Patch substantial workspace
-   make Stage central workspace
-   preserve existing components
-   establish task-oriented navigation
-   no deep feature rewrite yet

## Wave 2 --- Visual Universe Patch Surface

-   fixture library
-   mode
-   quantity
-   universe grid
-   fixture footprint blocks
-   drag/drop
-   ghost validation
-   next-free
-   repatch drag
-   List alternate view

## Wave 3 --- Stage Editing UX

-   full central canvas
-   fixture symbols
-   multi-select
-   marquee
-   rotate/scale
-   align/distribute
-   grid/snap
-   zoom/pan/fit
-   scenic objects
-   Inspector integration

## Wave 4 --- Authoritative Live Stage

-   resolved semantic frame architecture
-   remove AppModel reconstruction
-   intensity/color
-   movement
-   beams
-   strobe
-   fog/haze/laser schematic states
-   dominant background
-   Freeze correctness

## Wave 5 --- Cross-Surface Integration

-   Stage ↔ Browser
-   Stage ↔ Groups
-   Stage ↔ Programmer
-   Stage ↔ Inspector
-   Patch ↔ Inspector
-   Patch ↔ Stage placement awareness

## Wave 6 --- Tests / Performance / Visual Review

-   automated tests
-   large-rig test
-   macOS Debug build
-   screenshot review
-   workflow review
-   update parity matrix with evidence

------------------------------------------------------------------------

# 48. Hard Stop / Visual Review

Before declaring this redesign complete, capture and review at least:

``` text
Patch empty universe
Patch populated universe
Patch quantity=4 drag preview
Patch collision preview
Patch multi-universe project
Stage Edit simple rig
Stage Edit complex rig
Stage multi-selection
Stage scenic objects
Stage Live color/intensity
Stage Live moving-head beams
Stage Live cue transition
Stage Live Blackout
Stage Live Freeze
Stage with ~80 fixtures
```

Do not mark the UX complete merely because unit tests pass.

------------------------------------------------------------------------

# 49. Success Criteria --- Patch

Patch is successful when a new operator can reasonably infer:

> "Find my fixture, choose the mode and how many I have, then put them
> where they live in DMX."

without being taught Aurora's internal data model.

Checklist:

``` text
[ ] Fixture library is obvious
[ ] Search is fast
[ ] Mode selection is obvious
[ ] Quantity is obvious
[ ] Universe is visually represented
[ ] Fixture footprints are spatially obvious
[ ] Drag-to-address works
[ ] Batch preview works
[ ] Collision preview works
[ ] Invalid drops are rejected clearly
[ ] Existing fixtures can be dragged/repatched
[ ] Next-free workflow exists
[ ] Undo/redo works
[ ] List view remains available for power administration
```

------------------------------------------------------------------------

# 50. Success Criteria --- Stage

Stage is successful when it feels like an actual representation of the
rig rather than a diagnostic panel.

Checklist:

``` text
[ ] Stage is a major central workspace
[ ] Edit and Live modes are obvious
[ ] Fixture types have recognizable symbols
[ ] Fixtures can be multi-selected
[ ] Marquee selection works
[ ] Move works
[ ] Rotate works
[ ] Scale works
[ ] Align works
[ ] Distribute works
[ ] Grid works
[ ] Snap works
[ ] Zoom works
[ ] Pan works
[ ] Fit Stage works correctly
[ ] Fit Selection works
[ ] Scenic objects are useful
[ ] Inspector is contextual
[ ] Browser ↔ Stage selection is synchronized
[ ] Group ↔ Stage selection is synchronized
[ ] Stage ↔ Programmer selection is synchronized
[ ] Live intensity is visible
[ ] Live color is visible
[ ] Moving-head orientation is visible
[ ] Virtual beams are useful
[ ] Cue fades are visible
[ ] Effects are visible
[ ] MIDI-driven changes are visible
[ ] Master is visible
[ ] Blackout is correct
[ ] Freeze is correct
[ ] Dominant background remains tasteful
[ ] Stage rendering cannot destabilize DMX output
```

------------------------------------------------------------------------

# 51. Final Product Direction

The goal is **not**:

> "Make Aurora look like LightKey."

The goal is:

> **Give Aurora the same immediate lighting-operator clarity that makes
> LightKey pleasant to use, while retaining Aurora's more modern
> architecture, richer MIDI ambitions, modularity, and visual
> identity.**

For these two workflows, prioritize the operator's physical mental
model.

For Patch:

``` text
REAL WORLD:
"I own four of these fixtures and they start at DMX 101."

AURORA:
Find fixture → Quantity 4 → Drag to 101
```

For Stage:

``` text
REAL WORLD:
"These are my lights, this is where they are, and this is what they're doing."

AURORA:
Arrange them visually → select them visually → watch them behave visually
```

If Aurora requires the operator to translate either thought into
software architecture before acting, the UX still needs work.

------------------------------------------------------------------------

# 52. Instruction to Grok

Implement this as a focused UX correction pass.

Do not respond by merely adding buttons to the current Patch and Stage
panels.

Do not discard correct backend work.

Restructure the **interaction surfaces** around the workflows described
above.

When finished:

1.  run tests,
2.  run macOS Debug build,
3.  capture the required visual states,
4.  update the parity matrix with evidence,
5.  document remaining discrepancies,
6.  stop for review before proceeding with unrelated UI expansion.

**Patch should feel like patching a lighting rig.**

**Stage should feel like looking at and manipulating the lighting rig.**

That is the acceptance standard.
