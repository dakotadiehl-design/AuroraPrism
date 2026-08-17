# Aurora Programmer Color Engine 1.1 Closeout

## Saturation Geometry, White-Balance Marker Accuracy, Draft-State Reset, Mixed Preview, Palette Round-Trip, Emitter Importing, Global Master Safety, and Virtual Dimmer

**Project:** Aurora Lighting Control\
**Target:** `Aurora_ColorEngine.zip` first Color Engine pass\
**Phase:** Programmer Color Engine 1.1 corrective closeout\
**Status:** Required before Color Engine acceptance\
**STOP:** After implementation, tests, and production screenshots. Do
**not** begin Advanced MIDI Engine automatically.

------------------------------------------------------------------------

# 1. Executive Summary

The first Programmer Color Engine pass has the correct overall
architecture and should be preserved.

The following design decisions are correct and must remain:

-   `colorHue`, `colorSat`, `colorVal`, and `colorWB` are first-class
    Programmer authoring state.
-   `colorR`, `colorG`, and `colorB` remain resolved physical RGB output
    attributes.
-   White, Amber, and UV remain independent physical emitter attributes.
-   The Color Programmer uses the LightKey-inspired layout:
    -   master Dimmer on the left,
    -   hero RGB wheel in the center,
    -   center color preview,
    -   split White Balance / RGB Brightness inner ring,
    -   dedicated emitter faders on the right.
-   The same production Programmer surface is used docked and floating.
-   Mixed/partial capability semantics should reuse Aurora's existing
    presentation language.

Hands-on/code review found several implementation defects that should be
corrected as a focused 1.1 pass rather than redesigning the Color
Engine.

The most important addition confirmed by product review is:

> **Aurora must always provide a usable overall Dimmer for color
> fixtures. If a fixture has no dedicated physical dimmer channel,
> Aurora must synthesize a virtual dimmer by scaling its color
> emitters.**

This is required for RGB-only and similar fixtures and should behave
like LightKey's overall fixture Dimmer.

------------------------------------------------------------------------

# 2. Preserve the Current Color Architecture

Do **not** collapse the new authoring model back into raw RGB.

Retain this conceptual pipeline:

``` text
Authoring state:
    colorHue
    colorSat
    colorVal
    colorWB

        ↓ ColorMath / resolver

Physical RGB:
    colorR
    colorG
    colorB

Dedicated physical emitters:
    colorW
    colorA
    colorUV
    future emitters

Master fixture intensity:
    physical dimmer if present
    OR virtual dimmer if absent
```

The UI should continue presenting these domains independently.

------------------------------------------------------------------------

# 3. Fix A --- Saturation Control Geometry

## 3.1 Current defect

The current wheel geometry maps saturation as though the usable
saturation field extends from the center of the wheel to the hue ring.

But the center is occupied by:

-   the color preview,
-   the White Balance / Brightness ring.

As a result, the user can only reach roughly the upper portion of the
saturation range by dragging the visible saturation annulus.

Practical symptom:

``` text
very saturated colors → reachable
pastel / low-saturation colors → difficult or impossible to reach
```

This is a functional bug.

## 3.2 Required mapping

Map saturation specifically to the **visible saturation annulus**.

Conceptually:

``` text
inner saturation radius = outside edge of character ring
outer saturation radius = inside edge of hue ring
```

Then:

``` text
sat = clamp(
    (pointerRadius - innerSatRadius)
    /
    (outerSatRadius - innerSatRadius),
    0...1
)
```

Depending on visual orientation:

``` text
inner edge → low saturation
outer edge → high saturation
```

This is the recommended mapping.

## 3.3 Thumb position

The saturation thumb must use the same inverse mapping:

``` text
r = innerSatRadius
    + saturation * (outerSatRadius - innerSatRadius)
```

Do not continue using center-to-hue-ring radius.

## 3.4 Acceptance

The operator must be able to smoothly drag:

``` text
100% saturated red
→ pastel red
→ near-neutral red-tinted white/gray
```

without leaving the visible saturation control.

------------------------------------------------------------------------

# 4. Fix B --- White Balance Marker Direction

## 4.1 Current defect

The gesture math correctly produces negative values for the cool side
and positive values for the warm side.

