# Aurora Design Workspace / Lightkey UX Alignment

## Implementation Directive for Grok

**Status:** High-priority UX architecture amendment\
**Timing:** Apply before deep Checkpoint C Stage implementation\
**Primary goal:** Unify lighting programming and 2D visualization into
one continuous creative workflow\
**Reference philosophy:** Lightkey's proven Preview + contextual Design
workflow, adapted to Aurora's architecture and visual language\
**Do not:** blindly pixel-clone Lightkey, duplicate rendering/state
logic, or make docking/floating windows a prerequisite for a good
single-screen workflow

------------------------------------------------------------------------

# 0. Executive Direction

Aurora's current top-level separation between **PROGRAM** and **STAGE**
creates an artificial boundary between two actions that must happen
together:

1.  selecting/programming fixtures, and
2.  seeing the visual result of that programming.

This must change.

The new core mental model is:

> **The rig is the primary object. The Programmer serves the rig.**

Aurora should behave much more like Lightkey in this area.

The user should be able to select fixtures or groups, modify
intensity/color/position/beam/etc., and see the result immediately on
the 2D Stage Preview **without changing workspaces**.

The Stage surface is therefore no longer merely a destination/tab.

> **Stage is a reusable visualization surface.**

The full Stage editing environment adds geometry-editing tools around
that surface, but the same Stage renderer must also be present in the
normal lighting-programming workflow.

------------------------------------------------------------------------

# 1. UX Problem Being Solved

Current conceptual flow:

``` text
PROGRAM
→ select fixtures
→ change color / position / intensity

then

STAGE
→ inspect visual result
```

This is too disconnected.

It forces a context switch between action and feedback.

Lighting programming should instead be:

``` text
Select fixtures on Stage or in Browser
        ↓
Contextual Programmer appears/updates
        ↓
Change intensity/color/position/etc.
        ↓
Stage updates immediately
        ↓
Continue programming while watching result
```

The feedback loop must be continuous.

This is a **must-have workflow**, not an optional convenience feature.

------------------------------------------------------------------------

# 2. Lightkey UX Principle to Adopt

Aurora may unashamedly borrow Lightkey's core UX philosophy here.

The important concept is not superficial styling. It is the relationship
between:

-   visual Preview,
-   fixture selection,
-   contextual fixture-property controls,
-   live feedback,
-   stage-layout editing.

The Preview should remain visible during normal programming.

The fixture-property editor should adapt to the currently selected
fixtures.

The user should not need a second monitor, floating window, or workspace
switch merely to see the result of a programming change.

Aurora should preserve its own visual identity, backend architecture,
Song workflow, Inspector, advanced MIDI capabilities, and future
extensibility.

------------------------------------------------------------------------

# 3. Revised Top-Level Workspace Model

The current:

``` text
PROGRAM | PATCH | STAGE | PROFILES
```

should be reconsidered.

Preferred direction:

``` text
DESIGN | PATCH | PROFILES
```

while retaining the higher-level:

``` text
BUILD | PERFORM
```

application modes if already established.

## Why DESIGN?

"Design" naturally includes both:

-   designing the lighting state, and
-   designing the physical Stage layout.

This removes the artificial conceptual wall between PROGRAM and STAGE.

### Alternative naming

If changing the navigation label is considered too disruptive
immediately, the implementation may temporarily retain `PROGRAM`, but
the architecture and layout must still follow this directive.

Do **not** let naming block the UX change.

Preferred long-term name: **DESIGN**.

------------------------------------------------------------------------

# 4. New Default DESIGN Workspace

The default single-screen workspace should resemble:

``` text
┌──────────────────────────────────────────────────────────────┐
│ AURORA              DESIGN | PATCH | PROFILES     BUILD ... │
├──────────────┬──────────────────────────────┬────────────────┤
│ FIXTURES     │                              │ INSPECTOR      │
│ & GROUPS     │                              │                │
│              │        STAGE PREVIEW         │                │
│ Groups       │                              │                │
│ Fixtures     │                              │                │
│              │                              │                │
├──────────────┴──────────────────────────────┴────────────────┤
│ CONTEXTUAL PROGRAMMER                                       │
│ Intensity | Position | Color | Beam | Gobo | ...            │
├──────────────────────────────────────────────────────────────┤
│ PALETTES | CUES | SONG | DIAGNOSTICS                        │
└──────────────────────────────────────────────────────────────┘
```

