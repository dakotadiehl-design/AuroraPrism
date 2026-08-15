# Aurora C3.1 Interaction Closeout

## Stage Navigation, Collapsible Creative Shelf, and Live Fixture Manipulation

**Project:** Aurora Lighting Control\
**Checkpoint:** C3.1 Interaction Closeout\
**Purpose:** Close the interaction gaps discovered during C3 before
beginning C4 visual polish and later smoke testing.\
**Implementation target:** Existing C3 codebase. Preserve the C1-C3
architecture and improve interaction behavior rather than redesigning
the workspace again.

------------------------------------------------------------------------

## 1. Executive Summary

C3 establishes the correct overall direction for Aurora's in-place Stage
editing workflow, but hands-on use exposed three interaction problems
that should be corrected before C4:

1.  **The Stage canvas does not provide natural click-drag navigation.**
2.  **The lower creative shelf containing Cues, Palettes, Songs, and
    related content cannot be collapsed when the user needs more
    Stage/Programmer space.**
3.  **Fixture movement lacks live visual feedback.** During a drag, the
    fixture remains at its old location and jumps to the destination
    only when the mouse button is released.

These are not cosmetic issues. They affect the primary
direct-manipulation workflow of the application. C4 should polish a
Stage surface whose navigation and manipulation semantics are already
correct.

The goal of C3.1 is therefore:

> **Make the DESIGN/Stage workspace feel immediate, spatial, and
> predictable under the mouse without changing the architectural model
> established in C1-C3.**

This checkpoint should remain deliberately focused. Do not use it as an
opportunity to redesign Stage rendering, change the overall workspace
hierarchy, rewrite the lighting engine, or begin unrelated C4
visual-polish work.

------------------------------------------------------------------------

# 2. Existing Architecture to Preserve

The C1-C3 architecture should remain intact.

In particular:

-   `StageCanvasView` remains the shared Stage visualization/editing
    surface.
-   DESIGN remains the primary programming workspace.
-   Stage editing occurs in place rather than becoming a separate
    disconnected workflow.
-   `project.stageLayout` remains the authoritative committed Stage
    geometry.
-   Stage preview continues to derive from the existing authoritative
    lighting/preview path.
-   `DocumentSession` and the existing command/undo architecture remain
    responsible for committed document mutations.
-   Stage geometry remains protected outside the appropriate editing
    mode.
-   Fixture selection remains shared between Stage, Browser, Programmer,
    and Inspector.
-   Existing focus presets and workspace-layout persistence should
    continue working.
-   The lower creative shelf remains part of DESIGN. This task adds the
    ability to collapse it; it does not remove or relocate it.

C3.1 should introduce **transient interaction state** where necessary,
but transient state must never become a competing document model.

------------------------------------------------------------------------

# 3. Requirement A: Natural Stage Canvas Panning

## 3.1 Problem

The current Stage pan implementation does not behave like a normal
direct-manipulation canvas.

The C3 implementation effectively accumulates a scaled version of
`DragGesture.Value.translation` into the current pan. Conceptually, it
behaves like:

``` swift
pan = CGSize(
    width: pan.width + value.translation.width * 0.015,
    height: pan.height + value.translation.height * 0.015
)
```

`translation` already represents the displacement from the beginning of
the current gesture. Repeatedly adding it to the current camera position
creates incorrect gesture semantics, and the `0.015` multiplier makes
the Stage feel detached from the pointer.

Aurora should instead use a drag-start camera position plus the current
gesture translation.

------------------------------------------------------------------------

## 3.2 Required Camera Model

Introduce explicit transient camera-drag state.

Conceptually:

``` swift
@State private var pan: CGSize = .zero
@State private var panAtDragStart: CGSize?
```

At gesture start:

``` text
panAtDragStart = current pan
```

During the gesture:

``` text
displayed pan = panAtDragStart + current gesture translation
```

At gesture end:

``` text
commit final pan
clear panAtDragStart
```

Do not repeatedly accumulate a gesture's full translation into an
already-modified value.