However, the marker angle calculation currently places the cool/negative
value on the wrong side of the rendered ring.

Observed conceptual mismatch:

``` text
drag cool side
→ value becomes negative correctly
→ marker appears in bottom/wrong location
```

## 4.2 Required fix

Make:

``` text
gesture mapping
marker mapping
tick labels
visual warm/cool gradient
```

all use the same angular convention.

Do not patch only the marker visually.

Create one canonical helper for:

``` text
whiteBalance value [-1...1]
↔
arc angle
```

and use it for both:

-   pointer → value,
-   value → marker.

## 4.3 Tests

Test:

``` text
w = -1 → extreme cool end
w = 0  → neutral center
w = +1 → extreme warm end
```

The marker must match the gesture location exactly.

------------------------------------------------------------------------

# 5. Fix C --- Reset Local Draft State Deterministically on Selection Change

## 5.1 Current defect

`syncDrafts()` only overwrites local draft values when the new
`ProgrammerColorPresentation` contains a concrete value.

This allows stale values from the previous selection to survive.

Example:

``` text
Fixture A:
White = 70%

select Fixture B:
White is unset / not owned by Programmer

draftEmitters["colorW"] remains 70%
```

The UI can therefore display a value belonging to the previous
selection.

The same risk exists for:

-   Dimmer,
-   Hue,
-   Saturation,
-   Brightness,
-   White Balance,
-   dedicated emitters.

## 5.2 Required rule

> Selection change must rebuild Color Engine draft state from scratch.

Do not incrementally patch old draft state.

Conceptually:

``` swift
func rebuildDrafts(from presentation: ProgrammerColorPresentation) {
    draftDimmer = ...
    draftHue = ...
    draftSaturation = ...
    draftBrightness = ...
    draftWhiteBalance = ...
    draftEmitters = [:]

    for emitter in presentation.emitters {
        draftEmitters[emitter.attribute] = ...
    }
}
```

## 5.3 Mixed / unset values

For:

``` text
mixed
partial mixed
unset
unsupported
```

use explicit optional/mixed state rather than leaving a previous numeric
draft behind.

Do not invent a numeric value solely because a SwiftUI `Slider` wants
one.

If a slider requires a fallback numeric position for rendering, keep:

``` text
display fallback
```

separate from:

``` text
semantic value
```

------------------------------------------------------------------------

# 6. Fix D --- Mixed-Selection Center Preview

## 6.1 Current defect

`ProgrammerColorPresentation` can compute/provide a mixed preview
representation.

`ProgrammerColorEngineView` currently ignores that and calculates the
center preview from local draft H/S/V/WB.

In a mixed selection, those drafts can be stale or arbitrary.

Result:

> The center preview can show a believable solid color that is not
> actually representative of the mixed fixture state.

## 6.2 Required behavior

When RGB state is concrete:

``` text
center preview = resolved current RGB authoring state
```

When RGB is mixed:

Use the presentation's mixed indication.

Acceptable visual strategies:

### Preferred

A mixed-color preview:

``` text
split/quartered preview
subtle multicolor/mixed treatment
```

### Acceptable

Neutral center with:

``` text
—
MIXED
```

or Aurora's existing mixed-value visual treatment.

Do not show a stale previous fixture color.

## 6.3 Presentation source of truth

Use:

``` text
ProgrammerColorPresentation.previewRGB
```

or equivalent production presentation data.

Do not derive mixed preview purely from local SwiftUI draft state.

------------------------------------------------------------------------

# 7. Fix E --- Color Palette Capture Must Preserve Dedicated Emitters

## 7.1 Current defect

The Color Palette capture key list currently includes only:

``` text
colorR
colorG
colorB
colorW
```

It omits:

``` text
colorA
colorUV
```

Therefore:

``` text
RGB + White + Amber + UV look
→ create Color Palette
→ Amber/UV silently lost
```

This is a direct functional bug.

## 7.2 Required physical attribute capture

Color Palette capture must include supported color-output attributes:

``` text
colorR
colorG
colorB
colorW
colorA
colorUV
```

and future recognized color emitters where appropriate.

Do not hard-code the palette system permanently to those six strings if
a reusable emitter registry now exists.