The exact proportions may be tuned responsively.

The hierarchy is what matters:

``` text
1. Stage Preview / rig
2. Fixture selection
3. Contextual Programmer
4. Inspector
5. Cue/Palette/Song shelf
```

The Stage Preview should receive substantial visual area.

------------------------------------------------------------------------

# 5. Stage Preview Is the Visual Heart

During ordinary lighting programming, the Stage Preview must remain
available by default.

It displays the same Stage model used by Stage editing.

It must reflect the authoritative resolved lighting state.

Examples:

``` text
Change color
→ fixture/beam color updates immediately

Change intensity
→ preview intensity updates immediately

Change pan/tilt
→ fixture orientation/beam updates immediately

Apply fan
→ fixture beams spread visibly

Apply effect
→ preview animates effect

Fire cue
→ preview follows transition

Change master
→ preview follows master

Blackout
→ preview goes dark

Freeze
→ preview respects Freeze semantics

MIDI input changes a property
→ preview follows that resolved result
```

Do not create a second independent "preview lighting engine."

------------------------------------------------------------------------

# 6. Shared Authoritative State

The architecture should remain conceptually:

``` text
Playback
Programmer
Effects
MIDI
Masters
Blackout
Freeze
        ↓
AUTHORITATIVE RESOLVED SEMANTIC STATE
       ↙                         ↘
DMX / output                 Stage Renderer
                                  │
                     ┌────────────┴────────────┐
                     ▼                         ▼
               DESIGN Preview           Stage Edit mode
```

There is one semantic truth.

Stage presentation consumes it.

Do not duplicate show-intent resolution in:

-   AppModel
-   Design workspace
-   Stage workspace
-   Preview-specific models

Presentation may throttle rendering independently, but semantic state
must remain shared.

------------------------------------------------------------------------

# 7. Stage Renderer Must Be Reusable

Refactor Stage presentation if necessary so it is **not owned
exclusively by a STAGE tab**.

Preferred conceptual separation:

``` text
StageModel
StagePresentationState
StageRenderer / StageCanvas
StageSelectionBridge
```

Then compose that renderer into different contexts.

## Context A --- DESIGN Preview

Capabilities:

-   live visualization
-   fixture selection
-   group-aware selection
-   pan
-   zoom
-   Fit
-   Reveal
-   optional contextual HUDs later

Geometry editing is disabled by default.

## Context B --- Stage Edit

Same Stage model and renderer, plus:

-   fixture placement
-   move
-   rotate
-   scale if supported
-   scenic objects
-   truss
-   Stage Area
-   text
-   alignment
-   distribution
-   Remove From Stage
-   Add menu
-   geometry Inspector controls

Do not fork the renderer.

------------------------------------------------------------------------

# 8. Stage Editing Should Happen In Place

Do not require navigation to a separate major workspace merely to
arrange the Stage.

Provide a clear control inside DESIGN Preview such as:

``` text
[ Edit Stage ]
```

or:

``` text
Mode:  Live/Program | Edit Stage
```

Normal state:

``` text
DESIGN / PROGRAMMING MODE
→ geometry protected
→ fixture selection enabled
→ live output visible
→ programming enabled
```

Edit Stage state:

``` text
EDIT STAGE
→ geometry editing enabled
→ scenic-object tools available
→ placement enabled
→ alignment/distribution enabled
→ lighting preview may remain visible where useful
```

Exit Edit Stage:

``` text
→ geometry locks again
→ normal programming continues
→ no workspace navigation required
```

This should feel like changing the canvas tool mode, not leaving the
creative workspace.

------------------------------------------------------------------------

# 9. Selection Must Be Shared Everywhere

Selection is central to this design.

There should be one authoritative fixture/group selection concept shared
among:

``` text
Fixture Browser
Stage Preview
Programmer
Inspector
Groups
Cue/Palette operations where relevant
```

## Example: select a group