The Stage should visually track the pointer at approximately 1:1
movement unless the existing coordinate transform requires a
mathematically justified conversion.

------------------------------------------------------------------------

## 3.3 Required Input Semantics

### Normal DESIGN mode

When Stage geometry is not being edited:

-   Dragging **empty Stage space** pans the Stage camera.
-   Clicking a fixture still selects it.
-   Dragging a fixture must not accidentally pan the Stage.
-   Existing zoom/Fit behavior must continue to work.

### Edit Stage mode

Empty-space dragging may already have or later require selection/marquee
semantics, so Stage editing needs an unambiguous pan gesture.

Required:

-   **Space + primary-button drag** pans the Stage.
-   Space-drag must work even while Edit Stage is active.
-   Fixture geometry must not move while the Space key is being used for
    camera navigation.

Strongly preferred if practical with the existing macOS event
architecture:

-   Middle mouse/button drag pans the Stage.
-   Trackpad two-finger scrolling pans the Stage.
-   Trackpad/pointer behavior should feel native on macOS.

Do not delay C3.1 solely because middle-button or trackpad support
requires disproportionate infrastructure. Space-drag is the required
Edit Stage escape hatch.

------------------------------------------------------------------------

## 3.4 Cursor Feedback

Provide appropriate cursor feedback where the current SwiftUI/AppKit
integration makes this practical.

Desired behavior:

-   Hover over pannable empty Stage space: normal pointer is acceptable.
-   Hold Space: indicate that the canvas is in pan/navigation mode.
-   While actively panning: use an appropriate
    closed-hand/grabbing-style cursor if available.
-   Fixture manipulation must retain fixture-manipulation semantics
    rather than showing a pan cursor.

Cursor work should remain restrained and native. Do not build a custom
cursor system solely for this checkpoint.

------------------------------------------------------------------------

## 3.5 Pan Persistence

Clarify the distinction between:

-   **Stage document geometry**, which belongs in the project, and
-   **camera/view state**, which belongs in workspace/UI state.

Camera pan and zoom should not mutate fixture positions.

If camera state is already persisted as part of the workspace, preserve
that model. If it is currently ephemeral, do not introduce
project-document mutations merely to save the viewport.

------------------------------------------------------------------------

## 3.6 Fit Interaction

The existing Fit command remains important.

After arbitrary pan/zoom:

-   Fit should restore a useful view of the rig.
-   Fit should not change Stage geometry.
-   Fit should work in both normal DESIGN and Edit Stage modes.
-   After Fit, subsequent panning should begin from the fitted camera
    state without jumps.

------------------------------------------------------------------------

# 4. Requirement B: Collapsible Lower Creative Shelf

## 4.1 Problem

The lower DESIGN shelf containing creative/programming resources such as
Cues, Palettes, and Songs can consume substantial vertical space.

The user needs to be able to temporarily reclaim that space,
particularly while:

-   arranging Stage geometry,
-   working with a large rig,
-   using a smaller display,
-   emphasizing Stage Preview,
-   emphasizing the Programmer.

Resizing alone is not sufficient. The shelf needs a true collapsed
state.

------------------------------------------------------------------------

## 4.2 Workspace Layout Model

Extend the existing `WorkspaceLayout` model with a persistent collapsed
state.

Recommended property:

``` swift
var lowerShelfCollapsed: Bool
```

Use the project's established naming conventions if a more appropriate
name already exists.

Update:

-   Codable representation
-   schema/version handling if required
-   legacy migration/default behavior
-   workspace-layout tests
-   any reset/default-layout code
-   focus preset behavior where relevant

### Migration behavior

Existing projects/workspaces that predate this property must decode
successfully.

Recommended default:

``` text
lowerShelfCollapsed = false
```

This preserves the current visible-by-default behavior.

------------------------------------------------------------------------

## 4.3 Preserve Previous Shelf Height

Collapsing the shelf must not destroy the user's preferred expanded
height.

Example:

1.  User resizes shelf to 34% of available height.
2.  User collapses shelf.
3.  User later expands shelf.
4.  Shelf returns to approximately 34%.

Do not overwrite `bottomFraction` with zero merely to represent
collapsed state.

Use separate concepts:

``` text
bottomFraction = preferred expanded size
lowerShelfCollapsed = whether the shelf body is currently hidden
```

This also keeps layout persistence clean.

------------------------------------------------------------------------

## 4.4 Collapsed Presentation

When collapsed, do **not** make the shelf vanish without a trace.

Leave a thin, visually quiet restoration affordance.

Conceptual layout:

``` text
┌──────────────────────────────────────────────────────────┐
│                                                          │
│                 Stage / Programmer                       │
│                                                          │
├──────────────────────────────────────────────────────────┤
│ Cues · Palettes · Songs                              ▲   │
└──────────────────────────────────────────────────────────┘
```

The collapsed strip should:

-   consume minimal vertical space,
-   clearly indicate that the lower shelf exists,
-   provide a one-click expand control,
-   preserve the currently selected lower-shelf section/tab,
-   use existing Aurora visual language rather than introducing a
    foreign-looking control.

When expanded, provide an equally obvious collapse affordance.

------------------------------------------------------------------------

## 4.5 Resize Divider Behavior

When expanded:

-   existing lower-shelf resizing should continue working,
-   the divider should retain the existing minimum/maximum constraints,
-   dragging the divider should update `bottomFraction`,
-   resizing must not accidentally toggle collapse.

Optional refinement if easy and consistent with existing behavior:

-   double-clicking the divider may toggle collapse/restore.

Do not make this optional refinement a blocker.

------------------------------------------------------------------------

## 4.6 Focus Presets

Review the existing focus presets:

-   Balanced
-   Programmer Focus
-   Preview Focus
-   Cue Focus

Ensure the new collapsed state does not make them internally
inconsistent.

Suggested semantics:

### Balanced

Normal expanded shelf unless the existing design intentionally preserves
user collapse state.

### Programmer Focus

May reduce or collapse the lower shelf if that matches the existing
preset intent.

### Preview Focus

May reduce/collapse the shelf to maximize Stage Preview.

### Cue Focus

Must expand the shelf and give it useful space.

The exact policy should follow the existing focus-preset architecture.
The important requirement is deterministic, unsurprising behavior.

------------------------------------------------------------------------

# 5. Requirement C: Live Fixture Drag Preview

## 5.1 Problem

In C3, dragging a fixture changes its final geometry, but the fixture
glyph does not visibly follow the pointer during the drag.

Observed behavior:

1.  Mouse down on fixture.
2.  Drag across Stage.
3.  Fixture remains drawn at its original position.
4.  Release mouse.
5.  Fixture suddenly appears at the destination.

This breaks direct manipulation and makes accurate placement
unnecessarily difficult.

------------------------------------------------------------------------

# 6. Do Not Solve Live Dragging by Spamming Document Commands

A tempting fix would be to force the entire application to refresh every
time `DragGesture.onChanged` mutates `project.stageLayout`.

Do **not** make that the primary solution.

A pointer drag may produce dozens or hundreds of updates per second.
Each intermediate pointer sample is not a meaningful document edit.

Aurora should distinguish:

### Transient interaction state

"What should the user see while the mouse is currently down?"

from:

### Committed document state

"What geometry should be saved, undoable, serialized, and treated as
authoritative after the interaction completes?"

This distinction will also benefit future direct-manipulation features.

------------------------------------------------------------------------

# 7. Required Drag Architecture

## 7.1 Capture Drag Origins

At the beginning of a fixture drag, capture the original committed
positions of every fixture participating in the drag.

Conceptually:

``` swift
struct StageFixtureDragState {
    let anchorFixtureID: FixtureID
    let originalPositions: [FixtureID: CGPoint]
    var currentDelta: CGSize
}
```

Use the project's real fixture-ID and coordinate types.

This state should be transient UI interaction state.

------------------------------------------------------------------------

