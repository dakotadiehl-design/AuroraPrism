# Aurora Patch & Stage Visual Overhaul

## Corrected Grok Implementation Plan Directive

**Status:** Required re-plan before implementation\
**Priority:** High\
**Applies to:** Current production Aurora UI after the Patch/Stage UX
redesign work\
**Supersedes for this task:** Any interpretation that this is a UI-01C
component-gallery or general design-system refinement pass

------------------------------------------------------------------------

# 0. STOP: The Previous Plan Misidentified the Scope

Do **not** execute the previously proposed:

> `Aurora UI-01C — High-Fidelity Visual Alignment Plan`

as written.

That plan contains useful design-language observations, but it targets
the wrong implementation layer.

The current task is **not**:

-   a return to UI-01C
-   a component-gallery refinement project
-   a broad Aurora design-system rewrite
-   a Programmer redesign
-   a Cue List redesign
-   a Perform cockpit redesign
-   a MIDI Settings redesign
-   a general polish pass over every shared component
-   a new product-roadmap phase

The current task **is**:

> **A focused visual and interaction overhaul of the actual running
> production Patch and Stage workspaces.**

The supplied files:

``` text
Aurora_Patch_Stage_Visual_Overhaul_Reference.pdf
Aurora_Patch_Stage_Visual_Overhaul_Grok_Instructions.md
```

are specifically intended to guide the **production Patch and Stage
UI**.

The production application, not a component gallery, is the acceptance
surface.

------------------------------------------------------------------------

# 1. Why the Previous Plan Was Wrong

The previous plan proposed a flow approximately like:

``` text
Design token audit
        ↓
Shared component refinement
        ↓
Component gallery compositions
        ↓
Gallery screenshots
        ↓
STOP
        ↓
Production screens inherit polish later
```

That is not the requested work.

Aurora has already passed through the UI-01/UI-01C design-system and
gallery phases.

The current usability problem is visible in the **running application**:

-   Patch has the right backend concepts but does not yet visually feel
    like patching a lighting rig.
-   Stage has the right functional ingredients but does not yet visually
    feel like manipulating and watching a lighting rig.
-   The UI exposes too many controls at equal visual weight.
-   The rig itself is not sufficiently dominant.
-   Patch/Stage still inherit too much generic workspace chrome.
-   Stage toolbars can read like a requirements checklist.
-   The lower Cue/Palette/Song/Console workspace competes with
    Patch/Stage for screen area.
-   The visual hierarchy does not yet match the supplied Patch/Stage
    reference.

Therefore, a beautiful component gallery would **not** solve the current
problem.

------------------------------------------------------------------------

# 2. Correct Product Goal

Aurora should feel like:

> **A visual lighting workstation where the rig itself is the primary
> interface.**

The target combination is:

``` text
LightKey-level workflow clarity
+
modern native macOS creative-workstation polish
+
Aurora's own visual identity
```

Do not pixel-copy LightKey.

Do adopt the interaction principle that makes LightKey easy to
understand:

> Manipulate the lighting concept itself whenever possible instead of
> manipulating a form that describes it.

Examples:

``` text
Patch fixture
→ place fixture directly in DMX space

Repatch fixture
→ drag fixture to a new address

Place fixture on Stage
→ drag fixture onto Stage

Select fixture
→ click fixture

Program fixture
→ select it visually and use Programmer

Inspect fixture
→ selection drives Inspector

Watch show
→ Stage displays authoritative resolved lighting state
```

------------------------------------------------------------------------

# 3. Authoritative Visual Reference

For this task, the primary visual reference is:

``` text
Aurora_Patch_Stage_Visual_Overhaul_Reference.pdf
```

Treat it as a **design reference for the production application**, not
as a loose mood board.

The exact pixels need not be copied blindly, but the following hierarchy
is intentional:

``` text
PROGRAM | PATCH | STAGE | PROFILES
```

and, specifically:

## Patch

