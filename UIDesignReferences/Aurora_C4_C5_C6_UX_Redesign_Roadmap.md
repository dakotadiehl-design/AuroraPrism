# Aurora UX Redesign Roadmap

## C4 Stage Designer & Visual Polish → C5 Multi-Monitor Workspace → C6 Splash & Brand Fidelity

**Project:** Aurora Lighting Control\
**Prerequisite:** C3.1 final closeout approved\
**Goal:** Complete the remaining major UX/design requirements before
final UX acceptance and smoke testing.

------------------------------------------------------------------------

# 1. Roadmap Overview

The remaining redesign work is divided into three focused phases:

## C4 --- Stage Designer & Visual Polish

Turn the shared Stage canvas into a complete, polished 2D stage-layout
environment. Existing non-fixture objects become directly manipulable,
and Aurora gains its own stock library of performer/stage silhouettes
and images.

## C5 --- Multi-Monitor / Undockable Workspace

Allow major BUILD/DESIGN workspace surfaces to leave the main window and
become real macOS windows that can be placed on other monitors, while
preserving one authoritative application state.

## C6 --- Splash & Brand Fidelity Closeout

Bring the current splash implementation back into fidelity with the
previously approved Aurora splash design and close remaining
brand/presentation inconsistencies.

After C6:

> **Final UX Acceptance → Smoke Testing**

Do not treat smoke testing as another design phase. The purpose of C4-C6
is to close known UX requirements so smoke testing can concentrate on
real application behavior and defects.

------------------------------------------------------------------------

# 2. C4 --- Stage Designer & Visual Polish

## 2.1 Product Goal

The Aurora Stage should be more than a fixture coordinate map.

It should function as a lightweight visual stage designer that
communicates:

-   where fixtures are,
-   where performers are,
-   where truss and scenic elements are,
-   where the audience is,
-   what the lighting is doing relative to those elements.

The guiding rule is:

> **If an editable object exists on the Stage canvas, the user should be
> able to select it and move it.**

------------------------------------------------------------------------

# 3. C4A --- Unified Stage Object Interaction

## Current Gap

Fixtures gained correct live drag behavior in C3.1, but existing Stage
objects such as truss and stage areas cannot necessarily be repositioned
after placement.

This creates inconsistent interaction:

``` text
fixture → selectable and movable
truss   → draw once, effectively frozen
shape   → draw once, effectively frozen
```

That must be eliminated.

## Required Object Families

Conceptually support:

``` text
StageObject
├── FixturePlacement
├── ShapeObject
│   ├── Rectangle
│   ├── Rounded Rectangle
│   ├── Ellipse
│   ├── Triangle
│   └── Line
├── TrussObject
│   ├── Straight
│   ├── Curved
│   └── Circular
├── TextObject
└── ImageObject
```

Do not force a single Swift enum/class hierarchy if the existing
document architecture favors another representation. The requirement is
**consistent interaction semantics**, not a specific inheritance tree.

## Required Common Operations

Where appropriate for the object type:

-   select,
-   multi-select,
-   move,
-   live drag preview,
-   resize,
-   rotate,
-   duplicate,
-   delete,
-   lock/unlock,
-   bring forward,
-   send backward,
-   bring to front,
-   send to back.

Not every object requires every transform. For example, text may use
font-size editing rather than arbitrary geometric scaling if that better
matches the existing model.

## Direct Manipulation

Reuse the C3.1 interaction philosophy:

``` text
mouse-down
→ capture committed origin
→ render transient movement live
→ mouse-up
→ one committed document operation
```

Do not reintroduce teleport-on-release behavior for non-fixture objects.

One drag should be one Undo operation.

## Selection Presentation

Selected Stage objects should have a restrained professional selection
treatment:

-   bounding outline,
-   handles where resize/rotation is supported,
-   clear locked state,
-   no giant toy-like handles,
-   remain legible over live lighting visualization.

------------------------------------------------------------------------

# 4. C4B --- Stage Object Palette

Aurora needs a compact object library available while editing the Stage.

The LightKey screenshots supplied during review demonstrate a useful
concept: a single palette containing **Shapes** and **Images**, with
performer and stage-context silhouettes available for placement.

Aurora should adopt the workflow concept but use its **own original
artwork and visual system**.

Do not copy or redistribute LightKey's actual image assets.

## Suggested Palette Structure

