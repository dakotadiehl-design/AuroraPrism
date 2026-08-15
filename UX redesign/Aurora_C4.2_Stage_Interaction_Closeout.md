# Aurora C4.2 Stage Interaction Closeout

## Correct Resize Gesture Ownership, Direct Beam Aiming, and Rotation Control Repair

**Project:** Aurora Lighting Control\
**Target:** Current post-C4.1 repository (`Aurora(1).zip`)\
**Phase:** C4.2 interaction closeout\
**Status:** Required before C5\
**Purpose:** Correct the remaining direct-manipulation defects found
during hands-on testing of the C4.1 Stage Designer.

------------------------------------------------------------------------

# 1. Executive Summary

C4.1 materially improved Aurora's Stage Designer:

-   resize handles are now visible,
-   beam rendering has moved from capsule/"lightsaber" geometry to
    directional wedges,
-   physical Stage aim exists separately from DMX Pan/Tilt,
-   static fixtures can participate in Stage beam visualization,
-   Stage objects and performer silhouettes are now useful spatial
    context.

Hands-on testing exposed three remaining interaction defects:

1.  **The visible resize handles move the selected object instead of
    resizing it.**
2.  **Beam direction is currently controlled primarily through a slider,
    which is too indirect and clunky for a spatial Stage-design task.**
3.  **The Rotation slider at the top of Edit Stage is visible but cannot
    be clicked or dragged.**

These should be fixed as a focused C4.2 closeout. Do not reopen the
Stage architecture and do not begin C5 multi-monitor work until this
interaction pass is accepted.

The product principle for C4.2 is:

> **Move, resize, rotate, and aim must be distinct direct-manipulation
> gestures with unambiguous ownership.**

------------------------------------------------------------------------

# 2. Preserve the Existing C4.1 Architecture

Do not back out the C4.1 model.

Retain:

-   `StageFixturePlacement` physical Stage aim properties,
-   separation of physical Stage aim from live DMX Pan/Tilt,
-   current wedge/cone beam rendering architecture,
-   transient interaction state,
-   one-commit-on-mouse-up semantics,
-   Stage object locking,
-   normalized stock asset bounds,
-   existing Stage object selection architecture.

C4.2 is primarily an interaction-layer correction.

------------------------------------------------------------------------

# 3. Fix Resize Handle Gesture Ownership

## 3.1 Observed defect

Resize handles are visible on selected objects, but dragging a handle
moves the entire object instead of resizing it.

The current implementation already contains resize math/finalization
infrastructure, so do not replace the resize model unless inspection
proves it is defective.

The likely failure mode is gesture arbitration:

``` text
pointer down on resize handle
        ↓
child resize gesture attempts to begin
        +
parent Stage-object move gesture also owns/intercepts drag
        ↓
object moves
```

## 3.2 Required rule

> When a resize handle owns a pointer drag, the object move gesture must
> not participate in that drag.

Do not rely on gesture priority alone if it remains ambiguous.

Introduce explicit transform ownership.

Conceptually:

``` swift
enum StageTransformInteraction {
    case none
    case move(objectID: UUID)
    case resize(objectID: UUID, handle: ResizeHandle)
    case rotate(objectID: UUID)
    case aim(fixtureID: UUID)
}
```

Exact implementation may differ, but Aurora needs one authoritative
answer to:

``` text
"What transform currently owns this pointer?"
```

## 3.3 Resize lifecycle

Required:

``` text
mouse-down on resize handle
→ mark active transform = resize
→ capture original object geometry
→ parent move gesture becomes ineligible
→ update transient resize live
→ mouse-up
→ commit one final Stage layout mutation
→ clear active transform
```

If the drag is cancelled:

``` text
Escape / cancellation
→ discard transient resize
→ restore committed geometry
→ clear active transform
```

## 3.4 Handle behavior

Retain the professional C4.1 handle presentation:

-   four corners for normal 2D objects,
-   visible marker smaller than hit target,
-   sensible cursor feedback,
-   aspect preservation for stock silhouettes/images,
-   free resizing for shapes where appropriate.

