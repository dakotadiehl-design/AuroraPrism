# Aurora C4.3 Stage Rendering & Interaction Stabilization

## Eliminate Drag Ghosting, Add Live Rotation Preview, Centralize Transient Transform State, and Repair macOS Menu Structure

**Project:** Aurora Lighting Control\
**Target:** Current post-C4.2 repository (`Aurora_c4again`)\
**Phase:** C4.3 stabilization closeout\
**Status:** Required before C5\
**Purpose:** Fix the remaining rendering/compositing and interaction
defects observed during hands-on Stage Designer testing.

------------------------------------------------------------------------

# 1. Executive Summary

The latest C4 pass has the correct broad Stage architecture, but
production testing exposes three defects that are serious enough to
block C5:

1.  **Dragging Stage objects produces severe visual ghosting/trailing
    copies.**
2.  **The Rotation slider does not live-update the selected object while
    the slider is being dragged.**
3.  **Aurora displays two top-level `View` menus in the macOS menu
    bar.**

The ghosting issue has survived earlier gesture-priority and
`.offset(...)` fixes. At this point, do **not** continue trying
increasingly elaborate combinations of SwiftUI gesture priority,
`.position`, `.offset`, or per-object animation suppression.

The stabilization strategy for C4.3 is:

> **An actively transformed Stage element must be rendered exactly once,
> in a dedicated transient transform layer.**

At the same time, toolbar-driven rotation and canvas-driven rotation
should use the same transient interaction state so Aurora can provide
live preview without committing document mutations continuously.

Finally, the menu bar should follow native macOS structure rather than
creating a second top-level `View` menu.

------------------------------------------------------------------------

# 2. Preserve Existing Architecture

Do not reopen or replace the successful C4/C4.1/C4.2 work.

Preserve:

-   Stage object model,
-   Stage fixture placement model,
-   physical Stage aim separate from live Pan/Tilt,
-   current wedge/cone beam renderer,
-   direct beam aim handle,
-   object resize infrastructure,
-   object rotation infrastructure,
-   locking and z-order,
-   camera pan/zoom,
-   one logical transform gesture = one Undo,
-   stable silhouette asset keys,
-   current project serialization/migration behavior.

C4.3 is a **rendering and interaction-state stabilization pass**, not
another Stage feature redesign.

------------------------------------------------------------------------

# 3. Defect A --- Severe Ghosting During Drag

## 3.1 Observed behavior

During a Stage-object drag, stale copies/trails of the object remain
visible behind the current pointer position.

This is especially obvious when rapidly moving silhouettes or other
image-backed Stage objects.

The artifact makes the canvas appear to smear or leave "ghosts" during
interaction.

This is not acceptable for a production Stage editor.

## 3.2 Current implementation concern

The current Stage code applies transient movement to the normal
committed object view using a changing offset/position inside the
transformed Stage hierarchy.

Conceptually:

``` swift
object
    .rotationEffect(...)
    .position(x: committedX, y: committedY)
    .offset(x: transientDX, y: transientDY)
```

This approach has already been adjusted in previous passes to suppress
ghosting, but the production recording demonstrates that the problem
persists.

Treat this as a **rendering/compositing issue**, not primarily a
gesture-arbitration issue.

Do not spend C4.3 merely shuffling `.gesture`, `.highPriorityGesture`,
`.simultaneousGesture`, `.transaction`, `.drawingGroup`, or `.offset`
modifiers without changing the fundamental "active object is still
rendered in the normal committed layer" behavior.

------------------------------------------------------------------------

# 4. Dedicated Transient Transform Rendering Layer

## 4.1 Required rendering invariant

During any active transform:

> **The transformed object/fixture must have exactly one visual
> representation on the Stage.**

For an object being moved:

``` text
Committed Stage Object Layer
├── Object A
├── Object B   ← omitted/hidden while B is actively transformed
└── Object C

Transient Transform Layer
└── Object B   ← rendered once at transient geometry
```

Do not render committed B underneath transient B.

## 4.2 World-space placement