Prefer deriving the physical color attribute family from:

``` text
ColorEmitterKind
+
RGB physical attributes
```

------------------------------------------------------------------------

# 8. Preserve Authoring State Through Palettes

The current engine correctly made:

``` text
colorHue
colorSat
colorVal
colorWB
```

first-class Programmer authoring state.

Palette recall should not destroy that fidelity.

## 8.1 Required outcome

If a user:

``` text
Hue = 220°
Saturation = 75%
Brightness = 40%
White Balance = +25%
Amber = 20%
```

and captures a Color Palette, recalling that palette should restore:

-   the physical color look,
-   the dedicated emitters,
-   the Color Programmer's wheel/inner-ring state.

## 8.2 Recommended implementation

Allow Color Palettes to store both:

### Authoring metadata

``` text
colorHue
colorSat
colorVal
colorWB
```

### Physical emitter/output attributes

``` text
colorR
colorG
colorB
colorW
colorA
colorUV
...
```

The authoring fields are not DMX channels.

They are Programmer metadata.

Do not let fixture capability filtering discard them simply because the
fixture has no physical parameter named `colorHue`.

## 8.3 Palette apply order

Recommended:

``` text
restore authoring H/S/V/WB
→ resolve physical RGB consistently
→ restore dedicated emitters
```

If both authoring and physical RGB are stored, define one canonical
authority to prevent conflict.

Recommended authority:

``` text
authoring state is canonical when present
physical RGB is backward compatibility / resolved state
```

Document this.

## 8.4 Legacy palettes

Existing palettes that contain only physical RGB/W must continue to
work.

On recall:

``` text
physical RGB
→ derive H/S/V
→ WB defaults/best-effort neutral
```

Do not require migration of every old palette.

------------------------------------------------------------------------

# 9. Cue / Playback Verification

The cue/look system uses a generic attribute bag and should already
preserve:

``` text
colorA
colorUV
```

if written.

Verify this with automated tests.

Also verify the new authoring state behavior.

A recorded cue containing:

``` text
colorHue
colorSat
colorVal
colorWB
```

must not cause those soft authoring fields to be treated as physical DMX
channels.

They may exist in the look as Programmer metadata, but output resolution
must use only recognized physical attributes.

------------------------------------------------------------------------

# 10. Fix F --- Fixture Importer Must Recognize Dedicated Emitters Correctly

## 10.1 Current defect

`FixtureImporter.attribute(forChannelName:)` currently recognizes some
color names, but:

-   UV is not reliably mapped,
-   Warm White can be swallowed by generic White recognition,
-   Cool White can be swallowed by generic White recognition,
-   Lime is not recognized,
-   Cyan dedicated emitter is not recognized separately from RGB
    interpretation where applicable.

## 10.2 Ordered recognition

Use most-specific names before generic names.

Recommended order:

``` text
Warm White
Cool White
Ultraviolet / UV
Amber
Lime
Cyan
White
Red
Green
Blue
```

Do not test `"white"` before `"warm white"` / `"cool white"`.

## 10.3 Attribute mapping

Recommended:

``` text
Warm White → colorWarmWhite
Cool White → colorCoolWhite
White      → colorW
Amber      → colorA
UV         → colorUV
Lime       → colorLime
Cyan       → colorCyan
```

Use existing naming if Aurora already established equivalents.

Do not add duplicate attribute namespaces.

## 10.4 Alias matching

Recognize common variants:

``` text
UV
U.V.
Ultraviolet
Amber
A
Warm White
WarmWhite
WW
Cool White
CoolWhite
CW
Lime
Cyan
```

Avoid dangerous one-letter matching without channel-name tokenization.

------------------------------------------------------------------------

# 11. Fix G --- Global Show Control Must Exclude Soft Color Authoring Attributes

## 11.1 Current defect

`GlobalShowControl.isColorEmitter()` currently has a broad fallback
similar to:

``` swift
lower.hasPrefix("color")
```

This incorrectly classifies:

``` text
colorHue
colorSat
colorVal
colorWB
```

as physical emitters.

On fixtures without a physical dimmer, Global Master / Blackout can
therefore scale or zero these authoring values.