Test every handle:

-   NW,
-   NE,
-   SW,
-   SE.

A handle must never act as a move handle.

## 3.5 Zoom and rotation

Resize math must remain correct when:

-   Stage is zoomed,
-   Stage is panned,
-   object is rotated,
-   object has normalized visual bounds.

Use Stage/world coordinates rather than raw screen-space deltas.

For rotated objects, perform resize math in the object's appropriate
local coordinate system where required.

## 3.6 Locked objects

Locked objects:

-   cannot move,
-   cannot resize,
-   cannot rotate,
-   should not expose active transform handles.

------------------------------------------------------------------------

# 4. Add Direct Beam Aim Handles

## 4.1 Product problem

Physical Stage aim is fundamentally spatial.

A numeric/slider control is useful for precision, but it should not be
the primary way a designer aims a fixture on a visual Stage.

Current workflow:

``` text
select PAR
→ find Direction slider
→ drag slider
→ watch Stage
→ correct slider
```

Desired workflow:

``` text
select PAR
→ grab beam aim handle
→ point beam at vocalist
→ release
```

This is substantially more natural and should be implemented now that
the physical Stage aim model exists.

------------------------------------------------------------------------

# 5. Aim Handle Presentation

When a fixture is selected in **Edit Stage**, show a direct-manipulation
beam aim handle.

Conceptually:

``` text
              ●  aim handle
             / \
            /   \
           /     \
          /       \
       [fixture]
```

The handle should sit on the beam centerline at the current
visualization reach.

Requirements:

-   visible only when useful,
-   visually distinct from resize/rotation handles,
-   sufficiently large hit target,
-   restrained Aurora styling,
-   remains usable over colored beams,
-   correct at different zoom levels.

Do not show the aim handle during ordinary live programming if geometry
is locked.

------------------------------------------------------------------------

# 6. Aim Handle Geometry

The direct aim gesture should derive Stage geometry from the pointer.

Given:

``` text
fixture center = F
pointer/handle = P
```

derive:

``` text
dx = P.x - F.x
dy = P.y - F.y

aimDirection = atan2(dy, dx)
beamLength = distance(F, P)
```

Convert to Aurora's existing angle convention consistently.

Do not introduce a second incompatible angle coordinate system.

## Recommended behavior

Dragging the primary aim handle should update:

-   **physical `aimDirection`**
-   **visual `beamLength`**

simultaneously.

This makes the handle behave like "point this fixture here."

Keep `beamSpread` as an Inspector control for C4.2.

A future enhancement may add spread edge handles, but that is not
required here.

------------------------------------------------------------------------

# 7. Static Fixtures

The aim handle must work for fixtures without Pan/Tilt DMX capabilities.

Mandatory examples:

-   PAR,
-   flood,
-   static wash,
-   static profile,
-   audience light,
-   LED bar where directional Stage visualization is enabled.

Example:

``` text
[PAR] ---------------- ●
                       vocalist
```

Dragging the handle toward the vocalist must physically aim the Stage
visualization at that performer without inventing DMX Pan/Tilt channels.

This edits **Stage placement geometry**, not Programmer state.

------------------------------------------------------------------------

# 8. Moving Fixtures

For a moving fixture, the direct aim handle edits the **base/physical
Stage aim**.

Live output continues to modify the rendered beam from that base
orientation.

Conceptually:

``` text
physical Stage aim
+
resolved live Pan/Tilt visualization
=
current beam direction
```

Do not let direct Stage aiming overwrite live Pan/Tilt Programmer
values.

Do not let live Pan/Tilt permanently rewrite Stage geometry.

These remain separate domains.

------------------------------------------------------------------------

# 9. Aim Gesture Lifecycle and Undo

Use the same transient architecture as move/resize.

``` text
mouse-down aim handle
→ capture committed aim + length
→ active transform = aim
→ update beam direction/length live
→ mouse-up
→ one committed Stage geometry operation
```

One aim drag = one Undo.

Undo should restore both direction and length to their pre-drag values
if both were changed by the gesture.

Escape/cancel should discard the transient aim.

