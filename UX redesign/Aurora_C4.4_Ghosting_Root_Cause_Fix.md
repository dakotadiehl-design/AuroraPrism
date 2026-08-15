# Aurora C4.4 Ghosting Root-Cause Fix

## Genuine Committed/Transient Render Separation for Stage Layout Objects

**Project:** Aurora Lighting Control\
**Target:** `Aurora_StillGhosting` repository\
**Phase:** C4.4 surgical stabilization\
**Status:** Required before C5\
**Scope:** Stage layout-object transform rendering only, followed by
controlled generalization\
**Primary defect:** Severe visual ghosting/trailing while dragging Stage
objects

------------------------------------------------------------------------

# 1. Executive Summary

C4.3 successfully corrected the Rotation live-update problem and the
duplicate macOS `View` menu. **Do not reopen those fixes.**

The Stage-object ghosting defect remains.

A deeper review of the current repository shows that C4.3's central
rendering requirement was **not actually implemented for
`StageLayoutObject` visuals**.

C4.3 required:

> During an active transform, remove the active element from the
> committed visual render path and render it exactly once in a dedicated
> transient transform layer.

The current repository does this for **fixtures**, but layout objects
such as:

-   performer silhouettes,
-   truss,
-   scenic objects,
-   stock images,
-   imported images

remain inside their normal persistent `ForEach` and are moved by
changing their transient `.position`/geometry.

At the same time, the active object and/or Stage world are passed
through `compositingGroup()` / `drawingGroup(opaque: false)` during
transforms.

The first C4.4 objective is therefore not another gesture-priority
experiment.

It is to **literally implement the committed/transient visual split for
Stage layout objects** and remove unnecessary offscreen compositing from
the live transform path.

------------------------------------------------------------------------

# 2. Confirmed Repository Finding

## 2.1 Fixtures already use the intended architecture

The current fixture path uses `StageEditRenderEligibility` to separate
committed and transient rendering.

Conceptually:

``` swift
displayPlacements.filter {
    StageEditRenderEligibility.shouldRenderInCommittedLayer(
        elementID: $0.fixtureID,
        transientElementIDs: transientFixtureIDs
    )
}
```

followed by a transient fixture pass using:

``` swift
StageEditRenderEligibility.shouldRenderInTransientLayer(...)
```

This is the correct architectural pattern.

Preserve it unless a narrowly related change is necessary.

## 2.2 Layout objects do not use the same split

The layout-object pass currently resembles:

``` swift
ForEach(
    layout.objects
        .filter { !$0.hidden }
        .sorted { $0.zIndex < $1.zIndex }
) { obj in
    layoutObjectView(obj)
}
```

The active layout object is **not filtered out of this committed pass**.

Instead, `layoutObjectView` determines whether the object is
live/transient and changes the geometry of the same persistent view.

Conceptually:

``` swift
let isLive = transientLayoutObjectIDs.contains(obj.id)

...
.position(x: livePosition.x, y: livePosition.y)
.modifier(StageLiveObjectCompositingModifier(active: isLive))
```

That is not the committed/transient visual split specified in C4.3.

## 2.3 Important distinction

The comment that a layout object is "rendered exactly once" because it
appears once in one `ForEach` is not sufficient.

The intended invariant is stronger:

``` text
inactive:
    committed visual layer = yes
    transient visual layer = no

active transform:
    committed visual layer = no
    transient visual layer = yes
```

The active visual must leave the normal committed rendering hierarchy.

------------------------------------------------------------------------

# 3. Do Not Start With More Gesture Modifier Shuffling

Do not begin C4.4 by rearranging:

``` swift
.gesture(...)
.highPriorityGesture(...)
.simultaneousGesture(...)
.offset(...)
.position(...)
.transaction(...)
```

The current gesture arbitration is already substantially more deliberate
than earlier passes.

The remaining symptom is consistent with a rendering/compositing
problem.

Gesture ownership still matters because moving a view between render
hierarchies can terminate a gesture, but solve that **explicitly**
rather than preserving the flawed visual path solely to keep SwiftUI
view identity alive.

------------------------------------------------------------------------

# 4. First Experiment Must Be Deliberately Small

Before generalizing anything, prove the rendering model with one stock
silhouette.

Use a small branch/commit and implement only:

> **Single selected stock silhouette → move drag → genuine transient
> visual layer → zero ghosting.**

For this proof:

-   do not change resize,
-   do not change rotation,
-   do not change aim,
-   do not redesign beams,
-   do not modify menu structure,
-   do not begin C5.

Use a performer asset such as vocalist/guitarist as the test object.

Stress-drag it for at least 20 seconds.

Only after this proof is clean should the architecture be generalized.

------------------------------------------------------------------------

# 5. Implement a Genuine Committed Layout-Object Layer

The normal layout-object render pass must exclude objects currently
represented by transient transform state.

Conceptually:

``` swift
ForEach(
    layout.objects
        .filter {
            !$0.hidden &&
            StageEditRenderEligibility.shouldRenderInCommittedLayer(
                elementID: $0.id,
                transientElementIDs: transientLayoutObjectIDs
            )
        }
        .sorted { $0.zIndex < $1.zIndex }
) { obj in
    committedLayoutObjectView(obj)
}
```

The committed view should render committed geometry only.

Do not make `committedLayoutObjectView` inspect live movement state and
reposition itself.

Its contract should be simple:

> Render the document's committed object at its committed geometry.

This makes the layer deterministic.

------------------------------------------------------------------------

# 6. Add a Dedicated Transient Layout-Object Layer

Add a separate world-space layer for active layout objects.

Conceptually:

``` swift
ZStack {
    ForEach(
        layout.objects
            .filter {
                !$0.hidden &&
                StageEditRenderEligibility.shouldRenderInTransientLayer(
                    elementID: $0.id,
                    transientElementIDs: transientLayoutObjectIDs
                )
            }
            .sorted { $0.zIndex < $1.zIndex }
    ) { obj in
        transientLayoutObjectView(obj)
    }
}
.transaction { transaction in
    transaction.animation = nil
}
```

This layer must use the same Stage/world transform as committed content.

It must not be a detached screen-space overlay.

The transient view derives displayed geometry from:

``` text
committed object
+
current transient interaction preview
```

and renders the object once.

------------------------------------------------------------------------

# 7. Hard Single-Render Invariant

During an active transform of layout object `X`:

``` text
shouldRenderInCommittedLayer(X) == false
shouldRenderInTransientLayer(X) == true
```

For an inactive layout object `Y`:

``` text
shouldRenderInCommittedLayer(Y) == true
shouldRenderInTransientLayer(Y) == false
```

There must never be a frame in which:

``` text
committed X visible
+
transient X visible
```

There must also never be a transform frame in which both are false
unless the interaction is intentionally cancelled/removed.

Add assertions/debug diagnostics if useful.

------------------------------------------------------------------------

# 8. Gesture Ownership Must Be Separate From Visual Ownership

A critical SwiftUI issue must be handled intentionally.

If the user's drag begins on the committed object view and Aurora
removes that view from its `ForEach` as soon as the transform starts,
SwiftUI may terminate the gesture because the original gesture-hosting
view disappeared.

Do not solve this by abandoning the transient visual split.

Instead separate:

``` text
gesture host
```

from:

``` text
visible artwork
```

Two viable approaches follow.

------------------------------------------------------------------------

# 9. Preferred Approach A --- Canvas/World-Owned Drag

Preferred long-term architecture:

1.  Object hit testing identifies which object was pressed.
2.  Stage/world interaction state claims the move transform.
3.  A canvas/world-level gesture owns subsequent pointer movement.
4.  The object's committed visual can safely disappear.
5.  The transient visual follows the canvas-owned gesture.

Conceptually:

``` text
pointer-down
→ hit-test object B
→ interactionState.beginMove(B)

pointer-drag
→ canvas updates transient position for B

pointer-up
→ finalizer commits B
```

This removes gesture lifetime from the rendered object's SwiftUI
identity.

If the current Stage architecture can adopt this cleanly without
destabilizing other interactions, prefer it.

------------------------------------------------------------------------

# 10. Smaller Approach B --- Invisible Gesture Proxy

If canvas-owned drag is too invasive for this surgical pass, retain a
nonvisual gesture host in the committed hierarchy.

Conceptually:

``` text
Committed interaction layer:
    transparent hit proxy for B
    NO B artwork

Transient visual layer:
    visible B at live geometry
```

Example concept:

``` swift
Color.clear
    .contentShape(Rectangle())
    .frame(width: hitWidth, height: hitHeight)
    .position(committedOrAppropriateHitPosition)
    .gesture(existingMoveGesture)
```

Important:

-   proxy must render no silhouette/image/truss artwork,
-   proxy must not introduce visible selection chrome,
-   transient layer remains the only visual copy,
-   hit proxy exists only as needed to preserve gesture ownership.

This is acceptable for C4.4 if it produces clean behavior.

Document which approach was chosen and why.

------------------------------------------------------------------------

# 11. Remove `drawingGroup()` From the Initial Proof

The current repository uses compositing helpers similar to:

``` swift
.compositingGroup()
.drawingGroup(opaque: false)
```

for active objects and/or the Stage transform world.

`drawingGroup()` is not an anti-ghosting primitive. It creates an
offscreen rendering/compositing path and may be contributing to the
artifact with image-backed objects moving inside a scaled/panned
hierarchy.

For the initial silhouette proof:

> **Remove `drawingGroup()` and `compositingGroup()` from the live
> layout-object transform path.**

Test ordinary SwiftUI rendering first:

``` text
committed layer
+
transient layer
+
implicit animation disabled
```

Do not nest a moving image-backed transient object inside multiple
`drawingGroup()` passes unless measurement proves it is necessary.

------------------------------------------------------------------------

# 12. Review These Compositing Helpers

Specifically inspect and temporarily remove/bypass where they affect
live layout-object transforms:

``` text
StageTransformCompositingModifier
StageLiveObjectCompositingModifier
```

or equivalent current names.

Do not remove unrelated compositing used for static rendering unless
necessary.

The goal is to isolate whether the offscreen rendering path contributes
to ghost trails.

Record the result.

------------------------------------------------------------------------

# 13. Disable Implicit Animation at the Transient Layer Boundary

Apply no-animation behavior to the transient transform layer as a whole.

Conceptually:

``` swift
.transaction { transaction in
    transaction.animation = nil
}
```

The transient position should be a direct function of pointer movement.

Do not rely solely on per-object `.animation(nil, value:)` patches
scattered through the tree.

Expected:

``` text
pointer moves
→ transient geometry changes
→ frame renders immediately
```

------------------------------------------------------------------------

# 14. Selection Chrome Must Follow the Transient Visual

When the active layout object leaves the committed visual layer, its:

-   selection outline,
-   resize handles,
-   rotation handle,
-   other direct manipulation chrome

must not remain at the old committed position.

During the active transform, render transform chrome from transient
geometry.

Do not produce:

``` text
old selection frame
+
moving object
```

or:

``` text
old handles
+
new handles
```

Only one visual transform representation should exist.

------------------------------------------------------------------------

# 15. Multi-Selection Must Generalize the Same Way

The current `transientLayoutObjectIDs` already appears capable of
representing multiple layout-object IDs during a group move.

Use that plumbing.

If three selected layout objects are moved:

``` text
Singer
Guitarist
Drummer
```

then all three must:

``` text
leave committed visual layer
→ enter transient visual layer
→ move together
→ commit together according to existing semantics
```

Do not special-case only the primary selection after the single-object
proof succeeds.

------------------------------------------------------------------------

# 16. Do Not Confuse Fixtures and Layout Objects

The current drag state appears to use a name such as:

``` swift
fixtureDrag
```

for movement that may include both fixtures and layout objects.

If confirmed, rename it during this pass if the change is safe and
localized.

Recommended conceptual names:

``` swift
elementDrag
stageElementDrag
stageDragState
```

This is not required to fix ghosting, but the current naming obscures
the fact that performer/truss/image movement is flowing through
"fixture" state.

Avoid a broad rename if it creates unnecessary churn. If deferred,
document it.

------------------------------------------------------------------------

# 17. Prove the Fix Before Generalizing

## Phase 1 --- one stock silhouette

Test:

-   100% zoom,
-   150% zoom,
-   200% zoom,
-   slow drag,
-   violent drag,
-   circles,
-   rapid direction reversals.

Run continuously for at least 20 seconds.

Required:

-   exactly one visible silhouette,
-   zero trails,
-   zero stale copies,
-   zero flash at committed origin,
-   zero jump on release.