The transient layer must participate in the same Stage world/camera
coordinate system as the normal content.

Correct:

``` text
Stage viewport
└── camera/world transform
    ├── committed content excluding active transformed element
    └── transient transform content
```

Avoid a detached screen-space overlay whose coordinates must be manually
reverse-mapped on every frame.

The transient item must naturally follow:

-   Stage pan,
-   Stage zoom,
-   object rotation,
-   normalized visual bounds.

## 4.3 Supported transforms

The dedicated transient layer should support the interaction classes
already present:

-   move,
-   resize,
-   rotate,
-   fixture aim where a transient fixture/beam representation is
    appropriate.

The most important immediate case is object movement, but design the
layer so resize/rotate do not need a separate rendering hack later.

## 4.4 Hide/omit committed representation

When:

``` text
activeTransform targets objectID == X
```

the normal committed-object `ForEach` must not render the visual
representation of X.

Prefer omission/filtering over "render it at opacity 0" if opacity-zero
content can still incur unwanted compositing/hit-testing.

The transient layer then renders X from:

``` text
committed geometry
+
transient transform preview
```

exactly once.

## 4.5 Selection chrome

Selection outline/handles for the active object should follow the
transient geometry.

Do not leave:

``` text
committed selection box at old location
+
transient object at new location
```

The transform chrome should belong to the active/transient
representation during the gesture.

## 4.6 Hit testing

While a transform is active:

-   the transient representation owns the active gesture,
-   the omitted committed representation must not be hit-testable,
-   other Stage elements should not accidentally steal the active
    pointer.

On mouse-up/cancel:

``` text
commit or discard
→ clear transient state
→ normal committed layer renders object again
```

There must not be a frame where both copies become visible.

------------------------------------------------------------------------

# 5. Eliminate Implicit Animation From Transform Preview

The transient transform layer should not implicitly animate geometry
changes.

Use a transaction/animation policy at the **transient layer boundary**,
not only scattered per-object.

Conceptually:

``` swift
.transaction { transaction in
    transaction.animation = nil
}
```

or an equivalent architecture appropriate to the existing SwiftUI/AppKit
implementation.

Required behavior:

``` text
pointer moves 4 px
→ object appears 4 px farther immediately
```

not:

``` text
pointer moves
→ object interpolates toward pointer
```

This applies to:

-   move,
-   resize,
-   rotate,
-   beam aim preview.

Do not disable intended show/playback animations globally.

This is specifically Stage Edit transform preview.

------------------------------------------------------------------------

# 6. Consider NSView/Layer Backing Only If Necessary

First implement the single-render transient-layer architecture cleanly
in SwiftUI.

If image-backed Stage objects still produce compositor trails after the
active object is truly rendered only once, investigate the specific
macOS backing/compositing behavior.

Possible escalation points include:

-   explicit layer-backed hosting for the Stage canvas,
-   controlled `NSViewRepresentable` for the transient interaction
    surface,
-   avoiding pathological offscreen rasterization combinations.

Do **not** jump to an AppKit rewrite unless the single-render invariant
still fails in production.

The desired outcome is correctness with the smallest architectural
escalation.

------------------------------------------------------------------------

# 7. Defect B --- Rotation Slider Does Not Live Update

## 7.1 Observed behavior

Dragging the Edit Stage Rotation slider changes the control value but
the selected Stage object does not visibly rotate until the slider
interaction ends.

This makes rotation feel disconnected and broken.

## 7.2 Root interaction pattern

The current pattern commits rotation only when slider editing finishes:

``` swift
Slider(value: $rotationValue, in: -180...180) { editing in
    if !editing {
        applyRotation()
    }
}
```

That is acceptable for **document commit**, but not for **visual
preview**.

Do not solve this by committing project/document mutations continuously
while the slider moves.

------------------------------------------------------------------------

# 8. Rotation Slider Must Use Transient Preview

Required lifecycle:

``` text
slider begins editing
→ capture committed rotation
→ begin transient rotation interaction

slider value changes
→ update transient rotation preview
→ Stage redraws selected item immediately
→ no document commit yet

slider ends editing
→ commit one final rotation operation
→ clear transient rotation state
```

One slider drag = one Undo.

## 8.1 No commit storm

Do not issue:

``` text
dozens/hundreds of StageLayout commands per second
```

while dragging the slider.

The project/document remains committed once at gesture completion.

## 8.2 Live synchronization

While dragging the slider:

-   object rotates live,
-   selection frame rotates live,
-   resize handles follow live rotation,
-   direct rotation handle follows live rotation if present,
-   numeric/slider value remains synchronized.

There must be no jump at mouse-up.

------------------------------------------------------------------------

# 9. Unify Canvas and Toolbar Rotation State

The Stage canvas already has transient transform concepts, while the
toolbar has separate local state for rotation controls.

C4.3 should stop treating these as unrelated systems.

Introduce or consolidate a small interaction-state owner such as:

``` swift
StageEditInteractionState
```

Exact naming is flexible.

Conceptually:

``` swift
StageEditInteractionState
├── activeTransform
├── movePreview
├── resizePreview
├── rotationPreview
└── aimPreview
```

This is **temporary UI interaction state**, not project/document state.

## 9.1 Single rotation preview

Both:

``` text
canvas rotation handle
```

and:

``` text
toolbar Rotation slider
```

must write to the same conceptual transient rotation preview.

Do not maintain two independent preview rotations.

## 9.2 Ownership

The state should know:

-   which element is being transformed,
-   which transform type owns the interaction,
-   original committed geometry,
-   current transient geometry.

The Stage renderer consumes this state.

The finalizer commits it once.

## 9.3 Scope

Do not turn this into a giant global application state refactor.

Keep it narrowly scoped to Edit Stage interaction.

------------------------------------------------------------------------

# 10. Transform Rendering Contract

After C4.3, all direct Stage transforms should follow the same pattern:

``` text
BEGIN
capture committed state
claim transform ownership
remove active element from committed render path

UPDATE
modify transient preview only
render active element exactly once from preview

END
commit one document operation
clear preview
release ownership
normal committed rendering resumes
```

Apply this contract consistently to:

-   move,
-   resize,
-   rotate,
-   aim.

This should become the canonical Stage Edit interaction model.

------------------------------------------------------------------------

# 11. Stress Test the Ghosting Fix

Do not validate this with a gentle 20-pixel drag.

Use intentionally abusive testing.

## Move stress test

1.  Place a performer silhouette.
2.  Select it.
3.  Drag it rapidly in circles around the Stage for at least 10 seconds.
4.  Reverse direction repeatedly.
5.  Cross other objects.
6.  Drag at 100%, 150%, and 200% Stage zoom.

Required:

-   no trails,
-   no stale copies,
-   no flashes at original position,
-   no flicker between committed/transient representations,
-   no release jump.

## Resize stress test

Rapidly resize from all four corners.

Required:

-   one visible object,
-   one visible selection frame,
-   no stale geometry.

## Rotate stress test

Use direct rotation handle, if present, and spin continuously.

Required:

-   one visible object,
-   no ghost rotations,
-   no delayed redraw.

## Aim stress test

Whip a PAR aim handle around rapidly.

Required:

-   beam follows continuously,
-   stale beam wedges are not left behind,
-   no persistent old aim handle.

------------------------------------------------------------------------

# 12. Defect C --- Duplicate macOS `View` Menus

## 12.1 Observed behavior

Aurora currently displays two top-level menu-bar items named:

``` text
View
View
```

This is a native macOS menu-structure defect.

## 12.2 Likely cause

The application currently creates:

``` swift
CommandMenu("View") {
    ...
}
```

while macOS/SwiftUI already supplies the standard View menu.

`CommandMenu("View")` creates another top-level menu instead of merging
into the system View menu.

Do not simply rename the duplicate to "View 2" or another arbitrary
title.

------------------------------------------------------------------------

# 13. Correct macOS Menu Architecture