Even if DMX output ignores them, the resolved state becomes semantically
wrong and the Programmer can lose authoring information.

## 11.2 Required rule

Soft authoring attributes are never physical emitters.

Create/use one canonical helper:

``` swift
ColorAuthoringAttribute.isAuthoring(_:)
```

Then:

``` swift
if ColorAuthoringAttribute.isAuthoring(attribute) {
    return false
}
```

before physical color-emitter detection.

## 11.3 Physical emitter detection

Prefer an explicit physical-emitter registry over:

``` text
attribute.hasPrefix("color")
```

Conceptually:

``` text
colorR
colorG
colorB
colorW
colorA
colorUV
colorWarmWhite
colorCoolWhite
colorLime
colorCyan
```

are physical emitters.

``` text
colorHue
colorSat
colorVal
colorWB
```

are authoring metadata.

------------------------------------------------------------------------

# 12. Fix H --- Implement Virtual Dimmer for Fixtures Without a Physical Dimmer

This is now an explicit product requirement.

> **Every relevant color fixture must have an overall Dimmer control in
> Aurora, even if the fixture personality has no dedicated Dimmer DMX
> channel.**

This is required to match the intended LightKey behavior.

------------------------------------------------------------------------

# 13. Physical vs Virtual Dimmer

## Physical dimmer fixture

Example:

``` text
Channel 1: Dimmer
Channel 2: Red
Channel 3: Green
Channel 4: Blue
```

Aurora Dimmer writes:

``` text
intensity
```

which resolves to the physical dimmer channel.

RGB values remain independent.

## No physical dimmer

Example:

``` text
Channel 1: Red
Channel 2: Green
Channel 3: Blue
```

Aurora still shows:

``` text
DIMMER
```

The Dimmer becomes a **virtual master intensity** for that fixture.

It must scale the physical color emitters at output resolution.

------------------------------------------------------------------------

# 14. Virtual Dimmer Semantics

For an RGB fixture:

``` text
authored RGB:
R = 1.00
G = 0.20
B = 0.00

virtual dimmer:
50%
```

resolved physical output should be approximately:

``` text
R = 0.50
G = 0.10
B = 0.00
```

while the Programmer still remembers:

``` text
RGB authoring:
R = 1.00
G = 0.20
B = 0.00

Dimmer:
50%
```

Do not destructively rewrite authored RGB values to half their values.

This is crucial.

The virtual dimmer must exist as its own master-intensity semantic.

------------------------------------------------------------------------

# 15. Virtual Dimmer Must Scale All Relevant Physical Emitters

For RGBWA+UV fixture with no physical master dimmer:

``` text
R
G
B
White
Amber
UV
```

must all be scaled by the virtual master Dimmer.

Example:

``` text
RGB blue = 80%
White = 40%
Amber = 20%
UV = 60%
Dimmer = 50%
```

resolved output becomes:

``` text
RGB contribution × 0.5
White × 0.5
Amber × 0.5
UV × 0.5
```

The stored authored emitter values remain unchanged.

## Future emitters

The same applies to:

``` text
Warm White
Cool White
Lime
Cyan
custom physical color emitters
```

Do not implement virtual dimming as RGB-only scaling if the fixture has
other independently controlled emitters.

------------------------------------------------------------------------

# 16. Virtual Dimmer and Non-Color Parameters

Virtual Dimmer must **not** scale:

-   Pan,
-   Tilt,
-   Zoom,
-   Focus,
-   Gobo,
-   Prism,
-   Shutter mode,
-   Macro,
-   Speed,
-   color authoring metadata,
-   other non-intensity attributes.

It scales only light-producing physical intensity/emitter contributions.

------------------------------------------------------------------------

# 17. Virtual Dimmer Domain Model

Do not fake this only in SwiftUI.

Aurora needs a first-class notion of:

``` text
effective intensity capability
```

Conceptually:

``` swift
enum FixtureIntensityMode {
    case physicalDimmer(attribute: String)
    case virtualEmitterScale
    case unsupported
}
```

or equivalent.

For most RGB fixtures:

``` text
virtualEmitterScale
```

For fixture with dedicated dimmer:

``` text
physicalDimmer
```

This should be resolved in capability/presentation/domain logic.