User clicks:

``` text
MOVERS
```

Result:

``` text
Fixture Browser
→ Movers selected

Stage Preview
→ all mover fixtures highlighted

Programmer
→ capabilities common/relevant to selected movers appear

Inspector
→ group information appears
```

## Example: select on Stage

User clicks one moving head on Preview:

``` text
Stage Preview
→ fixture selected

Fixture Browser
→ corresponding fixture highlighted/scrolled if appropriate

Programmer
→ exposes fixture capabilities

Inspector
→ fixture details
```

## Multi-selection

Support normal macOS/graphics semantics:

``` text
Click
→ replace selection

Shift-click
→ add

Command-click
→ toggle

Marquee where appropriate
→ replace/add depending modifier
```

Do not maintain separate "Stage selection" and "Programmer selection"
states that can drift.

------------------------------------------------------------------------

# 10. Contextual Programmer

The current Programmer should evolve from a large destination panel into
a **context-sensitive property deck** attached to the visual rig.

Aurora already has capability-aware behavior. Preserve and expand it.

The controls shown should depend on the selected fixtures.

## Example --- RGB washes

``` text
┌─────────────┐ ┌───────────────────────────────┐
│ INTENSITY   │ │ COLOR                         │
│             │ │                               │
│   fader     │ │        color wheel            │
│             │ │                               │
└─────────────┘ └───────────────────────────────┘
```

## Example --- moving heads

``` text
┌───────────┐ ┌────────────────┐ ┌────────────────┐
│ INTENSITY │ │ POSITION       │ │ COLOR          │
│           │ │                │ │                │
│  fader    │ │    XY pad      │ │  color wheel   │
│           │ │                │ │                │
└───────────┘ └────────────────┘ └────────────────┘
```

## Example --- advanced profile fixture

Potential capabilities:

``` text
INTENSITY
POSITION
COLOR
GOBO
PRISM
IRIS
FOCUS
ZOOM
FROST
SHUTTER/STROBE
```

Only relevant capabilities should appear.

Avoid showing disabled/meaningless controls merely because the
application supports them globally.

------------------------------------------------------------------------

# 11. Programmer Layout Must Be Responsive

Do not assume one fixed Programmer geometry.

The property deck should adapt to:

-   available window width
-   selected fixture capabilities
-   Stage Preview size
-   Inspector visibility
-   lower shelf visibility

Possible behavior:

``` text
wide window
→ controls arranged horizontally

medium window
→ primary controls horizontal, secondary controls wrapped

narrow window
→ compact tabs/sections or horizontally scrollable property deck
```

Do not make the user choose between seeing Stage and having usable
Programmer controls.

------------------------------------------------------------------------

# 12. Live Visual Feedback During Direct Manipulation

Changes should appear in Stage Preview while the interaction is
occurring, not only after mouse-up.

Examples:

``` text
drag intensity fader
→ preview dims continuously

drag position puck
→ beam moves continuously

drag color selector
→ beam/color changes continuously

adjust zoom
→ beam width changes continuously
```

The UI presentation may sample authoritative state at a safe cadence,
e.g. approximately 20--30 FPS, rather than output cadence.

Never place Stage rendering on the output-critical path.

------------------------------------------------------------------------

# 13. Stage Preview Is Also a Selection Surface

The Preview is not merely passive telemetry.

It must be a first-class way to work with fixtures.

Normal programming mode should allow:

-   click fixture
-   multi-select fixtures
-   select group members visually
-   Reveal selected fixture
-   pan/zoom
-   Fit
-   inspect fixture
-   program selected fixture(s)

Geometry remains protected unless Edit Stage is enabled.

This provides a powerful workflow:

``` text
see fixture
→ click fixture
→ edit fixture
→ see result
```

No list hunting is required.

------------------------------------------------------------------------

# 14. Contextual Fixture HUDs --- Architecture Now, Polish Later

Lightkey's use of contextual controls around Preview fixtures is useful.

Aurora does **not** need to implement a full HUD system in this
immediate pass.

However, architecture should not make it difficult later.

Potential future examples:

``` text
selected moving head
→ pan/tilt direction affordance

selected zoom fixture
→ zoom handle

selected fixture
→ compact intensity/color badge
```