``` text
Fixture Library
      |
      v
Visual DMX Universe
      |
      v
Contextual Inspector
```

## Stage

``` text
Fixtures / Groups
      |
      v
Large Stage Canvas
      |
      v
Contextual Inspector
```

The center canvas/work area must visually dominate.

------------------------------------------------------------------------

# 4. Existing UI-01C Work Is Supporting Infrastructure Only

The previous plan correctly identified useful existing infrastructure:

``` text
AuroraColor
AuroraTypography
AuroraSpacing
AuroraDensity
AuroraMetrics
AuroraPanel*
AuroraButton
AuroraStatusIndicator
AuroraModeToggle
lighting icons
etc.
```

Reuse these.

Refine them **only where necessary** to make the production Patch/Stage
screens match the new reference.

Do not make broad token/component refinement the primary deliverable.

Correct relationship:

``` text
Production Patch/Stage need visual improvement
        ↓
Use existing Aurora design system
        ↓
Refine a shared component/token only if production Patch/Stage require it
        ↓
Validate in production Patch/Stage
```

Incorrect relationship:

``` text
Polish entire design system
        ↓
Polish gallery
        ↓
Assume Patch/Stage will eventually improve
```

------------------------------------------------------------------------

# 5. Explicitly Out of Scope

Unless a production Patch/Stage dependency requires a tiny shared
adjustment, do **not** broadly redesign:

-   Programmer
-   detailed Programmer controls
-   Cue List
-   palette shelves
-   look tiles
-   Perform cockpit
-   GO transport
-   MIDI Mapping Settings
-   Web Remote
-   Effects
-   Output configuration
-   splash screen
-   unrelated Settings screens
-   component gallery compositions

Do not spend this pass polishing:

``` text
AuroraFader
AuroraMasterFader
AuroraPositionPad
AuroraColorWheel
AuroraBeamWell
AuroraGoboMatrix
AuroraCueRow
AuroraPaletteTile
AuroraLookTile
```

unless a specific production Patch/Stage dependency requires it.

This task has a narrow UX fire to extinguish.

------------------------------------------------------------------------

# 6. Correct Implementation Strategy

Re-plan around four production checkpoints:

``` text
CHECKPOINT A
Production Workspace Shell
        ↓
HUMAN VISUAL REVIEW
        ↓
CHECKPOINT B
Production Patch
        ↓
HUMAN VISUAL REVIEW
        ↓
CHECKPOINT C
Production Stage Edit
        ↓
HUMAN VISUAL REVIEW
        ↓
CHECKPOINT D
Production Stage Live
        ↓
HUMAN VISUAL REVIEW
```

Do not automatically execute A through D in one uninterrupted
implementation run.

The visual checkpoints are intentional.

------------------------------------------------------------------------

# 7. CHECKPOINT A --- Production Workspace Shell

## Goal

Make the **actual launched Aurora application** establish the correct
Patch/Stage visual hierarchy before implementing deeper polish.

This checkpoint should be relatively small.

Do not implement every final Patch/Stage interaction here.

### Production code is the target

Work in the actual production host and relevant production views,
including as appropriate:

``` text
BuildWorkspaceHost
PatchWorkspaceView
Stage workspace / StagePanel / StageCanvas host
production toolbar/navigation
production Inspector host
production Fixture Browser / Stage fixture tray
```

Do not make `AuroraComponentGallery` the deliverable.

------------------------------------------------------------------------

# 8. Checkpoint A --- Required Global Navigation

The running application should clearly communicate major Build tasks.

Use the approved equivalent of:

``` text
PROGRAM   PATCH   STAGE   PROFILES
```

The exact native control may be a segmented workspace selector, toolbar
item group, or equivalent Aurora component.

Requirements:

-   obvious current workspace
-   restrained Aurora accent
-   no oversized decorative navigation
-   feels native to a professional macOS creative application
-   no ambiguity about whether Patch/Stage are tiny subpanels or major
    workspaces