``` text
STAGE OBJECTS

SHAPES
- Rectangle
- Rounded Rectangle
- Ellipse
- Triangle
- Line
- Text

TRUSS
- Straight Truss
- Curved Truss
- Circular Truss

PERFORMERS
- Lead Vocal / Singer
- Female Vocal / Singer
- Guitarist
- Bassist
- Keyboardist
- Drummer / Drum Kit
- DJ
- Solo Performer
- Backing Vocal
- Performer Group

STAGE EQUIPMENT
- Mic Stand
- Music Stand
- Speaker + Stand
- Lighting Stand
- Riser
- Stage Platform
- Disco Ball

AUDIENCE
- Crowd Silhouette
- Raised Hands / Crowd Front
- Audience Block
```

The exact taxonomy can evolve during implementation, but drummer,
keyboardist, singer/vocalist, guitarist, bassist, crowd, stage/riser,
mic stand, speaker stand, and lighting stand should be represented.

## Placement Workflow

Preferred:

1.  Enter Edit Stage.
2.  Open Stage Objects palette.
3.  Select or drag an object.
4.  Place it on Stage.
5.  Object remains selected.
6.  Immediately move/resize/rotate as supported.

The palette may live contextually in the Inspector, a popover, or
another compact Stage editing surface consistent with Aurora's workspace
architecture.

Do not create a giant modal dialog for routine placement.

------------------------------------------------------------------------

# 5. C4C --- Aurora Original Vector Asset Library

Create an original Aurora silhouette library.

## Asset Requirements

-   Original artwork, not extracted LightKey assets.
-   Vector-first where practical.
-   Retina-clean at arbitrary Stage zoom.
-   Consistent visual weight.
-   Simple silhouette treatment that remains readable behind/within
    lighting beams.
-   Suitable for tint/opacity adjustments.
-   Efficient enough for many Stage objects.

## Performer Assets

At minimum:

-   drummer with drum kit,
-   keyboardist,
-   vocalist,
-   guitarist,
-   bassist,
-   additional vocalist/performer variation,
-   DJ/console performer,
-   performer group.

## Infrastructure Assets

At minimum:

-   crowd/audience,
-   mic stand,
-   speaker on stand,
-   lighting stand,
-   music stand,
-   riser/platform,
-   disco ball.

The Stage should communicate spatial context without becoming clip-art
soup.

------------------------------------------------------------------------

# 6. C4D --- Custom Image Import

Support user-provided Stage imagery.

Useful cases:

-   band logo,
-   venue floor plan,
-   scenic element,
-   custom stage outline,
-   drum riser reference,
-   room diagram,
-   custom performer/equipment symbol.

## Required Behavior

Imported image objects should support:

-   placement,
-   move,
-   resize,
-   lock/unlock,
-   delete,
-   z-order,
-   opacity,
-   project persistence.

Rotation is strongly preferred if the underlying object model supports
it cleanly.

## File Handling

Use a project-safe strategy.

Do not leave project documents dependent on arbitrary external absolute
file paths that can disappear.

Prefer embedding/copying imported assets into the Aurora project/package
or another deliberate managed-resource model.

------------------------------------------------------------------------

# 7. C4E --- Stage Layering

A real stage layout needs predictable visual layering.

Provide:

-   Bring Forward
-   Send Backward
-   Bring to Front
-   Send to Back

Use an explicit stable z-order in the Stage document model.

Potential examples:

``` text
background/floor plan
stage platform
performer silhouettes
fixtures/truss
lighting visualization/beam presentation
selection overlays
```

Do not hard-code a layer order that prevents useful custom arrangements.
Define which rendering layers are structural and which user objects
participate in z-order.

------------------------------------------------------------------------

# 8. C4F --- Visual Polish

After object interaction is correct, perform the Stage visual polish
already planned for C4.

Review:

-   background treatment,
-   grid,
-   fixture glyphs,
-   selection treatment,
-   beam rendering,
-   beam opacity,
-   live color visualization,
-   dominant-scene/background behavior,
-   labels,
-   Stage chrome,
-   Edit Stage controls,
-   zoom/Fit affordances,
-   Stage Object palette,
-   empty states.

The target remains the approved Aurora identity:

-   professional macOS creative workstation,
-   restrained charcoal surfaces,
-   Aurora/purple accents,
-   high information density without clutter,
-   Stage/rig as the visual hero.

Do not allow the brown/red temporary Stage treatment from checkpoint
tooling to become the final aesthetic by inertia.

------------------------------------------------------------------------

# 9. C4 Acceptance

C4 is complete when a user can:

1.  create/place truss or a stage area,
2.  later select and move it,
3.  resize/rotate supported objects,
4.  Undo the transform in one operation,
5.  add a drummer silhouette,
6.  add other performer/equipment silhouettes,
7.  move and resize those images,
8.  import a custom image,
9.  adjust opacity and lock it,
10. arrange object z-order,
11. program lighting while seeing useful stage context,
12. pan/zoom/Fit without interfering with object manipulation.