The Color tab simply shows the Dimmer because the fixture supports an
**effective** intensity control.

------------------------------------------------------------------------

# 18. Existing `intensity` Attribute

Preferred implementation:

Continue using Aurora's canonical:

``` text
intensity
```

Programmer attribute for both physical and virtual dimmer authoring.

Then output resolution decides:

``` text
physical dimmer exists
→ map intensity to physical dimmer

no physical dimmer
→ use intensity as virtual emitter scale
```

This keeps:

-   Programmer,
-   cues,
-   palettes,
-   MIDI mappings,
-   future remote control,

from needing separate `virtualIntensity` APIs.

Do not create two different user-facing intensity concepts unless
absolutely necessary.

------------------------------------------------------------------------

# 19. Output Resolution Order With Virtual Dimmer

Recommended conceptual order:

``` text
Author H/S/V/WB
    ↓
resolve RGB physical values

Dedicated emitter authored values
    ↓
White / Amber / UV / etc.

        ↓

Master intensity / Dimmer
    ↓

IF physical dimmer exists:
    write emitter values normally
    write physical dimmer channel

IF no physical dimmer:
    scale all physical light-producing emitters
    do not invent a nonexistent DMX dimmer channel
```

This distinction belongs in the fixture/output resolver.

------------------------------------------------------------------------

# 20. Global Master and Blackout With Virtual Dimmer

Aurora already has global master/blackout logic.

Required hierarchy:

``` text
Fixture authored intensity
×
Global Master
×
Blackout state
```

For physical-dimmer fixture:

``` text
final physical Dimmer channel
```

For virtual-dimmer fixture:

``` text
final physical emitter scaling
```

Do not apply virtual intensity twice.

Example:

``` text
Fixture virtual Dimmer = 50%
Global Master = 50%

final emitter scale = 25%
```

not 12.5%.

Define one canonical intensity multiplication path.

------------------------------------------------------------------------

# 21. Cue / Palette Behavior for Virtual Dimmer

Because the user-facing Dimmer remains:

``` text
intensity
```

existing cue storage should preserve it naturally.

Verify:

-   recording RGB-only fixture at Dimmer 30% stores intensity 0.3,
-   playback reconstructs 30% virtual scale,
-   changing RGB later does not change stored intensity,
-   palette semantics remain consistent with existing Aurora
    intensity/color separation.

Color palettes should generally not capture master Dimmer unless
Aurora's existing palette taxonomy intentionally includes intensity.

Do not change palette-family semantics solely because virtual dimmer
exists.

------------------------------------------------------------------------

# 22. Mixed Selection and Virtual Dimmer

Example selection:

``` text
Fixture A:
physical dimmer

Fixture B:
RGB-only virtual dimmer
```

The user should still see one:

``` text
DIMMER
```

control.

Dragging it should set:

``` text
intensity
```

for both fixtures.

At output:

``` text
A → physical dimmer channel
B → virtual emitter scaling
```

This is exactly why the UI should operate on semantic intensity rather
than raw channel presence.

------------------------------------------------------------------------

# 23. Dimmer Visibility Rules

Recommended:

``` text
fixture has physical dimmer
→ show Dimmer

fixture has light-producing emitters but no physical dimmer
→ show Dimmer as virtual

fixture truly has no meaningful intensity/light output control
→ Dimmer unsupported
```

An RGB/RGBW/RGBA/RGBWA/UV fixture should virtually always get a Dimmer.

------------------------------------------------------------------------

# 24. Fix I --- Reduce Broad UI Invalidations During Color Drag

## 24.1 Current concern

Each high-frequency wheel sample eventually reaches:

``` text
AppModel.noteProgrammerUIChanged()
```

which can trigger broad:

``` text
notifyUI()
```

behavior.

The new hero wheel can easily produce:

``` text
60–120 pointer updates/sec
```

This is exactly the high-frequency path identified in the Post-C6
hardening audit.

## 24.2 Do not redesign observation blindly

First instrument.

Measure during:

-   hue drag,
-   saturation drag,
-   WB drag,
-   brightness drag,
-   emitter fader drag,
-   virtual Dimmer drag.

Track:

``` text
AppModel objectWillChange frequency
ProgrammerPanel body evaluation frequency
BuildWorkspaceHost body evaluation frequency
StageCanvasView body evaluation frequency
Browser/Inspector redraws
```

## 24.3 Required optimization

The desired path is:

``` text
Color control sample
→ Programmer values update
→ local Color UI refresh
→ Stage/output refresh
```

without forcing unrelated shell panels to rebuild on every sample.

Remove redundant broad `notifyUI()` calls where child observable state
already publishes.

Use the Post-C6 presentation equality optimization.

If necessary, split:

``` text
capability/selection presentation
```

from:

``` text
high-frequency numeric color values
```

so capability resolver work is not repeated for every RGB sample.

------------------------------------------------------------------------

# 25. Capability Presentation Should Not Recompute Needlessly

A color-wheel drag changes:

``` text
Hue/Saturation/Brightness/WB
```

It does not change:

``` text
Does fixture support White?
Does fixture support Amber?
Does fixture support UV?
Is emitter partial across selection?
```

Do not recompute expensive capability structure at pointer rate if
avoidable.

Recommended separation:

``` text
ProgrammerColorCapabilities
    relatively stable per selection

ProgrammerColorValues
    high-frequency live state
```

The exact type split is optional.

The performance characteristic is required.

------------------------------------------------------------------------

# 26. Automated Tests --- Saturation Geometry

Add tests for:

``` text
inner annulus edge → saturation ≈ 0
mid annulus        → saturation ≈ 0.5
outer annulus edge → saturation ≈ 1
```

Test inverse thumb geometry too.

Round-trip:

``` text
sat
→ thumb radius
→ pointer conversion
→ same sat
```

within tolerance.

------------------------------------------------------------------------

# 27. Automated Tests --- White Balance Geometry

Test:

``` text
cool endpoint
neutral midpoint
warm endpoint
```

for both:

``` text
value → angle
angle → value
```

Round-trip must match.

------------------------------------------------------------------------

# 28. Automated Tests --- Draft Reset

Create:

``` text
Fixture A:
White = 0.7

Fixture B:
White unset
```

Select A then B.

Expected:

``` text
B UI does not show 0.7 as owned current value
```

Repeat for:

-   Dimmer,
-   Hue,
-   Saturation,
-   Brightness,
-   WB,
-   Amber,
-   UV.

------------------------------------------------------------------------

# 29. Automated Tests --- Mixed Preview

Select two fixtures with distinct colors.

Expected:

-   presentation reports mixed,
-   center preview uses explicit mixed visual/state,
-   old single-fixture draft color is not reused.

------------------------------------------------------------------------

# 30. Automated Tests --- Palette Round-Trip

Mandatory RGBWA+UV case.

Create authored state:

``` text
H = 210°
S = 0.75
V = 0.40
WB = +0.25
White = 0.35
Amber = 0.20
UV = 0.50
```

Capture Color Palette.

Change all values.

Recall palette.

Expected:

``` text
wheel H/S/V restored
WB restored
White restored
Amber restored
UV restored
physical RGB matches resolved authoring state
```

Also test a legacy RGB-only palette.

------------------------------------------------------------------------

# 31. Automated Tests --- Fixture Importer

Input channel names:

``` text
White
Warm White
Cool White
Amber
UV
Ultraviolet
Lime
Cyan
```

Verify correct semantic attributes.

Test specificity:

``` text
"Warm White"
must NOT resolve to generic colorW
```

------------------------------------------------------------------------

# 32. Automated Tests --- Global Master Safety

Given:

``` text
colorHue = 0.6
colorSat = 0.7
colorVal = 0.8
colorWB  = 0.2
```

apply:

``` text
Global Master = 0.5
```

Expected:

``` text
authoring fields unchanged
```

Physical emitter outputs/intensity may scale according to fixture mode.

Blackout must also leave authoring metadata unchanged.

------------------------------------------------------------------------

# 33. Automated Tests --- Virtual Dimmer RGB Fixture

Fixture:

``` text
RGB
no physical dimmer
```

Authored:

``` text
R = 1
G = 0.5
B = 0
intensity = 0.4
```

Expected output:

``` text
R = 0.4
G = 0.2
B = 0
```

Expected stored authoring:

``` text
R = 1
G = 0.5
B = 0
intensity = 0.4
```

------------------------------------------------------------------------

# 34. Automated Tests --- Virtual Dimmer RGBWA+UV Fixture

Fixture:

``` text
RGBWA+UV
no physical dimmer
```

Authored:

``` text
RGB resolved values
White = 0.6
Amber = 0.4
UV = 0.8
intensity = 0.5
```

Expected all physical emitters scaled by 0.5.

Authoring values remain unchanged.

------------------------------------------------------------------------

# 35. Automated Tests --- Physical Dimmer Fixture

Fixture has:

``` text
physical intensity
+
RGBWA+UV
```

Set:

``` text
intensity = 0.5
```

Expected:

-   physical dimmer channel receives 0.5,
-   emitter values are not pre-scaled by virtual-dimmer logic unless
    existing DMX output model intentionally requires final master
    scaling elsewhere,
-   no double scaling.

------------------------------------------------------------------------

# 36. Automated Tests --- Mixed Physical/Virtual Selection

Select:

``` text
Fixture A: physical dimmer
Fixture B: virtual dimmer
```

Set:

``` text
Dimmer = 30%
```

Expected:

``` text
A intensity semantic = 0.3 → physical channel
B intensity semantic = 0.3 → emitter scale
```

UI shows one coherent Dimmer.

------------------------------------------------------------------------

# 37. Manual Acceptance Matrix

## Low saturation

-   [ ] Select RGB fixture.
-   [ ] Drag saturation toward inner usable edge.
-   [ ] Reach visibly pastel / near-neutral colors.
-   [ ] Drag back outward to full saturation.

## White Balance marker

-   [ ] Drag cool side.
-   [ ] Marker follows cool side.
-   [ ] Drag neutral.
-   [ ] Marker centers.
-   [ ] Drag warm side.
-   [ ] Marker follows warm side.

## Selection reset

-   [ ] Set White high on Fixture A.
-   [ ] Select untouched Fixture B.
-   [ ] White UI does not inherit A's displayed value.

## Mixed color

-   [ ] Select two differently colored fixtures.
-   [ ] Center preview clearly indicates mixed state.
-   [ ] No stale previous color displayed as though concrete.

------------------------------------------------------------------------

# 38. Manual Palette Acceptance

-   [ ] Build RGBWA+UV look.
-   [ ] Set non-neutral WB.
-   [ ] Capture Color Palette.
-   [ ] Change all values.
-   [ ] Recall palette.
-   [ ] Wheel returns to same hue/saturation/brightness.
-   [ ] WB ring returns to same position.
-   [ ] White returns.
-   [ ] Amber returns.
-   [ ] UV returns.

------------------------------------------------------------------------

# 39. Manual Virtual Dimmer Acceptance

## RGB-only fixture

-   [ ] Select RGB fixture with no physical dimmer.
-   [ ] DIMMER is visible on left.
-   [ ] Set RGB color.
-   [ ] Move DIMMER from 100% to 0%.
-   [ ] Fixture fades smoothly.
-   [ ] RGB wheel position/color does not collapse toward black.
-   [ ] Return DIMMER to 100%.
-   [ ] Original color returns exactly.

## RGBWA+UV without physical dimmer

-   [ ] Set RGB + White + Amber + UV.
-   [ ] Lower DIMMER.
-   [ ] All emitters fade proportionally.
-   [ ] Individual fader values remain unchanged.
-   [ ] Raise DIMMER.
-   [ ] Original emitter mix returns.

## Physical-dimmer fixture

-   [ ] Dimmer behaves normally.
-   [ ] No double dimming.

------------------------------------------------------------------------

# 40. Manual Importer Acceptance

Use fixtures/profiles containing:

``` text
Warm White
Cool White
UV
Amber
Lime
Cyan
```

Verify the correct faders appear.

No Warm White channel should appear as generic White solely because
`"white"` matched first.

------------------------------------------------------------------------

# 41. Manual Global Master / Blackout Acceptance

With non-neutral H/S/V/WB:

-   [ ] Set Global Master to 50%.
-   [ ] Output dims.
-   [ ] Wheel does not move.
-   [ ] WB marker does not move.
-   [ ] Dedicated fader authored values remain semantically unchanged.
-   [ ] Restore Global Master.
-   [ ] Look returns exactly.