## 7.2 Live Rendering

While dragging, render participating fixture glyphs at:

``` text
displayed position = original committed position + current drag delta
```

after applying any appropriate coordinate transform and snapping logic.

The user should see the fixture remain under the pointer throughout the
drag.

The committed `project.stageLayout` does not need to change on every
pointer event.

------------------------------------------------------------------------

## 7.3 Commit on Mouse-Up

On gesture completion:

1.  Calculate final Stage-space positions.
2.  Apply snapping.
3.  Validate movement constraints.
4.  Create/update the final `StageLayout`.
5.  Commit **one logical document command**.
6.  Notify the relevant UI/document state through the normal production
    path.
7.  Clear transient drag state.

One physical drag should correspond to one undoable operation.

Pressing Undo once after moving a fixture should return the fixture to
the position it occupied before the drag began.

------------------------------------------------------------------------

# 8. Multi-Fixture Dragging

C3 already supports multi-selection, so live dragging must account for
it now rather than creating a single-fixture-only interaction that must
later be replaced.

## 8.1 Required Selection Semantics

When the user begins dragging a fixture:

### Fixture is already part of the current multi-selection

Move all selected, movable fixtures together.

### Fixture is not currently selected

Follow the application's established selection semantics first, then
begin the drag using the resulting selection.

Do not silently move unrelated fixtures.

------------------------------------------------------------------------

## 8.2 Preserve Relative Geometry

If fixtures A, B, and C begin at:

``` text
A = (100, 100)
B = (150, 100)
C = (200, 100)
```

and the user drags by:

``` text
(+40, -20)
```

the preview and final positions should become:

``` text
A = (140, 80)
B = (190, 80)
C = (240, 80)
```

Their relative spacing must remain unchanged.

------------------------------------------------------------------------

## 8.3 Snapping for Group Movement

Do not independently snap every selected fixture to the grid if doing so
can alter relative spacing.

Preferred behavior:

1.  Calculate movement from the anchor fixture or group drag delta.
2.  Snap the anchor/final delta according to Stage grid rules.
3.  Apply the same snapped delta to the rest of the movable selection.

This preserves the group shape.

If the existing Stage snapping architecture provides a better equivalent
mechanism, use it.

------------------------------------------------------------------------

# 9. Locked Fixtures

Existing fixture locking semantics must remain authoritative.

Required behavior:

-   A locked fixture cannot be moved by direct drag.
-   A drag beginning on a locked fixture should not silently mutate its
    position.
-   Multi-selection containing locked and unlocked fixtures must have
    deterministic behavior.

Preferred multi-selection behavior:

-   unlocked selected fixtures move,
-   locked selected fixtures remain stationary,
-   the UI should make this behavior understandable.

If the existing Stage model already establishes different lock
semantics, preserve those semantics and document them in the C3.1
checkpoint notes.

------------------------------------------------------------------------

# 10. Drag Cancellation and Mode Changes

Transient drag state must never leak across interaction-mode changes.

Clear/cancel transient geometry when appropriate, including:

-   leaving Edit Stage,
-   switching projects/documents,
-   losing the relevant Stage editing context,
-   invoking a command that replaces Stage layout,
-   cancelling an interaction if the current event architecture exposes
    cancellation.

If Escape-based drag cancellation is straightforward with the existing
architecture, implement:

``` text
Escape during drag → discard transient positions → return to committed geometry
```

This is desirable but should not require a large custom event subsystem.

------------------------------------------------------------------------

# 11. Coordinate-System Requirements

Be careful about coordinate spaces.

The drag implementation may involve:

-   SwiftUI view coordinates,
-   Stage/world coordinates,
-   camera pan,
-   camera zoom,
-   Stage scaling/Fit transforms.

The final document position must be calculated in **Stage/world
coordinates**, not raw screen pixels.

Required invariant:

> Moving a fixture the same apparent Stage distance must produce correct
> Stage geometry regardless of current zoom and pan.

Test this explicitly at multiple zoom levels.