Validate in the production app.

STOP for human review before C5.

------------------------------------------------------------------------

# 10. C5 --- Multi-Monitor / Undockable Workspace

## Product Goal

Aurora's default single-window BUILD/DESIGN workspace should remain
coherent and polished, but power users must be able to move major
workspace surfaces to independent macOS windows and other displays.

Guiding principle:

> **Excellent single-window default, flexible multi-window capability.**

Aurora does not need LightKey's exact "Single Window / Dual Window"
toggle. A more flexible panel/window system is preferable.

------------------------------------------------------------------------

# 11. C5A --- Detachable Workspace Surfaces

At minimum, support floating for:

-   Fixture / Group Browser,
-   Stage Preview / Stage,
-   Programmer,
-   Inspector,
-   lower creative shelf or its major creative content,
-   Diagnostics/secondary utility surfaces where appropriate.

Do not clone these views.

The same production content should be hostable either:

``` text
inside main workspace
```

or:

``` text
inside independent macOS window
```

One panel, multiple presentation containers.

------------------------------------------------------------------------

# 12. C5B --- Panel Presentation State

Introduce explicit workspace presentation state, conceptually:

``` text
.docked
.floating(windowID)
.hidden
```

Exact implementation may differ.

This state is **workspace/UI state**, not lighting-show content.

Persist:

-   docked/floating state,
-   window size,
-   window position,
-   relevant panel configuration,
-   display association where safely restorable,
-   lower shelf collapse state,
-   selected tools/tabs where already considered workspace state.

------------------------------------------------------------------------

# 13. C5C --- Real macOS Windows

Floating panels must become real macOS windows/SwiftUI scenes or
appropriate AppKit-backed windows.

Do not implement fake draggable rectangles trapped inside the main
Aurora window.

Required:

-   move to another monitor,
-   participate naturally in macOS Spaces,
-   normal window focus,
-   appropriate minimum sizes,
-   correct Retina scaling,
-   survive monitor configuration changes gracefully.

------------------------------------------------------------------------

# 14. C5D --- Undock / Redock UX

Every detachable surface should have a discoverable command such as:

``` text
⋯
Move to Window
```

Floating equivalent:

``` text
⋯
Dock in Main Window
```

Also expose sensible View-menu commands.

Drag-to-undock is desirable but **not required for the first robust
implementation**. Explicit commands are preferable to a fragile drag
system.

Closing a floating panel must have deterministic behavior:

-   redock,
-   hide,
-   or close its presentation while preserving content state.

Choose and document one consistent policy.

Do not destroy project state.

------------------------------------------------------------------------

# 15. C5E --- Monitor Removal / Recovery

Handle:

-   external monitor disconnected,
-   laptop lid/display configuration changed,
-   previously saved floating window now outside visible screen bounds.

Aurora must recover windows onto an available display.

Never strand an Inspector or Programmer permanently off-screen because
yesterday's monitor is gone.

------------------------------------------------------------------------

# 16. C5F --- Future Workspace Presets

Architect for future presets without requiring a large preset editor
now.

Potential future presets:

-   Single Display
-   Dual Display
-   Programming
-   Performance
-   Custom 1 / Custom 2

C5 does not need to ship a sophisticated preset manager unless
implementation is already low-cost.

The important requirement is that panel/window state is represented
cleanly enough to support presets later.

------------------------------------------------------------------------

# 17. C5 Acceptance

Test at minimum:

### Single display

-   default workspace remains excellent,
-   undock/redock every required panel,
-   restart and restore layout.

### Two displays

-   move Stage to second monitor,
-   move Programmer or Inspector independently,
-   program fixtures and confirm all windows remain synchronized,
-   close/redock panels,
-   restart with both displays and restore useful layout.

### Display removal

-   float windows to external monitor,
-   quit Aurora,
-   disconnect monitor,
-   relaunch,
-   verify all windows recover visibly.

### Shared state

Selection, Programmer edits, Stage Preview, cues, and Inspector must
remain synchronized regardless of which window hosts them.

STOP for human review before C6.

------------------------------------------------------------------------

# 18. C6 --- Splash & Brand Fidelity Closeout

## Product Goal

The current splash implementation does not meet the quality/fidelity of
the splash design previously developed for Aurora.

C6 is **not a splash redesign**.

The approved splash concept is the source of truth. C6 brings production
implementation back into alignment with it.

------------------------------------------------------------------------

# 19. C6A --- Source-of-Truth Comparison

Before changing code:

1.  Locate the approved Aurora splash design/specification from the
    Splash Screen work.
2.  Locate all current production splash implementation code/assets.
3.  Produce a discrepancy checklist.
4.  Correct production implementation against the approved design.