------------------------------------------------------------------------

# 9. Checkpoint A --- Program Must Not Regress

Program mode should preserve the already-working programming workspace.

Do not use this task to redesign Program.

Acceptance:

``` text
PROGRAM
→ existing Programmer-centric workflow remains functional
→ existing approved panels remain available
→ no backend behavior regression
```

The goal is to make Patch/Stage more task-specific without damaging
Program.

------------------------------------------------------------------------

# 10. Checkpoint A --- Patch Must Own the Center

When Patch is selected, the production application should visibly
transform into a Patch workspace.

Target skeleton:

``` text
┌──────────────────────────────────────────────────────────────┐
│ AURORA        PROGRAM  PATCH  STAGE  PROFILES      STATUS   │
├───────────────┬─────────────────────────────┬────────────────┤
│ FIXTURE       │                             │ INSPECTOR      │
│ LIBRARY       │                             │                │
│               │       DMX UNIVERSE          │                │
│ Search        │                             │                │
│ Favorites     │                             │                │
│ Manufacturers │                             │                │
│ Recent        │                             │                │
│               │                             │                │
├───────────────┴─────────────────────────────┴────────────────┤
│ compact contextual Patch controls only                      │
└──────────────────────────────────────────────────────────────┘
```

The DMX universe is the visual center of gravity.

------------------------------------------------------------------------

# 11. Checkpoint A --- Stage Must Own the Center

When Stage is selected:

``` text
┌──────────────────────────────────────────────────────────────┐
│ AURORA        PROGRAM  PATCH  STAGE  PROFILES      STATUS   │
├───────────────┬─────────────────────────────┬────────────────┤
│ FIXTURES      │                             │ INSPECTOR      │
│ & GROUPS      │                             │                │
│               │          STAGE              │                │
│ UNPLACED      │                             │                │
│ ON STAGE      │                             │                │
│               │                             │                │
│ Groups        │                             │                │
│               │                             │                │
├───────────────┴─────────────────────────────┴────────────────┤
│ compact contextual Stage controls only                      │
└──────────────────────────────────────────────────────────────┘
```

The Stage canvas must receive the majority of useful screen area.

The screen should visually say:

> "This is your stage."

not:

> "This is a panel containing Stage-related controls."

------------------------------------------------------------------------

# 12. Checkpoint A --- Hide the Unrelated Lower Workspace

This is required.

In Patch and Stage, hide by default the large lower workspace containing
things such as:

``` text
Cue List
Palettes
Song
Console
Universe Monitor
MIDI
```

Those tools may remain accessible intentionally if the architecture
supports revealing them.

But they must not consume a large percentage of Patch/Stage by default.

### Reason

Program is naturally a multi-panel programming environment.

Patch and Stage are spatial tasks.

They need canvas area.

Correct:

``` text
PATCH
→ Patch owns center and vertical space

STAGE
→ Stage owns center and vertical space
```

Incorrect:

``` text
STAGE
→ Stage gets upper half
→ unrelated Cue List permanently gets lower half
```

------------------------------------------------------------------------

# 13. Checkpoint A --- Restrained Toolbars

Do not expose every implemented operation as a permanent button.

Avoid Stage toolbars resembling:

``` text
Edit
Live
Fit Stage
Fit Sel
-
+
100%
Reveal
Align L
Align C
Align R
Align T
Align B
Dist H
Dist V
+ Stage Area
+ Scenic
Rotation slider
...
```

This may be functionally complete but visually communicates no
hierarchy.

Instead establish a compact grammar.

Example:

``` text
EDIT | LIVE

Pointer
Pan
Marquee

Fit ▾
Zoom

Align ▾
Distribute ▾

+ Add ▾
```

Use:

-   icons
-   tooltips
-   menus
-   popovers
-   Inspector
-   context menus

for secondary operations.

### Core rule

> **Content first. Context second. Controls third.**

------------------------------------------------------------------------