A drag at 200% zoom must not move the fixture twice as far in Stage
coordinates merely because the pointer traversed more view pixels.

------------------------------------------------------------------------

# 12. Interaction Priority / Gesture Arbitration

The Stage now has multiple possible pointer actions:

-   fixture selection,
-   fixture drag,
-   multi-selection,
-   camera pan,
-   possible marquee selection,
-   zoom,
-   Stage editing.

Define gesture priority deliberately.

At minimum:

### Normal DESIGN

-   click fixture → select
-   click empty Stage → normal empty-space selection behavior
-   drag empty Stage → pan
-   fixture geometry remains locked

### Edit Stage

-   click fixture → select
-   drag movable fixture → live geometry move
-   Space + drag anywhere appropriate → pan camera
-   dragging fixture without Space must not pan camera
-   dragging empty Stage without Space remains available for the Stage
    editor's existing/future selection semantics

Do not create a state where a fixture simultaneously moves and the
camera pans.

------------------------------------------------------------------------

# 13. Undo/Redo Requirements

Fixture movement must integrate cleanly with existing document
undo/redo.

For one drag gesture:

``` text
mouse-down → many pointer samples → mouse-up
```

there should be:

``` text
one logical committed Stage geometry edit
```

not dozens of undo steps.

Required:

-   Undo once restores all fixtures moved by that drag.
-   Redo once reapplies the entire drag.
-   Multi-fixture movement is one logical operation.
-   Camera panning is not a document geometry undo operation.
-   Collapsing/expanding the lower shelf is workspace UI state, not
    project Stage geometry.

------------------------------------------------------------------------

# 14. Performance Expectations

Live fixture movement should feel immediate.

Avoid architectures that cause:

-   full project serialization per pointer event,
-   command-stack insertion per pointer event,
-   unnecessary lighting-engine recomputation,
-   repeated expensive Stage snapshot construction solely to move a
    glyph,
-   visible frame hitching.

The transient drag overlay/state should be lightweight.

The Stage preview may continue showing live lighting state while
geometry is being manipulated.

------------------------------------------------------------------------

# 15. Recommended Internal Separation

Exact names are implementation-dependent, but the design should trend
toward three clearly separated concepts:

``` text
Stage document model
    ↓
Committed fixture geometry

Stage camera state
    ↓
Pan / zoom / fit

Stage interaction state
    ↓
Current drag origins / drag delta / pan gesture / modifier state
```

Do not conflate these.

This separation will make later features such as alignment, duplication,
marquee transforms, keyboard nudging, and richer Stage design tools much
easier.

------------------------------------------------------------------------

# 16. Tests Required for C3.1

Add focused automated tests where the existing test architecture
permits.

## 16.1 Pan math

Test that:

``` text
start pan + current gesture translation = displayed/final pan
```

and that gesture updates do not compound total translation incorrectly.

Example:

``` text
initial pan = (100, 50)
gesture translation = (40, -10)
expected pan = (140, 40)
```

A second event reporting translation `(60, -20)` should produce:

``` text
(160, 30)
```

not an accumulated value based on the previous `(40, -10)` sample.

------------------------------------------------------------------------

## 16.2 Lower shelf persistence

Test:

-   new/default layout decodes with shelf expanded,
-   collapsed state round-trips,
-   legacy workspace layouts decode successfully,
-   `bottomFraction` survives collapse/expand,
-   invalid layout values remain clamped according to existing rules.

------------------------------------------------------------------------

## 16.3 Single-fixture drag

Test:

-   transient delta produces expected preview geometry,
-   final commit produces expected Stage-space position,
-   one drag creates one logical committed edit where testable,
-   Undo restores the original position.

------------------------------------------------------------------------

## 16.4 Multi-fixture drag

Test:

-   selected fixtures receive the same delta,
-   relative positions remain unchanged,
-   snapping does not distort group spacing,
-   one undo restores the entire group.

------------------------------------------------------------------------

## 16.5 Locked fixture behavior

Test the final chosen lock semantics.

At minimum:

-   locked fixture cannot be moved,
-   locked geometry is unchanged after drag completion.

------------------------------------------------------------------------

## 16.6 Zoom-aware drag math

Test fixture movement at more than one camera zoom level.

The Stage/world result must be mathematically correct after conversion
from view-space pointer movement.

------------------------------------------------------------------------

## 16.7 Interaction cleanup

Test or otherwise verify:

-   exiting Edit Stage clears transient fixture drag state,
-   switching contexts does not leave a ghost fixture offset,
-   completed drag clears temporary state,
-   cancelled drag restores committed positions.

------------------------------------------------------------------------

# 17. Manual Acceptance Checklist

Automated tests are not enough for these interaction changes. Perform
hands-on validation in the actual production Aurora application.

## Stage panning

-   [ ] Open DESIGN.
-   [ ] Place enough fixtures that panning is meaningful.
-   [ ] Drag empty Stage space in normal DESIGN.
-   [ ] Confirm the Stage follows the pointer naturally.
-   [ ] Confirm fixture geometry does not move.
-   [ ] Enter Edit Stage.
-   [ ] Hold Space and drag.
-   [ ] Confirm the camera pans instead of moving fixtures.
-   [ ] Zoom and pan again.
-   [ ] Use Fit and confirm a useful fitted view returns.
-   [ ] Pan after Fit and confirm there is no jump.

## Lower creative shelf

-   [ ] Resize the lower shelf to a recognizable custom height.
-   [ ] Collapse it.
-   [ ] Confirm Stage/Programmer reclaim the released vertical space.
-   [ ] Confirm a thin restoration affordance remains visible.
-   [ ] Expand it.
-   [ ] Confirm the previous custom height returns.
-   [ ] Confirm the previously selected Cues/Palettes/Songs section
    remains selected.
-   [ ] Relaunch/reopen as appropriate and confirm workspace
    persistence.
-   [ ] Exercise existing focus presets and confirm sensible behavior.

## Single fixture movement

-   [ ] Enter Edit Stage.
-   [ ] Select one movable fixture.
-   [ ] Press and hold on the fixture.
-   [ ] Drag it slowly across the Stage.
-   [ ] Confirm the glyph visibly remains under/follows the pointer.
-   [ ] Confirm snapping is visible/predictable if enabled.
-   [ ] Release.
-   [ ] Confirm there is no visual jump at commit.
-   [ ] Undo once.
-   [ ] Confirm the fixture returns to its original position.
-   [ ] Redo once.
-   [ ] Confirm the final position returns.

## Multi-fixture movement

-   [ ] Select several fixtures.
-   [ ] Drag one selected fixture.
-   [ ] Confirm all movable selected fixtures move live.
-   [ ] Confirm relative spacing is preserved.
-   [ ] Release.
-   [ ] Undo once.
-   [ ] Confirm the entire group returns in one operation.

## Locked fixtures

-   [ ] Lock a fixture.
-   [ ] Attempt to drag it.
-   [ ] Confirm it does not move.
-   [ ] Include locked/unlocked fixtures in a multi-selection.
-   [ ] Confirm behavior matches the documented chosen semantics.

## Zoom/coordinate correctness

-   [ ] Move a fixture at normal zoom.
-   [ ] Repeat at a substantially different zoom.
-   [ ] Confirm drag movement remains spatially correct and predictable.
-   [ ] Pan the camera and repeat.
-   [ ] Confirm camera offset does not corrupt final fixture
    coordinates.

------------------------------------------------------------------------

# 18. Production Validation Requirement

Checkpoint screenshots and acceptance evidence must represent the
**actual production DESIGN workspace**.

Do not use a hand-built approximation of the surrounding workspace as
the primary proof of completion.

For C3.1, the most useful evidence is hands-on behavior in the real
application.

Provide either production-app captures or equivalent deterministic
production-host evidence showing:

1.  normal DESIGN with lower shelf expanded,
2.  normal DESIGN with lower shelf collapsed,
3.  Edit Stage with lower shelf collapsed,
4.  fixture drag in progress with the glyph visibly displaced from its
    committed origin,