Use native `CommandGroup` placement to add genuine View commands to the
standard View menu where appropriate.

Commands that conceptually belong in View include things such as:

-   Show/Hide Stage Preview,
-   Show/Hide lower shelf,
-   Show/Hide Inspector,
-   Show/Hide browser/sidebar,
-   other visibility/presentation commands.

Use an appropriate `CommandGroupPlacement` supported by the current
SwiftUI macOS target.

## 13.1 Add a `Workspace` menu

Commands that switch major Aurora work surfaces are not really
visibility commands.

Create a distinct top-level:

``` text
Workspace
```

menu for commands such as:

-   Build Mode,
-   Perform Mode,
-   Design,
-   Patch,
-   Stage,
-   Profiles.

Recommended high-level menu structure:

``` text
Aurora
File
Edit
View
Workspace
Playback
MIDI
Remote
Window
Help
```

Adjust ordering only where macOS framework constraints require it.

## 13.2 Future compatibility

This structure should leave room for C5:

### View

-   show/hide panels,
-   Stage Preview,
-   lower shelf,
-   Inspector,
-   browser.

### Window

-   window management,
-   bring windows forward,
-   future detached panel windows.

### Workspace

-   Build/Perform,
-   Design/Patch/Stage/Profiles,
-   future workspace presets if appropriate.

Do not implement C5 undocking in C4.3.

------------------------------------------------------------------------

# 14. Keyboard Shortcuts

Preserve existing useful keyboard shortcuts while moving menu commands.

Do not accidentally create duplicate shortcut ownership.

Verify:

-   each shortcut invokes exactly one command,
-   menu items display expected shortcuts,
-   disabled-state logic remains correct.

If two existing commands already collide, document and resolve the
collision.

------------------------------------------------------------------------

# 15. Rotation Slider Hit Testing

Previous passes also encountered a Rotation slider that could not
receive pointer input.

Even if that specific issue appears fixed in this repository, explicitly
regression-test it while implementing live preview.

The Rotation slider must:

-   accept track clicks,
-   accept thumb drags,
-   remain active during live preview,
-   not pan the Stage,
-   not move the selected object,
-   not trigger marquee,
-   not trigger beam aim.

Toolbar controls must have pointer precedence over Stage canvas
gestures.

------------------------------------------------------------------------

# 16. Beam Rendering During Aim

The current wedge/cone renderer is substantially better than the
original capsule renderer and should remain.

C4.3 may make small rendering changes needed to support the transient
layer, but do not redesign beam appearance from scratch.

During fixture aim:

-   current/active beam should render once,
-   beam geometry follows transient aim,
-   committed beam at the old aim must not remain visible underneath,
-   aim handle follows the transient beam.

This uses the same single-render principle as Stage objects.

------------------------------------------------------------------------

# 17. Selection and Inspector Synchronization

While a transform preview is active, precision UI should reflect the
transient value where appropriate.

Examples:

### Move

Inspector X/Y may display transient coordinates.

### Resize

Inspector width/height may display transient dimensions.

### Rotate

Rotation slider/numeric value displays transient angle.

### Aim

Direction/Length controls display transient aim values.

Do not commit document changes merely to make these controls update.

When the transform ends:

``` text
transient value == newly committed value
```

so there should be no visible snap.

------------------------------------------------------------------------

# 18. Undo / Redo Contract

C4.3 must preserve clean Undo semantics.

One interaction = one Undo:

-   one move drag,
-   one resize drag,
-   one rotation-handle drag,
-   one Rotation-slider drag,
-   one aim drag.

The transient preview itself does not create Undo entries.

If an interaction is cancelled, it creates no Undo entry.

After Undo/Redo:

-   Stage geometry,
-   toolbar values,
-   Inspector values,
-   selection chrome

must all synchronize correctly.

------------------------------------------------------------------------

# 19. Automated Tests

Add tests around state transitions and finalization where practical.

## 19.1 Interaction state

Test conceptual transitions:

``` text
none
→ move
→ none
```