# 14. Checkpoint A --- Required Screenshot Package

After implementing only the production shell hierarchy, run the actual
Aurora application.

Capture:

``` text
1. Program workspace
2. Patch workspace
3. Stage workspace
```

At this point:

-   Patch does not need every final fixture-card treatment.
-   Stage does not need every final beam effect.
-   The workspace hierarchy **does** need to be correct.

### STOP

Do not proceed to Checkpoint B until these screenshots are reviewed.

------------------------------------------------------------------------

# 15. CHECKPOINT B --- Production Patch Visual Overhaul

After Checkpoint A approval, refine the real Patch workspace.

The primary mental model is:

``` text
Find fixture
→ choose mode
→ choose quantity
→ put fixtures where they live in DMX
```

------------------------------------------------------------------------

# 16. Patch --- Fixture Library

The Fixture Library should feel like a library, not merely a database
list.

Support:

``` text
Search
Favorites
Recent
Manufacturer
Fixture model
Mode/personality
User fixtures
Generic fixtures
```

Prefer visually meaningful fixture/profile cards.

Example:

``` text
┌──────────────────────────┐
│ [fixture icon] LP12 HEX  │
│                Chauvet   │
│                8ch       │
└──────────────────────────┘
```

Use existing Aurora lighting iconography where appropriate.

Do not create giant decorative cards.

Keep density professional.

------------------------------------------------------------------------

# 17. Patch --- Preparation Strip

When a fixture/profile is selected, expose the common patch parameters
clearly:

``` text
Fixture
Mode
Quantity
Name Prefix
Footprint
```

Primary actions:

``` text
PATCH
NEXT FREE
```

Do not crowd this area with:

``` text
CSV
Report
Renumber
Bulk metadata
diagnostic operations
```

Those remain secondary tools.

------------------------------------------------------------------------

# 18. Patch --- Visual Universe

The universe is the hero.

Prefer a wrapped spatial representation of the 512-channel address
space.

Initial target:

``` text
001 ───────────────────────── 032
033 ───────────────────────── 064
065 ───────────────────────── 096
097 ───────────────────────── 128
...
481 ───────────────────────── 512
```

Exact responsive geometry may vary.

Important principle:

> Fixture blocks are the information. Empty DMX channels are the
> coordinate system.

Therefore:

-   fixture blocks visually dominate
-   empty cells recede
-   channel labels act as landmarks
-   avoid making all 512 channel numbers equally visually loud
-   avoid tiny spreadsheet-like cells that become unreadable

------------------------------------------------------------------------

# 19. Patch --- Fixture Blocks

Where space permits, show:

``` text
Fixture Name
Model
Address Range
```

Example:

``` text
LP12 1
LP12 Hex
101–108
```

At smaller widths, progressively reduce information.

Hover and Inspector expose full metadata.

Visually distinguish:

``` text
normal
selected
hover
valid ghost
invalid ghost
patch problem
```

Use restrained semantic states.

------------------------------------------------------------------------

# 20. Patch --- Three Equivalent Placement Workflows

All must share the same validation and command path.

## Drag

``` text
Fixture card
→ drag to address
→ ghost complete quantity
→ drop
```

## Patch then click

``` text
Fixture
→ PATCH
→ click starting address
→ preview
→ commit
```

## Next Free

``` text
Fixture
→ NEXT FREE
→ first contiguous valid range
```

Existing fixture blocks should be draggable for repatching.

Invalid placement should be explained, not silently moved.

------------------------------------------------------------------------

# 21. Patch --- Power Tools Are Secondary

Retain useful functionality:

``` text
List View
CSV import/export
Patch report
Renumber
Bulk operations
Clone
diagnostics
```

But place these in:

-   secondary toolbar menus
-   context menus
-   Inspector
-   alternate List view

Do not allow them to compete visually with ordinary patching.

------------------------------------------------------------------------

# 22. Checkpoint B Screenshot Package

Capture production screenshots of:

``` text
1. Empty universe
2. Populated universe
3. Selected fixture
4. Quantity = 4 valid ghost placement
5. Invalid/collision ghost
6. Alternate List view
7. Multiple universes if implemented
```

Compare directly with the supplied PDF.

### STOP

If the running Patch screen is not visually recognizable as the
reference family, do not continue to Stage polish.

------------------------------------------------------------------------

# 23. CHECKPOINT C --- Production Stage Edit Overhaul

After Patch visual approval, refine Stage Edit.

Primary mental model:

``` text
These are my lights.
This is where they are.
```

The Stage canvas is the hero.

------------------------------------------------------------------------

# 24. Stage --- Left Fixture/Group Tray

Clearly distinguish:

``` text
FIXTURES

UNPLACED
  Front Wash L
  Front Wash R
  Mover 1
  Mover 2

ON STAGE
  Drum Wash
  Guitar Wash
  Backlight 1

GROUPS
  Front
  Movers
  Backlights
```

Unplaced fixtures should be directly draggable onto Stage.

Provide:

``` text
PLACE ALL UNPLACED
```

for large rigs.

------------------------------------------------------------------------

# 25. Stage --- Placement Semantics

Preserve the distinction:

``` text
Fixture exists
≠
Fixture is patched
≠
Fixture has Stage placement
```

Therefore:

``` text
Remove From Stage
```

removes only Stage placement.

It must **not**:

-   delete fixture
-   unpatch fixture
-   remove fixture from groups
-   destroy programming references

After removal, the fixture returns to Unplaced.

------------------------------------------------------------------------

# 26. Stage --- Canvas

The canvas should occupy most of the central area.

It should feel closer to a professional graphics/lighting workspace than
a form editor.

Support the existing Stage capabilities, but present them visually
around the canvas rather than competing with it.

------------------------------------------------------------------------

# 27. Stage --- Fixture Symbols

Do not use generic dots for every fixture.

Use recognizable Aurora-native schematic symbols for categories such as:

``` text
PAR / wash
moving head
spot/profile
bar/batten
blinder
strobe
laser
fog/haze
pixel/matrix
generic
```

Symbols should be:

-   readable at small sizes
-   scalable
-   rotatable
-   visually consistent
-   professional
-   schematic, not photorealistic

------------------------------------------------------------------------

# 28. Stage --- Edit Controls

Keep common tools visible:

``` text
Edit / Live
Pointer
Pan
Marquee
Zoom
Fit
Reveal
Add
```

Move secondary operations into compact controls:

``` text
Align ▾
Distribute ▾
+ Add ▾
```

`+ Add` may contain:

``` text
Stage Area
Truss
Rectangle
Line
Text
Image
```

Avoid permanent buttons for every object type.

------------------------------------------------------------------------

# 29. Stage --- Selection Semantics

Use graphics-editor semantics:

``` text
Click
→ replace

Shift-click
→ add

Command-click
→ toggle

Marquee
→ replace

Shift-marquee
→ add

Command-A
→ select relevant Stage items

Escape
→ clear when safe
```

Selection must remain synchronized with the shared Aurora selection
authority.

------------------------------------------------------------------------

# 30. Stage --- Inspector

Inspector follows context.

Fixture selection:

``` text
Fixture identity
Patch
Position
Rotation
Scale
Layer
Label
Beam display
capabilities
```

Scenic object:

``` text
type
position
size
rotation
layer
lock
visibility
text/style where relevant
```

Multi-selection:

``` text
count
shared values
mixed values
alignment/distribution
```

Do not permanently expose all of these on the canvas toolbar.

------------------------------------------------------------------------

# 31. Stage --- Scenic Objects

Baseline:

``` text
Stage Area
Truss
Rectangle
Line
Text
Image/background if supported
```

This is schematic stage visualization, not CAD.

Do not expand scope into architectural drawing.

------------------------------------------------------------------------

# 32. Checkpoint C Screenshot Package