5.  multi-fixture drag in progress,
6.  Stage after final drag commit.

A static screenshot cannot prove smooth dragging by itself, so
checkpoint notes should also state that manual drag validation was
performed in the running application.

------------------------------------------------------------------------

# 19. Explicit Non-Goals

Do **not** expand C3.1 into unrelated work.

Out of scope:

-   major Stage visual redesign,
-   new beam rendering,
-   background-color polish,
-   new fixture glyph artwork,
-   C4 visual styling work,
-   lighting-engine redesign,
-   cue engine redesign,
-   Song Mode redesign,
-   fixture-library work,
-   new MIDI functionality,
-   web remote work,
-   new Stage alignment/distribution tool suite,
-   rotation/scale transform handles unless already required by C3,
-   elaborate CAD-style navigation systems,
-   replacing the shared `StageCanvasView` architecture.

Fix the interaction foundation first.

------------------------------------------------------------------------

# 20. Suggested Implementation Order

Implement in this order to reduce cross-interaction regressions:

### Step 1: Refactor camera pan math

Establish correct pan-origin + translation behavior before introducing
additional drag state.

### Step 2: Define gesture arbitration

Make the rules for fixture drag vs camera pan explicit, including
Space-drag during Edit Stage.

### Step 3: Introduce transient fixture drag state

Keep committed Stage geometry unchanged during intermediate pointer
samples.

### Step 4: Render live drag geometry

Feed transient positions into fixture glyph rendering.

### Step 5: Commit drag once

Convert final positions to Stage coordinates and perform one document
mutation.

### Step 6: Extend drag to multi-selection

Preserve relative geometry and use group-safe snapping.

### Step 7: Verify locking and cancellation

Ensure transient state cannot bypass Stage edit protections.

### Step 8: Add lower-shelf collapsed state

Extend `WorkspaceLayout`, migration, persistence, and UI affordance.

### Step 9: Reconcile focus presets

Ensure presets intentionally handle expanded/collapsed shelf state.

### Step 10: Automated and manual validation

Run tests and validate the real production application.

------------------------------------------------------------------------

# 21. Completion Criteria

C3.1 is complete only when all of the following are true:

-   Stage camera panning feels direct and predictable.
-   Normal DESIGN supports convenient empty-space click-drag panning.
-   Edit Stage supports Space + drag camera navigation.
-   Camera navigation never mutates fixture geometry.
-   The lower creative shelf can be collapsed and restored with one
    click.
-   Shelf collapse state persists appropriately.
-   Expanding restores the previous shelf height.
-   Fixtures visibly follow the pointer during geometry editing.
-   Intermediate drag samples do not create a stream of committed
    document edits.
-   One completed drag is one logical undo operation.
-   Multi-selected fixtures can move together while preserving spacing.
-   Locked fixtures remain protected.
-   Drag calculations remain correct across camera zoom/pan.
-   Transient interaction state is reliably cleared.
-   Existing C1-C3 Stage/selection/preview architecture remains intact.
-   Existing tests continue passing.
-   New C3.1 tests pass.
-   Manual validation is performed against the actual production Aurora
    application.

------------------------------------------------------------------------

# 22. Stop Condition

After implementing and validating the requirements above:

> **STOP and produce a C3.1 checkpoint for human review before beginning
> C4.**

Do not automatically continue into C4 visual polish.

The purpose of this checkpoint is to establish that Aurora's primary
Stage surface now **feels correct under direct manipulation**. Once
approved, C4 can concentrate on making that already-correct interaction
surface visually excellent.

------------------------------------------------------------------------

## Product Principle

Aurora is a live creative workstation. Its Stage should behave less like
a configuration form and more like a physical work surface.

When the user grabs the Stage, **the Stage moves**.

When the user grabs a fixture, **the fixture moves with their hand**.

When the user needs room, **the surrounding interface gets out of the
way**.

Those three behaviors are the acceptance standard for C3.1.