Do not rationalize visual drift merely because the current version is
easier to implement.

If a specific approved effect is impractical in Swift/macOS, document
the constraint and implement the closest high-quality native equivalent.

------------------------------------------------------------------------

# 20. C6B --- Fidelity Review Areas

Compare:

-   Aurora mark geometry,
-   wordmark/typography,
-   type weights,
-   spacing,
-   overall proportions,
-   centering,
-   charcoal background treatment,
-   Aurora accent/glow,
-   gradient treatment,
-   animation sequence,
-   animation duration,
-   easing,
-   opacity curves,
-   loading/status text,
-   progress indication if present,
-   transition into main workspace,
-   Retina rendering,
-   different display sizes/scales.

Avoid gratuitous animation.

The splash should feel intentional, cinematic, and brief, not like a
collection of independently pulsing controls.

------------------------------------------------------------------------

# 21. C6C --- Startup Behavior

Visual quality must not compromise application startup correctness.

Ensure:

-   splash appears promptly,
-   app remains responsive,
-   splash does not block necessary startup work incorrectly,
-   loading/status messages correspond to real states if shown,
-   transition to main workspace is clean,
-   failures do not leave a permanent splash window,
-   multiple monitors do not create duplicate/stranded splash windows,
-   reduced-motion/accessibility behavior is reasonable.

------------------------------------------------------------------------

# 22. C6D --- Brand Consistency Sweep

While closing the splash, perform a limited brand-fidelity sweep of
high-visibility application surfaces:

-   app icon usage,
-   Aurora mark,
-   wordmark,
-   welcome/empty states,
-   About surface,
-   primary toolbar branding,
-   splash.

Do not turn C6 into another broad UI redesign.

The goal is consistency, not novelty.

------------------------------------------------------------------------

# 23. C6 Acceptance

Capture the actual production splash and compare side-by-side with the
approved design.

Validate:

-   visual fidelity,
-   animation fidelity,
-   startup transition,
-   Retina quality,
-   primary and external display behavior,
-   no startup regression.

STOP for final UX acceptance.

------------------------------------------------------------------------

# 24. Final UX Acceptance Gate

After C4, C5, and C6 are individually approved, perform one consolidated
UX pass.

Validate the complete workflow:

``` text
Launch Aurora
→ splash
→ open/create project
→ patch fixtures
→ DESIGN workspace
→ Stage navigation
→ Edit Stage
→ place/move truss and stage objects
→ place performer silhouettes
→ program fixtures
→ use palettes/cues/songs
→ collapse/restore shelf
→ float panels to second monitor
→ redock
→ save/reopen workspace/project
```

The purpose is to verify that independently successful checkpoints form
one coherent application.

------------------------------------------------------------------------

# 25. Smoke Testing Gate

Once Final UX Acceptance passes:

# BEGIN SMOKE TESTING

Smoke testing should then concentrate on application functionality,
integration, hardware, persistence, and real show workflows rather than
known unfinished UX design.

Expected smoke-test areas include:

-   project creation/open/save,
-   fixture library and patching,
-   DMX addressing,
-   serial DMX output,
-   Art-Net/sACN,
-   live Programmer output,
-   palettes/presets,
-   cues/playback,
-   Song Mode,
-   MIDI,
-   Stage visualization,
-   Stage editing,
-   undo/redo,
-   multi-monitor operation,
-   project persistence,
-   error handling,
-   hardware reconnect behavior,
-   real lighting-rig testing.

Do not begin smoke testing while known C4-C6 acceptance blockers remain.

------------------------------------------------------------------------

# 26. Phase Stop Rules

Each phase is a human-review checkpoint.

``` text
C3.1 closeout
    ↓ STOP / REVIEW

C4 Stage Designer & Visual Polish
    ↓ STOP / REVIEW

C5 Multi-Monitor / Undockable Workspace
    ↓ STOP / REVIEW

C6 Splash & Brand Fidelity
    ↓ STOP / REVIEW

Final UX Acceptance
    ↓

SMOKE TESTING
```

Grok must not automatically continue into the next phase after
completing one phase.

------------------------------------------------------------------------

# 27. Final Product Principles

### Stage

If the user can see an editable Stage object, they should be able to
grab it and manipulate it predictably.

### Context

Performer silhouettes, truss, stage areas, audience, and equipment exist
to make lighting visualization spatially meaningful, not merely
decorative.

### Workspace

Aurora should be excellent on one screen and liberating on several.

### Brand

The splash and high-visibility identity surfaces should look like the
Aurora that was designed, not a compromised approximation that became
permanent.

### Testing

Once this roadmap closes, stop designing the basic workstation and start
using it hard enough to discover what actually breaks.