``` text
none
→ resize
→ none
```

``` text
none
→ rotate
→ none
```

``` text
none
→ aim
→ none
```

Verify a second incompatible transform cannot claim ownership while
another is active.

## 19.2 Single-render eligibility

Extract a small pure helper if useful:

``` text
shouldRenderInCommittedLayer(elementID, interactionState)
```

Expected:

``` text
inactive element → true
active transformed element → false
```

And:

``` text
shouldRenderInTransientLayer(...)
```

must be the inverse for the active target.

This is valuable because the central ghosting guarantee can then be
unit-tested.

## 19.3 Rotation preview

Test:

``` text
committed = 10°
begin slider
preview = 45°
document still = 10°
rendered rotation = 45°
end slider
document = 45°
preview cleared
```

## 19.4 Cancellation

Test:

``` text
committed = 10°
preview = 90°
cancel
document = 10°
preview cleared
```

## 19.5 Menu command structure

Where practical, add lightweight tests around command routing/state
rather than UI menu titles.

At minimum, production acceptance must verify only one top-level View
menu appears.

------------------------------------------------------------------------

# 20. Production Manual Acceptance Checklist

## Ghosting

-   [ ] Place performer.
-   [ ] Drag rapidly in circles for 10 seconds.
-   [ ] No ghost trails.
-   [ ] No stale original copy.
-   [ ] No release jump.
-   [ ] Repeat at 150% zoom.
-   [ ] Repeat at 200% zoom.
-   [ ] Repeat with truss.
-   [ ] Repeat with imported image if supported.

## Resize

-   [ ] Rapidly resize all four corners.
-   [ ] Exactly one object remains visible.
-   [ ] Selection frame follows transient geometry.
-   [ ] No stale boxes.

## Rotation handle

-   [ ] Rotate continuously.
-   [ ] Exactly one object remains visible.
-   [ ] No stale rotated copies.

## Rotation slider

-   [ ] Start at 0°.
-   [ ] Slowly drag to 45°.
-   [ ] Object visibly rotates during slider movement.
-   [ ] Continue to 90°.
-   [ ] Continue to -90°.
-   [ ] Continue to 180°.
-   [ ] No mouse-up-only update.
-   [ ] Release.
-   [ ] Undo once.
-   [ ] Object returns to pre-slider rotation.
-   [ ] Slider value also returns.

## Aim

-   [ ] Select static PAR.
-   [ ] Rapidly move aim handle.
-   [ ] Beam tracks live.
-   [ ] No stale beam wedges.
-   [ ] No old handle remains.
-   [ ] Undo once restores original aim.

## Menu bar

-   [ ] Launch production Aurora.
-   [ ] Confirm exactly one top-level `View` menu.
-   [ ] Confirm `Workspace` menu exists.
-   [ ] Confirm Stage Preview visibility commands are in View.
-   [ ] Confirm Build/Perform and Design/Patch/Stage/Profiles commands
    are in Workspace.
-   [ ] Confirm shortcuts still work.
-   [ ] Confirm standard macOS Window menu remains intact.

------------------------------------------------------------------------

# 21. Production Evidence Required

Provide evidence from the actual running Aurora application.

## Screenshots

Capture:

1.  final menu bar showing one `View` and one `Workspace`,
2.  Rotation slider mid-edit with object visibly rotated,
3.  Stage object mid-transform in the corrected transient rendering
    path,
4.  PAR mid-aim with only one beam representation.

## Screen recording

A short production recording is strongly requested because the primary
bug is temporal/compositing behavior.

Record:

``` text
rapid performer drag
→ resize
→ rotate with direct handle
→ rotate with slider
→ aim PAR
→ open View menu
→ open Workspace menu
```

The recording must show no ghost trails.

------------------------------------------------------------------------

# 22. Diagnostics During Development

If ghosting persists after the transient-layer implementation,
temporarily add diagnostic overlays/logging showing:

``` text
active transform
active target ID
committed-layer render eligibility
transient-layer render eligibility
current transient geometry
```

