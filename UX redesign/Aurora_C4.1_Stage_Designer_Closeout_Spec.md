# Aurora C4.1 Stage Designer Closeout

## Responsive Object Palette, Professional Object Transforms, Asset Bounds Normalization, and Directional Beam Visualization

**Project:** Aurora Lighting Control\
**Target:** Current C4 repository\
**Phase:** C4.1 corrective closeout\
**Prerequisite:** Existing C4 implementation\
**Purpose:** Correct the usability and visualization defects found
during hands-on C4 review before C4 is approved and before C5
multi-monitor work begins.

------------------------------------------------------------------------

# 1. Executive Summary

C4 successfully introduced major Stage Designer capabilities:

-   Stage Objects palette,
-   stock Aurora silhouettes,
-   shapes and truss objects,
-   imported image support,
-   movable Stage objects,
-   transient object dragging,
-   object resize infrastructure,
-   locking,
-   z-order,
-   live Stage visualization.

Hands-on review exposed four issues that must be corrected before C4 can
be considered complete:

1.  **The Stage Objects palette is clipped by the Stage Edit sidebar.**
2.  **Object resizing is technically present but is not discoverable or
    practically usable.**
3.  **Some stock assets, especially angled/curved truss, have selection
    bounds dramatically larger than the visible artwork.**
4.  **Fixture beam rendering is visually incorrect and only meaningfully
    supports fixtures with live Pan data. Static PARs, floods, washes,
    bars, and similar fixtures also need physical Stage aim and beam
    visualization.**

These are C4 closeout issues. Do not begin C5 until they are
implemented, tested, and reviewed.

The guiding product principles are:

> **A Stage object should occupy, select, and transform according to the
> thing the user can actually see.**

and:

> **A Stage beam represents the physical direction and spread of light,
> not merely whether a fixture happens to expose DMX Pan/Tilt
> channels.**

------------------------------------------------------------------------

# 2. Current Repository Findings

The following findings are based on the current C4 implementation and
should be treated as implementation guidance rather than hypothetical
suggestions.

## 2.1 Palette clipping

`Sources/AuroraUI/Stage/StageObjectPaletteView.swift` currently ends its
root view with:

``` swift
.frame(width: 220)
```

The palette is hosted in a Stage Edit rail whose available width can be
smaller than this fixed width. The category picker contains six
sections:

-   Performers
-   Audience
-   Equipment
-   Truss
-   Special
-   Shapes

The fixed width plus a six-item segmented picker causes the palette to
clip horizontally in the production workspace.

## 2.2 Resize implementation exists

`StageCanvasView` already provides a selected-object resize handle and
uses `StageLayoutResizeFinalizer` for live and committed sizing.

The current handle is approximately:

``` swift
let handle: CGFloat = 8
```

and only exposes a southeast corner handle.

The infrastructure is therefore present, but the transform UI is too
subtle and limited for a production Stage Designer.

## 2.3 Selection bounds use object width/height

`layoutObjectView(_:)` renders the object using its declared object
dimensions and positions the resize handle at the rectangular bounds.
For stock artwork whose visible silhouette occupies only a small part of
the source asset canvas, the selection rectangle therefore surrounds
large amounts of transparent/empty area.

This is visible with angled truss artwork.

## 2.4 Beam renderer is currently a blurred Capsule

`StageCanvasView.fixtureView(_:)` currently renders a beam only when
live Pan exists:

``` swift
if beamDetail > 0, let panV = state?.pan {
    ...
    Capsule()
        .fill(...)
        .frame(...)
        .rotationEffect(angle)
        .blur(...)
}
```

This produces a narrow glowing rod rather than a theatrical beam/wash
and prevents useful direction visualization for static fixtures without
Pan.

C4.1 must replace this model.

------------------------------------------------------------------------

# 3. Requirement A --- Make the Stage Objects Palette Responsive

## 3.1 Remove fixed palette width

Remove the hard-coded:

``` swift
.frame(width: 220)
```

from the root of `StageObjectPaletteView`.

The palette should consume the width offered by its parent Stage Edit
rail:

``` text
parent decides rail width
palette adapts to available width
```

Do not make the child palette wider than its container.