Capture:

``` text
1. Empty Stage with Unplaced tray
2. Populated Stage
3. Fixture being placed
4. Single fixture selected
5. Multiple fixtures selected
6. Stage Area + truss + text/scenic object
7. Contextual Inspector
8. Add menu
9. Align/Distribute access
```

### STOP

Review the actual running application before Stage Live polish.

------------------------------------------------------------------------

# 33. CHECKPOINT D --- Production Stage Live

Primary mental model:

``` text
These are my lights.
This is what they are doing.
```

Live mode protects geometry but remains interactive.

------------------------------------------------------------------------

# 34. Live Mode Is Not Inert

In Live:

``` text
Click fixture
→ select fixture
→ shared selection updates
→ Programmer updates
→ change lighting
→ Stage reflects authoritative result
```

Still allow:

``` text
selection
group selection
Inspector
Programmer interaction
pan
zoom
Fit
Reveal
```

Protect against accidental:

``` text
move
rotate
scale
scenic-object edits
```

------------------------------------------------------------------------

# 35. Stage Live Uses Authoritative Resolved State

This remains non-negotiable.

Do not reconstruct show intent separately in AppModel or Stage.

Conceptually:

``` text
Playback
Programmer
Effects
Masters
Blackout
Freeze
        ↓
AUTHORITATIVE RESOLVED SEMANTIC STATE
       ↙                         ↘
DMX/output                    Stage presentation
```

Stage may transform that semantic state into visual geometry, but must
not independently recalculate lighting intent.

------------------------------------------------------------------------

# 36. Stage Rendering Cadence

Stage presentation does not need to render at DMX cadence.

It may sample the authoritative state at an appropriate UI rate such as:

``` text
~20–30 FPS
```

as needed.

Requirements:

-   no Stage layout/rendering on output-critical path
-   physical output priority
-   smooth enough cue fades and movement
-   no semantic divergence caused by throttling

------------------------------------------------------------------------

# 37. Live Fixture State

Stage should visually communicate:

``` text
intensity
color
pan/tilt orientation
approximate beam direction
approximate beam width
shutter/strobe where useful
fog/haze state where useful
laser active state where useful
```

Do not attempt photorealistic simulation.

The goal is fast operational comprehension.

------------------------------------------------------------------------

# 38. Adaptive Beam Rendering

Allow automatic complexity scaling:

``` text
small rig
→ richer translucent beams

medium rig
→ simplified beam cones/wedges

large rig/high UI load
→ minimal directional geometry
```

Selected fixtures should retain useful beam detail.

Never sacrifice engine/output stability for prettier beams.

------------------------------------------------------------------------

# 39. Dominant Stage Background

Retain the approved behavior where Stage subtly reacts to the dominant
active look color.

Requirements:

-   restrained
-   smooth
-   readable
-   does not overpower fixture symbols
-   Blackout returns toward neutral/dark
-   Freeze semantics remain correct

This is atmosphere, not wallpaper.

------------------------------------------------------------------------

# 40. Checkpoint D Screenshot Package

Capture:

``` text
1. Live Stage with colored washes
2. Moving-head beams
3. Selected moving head
4. Programmer-driven color/intensity change
5. Programmer-driven movement
6. Cue transition
7. Effect active
8. MIDI-driven change where available
9. Master change
10. Blackout
11. Freeze
12. Large-rig / degraded-beam case
```

### STOP

Human review is required before unrelated UI expansion.

------------------------------------------------------------------------

# 41. Useful Ideas From the Rejected Plan That Should Be Retained

The previous plan contained good design-language observations.

Keep these as implementation principles.

## Surface hierarchy

``` text
application
→ workspace
→ panel
→ control surface
→ active/selected
```

Do not flatten everything into one black plane.

## Geometry

Do not make every object the same rounded rectangle.

Use:

-   tight geometry for lists/tables/inspectors
-   softer object presence for fixture/profile cards
-   appropriate canvas geometry for Stage
-   restrained borders and separators