Do not duplicate Programmer functionality gratuitously.

HUDs should eventually be reserved for controls that benefit
specifically from spatial manipulation.

------------------------------------------------------------------------

# 15. Inspector Role

Keep Aurora's Inspector.

It complements the Lightkey-inspired workflow.

The division should be:

``` text
Stage Preview
→ visual selection and immediate feedback

Contextual Programmer
→ creative lighting properties

Inspector
→ detailed metadata/configuration
```

For a selected fixture, Inspector may show:

``` text
identity
profile/personality
patch address
universe
groups
Stage placement
position/rotation when Edit Stage
capabilities
fixture metadata
```

For a group:

``` text
name
member count
members
group operations
```

For scenic objects in Edit Stage:

``` text
type
position
size
rotation
layer
lock
visibility
style
```

------------------------------------------------------------------------

# 16. Lower Shelf: Palettes / Cues / Song

Aurora's lower creative shelf remains valuable.

Retain:

``` text
PALETTES | CUES | SONG | DIAGNOSTICS
```

or the current equivalent.

But make it **collapsible/resizable**.

The user should be able to prioritize:

``` text
large Stage Preview
large Programmer
large Cue/Song shelf
```

depending on task.

The default should be balanced for a single-screen Mac.

Do not require floating windows for basic usability.

------------------------------------------------------------------------

# 17. Preview Visibility

Although Stage Preview should be visible by default, allow it to be
hidden/collapsed when the user intentionally needs maximum Programmer or
Cue space.

Provide a command such as:

``` text
View → Stage Preview
```

and/or an obvious workspace control.

Potential layout states:

``` text
DEFAULT
Stage Preview + Programmer + lower shelf

PROGRAMMER FOCUS
Preview collapsed
Programmer expanded

PREVIEW FOCUS
Preview expanded
Programmer compact

CUE FOCUS
lower shelf expanded
Preview/Programmer reduced
```

These may initially be simple split-view states rather than a
sophisticated layout-presets system.

------------------------------------------------------------------------

# 18. Docking and Floating Panels

Docking/floating remains desirable long-term.

It is **not** the solution to the core single-screen workflow.

Correct priority:

``` text
excellent default single-screen layout
        ↓
collapsible/resizable regions
        ↓
saved workspace layouts
        ↓
dockable/floating/multi-monitor panels
```

Do not block this redesign on implementing a full docking framework.

Do architect reusable views so future detachment is practical.

------------------------------------------------------------------------

# 19. Future Multi-Monitor Behavior

The architecture should eventually support:

``` text
Monitor 1
→ Fixture Browser + Programmer + Cues

Monitor 2
→ large Stage Preview

Monitor 3
→ Song / Cue Lists / Diagnostics
```

But this is future flexibility.

Do not implement it in this immediate pass unless trivial existing
infrastructure already supports it.

------------------------------------------------------------------------

# 20. Relationship to Current STAGE Workspace

The existing Stage work should not be discarded.

Reuse:

-   Stage model
-   canvas rendering
-   placement
-   selection
-   Edit/Live concepts
-   grid
-   scenic-object infrastructure
-   Inspector integration
-   Stage persistence
-   authoritative live-state integration

The key change is **composition**.

Instead of:

``` text
PROGRAM tab owns Programmer
STAGE tab owns Stage
```

move toward:

``` text
DESIGN workspace owns the creative workflow

Stage Preview is always available
Programmer is contextual
Edit Stage augments the Preview
```

If retaining a dedicated STAGE navigation item temporarily makes
migration safer, it may act as a transitional alias/focus mode, but do
not duplicate state or renderer logic.

Long-term preference is to remove the conceptual duplication.

------------------------------------------------------------------------

# 21. Relationship to PATCH

Patch remains separate.

Do not merge Patch into DESIGN.

Patch answers:

> What fixtures exist and where do they live in DMX?

Design answers:

> What are these fixtures doing, and where are they physically located?

Profiles answers:

> What is this fixture personality capable of?

This gives a clean model:

``` text
DESIGN
→ work with the rig

PATCH
→ wire/address the rig

PROFILES
→ define fixture personalities
```