If this fails, **STOP** and investigate the rendering layer before
modifying resize/rotate/etc.

------------------------------------------------------------------------

# 18. If the Single Silhouette Still Ghosts

Only after the genuine committed/transient split and removal of live
`drawingGroup()` are proven in code should lower-level escalation begin.

Inspect:

-   `StageStockGlyphView`,
-   image/vector loading path,
-   `Image`/`NSImage` lifetime,
-   raster cache behavior,
-   layer backing,
-   parent Stage transforms,
-   clipping/masking,
-   opacity/effect stacks.

At that point, consider a narrow AppKit-backed transient host.

Possible direction:

``` text
NSViewRepresentable
→ layer-backed transient transform surface
→ one active visual
```

Do **not** rewrite the entire Stage canvas in AppKit.

Escalate only the transient interaction rendering surface if SwiftUI
still produces artifacts after the architectural fix.

------------------------------------------------------------------------

# 19. Diagnostic Mode

Add temporary diagnostics during development.

For active object ID:

``` text
active transform type
active target ID
committed visual eligible?
transient visual eligible?
gesture owner
committed position
transient position
```

The key invariant must print:

``` text
Committed: false
Transient: true
```

during movement.

If both print `true`, the implementation is wrong.

If both print `false`, the object may disappear.

Put diagnostics behind a debug flag or remove noisy logging before
checkpoint.

------------------------------------------------------------------------

# 20. After Move Is Proven, Generalize Carefully

Only after clean stock-silhouette movement:

## Step A

Apply to all stock Stage layout objects.

## Step B

Apply to imported images.

Imported raster images are an important stress case.

## Step C

Apply to truss/scenic objects.

## Step D

Apply the same transient visual ownership principle to resize.

## Step E

Apply to direct rotation.

## Step F

Verify fixture aim/beam already satisfies the same invariant. Adjust
only if stale beam visuals remain.

Do not change all transform paths simultaneously before proving the
basic move case.

------------------------------------------------------------------------

# 21. Rotation Is Already Fixed

The current pass has corrected Rotation live update.

Do not reopen that implementation unless required to integrate it with
the final transient rendering state.

Regression-test it after C4.4.

Required:

-   live slider preview remains,
-   direct rotation remains live,
-   one slider drag = one Undo,
-   no ghosting during rotation.

------------------------------------------------------------------------

# 22. Duplicate View Menu Is Already Fixed

The duplicate top-level View-menu defect is corrected.

Do not restructure the menu bar again in C4.4.

Regression-test only:

``` text
exactly one View menu
Workspace menu still correct
```

------------------------------------------------------------------------

# 23. Automated Tests

Add or strengthen tests around render eligibility.

## 23.1 Single object

``` text
inactive X:
committed = true
transient = false
```

``` text
active X:
committed = false
transient = true
```

## 23.2 Multiple objects

For transient set:

``` text
{A, B, C}
```

expect:

``` text
A committed false / transient true
B committed false / transient true
C committed false / transient true
D committed true  / transient false
```

## 23.3 Cancellation

Test:

``` text
begin move
→ transient eligibility
→ cancel
→ committed eligibility restored
```

## 23.4 Commit

Test:

``` text
begin move
→ transient preview
→ finish
→ committed geometry updated
→ transient set empty
→ committed visual eligible
```

## 23.5 Gesture ownership state

If canvas-owned drag or proxy ownership is represented in pure state,
test:

``` text
move begins
→ correct target owns transform
→ incompatible transform rejected
→ finish
→ ownership clears
```

------------------------------------------------------------------------

# 24. Manual Acceptance Matrix

## Stock performer

-   [ ] Slow drag clean.
-   [ ] Fast drag clean.
-   [ ] 20-second circular stress drag clean.
-   [ ] Direction reversals clean.
-   [ ] 100% zoom clean.
-   [ ] 150% zoom clean.
-   [ ] 200% zoom clean.

## Truss

-   [ ] Fast drag clean.
-   [ ] Rotated truss drag clean.
-   [ ] No stale selection frame.

## Imported image

-   [ ] Fast drag clean.
-   [ ] No raster trails.
-   [ ] No old copy at origin.

## Multi-selection

-   [ ] Select three objects.
-   [ ] Move rapidly.
-   [ ] Exactly three transient visuals.
-   [ ] No committed duplicates.
-   [ ] Release commits all correctly.
-   [ ] Undo restores group.