## Density

Use context-specific density:

``` text
compact
→ lists, patch administration, diagnostics

standard
→ creative workspace controls

performance
→ large calm live controls where applicable
```

## Color

Use Aurora violet deliberately for:

``` text
selection
owned/active state
workspace identity
focus
```

Do not create purple wallpaper.

Fixture colors should represent actual lighting content.

Health colors represent health only.

## Purpose-built controls

Avoid generic stock SwiftUI appearance where the production Patch/Stage
reference clearly calls for a purpose-built Aurora component.

But do not broadly rewrite unrelated controls during this task.

------------------------------------------------------------------------

# 42. Production Acceptance Surface

This task is accepted based on:

``` text
the launched Aurora application
```

not:

``` text
AuroraComponentGallery
SwiftUI previews
isolated token boards
mock screenshots disconnected from production
```

Previews and galleries may be used internally during implementation.

They are not the final proof.

------------------------------------------------------------------------

# 43. Required Build/Behavior Verification

At every checkpoint:

``` text
swift test
xcodebuild Debug
```

as appropriate for the current repository.

Also verify:

-   project opens
-   demo/test show opens
-   Program still works
-   Patch selection/commands still work
-   Stage persistence still works
-   Inspector follows selection
-   no backend/domain semantics were unintentionally changed
-   no new high-frequency UI observation destabilizes the engine

Visual correctness does not excuse functional regression.

Functional correctness does not excuse missing visual hierarchy.

Both are required.

------------------------------------------------------------------------

# 44. Re-Planning Requirement

Before implementation, replace the previous UI-01C plan with a new plan
structured around:

``` text
Checkpoint A — Production Workspace Shell
Checkpoint B — Production Patch
Checkpoint C — Production Stage Edit
Checkpoint D — Production Stage Live
```

For each checkpoint, specify:

1.  production files expected to change
2.  visual hierarchy being implemented
3.  existing backend/components being reused
4.  interaction changes
5.  tests
6.  screenshots
7.  explicit STOP condition

Do not include a broad UI-01C gallery-refinement wave.

Do not make component-gallery approval a prerequisite for touching
production Patch/Stage.

------------------------------------------------------------------------

# 45. Immediate Next Task

The immediate implementation target is **Checkpoint A only**.

Do not begin Checkpoint B yet.

Checkpoint A should establish:

``` text
[ ] PROGRAM / PATCH / STAGE / PROFILES hierarchy
[ ] Patch owns central workspace
[ ] Stage owns central workspace
[ ] Patch uses Library / Universe / Inspector proportions
[ ] Stage uses Fixtures / Canvas / Inspector proportions
[ ] lower Cue/Palette/Song/Console region hidden by default in Patch
[ ] lower Cue/Palette/Song/Console region hidden by default in Stage
[ ] Patch toolbar restrained
[ ] Stage toolbar restrained
[ ] Program workflow preserved
[ ] actual production app screenshots captured
```

Then:

> **STOP AND RETURN THE SCREENSHOTS FOR VISUAL REVIEW.**

Do not proceed automatically.

------------------------------------------------------------------------

# 46. Final Direction to Grok

The previous plan understood much of Aurora's desired design language
but applied it to the wrong phase.

Do not go backward to UI-01C.

Do not spend this pass polishing the component gallery.

Do not broadly refactor every Aurora UI component.

Do not implement another giant uninterrupted UI wave.

Instead:

> **Take the production Patch and Stage workspaces that already exist
> and make the running Aurora application visually and behaviorally
> match the supplied Patch/Stage reference.**

The rig must become visually dominant.

Patch should immediately communicate:

> **Choose the lights you own and put them where they live in DMX.**

Stage should immediately communicate:

> **Arrange your rig, select it directly, program it, and watch it
> behave.**

Start with Checkpoint A.

Run the real application.

Capture the real application.

Then stop.