At no point should logs indicate:

``` text
same target rendered in committed layer = true
and
same target rendered in transient layer = true
```

during an active transform.

Remove noisy diagnostics before final checkpoint unless they are useful
behind a debug flag.

------------------------------------------------------------------------

# 23. Non-Goals

Do not begin:

-   C5 undockable panels,
-   multi-monitor persistence,
-   workspace preset implementation,
-   C6 splash-screen remediation,
-   3D Stage visualization,
-   photometric simulation,
-   major beam renderer redesign,
-   wholesale AppKit rewrite,
-   general application-state refactor.

C4.3 is a targeted Stage rendering/interaction stabilization pass plus
menu cleanup.

------------------------------------------------------------------------

# 24. Recommended Implementation Order

## Step 1 --- Reproduce and instrument ghosting

Confirm the supplied behavior in the production app and identify the
active target's render paths.

## Step 2 --- Implement single-render transient layer

Hide/omit active target from committed Stage rendering and render it
once in the transient world-space layer.

## Step 3 --- Move transform chrome into transient geometry

Selection frame and handles follow the active preview.

## Step 4 --- Apply transform-layer no-animation policy

Remove implicit animation from Stage Edit transient transforms.

## Step 5 --- Centralize transient Stage edit interaction state

Unify move/resize/rotation/aim preview state enough for canvas and
toolbar to consume the same source.

## Step 6 --- Add live Rotation slider preview

Use transient rotation while editing, commit once on release.

## Step 7 --- Verify direct rotation uses same preview state

No duplicate rotation model.

## Step 8 --- Apply single-render rule to fixture aim/beam if necessary

No stale old beam during direct aim.

## Step 9 --- Repair menu structure

Remove duplicate `CommandMenu("View")`, merge real View commands into
native View, and create Workspace menu for major mode/work-surface
navigation.

## Step 10 --- Automated tests

Complete state/finalizer/render-eligibility tests.

## Step 11 --- Production stress test

Use the aggressive manual sequence in this document.

## Step 12 --- Capture evidence and STOP

Do not proceed into C5.

------------------------------------------------------------------------

# 25. Completion Criteria

C4.3 is complete only when:

-   rapid Stage-object dragging produces no ghosting/trailing copies,
-   an actively transformed element is rendered exactly once,
-   committed and transient representations never appear simultaneously,
-   transient movement has no implicit interpolation lag,
-   resize remains live and artifact-free,
-   direct rotation remains live and artifact-free,
-   Rotation slider updates Stage geometry visually while being dragged,
-   Rotation slider commits only once on release,
-   slider rotation and direct rotation use the same conceptual
    transient preview,
-   fixture aim remains live and does not leave stale beams,
-   one interaction still equals one Undo,
-   exactly one top-level View menu exists,
-   a coherent Workspace menu owns major Aurora workspace navigation,
-   standard macOS menu behavior remains intact,
-   automated tests pass,
-   native Xcode build succeeds,
-   production stress testing passes,
-   production recording shows no ghost trails.

------------------------------------------------------------------------

# 26. STOP CONDITION

After C4.3:

> **STOP and produce a C4.3 checkpoint for human review. Do not begin
> C5.**

The checkpoint report must include:

-   root cause of the drag ghosting,
-   exact transient-rendering solution implemented,
-   explanation of how duplicate rendering is prevented,
-   rotation-slider live-preview implementation,
-   transient interaction-state changes,
-   duplicate View-menu root cause and menu restructuring,
-   automated test results,
-   production manual acceptance results,
-   production screenshots,
-   production screen recording.

C5 begins only after C4.3 receives human approval.

------------------------------------------------------------------------

# 27. Product Standard

During Stage editing, Aurora must feel physically coherent.

When an object is grabbed, there is one object under the pointer, not a
trail of previous selves.

When Rotation moves, the Stage rotates with it immediately.

When a beam is aimed, the beam follows the hand.

And when the user opens the macOS menu bar, there is one View menu,
because even Aurora does not need two different opinions about what
"View" means.