------------------------------------------------------------------------

# 10. Keep Inspector Beam Controls

Do not remove the C4.1 Inspector controls.

They remain useful for:

-   exact numeric direction,
-   exact beam length,
-   beam spread,
-   show/hide beam,
-   future precision work.

The direct handle and Inspector must edit the same underlying model and
remain synchronized.

If the user drags the handle:

``` text
Inspector Direction updates
Inspector Length updates
```

If the user edits the Inspector:

``` text
aim handle moves
beam updates
```

One model, two interfaces.

------------------------------------------------------------------------

# 11. Repair the Edit Stage Rotation Slider

## 11.1 Observed defect

The Rotation slider displayed in the top Edit Stage toolbar cannot be
clicked or dragged.

The control is visible, so this is likely a hit-testing/gesture-layer
problem rather than missing rotation state.

Inspect the actual hierarchy around the Edit Stage tools bar, including:

-   overlays,
-   `contentShape`,
-   transparent hit-test views,
-   parent gestures,
-   `allowsHitTesting`,
-   z-order,
-   high-priority/simultaneous gestures,
-   Stage canvas gesture regions extending beyond the canvas.

Do not blindly replace the rotation model before verifying event
delivery.

## 11.2 Required behavior

When an eligible Stage object or fixture geometry target is selected:

-   Rotation slider is enabled,
-   clicking the track works,
-   dragging the thumb works,
-   value updates live,
-   Stage object rotates live,
-   mouse-up produces one logical committed edit,
-   Undo restores previous rotation.

When no rotatable selection exists:

-   control is disabled or hidden according to existing Aurora design
    language.

## 11.3 Slider interaction isolation

Dragging the Rotation slider must not:

-   pan the Stage,
-   move the selected object,
-   begin marquee selection,
-   trigger beam aiming,
-   resize an object.

The toolbar must own its own pointer events.

------------------------------------------------------------------------

# 12. Add a Direct Object Rotation Handle

The slider should be repaired regardless.

However, direct manipulation is preferable for spatial rotation as well.

If it can be implemented cleanly in this pass, add a rotation handle to
selected rotatable Stage objects.

Conceptually:

``` text
           ○  rotation handle
           |
      ┌──────────┐
      │  object  │
      └──────────┘
```

Dragging the rotation handle around the object's center derives:

``` text
rotation = atan2(pointerY - centerY,
                 pointerX - centerX)
         + orientationOffset
```

Use the existing Aurora angle convention.

## Priority

This is **strongly preferred**, but fixing the broken toolbar slider is
mandatory.

Do not destabilize C4.2 solely to force the direct rotation handle into
the checkpoint if it proves unexpectedly invasive.

If deferred, document it explicitly.

------------------------------------------------------------------------

# 13. Unified Transform Arbitration

C4.2 should leave the Stage with an explicit interaction precedence
model.

Recommended precedence:

``` text
1. toolbar/control interaction
2. resize handle
3. rotation handle
4. beam aim handle
5. fixture/object move
6. Space-pan
7. empty-space marquee/pan behavior
```

Exact SwiftUI/AppKit gesture composition may differ, but behavior must
be deterministic.

## Required exclusivity

A single pointer drag must never simultaneously:

-   move + resize,
-   move + rotate,
-   move + aim,
-   resize + pan,
-   aim + pan,
-   operate toolbar + Stage canvas.

This is the core C4.2 requirement.

------------------------------------------------------------------------

# 14. Visual Feedback During Transforms

## Resize

Show:

-   live object geometry,
-   active handle state,
-   selection frame updating continuously.

## Aim

Show:

-   beam moving continuously,
-   aim handle following pointer,
-   Direction/Length values updating.

## Rotate

Show:

-   object rotating continuously,
-   selection frame rotating with it,
-   Rotation value updating.

Avoid commit-time jumps.

------------------------------------------------------------------------

# 15. Beam Visual Tuning

The new wedge beam renderer is directionally correct and should be
retained.

Do not reopen the beam architecture unless necessary for aim-handle
integration.

However, while implementing the direct aim handle, perform a small
visual tuning pass for overlapping beams.