## Resize

After generalization:

-   [ ] rapid corner resize clean,
-   [ ] no stale object,
-   [ ] no stale selection chrome.

## Rotation regression

-   [ ] Rotation slider still live-updates.
-   [ ] Direct rotation still works.
-   [ ] No rotational trails.

## Aim regression

-   [ ] PAR aim remains live.
-   [ ] No stale beam wedges.

## Menu regression

-   [ ] One View menu.
-   [ ] Workspace menu present.

------------------------------------------------------------------------

# 25. Required Production Recording

This checkpoint must include a recording from the actual Aurora
application.

Show:

``` text
single vocalist
→ 20-second aggressive drag
→ zoom and drag
→ truss drag
→ imported-image drag
→ multi-selection drag
→ resize
→ rotate
```

Do not submit only screenshots for the ghosting fix.

This is a temporal rendering defect and needs temporal evidence.

------------------------------------------------------------------------

# 26. Required C4.4 Report

At checkpoint, report:

1.  Why C4.3 did not eliminate layout-object ghosting.
2.  Whether layout objects were previously kept in the committed
    `ForEach`.
3.  Which gesture-ownership strategy was chosen:
    -   canvas/world-owned drag, or
    -   invisible gesture proxy.
4.  How committed/transient visual exclusivity is enforced.
5.  Whether `drawingGroup()` removal changed the behavior.
6.  Whether a lower-level AppKit transient surface was necessary.
7.  Single-object stress-test results.
8.  Multi-selection results.
9.  Imported-image results.
10. Regression results for resize/rotation/aim.
11. Build and automated-test results.

------------------------------------------------------------------------

# 27. Recommended Implementation Order

## Step 1

Reproduce ghosting in current production build.

## Step 2

Instrument committed/transient eligibility for one silhouette.

## Step 3

Split layout-object rendering into genuine committed and transient
visual passes.

## Step 4

Preserve gesture ownership independently from artwork using Approach A
or B.

## Step 5

Remove live layout-object `drawingGroup()` / unnecessary compositing.

## Step 6

Disable implicit animation at transient layer boundary.

## Step 7

Run the 20-second single-silhouette stress test.

### If it fails:

STOP and investigate `StageStockGlyphView`/image/compositor path.

### If it passes:

continue.

## Step 8

Generalize to all layout-object types.

## Step 9

Generalize to multi-selection.

## Step 10

Verify resize and rotation against same visual ownership model.

## Step 11

Test imported raster images.

## Step 12

Run full regression suite.

## Step 13

Capture production recording.

## Step 14

STOP for human review.

------------------------------------------------------------------------

# 28. Completion Criteria

C4.4 is complete only when:

-   active layout objects are removed from the committed visual render
    path,
-   active layout objects are rendered in a dedicated transient visual
    layer,
-   gesture ownership is independent from visible artwork ownership,
-   active objects are never visually rendered in both layers,
-   `drawingGroup()` is not being used as an unproven ghosting
    workaround,
-   one silhouette survives aggressive 20-second movement without
    trails,
-   truss movement is clean,
-   imported-image movement is clean,
-   multi-object movement is clean,
-   resize remains clean,
-   rotation remains live and clean,
-   beam aiming remains clean,
-   no release jumps occur,
-   one gesture remains one Undo,
-   automated tests pass,
-   native Xcode build succeeds,
-   production recording demonstrates the result.

------------------------------------------------------------------------

# 29. STOP CONDITION

After C4.4:

> **STOP. Do not begin C5 until the production ghosting recording has
> been reviewed and C4.4 has explicit human approval.**

Do not declare success solely because unit tests pass.

Do not declare success solely because the code now contains a class or
helper named "TransientLayer."

The acceptance criterion is visual:

> **Grab a performer and throw it around the Stage. Aurora must draw one
> performer under the pointer, with no ghosts.**

------------------------------------------------------------------------

# 30. Product Standard

The current defect is no longer a question of adding more Stage
features. It is a question of rendering ownership.

The committed Stage describes where the object *was committed*.

The transient interaction layer describes where the object *is under the
user's hand right now*.

During a transform, only the second representation should be visible.

One object. One visual. One pointer. No ectoplasm.