------------------------------------------------------------------------

# 22. Patch Fixture Lifecycle Amendment

Before closing Patch work, add complete removal semantics.

A fixture must not become permanent merely because it was dropped onto a
universe.

Distinguish:

``` text
UNPATCH
≠
DELETE FIXTURE
```

## Unpatch

Selecting a fixture block and pressing Delete/Backspace should:

``` text
remove DMX address assignment
preserve fixture identity
preserve Stage placement
preserve groups
preserve programming references
preserve other fixture-level project data
```

The fixture must remain discoverable and repatchable.

Right-click fixture block:

``` text
Inspect
Repatch…
Unpatch
────────────
Delete Fixture…
```

## Delete Fixture

Permanent project deletion must be explicit.

It should use the canonical fixture-deletion path and safely handle
dependent references.

Require confirmation where appropriate.

Do not map ordinary Delete/Backspace directly to permanent fixture
deletion.

## Keyboard safety

Delete/Backspace must not trigger Unpatch while editing:

-   Search
-   Prefix
-   fixture name
-   address
-   text fields
-   profile fields

Reuse the existing keyboard-command/text-focus safety architecture.

------------------------------------------------------------------------

# 23. Patch Left-Side Show Fixture Visibility

Because Unpatch exists, Patch needs a discoverable place for project
fixtures that currently have no DMX address.

Possible design:

``` text
FIXTURE LIBRARY
Search...
Favorites
Recent
Manufacturers

SHOW FIXTURES
  UNPATCHED (2)
    Front Wash 3
    Spare Mover

  PATCHED (15)
    ...
```

or:

``` text
Library | Show Fixtures
```

Choose the cleaner implementation consistent with existing architecture.

Do not let an unpatched fixture disappear from the workflow.

------------------------------------------------------------------------

# 24. Current Checkpoint Strategy Must Change

The previous roadmap was:

``` text
A Shell
B Patch
C Stage Edit
D Stage Live
```

Checkpoint A has succeeded.

Checkpoint B's primary architecture is approved, with closeout
refinements.

Before implementing old Checkpoint C as a standalone Stage destination,
revise the roadmap.

New sequence:

``` text
A  Production shell                    COMPLETE
B  Patch + fixture lifecycle           CLOSE OUT
C1 Shared Stage renderer architecture
C2 DESIGN workspace integration
C3 Edit Stage in-place workflow
C4 Stage visual polish
D  Live resolved-state polish
```

Human visual checkpoints remain mandatory.

------------------------------------------------------------------------

# 25. Checkpoint C1 --- Shared Stage Architecture

Before major visual work:

-   extract/restructure Stage renderer so it is reusable
-   preserve one Stage model
-   preserve one selection authority
-   preserve one authoritative resolved-state input
-   separate geometry-editing capability from visualization
-   ensure Stage Preview can render inside DESIGN

Tests should cover state/selection behavior, not pixel layout.

### STOP CONDITION

Run production Aurora and prove the same Stage model can be shown in
DESIGN without duplicating state.

------------------------------------------------------------------------

# 26. Checkpoint C2 --- DESIGN Workspace Integration

Build the new single-screen creative workflow.

Required:

``` text
[ ] Stage Preview visible by default
[ ] Fixture Browser/Groups remains available
[ ] contextual Programmer below/adjacent to Preview
[ ] Inspector remains contextual
[ ] lower Palettes/Cues/Song shelf remains available
[ ] Preview can collapse
[ ] lower shelf can collapse/resize
[ ] selection synchronized
[ ] Programmer changes visibly update Preview
```

Capture screenshots at a realistic laptop/desktop window size.

### Required visual-validation selections

1.  RGB wash group
2.  mover group
3.  single moving head
4.  mixed fixture selection if supported
5.  no selection

### STOP FOR REVIEW

Do not proceed automatically.

------------------------------------------------------------------------

# 27. Checkpoint C3 --- Edit Stage In Place

Add/tighten:

``` text
Edit Stage
Pointer
Pan
Marquee
Fit
Reveal
Align
Distribute
Add
Remove From Stage
Rotation
```