## 3.2 Category navigation must adapt

The current six-item segmented picker is not robust at narrow widths.

Implement a responsive category selector.

Preferred options, in order:

### Option A --- horizontally scrollable compact category strip

A compact row of category buttons/tabs inside a horizontal `ScrollView`.

Advantages:

-   all categories remain directly visible/discoverable,
-   works at narrow widths,
-   visually appropriate for Aurora,
-   avoids microscopic segmented labels.

### Option B --- adaptive compact menu/picker

At widths below a defined threshold, replace the full category strip
with a compact category menu.

Example:

``` text
Objects
[ Truss ▾ ]
```

At wider widths, the normal tab/segmented presentation may be used.

Either approach is acceptable if it is polished and does not clip.

## 3.3 Asset grid

Keep the stock grid adaptive.

The existing concept:

``` swift
GridItem(.adaptive(minimum: 68))
```

is reasonable, but validate it at the actual sidebar widths Aurora
permits.

Requirements:

-   no horizontal clipping,
-   no partially visible thumbnails,
-   useful minimum thumbnail size,
-   labels remain readable where shown,
-   vertical scrolling remains available,
-   Import Image remains reachable.

## 3.4 Narrow-window acceptance

Test at:

-   normal application width,
-   minimum supported main-window width,
-   Stage Edit rail at its minimum width,
-   Retina scaling,
-   category with long labels such as `Performers` and `Equipment`.

No Stage Object category or placement control may be clipped off-screen.

------------------------------------------------------------------------

# 4. Requirement B --- Professional Object Resize and Transform Affordances

## 4.1 Problem

C4 technically supports resize, but users cannot reasonably discover or
operate it.

An 8×8 southeast-only handle is insufficient for a Stage layout editor.

## 4.2 Selection frame

When one unlocked resizable Stage object is selected in Edit Stage, show
a restrained transform frame closely matching the object's normalized
bounds.

The frame should:

-   clearly indicate selection,
-   remain visually lightweight,
-   not obscure the artwork,
-   scale sensibly with zoom,
-   remain operable at common Stage zoom levels.

## 4.3 Corner handles

Provide four corner resize handles for normal two-dimensional objects:

-   northwest,
-   northeast,
-   southwest,
-   southeast.

Recommended visual size:

``` text
6–8 pt visible marker
10–14 pt minimum interactive hit target
```

The hit target may be larger than the visible circle/square.

Do not make giant toy-like handles.

## 4.4 Cursor feedback

When hovering a resize handle, use an appropriate diagonal resize cursor
where AppKit integration permits.

The cursor should correspond to the active corner orientation.

## 4.5 Live resizing

Resizing must follow the pointer continuously using transient state.

Required lifecycle:

``` text
mouse-down on handle
→ capture original geometry
→ update transient size live
→ mouse-up
→ one committed StageLayout command
```

No teleport-on-release behavior.

One physical resize gesture must be one Undo operation.

## 4.6 Aspect-ratio behavior

### Stock silhouettes and stock image assets

Default behavior should preserve the asset's intrinsic aspect ratio.

This prevents a drummer from becoming six feet wide and eighteen inches
tall because of an accidental diagonal drag.

### Imported images

Default to preserving aspect ratio.

### Shapes

Rectangles, rounded rectangles, ellipses, stage areas, etc. may resize
freely.

### Truss

Truss should preserve its meaningful visual proportions unless a
specific truss type is intentionally stretchable along one axis.

For straight truss, length adjustment is useful. Do not distort tube
diameter/cross-section merely to fill arbitrary rectangular bounds.

### Modifier

If appropriate to Aurora's existing interaction conventions:

``` text
Shift = constrain/preserve aspect ratio
```

or the inverse for image objects if aspect preservation is default.

Pick one consistent macOS-like rule and document it.

## 4.7 Lines and straight truss

For line-like objects, corner-box resizing is not ideal.

Prefer endpoint/axis handles when practical:

``` text
●────────────●
```

Dragging an endpoint changes length and angle.

If implementing endpoint manipulation would significantly expand C4.1,
retain rectangular transform handles for this closeout but ensure the
object can at least be resized accurately. Record endpoint handles as a
future refinement.