Current concern:

-   multiple translucent wedge layers can become somewhat
    geometric/stained-glass-like when beams overlap.

Tune conservatively:

-   reduce harsh internal triangle boundaries,
-   keep feathered edges,
-   maintain readable center intensity,
-   avoid excessive blur,
-   preserve performance.

The goal remains:

``` text
light through haze
```

not:

``` text
stacked translucent polygons
```

This is a polish item, not permission for a renderer rewrite.

------------------------------------------------------------------------

# 16. Automated Tests

Add tests around the interaction math and finalizers rather than relying
exclusively on UI automation.

## Resize ownership/finalization

Test:

-   NW resize,
-   NE resize,
-   SW resize,
-   SE resize,
-   aspect-constrained image resize,
-   free shape resize,
-   locked object rejection,
-   zoom-aware delta conversion,
-   rotated object geometry,
-   one final layout result.

If practical, test the transform state machine:

``` text
begin resize
→ move attempt rejected while resize active
→ finish resize
→ interaction returns to none
```

## Aim math

Extract a pure helper if not already available.

Test:

``` text
fixture (0,0), pointer (100,0)
→ direction 0°
→ length 100
```

``` text
fixture (0,0), pointer (0,100)
→ expected Aurora direction convention
→ length 100
```

Also test all quadrants.

## Aim finalization

Verify:

-   static fixture aim changes without Pan/Tilt capability,
-   direction + length round-trip through project serialization,
-   one final Stage geometry result,
-   Undo restores both values.

## Moving fixture separation

Verify:

-   changing physical aim does not mutate live Pan,
-   changing live Pan does not mutate physical aim,
-   renderer composes both.

## Rotation

Test:

-   rotation finalizer,
-   slider-driven update path if testable,
-   direct rotation math if handle is implemented,
-   locked object cannot rotate.

------------------------------------------------------------------------

# 17. Manual Production Acceptance Checklist

Perform all tests in the actual Aurora application.

## Resize

-   [ ] Place vocalist silhouette.
-   [ ] Select it.
-   [ ] Drag NW handle.
-   [ ] Confirm object resizes and does not move as a whole.
-   [ ] Repeat NE/SW/SE.
-   [ ] Confirm aspect ratio behavior.
-   [ ] Undo once.
-   [ ] Place rectangle/stage area.
-   [ ] Resize freely.
-   [ ] Rotate object, then resize.
-   [ ] Confirm geometry remains sane.
-   [ ] Lock object and verify handles cannot transform it.

## Static beam aiming

-   [ ] Place a PAR.
-   [ ] Select it in Edit Stage.
-   [ ] Confirm aim handle appears.
-   [ ] Drag handle toward vocalist.
-   [ ] Confirm beam follows pointer live.
-   [ ] Confirm Direction and Length controls update.
-   [ ] Release.
-   [ ] Undo once.
-   [ ] Confirm original aim and length return.
-   [ ] Verify no Pan/Tilt DMX capability was required.

## Flood/wash

-   [ ] Place a broad wash/flood.
-   [ ] Aim with direct handle.
-   [ ] Confirm broad beam follows spatial direction naturally.

## Moving head

-   [ ] Place mover.
-   [ ] Use aim handle to set physical base aim.
-   [ ] Exit Edit Stage.
-   [ ] Manipulate live Pan.
-   [ ] Confirm beam moves relative to base aim.
-   [ ] Re-enter Edit Stage.
-   [ ] Confirm physical aim was not overwritten by live Pan.

## Rotation slider

-   [ ] Select rotatable Stage object.
-   [ ] Click Rotation slider track.
-   [ ] Confirm rotation changes.
-   [ ] Drag thumb.
-   [ ] Confirm smooth live rotation.
-   [ ] Confirm Stage does not pan/move while slider is used.
-   [ ] Undo once.

## Direct rotation handle, if implemented

-   [ ] Select object.
-   [ ] Drag rotation handle around object.
-   [ ] Confirm smooth rotation.
-   [ ] Confirm object center does not translate.
-   [ ] Confirm resize/move do not trigger simultaneously.
-   [ ] Undo once.