Only show geometry tools when editing Stage.

Normal programming mode should remain calm.

Required semantics:

``` text
Remove From Stage
→ remove placement only
→ fixture survives
→ patch survives
→ groups survive
→ programming survives
→ fixture returns to Unplaced
```

Unplaced tray should appear naturally during Edit Stage and may collapse
outside Edit Stage.

### STOP FOR REVIEW

Capture Edit Stage screenshots.

------------------------------------------------------------------------

# 28. Checkpoint C4 --- Stage Visual Polish

Now implement the visual language:

-   category-specific fixture symbols
-   readable labels
-   selected/hover states
-   Stage Area
-   truss
-   text
-   scenic geometry
-   subtle major/minor grid
-   Unplaced fixture glyphs
-   polished Inspector
-   context menus
-   large-rig readability

Do not turn this into CAD.

The goal is a beautiful lighting plot / live visualization.

------------------------------------------------------------------------

# 29. Checkpoint D --- Live State Polish

Once the integrated DESIGN workflow is approved:

-   intensity visualization
-   color
-   moving-head orientation
-   beam direction
-   beam width
-   shutter/strobe where useful
-   fog/haze state where useful
-   laser state where useful
-   cue transitions
-   effects
-   MIDI-driven changes
-   masters
-   blackout
-   freeze
-   adaptive beam complexity
-   dominant background tint

Dominant background color must be restrained.

Do **not** return to the earlier "entire canvas becomes bright green"
treatment.

Use a charcoal base with subtle atmospheric influence from the active
look.

------------------------------------------------------------------------

# 30. Stage Performance Requirements

Stage is presentation, not output-critical processing.

Requirements:

-   DMX/output has priority
-   Stage may render/sample around 20--30 FPS
-   no heavy layout work on output-critical path
-   adaptive beam complexity for large rigs
-   selection and UI remain responsive
-   throttling must not change semantic truth

------------------------------------------------------------------------

# 31. Visual Density Philosophy

Adopt the strongest aspects of Lightkey's ease of use while keeping
Aurora visually modern.

Priorities:

``` text
rig
→ selected fixtures
→ relevant properties
→ contextual details
→ secondary commands
```

Avoid:

-   giant permanent toolbars
-   every capability visible simultaneously
-   multiple competing canvases
-   generic form-editor layouts
-   large empty Programmer regions
-   excessive rounded cards
-   purple everywhere

Use Aurora violet primarily for:

-   selection
-   active modes
-   focus
-   owned state

Fixture output colors should come from the actual lighting state.

------------------------------------------------------------------------

# 32. Required Behavioral Scenarios

The final integrated DESIGN workflow must support these without changing
major workspaces.

## Scenario A --- Color programming

``` text
Select Front Wash group
→ Stage highlights members
→ Programmer exposes Intensity + Color
→ drag color wheel to amber
→ Stage preview changes live
→ record/update cue
```

## Scenario B --- Moving-head position

``` text
Select Movers group
→ Stage highlights movers
→ Programmer exposes Position
→ drag XY position
→ Stage beams move live
→ Fan
→ beams spread visibly
```

## Scenario C --- Stage-based selection

``` text
Click moving head on Stage
→ Browser selects fixture
→ Programmer exposes capabilities
→ Inspector shows fixture
→ change color/intensity
→ Stage updates
```

## Scenario D --- Layout edit

``` text
Edit Stage
→ geometry tools appear
→ drag fixture to new physical location
→ exit Edit Stage
→ geometry locks
→ continue programming immediately
```

## Scenario E --- MIDI

``` text
MIDI note/CC modifies lighting
→ authoritative engine state changes
→ DMX changes
→ Stage Preview follows
```

## Scenario F --- Cue playback

``` text
fire cue
→ transition begins
→ Stage Preview follows transition continuously
```

------------------------------------------------------------------------

# 33. Tests

Add or update tests for:

-   shared fixture selection between Browser/Stage/Programmer
-   Stage Preview uses shared Stage model
-   Edit Stage does not create alternate geometry state
-   Programmer changes propagate through authoritative state
-   Remove From Stage preserves fixture/patch/programming identity
-   Unpatch preserves fixture/Stage/groups/programming identity
-   Delete Fixture uses canonical cleanup
-   keyboard Delete routing respects text editing
-   Preview collapse does not affect engine state
-   switching layout modes does not alter show state