## 4.8 Rotation

C4 already carries rotation in the object model. Ensure the existing
rotation editing remains compatible with normalized bounds and resizing.

Do not let a rotated object's selection box explode into a huge
axis-aligned rectangle.

The transform frame should rotate with the object where practical.

------------------------------------------------------------------------

# 5. Requirement C --- Normalize Stock Asset Visual Bounds

## 5.1 Problem

The current object dimensions can represent a much larger rectangle than
the visible pixels/path inside a stock asset.

Result:

``` text
tiny angled truss
inside
massive purple selection rectangle
```

This damages:

-   selection,
-   resizing,
-   placement,
-   alignment,
-   perceived object size,
-   future hit testing.

## 5.2 Stock asset metadata

Extend the stock asset catalog with enough metadata to describe
intrinsic visual geometry.

Recommended conceptual fields:

``` text
assetKey
intrinsicAspectRatio
defaultStageWidth
defaultStageHeight
visualBounds
anchorPoint
```

Exact types/names may follow the existing catalog architecture.

### `visualBounds`

Represents the useful non-transparent content bounds within the source
asset coordinate space.

Example normalized coordinates:

``` text
x: 0.08
y: 0.12
width: 0.84
height: 0.72
```

Do not require every asset to specify this manually if it can be
reliably generated during asset preparation.

## 5.3 Preferred asset cleanup

Where the source SVG/PNG contains unnecessary transparent whitespace,
crop/normalize the actual source asset.

This is preferable to carrying pathological padding forever.

However, catalog metadata may still be useful for:

-   consistent default sizing,
-   anchors,
-   unusual artwork,
-   future asset revisions.

## 5.4 Stable asset keys

Do not change stable catalog keys merely because artwork or bounds are
corrected.

Existing projects should continue to resolve the same asset key.

## 5.5 Selection/hit-testing

The selection frame and transform handles should correspond to the
normalized object footprint.

Avoid requiring pixel-perfect alpha hit testing for C4.1.

A tight normalized rectangle is sufficient.

## 5.6 Truss acceptance

Specifically test:

-   Straight Short
-   Straight Long
-   Curved Left
-   Curved Right
-   Circle

Place each object, select it, rotate it where supported, and confirm the
transform frame is visually close to the actual truss.

The selected border must not contain huge empty margins.

------------------------------------------------------------------------

# 6. Requirement D --- Replace the "Lightsaber" Beam Renderer

## 6.1 Product intent

The 2D Stage Preview is meant to communicate where light is going.

The current blurred Capsule reads as a glowing rod. Replace it with a
theatrical Stage-light visualization.

The visual reference is the supplied LightKey screenshot: broad
directional wedges/cones that communicate source, direction, spread,
color, and approximate reach.

Do not copy LightKey artwork or code. Reproduce the useful visualization
concept in Aurora's own renderer.

------------------------------------------------------------------------

# 7. Separate Physical Stage Aim from DMX Pan/Tilt

This is the most important architectural requirement in the beam fix.

A fixture can have a physical aim even if it has no Pan/Tilt DMX
channels.

Examples:

-   PAR pointed toward center stage,
-   flood pointed toward drummer,
-   LED bar angled toward audience,
-   static profile aimed at vocalist,
-   audience wash aimed outward.

Therefore:

> **Stage fixture orientation/aim is Stage geometry. DMX Pan/Tilt is
> live fixture state. They are not the same thing.**

## 7.1 Extend StageFixturePlacement

Add Stage visualization properties to fixture placement.

Conceptually:

``` swift
public var aimDirection: Double
public var beamSpread: Double
public var beamLength: Double
public var beamVisible: Bool
```

Names/types may follow current model conventions.

Potential optional future field:

``` swift
public var beamSoftness: Double
```

Do not overload the existing object `rotation` property without
carefully defining semantics.

Recommended distinction:

``` text
fixture glyph rotation = physical fixture/body orientation on plot
beam aim direction = direction light travels on the 2D plot
```

If Aurora can cleanly define one orientation field as both, that is
acceptable, but static fixture aiming must remain editable independently
of DMX Pan/Tilt.