## Gesture arbitration

-   [ ] Drag object body → move only.
-   [ ] Drag resize handle → resize only.
-   [ ] Drag rotation handle → rotate only.
-   [ ] Drag beam aim handle → aim only.
-   [ ] Space-drag Stage → pan only.
-   [ ] Drag toolbar slider → toolbar only.

------------------------------------------------------------------------

# 18. Production Evidence

Provide screenshots from the actual production Aurora app showing:

1.  selected silhouette with resize handles,
2.  silhouette after resize,
3.  static PAR selected with direct aim handle visible,
4.  PAR beam aimed at a performer,
5.  moving head with physical aim plus live directional beam,
6.  Rotation slider active/usable,
7.  direct rotation handle if implemented.

A short recording showing the following sequence would be especially
useful:

``` text
resize performer
→ aim PAR by dragging handle
→ rotate scenic object
→ move object
→ Space-pan Stage
```

The important evidence is that each gesture does exactly one thing.

------------------------------------------------------------------------

# 19. Non-Goals

Do not begin:

-   C5 undockable workspace,
-   multi-monitor persistence,
-   workspace presets,
-   C6 splash remediation,
-   full beam spread edge handles,
-   3D visualization,
-   photometric simulation,
-   gobo projection,
-   advanced CAD transform tools.

C4.2 is an interaction closeout.

------------------------------------------------------------------------

# 20. Recommended Implementation Order

## Step 1

Trace and fix resize gesture ownership.

Do not add more transform gestures until resize and move are mutually
exclusive.

## Step 2

Introduce/solidify explicit active transform state.

Use it as the arbitration foundation for resize, rotate, aim, and move.

## Step 3

Repair Rotation slider hit testing.

This may expose a broader overlay/gesture-region problem that should be
corrected before adding the aim handle.

## Step 4

Implement direct beam aim handle and pure aim geometry helper.

## Step 5

Wire aim handle to transient state and one-command finalization.

## Step 6

Synchronize direct aim with Inspector Direction/Length controls.

## Step 7

Add direct object rotation handle if cleanly achievable.

## Step 8

Perform conservative beam overlap polish.

## Step 9

Complete automated tests.

## Step 10

Run full production acceptance and capture evidence.

------------------------------------------------------------------------

# 21. Completion Criteria

C4.2 is complete only when:

-   resize handles actually resize,
-   dragging a resize handle never moves the object,
-   all supported corner handles work,
-   resize remains correct under zoom and rotation,
-   static fixtures have a direct Stage aim handle,
-   aim handle edits physical direction live,
-   aim handle edits beam length live or otherwise follows the approved
    direct-aim behavior,
-   Inspector beam controls remain synchronized,
-   movers preserve separation between base Stage aim and live Pan/Tilt,
-   Rotation slider is fully clickable and draggable,
-   toolbar interaction cannot leak into Stage gestures,
-   move/resize/rotate/aim/pan are mutually exclusive,
-   one physical transform gesture produces one logical Undo,
-   locked objects cannot transform,
-   automated tests pass,
-   native Xcode build passes,
-   production manual acceptance passes.

------------------------------------------------------------------------

# 22. STOP CONDITION

After C4.2:

> **STOP and produce a C4.2 checkpoint for human review. Do not begin
> C5.**

Report:

-   root cause of resize-handle failure,
-   root cause of Rotation slider input failure,
-   transform-arbitration implementation,
-   direct beam aim implementation,
-   test results,
-   production acceptance results,
-   screenshots/recording evidence,
-   any explicitly deferred direct-rotation work.

C5 begins only after C4.2 is approved.

------------------------------------------------------------------------

# 23. Product Standard

Aurora's Stage Designer should behave like a physical workspace.

Grab the object and it moves.

Grab its corner and it resizes.

Grab its rotation control and it turns.

Grab the beam and point it where the light should go.

Grab empty Stage space with the appropriate navigation gesture and the
camera moves.

The user should never have to wonder which of those actions Aurora
thinks they meant.