Avoid brittle pixel tests unless the project already has a stable
snapshot-testing strategy.

------------------------------------------------------------------------

# 34. Migration / Risk Control

Do not rewrite the whole UI at once.

Preserve working production behavior while changing composition.

Recommended migration:

``` text
1. isolate reusable Stage canvas
2. embed it in current Program/Design host
3. prove shared selection
4. prove live state
5. reposition Programmer contextually
6. add in-place Edit Stage
7. only then remove/de-emphasize old standalone Stage navigation
```

If necessary, retain the old STAGE tab temporarily as a
compatibility/focus entry point while DESIGN integration stabilizes.

Do not maintain two independent implementations long-term.

------------------------------------------------------------------------

# 35. Production Acceptance Surface

Acceptance is based on the **launched Xcode production application**.

Not:

-   component gallery
-   mock-only SwiftUI previews
-   isolated demo views

At each checkpoint:

``` text
swift test
xcodebuild Debug
launch Aurora
open populated demo show
capture screenshots
STOP
```

------------------------------------------------------------------------

# 36. Required Screenshot Set for DESIGN Integration

Return screenshots showing:

1.  DESIGN with no selection
2.  DESIGN with RGB wash group selected
3.  DESIGN with Movers selected
4.  DESIGN with one moving head selected from Stage
5.  live color change visible
6.  live position change visible
7.  Programmer-focused layout with Preview collapsed
8.  Preview-focused layout
9.  lower shelf expanded
10. Edit Stage active with Unplaced tray
11. multi-selection on Stage
12. Stage Area + truss + fixture symbols

Do not proceed to unrelated UI work before review.

------------------------------------------------------------------------

# 37. Explicit Non-Goals

This amendment does not require:

-   full docking framework
-   multi-monitor implementation
-   photorealistic rendering
-   3D visualization
-   CAD features
-   redesign of Profiles
-   redesign of Patch beyond closeout/lifecycle work
-   broad Settings redesign
-   full HUD system
-   replacement of Aurora's Song model
-   duplication of Lightkey's visual branding

We are adopting the **workflow philosophy**, not cloning the brand.

------------------------------------------------------------------------

# 38. Definition of Success

Aurora succeeds when this feels natural:

> I see my rig.\
> I click the lights I want.\
> Aurora shows me the controls that matter.\
> I change the controls.\
> I immediately see what the lights are doing.\
> I record the result.\
> I never had to leave the creative workspace.

And Stage layout editing should feel like:

> I click Edit Stage, arrange the physical rig, exit Edit Stage, and
> immediately continue programming.

Patch remains:

> I define which fixtures exist and where they live in DMX.

Profiles remains:

> I define what a fixture personality means.

This creates a coherent application model:

``` text
DESIGN
    see + select + program + visualize + arrange

PATCH
    address the rig

PROFILES
    define the rig's capabilities

PERFORM
    run the show
```

------------------------------------------------------------------------

# 39. Immediate Instruction to Grok

Do **not** continue implementing the old standalone Checkpoint C Stage
plan unchanged.

First:

1.  close the small remaining Patch B items, including Unpatch/Delete
    Fixture semantics;
2.  re-plan Stage around a reusable Stage renderer;
3.  integrate Stage Preview into the normal creative DESIGN/PROGRAM
    workflow;
4.  make the Programmer contextual to selected fixtures;
5.  implement Stage editing as an in-place mode around that same
    Preview;
6.  preserve one authoritative selection model and one authoritative
    resolved lighting state;
7.  validate everything in the launched production app;
8.  return screenshots and STOP.

The key architectural rule is:

> **Stage is not merely a destination. Stage is a reusable visualization
> surface. The Stage editing mode adds geometry-editing capabilities
> around that surface, while the normal DESIGN workspace uses the same
> surface for continuous selection, programming, and live feedback.**

And the key UX rule is:

> **Do not separate the action of programming a light from seeing what
> that programming does.**