## 7.2 Codable migration

Existing projects must decode safely.

Provide defaults based on fixture category/personality where possible.

Fallback defaults must be deterministic.

------------------------------------------------------------------------

# 8. Fixture-Type Beam Defaults

Provide useful defaults so a newly placed fixture immediately has a
sensible visualization.

Conceptual defaults:

  Fixture family   Spread
  ---------------- ----------------
  Beam fixture     very narrow
  Spot/profile     narrow
  PAR              medium
  Wash             broad
  Flood            very broad
  LED bar          broad/fan-like
  Moving wash      broad
  Moving spot      narrow-medium

Do not require perfect photometric modeling.

This is a 2D show visualization, not an optical simulator.

The defaults should simply make different fixture classes visually
believable.

------------------------------------------------------------------------

# 9. Beam Geometry

## 9.1 Use a tapered path

Replace `Capsule` with a custom `Shape`/`Path`.

Basic cone geometry:

``` text
             far edge
        ┌──────────────┐
         \            /
          \          /
           \        /
            \      /
             \    /
              \  /
               \/
             fixture
```

In Aurora's top-down/diagram view, render this as a tapered wedge whose
width increases with distance.

For very narrow beam fixtures, the far width remains small.

For floods, the wedge becomes broad.

## 9.2 Beam origin

The beam should originate at or immediately adjacent to the fixture
glyph, not from the center of a large invisible frame.

## 9.3 Beam length

`beamLength` should represent Stage visualization reach.

Intensity may influence visual opacity/brightness, but should not
radically change the geometric length unless Aurora intentionally
chooses that visualization.

Prefer:

``` text
geometry = placement visualization settings
brightness/opacity = live intensity
color = live color
```

This gives the Stage plot stable spatial meaning.

## 9.4 Edge softness

Use layered paths or gradients to create feathered theatrical edges.

Recommended approach:

1.  broad low-opacity outer wedge,
2.  narrower higher-opacity inner wedge,
3.  optional subtle blur.

Avoid expensive multi-pass effects if they harm Stage performance.

The result should look like light in haze, not a neon sign.

## 9.5 Distance falloff

Opacity should decrease toward the far end.

A gradient along the beam direction is preferred.

Conceptually:

``` text
source: stronger
middle: visible
far end: fades gently
```

Do not end with a hard rounded capsule cap.

## 9.6 Color

Use the fixture's resolved live output color.

For fixtures without RGB color mixing, use an appropriate
resolved/default visualization color.

Beam color should continue updating live with Programmer/playback state.

## 9.7 Intensity

Intensity should primarily influence:

-   opacity,
-   central brightness,
-   optional glow.

At 0%, the live beam should disappear or become effectively invisible.

At low values, it should remain subtle.

Do not turn 100% intensity into an opaque slab.

------------------------------------------------------------------------

# 10. Static Fixture Beam Aim

## 10.1 Required behavior

In Edit Stage, selecting a fixture must allow the user to define
physical beam direction even when the fixture has no Pan/Tilt
capability.

This includes:

-   PARs,
-   floods,
-   static washes,
-   static profiles,
-   bars where a directional visualization makes sense.

## 10.2 Stage Inspector controls

When a Stage fixture is selected in Edit Stage, expose a compact
visualization/placement section.

Recommended controls:

``` text
STAGE AIM
Direction:  [ angle control / numeric degrees ]
Spread:     [ slider / numeric ]
Length:     [ slider / numeric ]
Beam:       [ Show ✓ ]
```

Use Aurora's existing Inspector/Programmer visual language.

Do not place these controls in the normal live Programmer as though they
were DMX channels.

They are Stage layout properties.

## 10.3 Direct manipulation

Strongly preferred:

When a fixture is selected in Edit Stage, show a small beam-aim handle
at or near the beam endpoint/direction.

Dragging this handle changes `aimDirection`.

This makes static fixture aiming spatial and intuitive.

If this direct handle is too large a scope for C4.1, Inspector controls
are the minimum requirement, but architect the model so a direct aim
handle can be added later.

------------------------------------------------------------------------

# 11. Moving Fixture Beam Direction