Blackout:

-   [ ] Output goes dark.
-   [ ] Programmer authoring state remains intact.
-   [ ] Release blackout.
-   [ ] Look returns.

------------------------------------------------------------------------

# 42. Performance Acceptance

During a continuous 10-second hue drag:

-   [ ] smooth pointer tracking,
-   [ ] live Stage update,
-   [ ] no visible shell hitching,
-   [ ] no fixture Browser flicker,
-   [ ] floating Programmer remains responsive,
-   [ ] CPU behavior is reasonable.

Record DEBUG invalidation metrics in checkpoint notes.

If broad shell invalidation remains very high, fix before closing the
Color Engine.

------------------------------------------------------------------------

# 43. Production Screenshot Evidence

Provide actual running Aurora screenshots for:

1.  RGB fixture with virtual Dimmer.
2.  RGBW fixture.
3.  RGBWA+UV fixture.
4.  Low-saturation pastel state.
5.  Non-neutral White Balance marker.
6.  Mixed selection.
7.  Floating Programmer window.
8.  Recalled RGBWA+UV palette matching authored wheel state.

Compare the main RGBWA+UV screenshot to:

``` text
Aurora_Programmer_Color_Reference.png
```

------------------------------------------------------------------------

# 44. Recommended Implementation Order

## Step 1

Fix saturation annulus mapping and tests.

## Step 2

Fix WB marker/value angular round-trip.

## Step 3

Rebuild draft state deterministically on selection changes.

## Step 4

Fix mixed-selection center preview.

## Step 5

Fix Global Show Control classification of authoring vs physical color
attributes.

## Step 6

Implement virtual intensity mode for fixtures without physical dimmer.

## Step 7

Extend importer recognition for White variants / Amber / UV / Lime /
Cyan.

## Step 8

Extend Color Palette capture/apply for physical emitters and authoring
state.

## Step 9

Verify cue/playback round-trip.

## Step 10

Instrument and optimize high-frequency UI invalidation.

## Step 11

Run automated and production acceptance.

------------------------------------------------------------------------

# 45. Completion Criteria

Color Engine 1.1 is complete only when:

-   low saturation is fully reachable,
-   WB marker matches WB gesture direction,
-   selection changes cannot inherit stale drafts,
-   mixed selection does not show stale concrete preview,
-   Color Palettes preserve White/Amber/UV,
-   Color Palettes preserve H/S/V/WB authoring state,
-   fixture importer recognizes all required emitters in correct
    specificity order,
-   Global Master/Blackout never mutate soft authoring state,
-   RGB fixtures without physical dimmer still show/use DIMMER,
-   virtual Dimmer scales all light-producing physical emitters,
-   physical-dimmer fixtures do not double-scale,
-   mixed physical/virtual intensity selections behave coherently,
-   high-frequency wheel interaction remains smooth,
-   docked/floating Programmer remain identical,
-   automated tests pass,
-   native Xcode build passes,
-   production screenshots match the approved reference closely.

------------------------------------------------------------------------

# 46. STOP CONDITION

After Color Engine 1.1:

> **STOP and produce a Color Engine checkpoint for human review. Do not
> begin the Advanced MIDI Engine automatically.**

The checkpoint should report:

-   saturation geometry correction,
-   WB angle correction,
-   draft reset behavior,
-   mixed preview behavior,
-   palette authoring/physical attribute model,
-   importer mapping table,
-   virtual dimmer architecture,
-   Global Master interaction,
-   UI invalidation metrics,
-   test results,
-   production screenshots.

------------------------------------------------------------------------

# 47. Product Standard

The Color Programmer must behave like an actual lighting console, not
merely expose channel values.

The wheel remembers the color the operator authored.

White, Amber, and UV remain real independent emitters.

The overall Dimmer always behaves like an overall Dimmer, even when the
fixture manufacturer forgot to give Aurora a physical dimmer channel to
write to.

For an RGB-only PAR:

> **pick the color in the middle, pull the Dimmer down on the left, and
> the lamp gets darker without the color control forgetting what it
> was.**

That is the required behavior.