Moving fixtures have both physical placement and live Pan/Tilt.

Required rendering model:

``` text
physical Stage mounting/base orientation
+
resolved live Pan/Tilt visualization
=
current rendered beam direction
```

The exact mapping from normalized Pan/Tilt to a 2D Stage angle may
remain approximate because the Stage view is not a full 3D photometric
renderer.

However:

-   live Pan must visibly steer the beam,
-   live Tilt may influence beam reach/spread/visibility where useful,
-   movement must be smooth,
-   physical mounting orientation must not be ignored.

Do not require Pan/Tilt in order for the fixture to have a beam.

------------------------------------------------------------------------

# 12. PAR / Flood Acceptance Scenario

This scenario is mandatory.

1.  Place a static PAR.
2.  Enter Edit Stage.
3.  Aim it toward a performer silhouette.
4.  Set a medium/broad spread.
5.  Exit Edit Stage.
6.  Raise its intensity and choose a color in the Programmer.
7.  Confirm the Stage shows a colored directional cone toward the
    performer.
8.  Confirm this works despite the fixture having no Pan/Tilt DMX
    capability.
9.  Re-enter Edit Stage and change physical aim.
10. Confirm the beam direction changes accordingly.

Repeat with a broad flood/wash and confirm the visualization is wider.

------------------------------------------------------------------------

# 13. Moving Head Acceptance Scenario

1.  Place a moving head.
2.  Give it a physical Stage orientation.
3.  Exit Edit Stage.
4.  Raise intensity.
5.  Manipulate Pan in the Programmer.
6.  Confirm beam direction changes live.
7.  Manipulate Tilt.
8.  Confirm the Stage visualization responds meaningfully.
9.  Change color.
10. Confirm beam color changes live.
11. Set intensity to zero.
12. Confirm beam disappears.

The result should visually read as a Stage light, not a glowing stick.

------------------------------------------------------------------------

# 14. LED Bars / Non-Circular Sources

Do not block C4.1 on a perfect rectangular photometric renderer, but
avoid designing the beam API so that every fixture must forever be a
circular cone.

The model should permit future visualization styles such as:

``` text
cone
wide wash
fan
rectangular wash
```

For C4.1, a broad wedge for bars is acceptable if it communicates
direction and spread correctly.

------------------------------------------------------------------------

# 15. Beam Rendering Performance

Stage Preview may contain many fixtures.

Avoid per-frame architectures that perform excessive:

-   image generation,
-   project mutations,
-   expensive blur stacks,
-   unbounded shadow effects,
-   layout recomputation.

Beam rendering should remain a pure visualization of:

``` text
Stage placement
+
resolved fixture state
+
camera transform
```

No document command should be generated by live DMX/Programmer beam
updates.

------------------------------------------------------------------------

# 16. Interaction with Performer Silhouettes and Scenic Objects

Validate beams in a Stage containing:

-   vocalist,
-   guitarist,
-   drummer,
-   keyboardist,
-   truss,
-   stage area.

The silhouettes should provide spatial context.

Do not automatically clip beams around silhouettes. Aurora is not doing
occlusion simulation in this phase.

Layering should make both the beam and performer context readable.

A sensible approach is:

``` text
background/stage objects
→ beam visualization
→ fixtures / important foreground glyphs
→ selection overlays
```

Adjust if the existing z-order architecture requires a different but
visually effective composition.

------------------------------------------------------------------------

# 17. Stage Object Inspector

C4 introduced richer Stage objects. Use the Inspector to make
selected-object editing discoverable.

For a selected scenic/layout object, expose relevant properties such as:

``` text
Name
Position X/Y
Width
Height
Rotation
Opacity
Locked
Layer / Arrange
```

For stock images, show asset identity read-only where useful.

For imported images, show a useful media label/reference without
exposing fragile filesystem internals.

This is not a replacement for direct manipulation. It is precision
editing and discoverability.

------------------------------------------------------------------------

# 18. Undo / Redo Requirements

All Stage design edits introduced or changed by C4.1 must preserve clean
Undo semantics.

One operation should equal one logical Undo step:

-   move object,
-   resize object,
-   rotate object,
-   change z-order,
-   change fixture Stage aim,
-   change beam spread,
-   change beam visualization length.

For continuously adjusted Inspector sliders, use the project's existing
coalescing strategy if available so a single slider drag does not create
dozens of unusable Undo entries.

Live lighting output changes are not Stage geometry edits and should
follow existing Programmer semantics.

------------------------------------------------------------------------

# 19. Automated Tests

Add or strengthen tests for the following.

## Palette

-   no fixed 220 pt dependency in palette layout logic,
-   category state remains stable when layout changes.

Visual clipping itself may require production/manual validation.

## Resize

-   each supported corner produces correct geometry,
-   minimum size remains enforced,
-   locked objects cannot resize,
-   image/silhouette aspect ratio behavior,
-   one final resize layout result,
-   rotated object resize does not corrupt geometry.

## Asset bounds

-   stock catalog decodes bounds metadata,
-   legacy catalog entries without bounds receive safe defaults,
-   stable asset keys remain unchanged,
-   default size honors intrinsic aspect ratio.

## Static fixture aim

-   `StageFixturePlacement` round-trips new aim/spread/length fields,
-   legacy project decode supplies defaults,
-   aim exists independently of live Pan.

## Beam math

Extract beam geometry into testable pure math where practical.

Test:

``` text
origin
direction
length
spread
→ expected wedge points
```

Test narrow and broad spreads.

## Moving fixture direction

Test the mapping/composition of:

``` text
base Stage aim + live Pan
```

with deterministic expected angles.

## Zero intensity

Beam visualization should resolve to hidden/effectively zero opacity at
zero output.

------------------------------------------------------------------------

# 20. Manual Production Acceptance Checklist

## Object palette

-   [ ] Enter Edit Stage.
-   [ ] Open Objects.
-   [ ] Verify all categories are reachable.
-   [ ] Resize main window narrower.
-   [ ] Verify no category strip clipping.
-   [ ] Verify asset thumbnails remain usable.
-   [ ] Verify Import Image remains visible/reachable.

## Object resizing

-   [ ] Place vocalist.
-   [ ] Select it.
-   [ ] Clearly see resize handles.
-   [ ] Resize larger and smaller.
-   [ ] Confirm live feedback.
-   [ ] Confirm aspect ratio remains sensible.
-   [ ] Undo once.
-   [ ] Place a stage rectangle and freely resize width/height.
-   [ ] Place truss and resize it.
-   [ ] Confirm locked object cannot resize.

## Asset bounds

-   [ ] Place Straight Short truss.
-   [ ] Select it.
-   [ ] Confirm border closely matches artwork.
-   [ ] Repeat Straight Long.
-   [ ] Repeat Curved Left.
-   [ ] Repeat Curved Right.
-   [ ] Repeat Circle.
-   [ ] Rotate angled/curved object.
-   [ ] Confirm no enormous empty selection box.

## Static beam

-   [ ] Place static PAR.
-   [ ] Aim it toward performer.
-   [ ] Set spread and length.
-   [ ] Program intensity/color.
-   [ ] Confirm broad directional beam.
-   [ ] Confirm no Pan/Tilt capability is required.

## Flood/wash

-   [ ] Place flood/wash.
-   [ ] Aim it.
-   [ ] Confirm substantially broader visualization than spot/beam
    fixture.

## Mover

-   [ ] Place mover.
-   [ ] Raise intensity.
-   [ ] Change Pan.
-   [ ] Confirm beam steers live.
-   [ ] Change color.
-   [ ] Confirm beam color changes.
-   [ ] Set intensity to zero.
-   [ ] Confirm beam disappears.

## Visual quality

-   [ ] Compare Aurora beam presentation against the supplied LightKey
    reference concept.
-   [ ] Confirm Aurora beams read as wedges/cones of light in haze.
-   [ ] Confirm they do **not** read as capsules, glowing rods, or
    "lightsabers."
-   [ ] Confirm performers and scenic objects remain readable.

------------------------------------------------------------------------

# 21. Production Screenshot Evidence

Provide screenshots from the **actual running Aurora application**, not
a synthetic checkpoint host, showing:

1.  responsive Objects palette at normal width,
2.  responsive Objects palette at narrow width,
3.  selected/resizable performer silhouette,
4.  selected curved/angled truss with tight bounds,
5.  static PAR with broad directional beam,
6.  flood/wash with wider beam,
7.  moving head with narrow directional beam,
8.  a populated Stage with performers and multiple beam types.

If possible, also provide a short screen recording/GIF for internal
review showing:

``` text
resize object
→ aim static PAR
→ change live color/intensity
→ move Pan on mover
```

A recording is useful but not required if the development workflow does
not currently produce one easily.

------------------------------------------------------------------------

# 22. Explicit Non-Goals

Do not use C4.1 to begin:

-   C5 undockable windows,
-   workspace presets,
-   multi-monitor persistence,
-   C6 splash work,
-   full 3D visualization,
-   photometric simulation,
-   gobo projection simulation,
-   shadows/occlusion,
-   haze physics,
-   automated fixture focus calculations,
-   CAD-grade transform tooling.

C4.1 is a 2D Stage Designer closeout.

------------------------------------------------------------------------

# 23. Recommended Implementation Order

## Step 1 --- Responsive palette

Fix the clipping first. It is isolated and provides immediate production
usability.

## Step 2 --- Asset bounds normalization

Correct catalog/source artwork bounds before expanding transform
handles. Transform UI should operate on correct geometry.

## Step 3 --- Professional resize affordances

Add usable handles, hit targets, aspect-ratio rules, and cursor
behavior.

## Step 4 --- Stage fixture visualization model

Extend `StageFixturePlacement` with physical
aim/spread/length/visibility and migration defaults.

## Step 5 --- Pure beam geometry

Create a testable wedge/cone geometry helper/Shape.

## Step 6 --- Static fixture beam rendering

Make PARs/washes/floods render from Stage aim independent of DMX
Pan/Tilt.

## Step 7 --- Moving fixture composition

Compose physical Stage orientation with resolved live movement.

## Step 8 --- Inspector controls

Expose Stage aim/spread/length and relevant object geometry controls.

## Step 9 --- Automated tests

Complete model, geometry, resize, migration, and beam tests.

## Step 10 --- Production visual validation

Run the full manual checklist and capture actual Aurora screenshots.

------------------------------------------------------------------------

# 24. C4.1 Completion Criteria

C4.1 is complete only when:

-   Stage Objects palette never clips at supported workspace sizes.
-   Every object category is reachable.
-   Selected resizable objects have obvious, professional transform
    handles.
-   Object resize is live.
-   One resize is one Undo.
-   Stock silhouettes preserve sensible proportions.
-   Truss selection bounds closely match visible artwork.
-   Static fixtures have editable physical Stage aim.
-   Static fixtures can render beams without Pan/Tilt DMX capability.
-   Beam spread can represent narrow spots, PARs, washes, and floods.
-   Moving heads steer their beams from live resolved position.
-   Beam color and intensity respond to live output.
-   Beam geometry is a tapered/fanned light shape, not a Capsule.
-   Beams fade/feather convincingly enough for a professional 2D Stage
    preview.
-   Existing C1-C4 Stage selection and document architecture remains
    intact.
-   Legacy projects migrate safely.
-   Native Xcode build succeeds.
-   Relevant automated tests pass.
-   Manual production-app acceptance passes.

------------------------------------------------------------------------

# 25. STOP CONDITION

After completing C4.1:

> **STOP and produce a C4.1 checkpoint for human review. Do not begin
> C5.**

The checkpoint should include:

-   implementation summary,
-   model/schema changes,
-   migration notes,
-   test results,
-   manual acceptance results,
-   actual production screenshots.

C5 multi-monitor/undockable workspace work begins only after C4/C4.1
receives human approval.

------------------------------------------------------------------------

# 26. Product Standard

The Stage Designer should communicate a lighting design at a glance.

A truss should select like the truss the user sees, not an invisible
rectangle around it.

A performer should resize like an illustration, not a spreadsheet cell.

A PAR should visibly point somewhere even though it has no motor.

A mover should sweep its beam as the live show moves.

And a beam should look like **light traveling through a stage**, not a
glowing plastic tube.
