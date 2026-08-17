# Aurora Programmer Color Engine --- Detailed UX & Implementation Planning Specification

## LightKey-Inspired RGB Wheel, Master Dimmer, White Balance, Dedicated Emitters, and Capability-Driven Fixture Control

**Project:** Aurora Lighting Control\
**Target phase:** Programmer / Color UX enhancement after current C5
closeout\
**Purpose:** Give Grok a precise visual and behavioral specification for
implementing Aurora's advanced color Programmer so it closely matches
the interaction model demonstrated by LightKey, while remaining native
to Aurora's architecture and visual identity.

------------------------------------------------------------------------

# 1. Source of Truth

Use the following supplied Aurora renderings as the primary visual
reference:

``` text
Aurora_Programmer_Color_Reference.png
Aurora_Programmer_Color_Reference_Alt.png
```

These reference images intentionally show the desired Aurora adaptation
of the LightKey color Programmer:

-   master Dimmer fader on the left,
-   large central RGB color wheel,
-   live color preview in the center,
-   inner semicircular brightness / white-balance control,
-   dedicated White / Amber / UV faders on the right,
-   capability-driven visibility,
-   Aurora dark workstation styling,
-   existing Programmer tab structure,
-   Fixture Browser / Inspector context around the Programmer.

The visual target is not a loose inspiration. The Programmer should
**look and function substantially like this reference**.

The LightKey screenshot supplied by the user is the interaction model
being intentionally mirrored where LightKey has already solved the
problem well.

Do not introduce a radically different color-control concept.

------------------------------------------------------------------------

# 2. Product Goal

Aurora currently needs a richer fixture color model.

Many real fixtures contain color emitters beyond RGB, including:

-   White,
-   Amber,
-   UV,
-   Warm White,
-   Cool White,
-   Lime,
-   Cyan,
-   other manufacturer-defined emitters.

The Programmer must stop treating every color fixture as though all
color channels are one undifferentiated RGB control.

The target UX separates:

``` text
MASTER FIXTURE INTENSITY
        ↓
      DIMMER

RGB COLOR MIXING
        ↓
  MAIN COLOR WHEEL

RGB COLOR CHARACTER
        ↓
Brightness / White Balance

DEDICATED EMITTERS
        ↓
White / Amber / UV / ...
```

This separation is essential.

------------------------------------------------------------------------

# 3. Core Behavioral Model

For a fixture with:

``` text
RGB + White + Amber + UV + Master Dimmer
```

Aurora should map controls approximately as follows:

``` text
DIMMER fader
    → fixture master dimmer / intensity capability

RGB wheel
    → Red / Green / Blue emitters only

Color Brightness
    → RGB contribution/value

White Balance
    → RGB color temperature / desaturation-style white balancing behavior
      as defined by Aurora's color engine
      NOT the dedicated physical White emitter unless explicitly specified

WHITE fader
    → dedicated White emitter

AMBER fader
    → dedicated Amber emitter

UV fader
    → dedicated UV emitter
```

Do not silently fold White, Amber, and UV into the RGB wheel.

The direct controls must correspond to physical fixture capabilities.

------------------------------------------------------------------------

# 4. Layout Target

The Color Programmer should use this general composition:

``` text
┌─────────────────────────────────────────────────────────────────┐
│ PROGRAMMER                                                      │
│ Intensity   COLOR   Position   Beam   Effects                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ DIMMER          COLOR                         WHITE AMBER UV     │
│                                                                 │
│  │              ┌──────────────────┐             │    │    │    │
│  │              │  RGB HUE WHEEL   │             │    │    │    │
│  │              │                  │             │    │    │    │
│  │              │   inner ring     │             │    │    │    │
│  │              │  WB / brightness │             │    │    │    │
│  │              │       ●          │             │    │    │    │
│  │              │ color preview    │             │    │    │    │
│  │              └──────────────────┘             │    │    │    │
│  │                                               │    │    │    │
│ 72%                swatches...                  35%  28%  18%   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

The wheel should remain the visual hero.

The surrounding controls must feel integrated with it, not bolted on.

------------------------------------------------------------------------

# 5. Programmer Tabs

Retain Aurora's main Programmer section model:

``` text
Intensity
Color
Position
Beam
Effects
```

When `Color` is active:

-   the Color Engine fills the main Programmer working area,
-   unrelated intensity/position/beam controls should not clutter the
    central layout,
-   the master Dimmer is still visible because it is an essential
    high-frequency companion to color,
-   dedicated emitter faders appear according to selected fixture
    capabilities.

------------------------------------------------------------------------

# 6. Master Dimmer Fader

## 6.1 Purpose

The left-side vertical fader is the **overall fixture brightness
control**.

This is distinct from the color-wheel brightness/value control.

For fixtures with a dedicated dimmer channel:

``` text
Dimmer → dedicated fixture intensity parameter
```

For fixtures without a dedicated dimmer but where Aurora's engine can
synthesize intensity through emitter scaling, preserve existing Aurora
intensity semantics.

Do not redefine the existing lighting engine solely to satisfy this
layout.

## 6.2 Visual treatment

Match the reference:

-   tall vertical fader,
-   large enough for precise dragging,
-   current value displayed numerically beneath,
-   Aurora-purple active track/accent,
-   neutral dark trough,
-   clear label: `DIMMER`.

## 6.3 Interaction

Support:

-   drag thumb,
-   click track,
-   keyboard adjustment when focused,
-   precise numeric entry if Aurora already supports it,
-   reset/home behavior consistent with existing Programmer conventions.

## 6.4 Live update

The fixture output must update continuously while the fader moves.

Do not wait for mouse-up.

Use existing Programmer coalescing/undo semantics rather than generating
unusable command spam.

------------------------------------------------------------------------

# 7. Main RGB Color Wheel

## 7.1 Purpose

The large outer wheel is the primary RGB hue/saturation control.

It should feel visually and behaviorally close to the LightKey wheel
shown by the user.

## 7.2 Outer hue ring

The outer ring represents full hue traversal.

Expected clockwise sequence:

``` text
Red
→ Orange
→ Yellow
→ Green
→ Cyan
→ Blue
→ Violet
→ Magenta
→ Red
```

The exact angular starting position should match the visual reference,
with red at/near top.

## 7.3 Hue indicator

Display a small directional marker/triangle at the current hue on the
outer perimeter.

Reference rendering shows:

-   distinct marker,
-   high contrast,
-   tinted to current hue where appropriate.

The marker must update live.

## 7.4 Saturation interaction

The wheel must provide intuitive saturation control.

Recommended mapping:

``` text
angular position = hue
radial component / wheel-specific control = saturation
```

Use the current Aurora color model if it already represents HSV/HSL.

The implementation should be mathematically deterministic and testable.

------------------------------------------------------------------------

# 8. Center Color Preview

The center of the color wheel must display the current resolved RGB
color.

This is explicitly required.

The center preview should:

-   be large enough to read instantly,
-   update continuously,
-   show the current RGB wheel result,
-   remain visually separate from dedicated White/Amber/UV contribution.

The purpose is:

> "What RGB color am I currently asking for?"

Do not make the preview simply show the physical final mixed output if
doing so would hide the distinction between RGB and dedicated emitters.

If Aurora later adds an overall physical-output preview, that can be a
separate enhancement.

------------------------------------------------------------------------

# 9. Inner Ring --- Brightness and White Balance

The LightKey-inspired center ring is a key part of the requested UX.

It should be implemented as a split circular control surrounding the
color preview.

Conceptually:

``` text
LEFT HALF
    White Balance

RIGHT HALF
    RGB Brightness
```

This is intentionally spatial and should not be replaced with two
generic horizontal sliders.

------------------------------------------------------------------------

# 10. RGB Brightness Half-Ring

## 10.1 Purpose

The right half of the inner ring controls RGB color brightness/value.

This is distinct from Master Dimmer.

Example:

``` text
RGB = Blue
RGB Brightness = 35%
Master Dimmer = 80%
```

means:

``` text
blue mix remains the selected hue
RGB contribution is reduced
overall fixture intensity remains independently controlled
```

## 10.2 Visual

Use a light-to-dark or color-to-black gradient similar to the reference.

The current value should have:

-   a clear marker,
-   tick marks or subtle radial divisions,
-   direct drag interaction.

## 10.3 Live behavior

Brightness updates live while dragging.

------------------------------------------------------------------------

# 11. White Balance Half-Ring

## 11.1 Purpose

The left half of the inner ring is White Balance.

This should behave similarly to LightKey's concept:

-   warmer/cooler or more/less white-balanced RGB color adjustment,
-   visually integrated with the selected RGB hue,
-   not equivalent to the physical White LED fader.

## 11.2 Color-engine definition

Before implementation, Grok should inspect Aurora's existing
color-engine semantics.

If Aurora already has:

-   white balance,
-   color temperature,
-   tint/desaturation,
-   RGBW conversion,

reuse the appropriate model.

If Aurora has no existing semantic for this, implementation planning
must explicitly define one before coding.

Do not create a visually convincing control whose mathematical behavior
is undefined.

## 11.3 Constraint

The user wants this to behave substantially like LightKey.

Therefore the final implementation plan should describe:

``` text
input range
neutral point
warm/cool direction
relationship to RGB values
interaction with dedicated White emitter
```

before implementation begins.

------------------------------------------------------------------------

# 12. Dedicated Emitter Faders

Dedicated physical emitters live on the right side of the wheel.

The reference explicitly requires:

``` text
WHITE
AMBER
UV
```

when the selected fixture supports them.

These controls should visually resemble the LightKey layout and the
approved Aurora rendering.

------------------------------------------------------------------------

# 13. Capability-Driven Visibility

Do not show emitter controls that the selected fixture does not support.

Examples:

## RGB fixture

``` text
Dimmer
Color Wheel
```

No White/Amber/UV faders.

## RGBW fixture

``` text
Dimmer
Color Wheel
White
```

## RGBA fixture

``` text
Dimmer
Color Wheel
Amber
```

## RGBWA fixture

``` text
Dimmer
Color Wheel
White
Amber
```

## RGBWA+UV fixture

``` text
Dimmer
Color Wheel
White
Amber
UV
```

Aurora should derive these controls from fixture capability metadata.

Never infer emitter availability merely from channel names at the view
layer if the fixture model already provides capability semantics.

------------------------------------------------------------------------

# 14. Generalize the Emitter Model

Do not hard-code the domain model to only:

``` text
White
Amber
UV
```

The architecture should permit:

``` text
ColorEmitter
├── red
├── green
├── blue
├── white
├── warmWhite
├── coolWhite
├── amber
├── uv
├── lime
├── cyan
└── custom/named emitter
```

The first production UI can prioritize:

-   White,
-   Amber,
-   UV,

because these are common and explicitly requested.

But the underlying model should not require another schema redesign to
support Lime six months later.

------------------------------------------------------------------------

# 15. Emitter Fader Ordering

Recommended canonical order:

``` text
White
Warm White
Cool White
Amber
Lime
Cyan
UV
Custom emitters
```

For the immediate approved rendering:

``` text
White
Amber
UV
```

If only one emitter exists, do not leave giant artificial spacing for
absent controls.

The right-side fader group should adapt responsively.

------------------------------------------------------------------------

# 16. Emitter Fader Styling

Each emitter fader should have its own visual accent:

``` text
White → neutral/cool white
Amber → amber/orange
UV → violet/purple
```

Use restraint.

Avoid neon toy-console aesthetics.

The active track can reflect emitter identity while the surrounding
fader remains Aurora charcoal.

Each fader includes:

-   label,
-   vertical control,
-   numeric percent readout,
-   appropriate disabled state.

------------------------------------------------------------------------

# 17. Fixture Selection Semantics

The Programmer must behave correctly for:

-   one fixture,
-   group selection,
-   mixed multi-selection.

This is critical.

------------------------------------------------------------------------

# 18. Single Fixture Selection

Show exactly the capabilities of that fixture.

Example fixture:

``` text
RGBAW+UV
```

shows:

``` text
Dimmer
Color Wheel
White
Amber
UV
```

------------------------------------------------------------------------

# 19. Group of Identical Fixtures

Show the same controls.

Adjustments should apply consistently to the group using existing
Programmer semantics.

------------------------------------------------------------------------

# 20. Mixed Fixture Selection

Aurora must not lie about capability support.

Example selection:

``` text
Fixture A: RGBW
Fixture B: RGBWA+UV
```

Potential policy:

``` text
RGB wheel:
    shown, applies to both

White:
    shown, applies to both

Amber:
    shown as partial capability OR hidden depending on Aurora policy

UV:
    shown as partial capability OR hidden
```

The implementation plan must inspect Aurora's existing mixed-capability
presentation model and choose a policy consistent with it.

Preferred professional behavior:

-   common capabilities = normal controls,
-   partial capabilities = visible with clear partial-support
    indication,
-   unsupported fixtures remain unchanged for that parameter.

Do not silently apply nonsense values.

------------------------------------------------------------------------

# 21. Partial-Capability Visual State

If Aurora supports partial mixed selection, emitter faders should be
visually distinguishable.

Potential treatment:

``` text
AMBER
(partial)
```

or a small mixed/partial indicator.

Do not clutter the interface.

Use the same visual language Aurora already uses for mixed Programmer
capabilities.

------------------------------------------------------------------------

# 22. Mixed Values

When selected fixtures have different current values:

``` text
White:
Fixture A = 10%
Fixture B = 60%
```

the fader should show Aurora's standard mixed-value state rather than
choosing one fixture's value.

Potential implementation:

-   indeterminate/mixed thumb,
-   subtle striped/multi indicator,
-   numeric `—`.

When the user moves the fader:

``` text
all supported fixtures receive the new value
```

------------------------------------------------------------------------

# 23. Color Preset Row

The rendering includes quick color swatches beneath the wheel.

Retain/add:

-   White,
-   Red,
-   Orange,
-   Yellow,
-   Green,
-   Cyan,
-   Blue,
-   Purple/Violet,
-   Magenta/Pink,
-   overflow `…`.

These are RGB color shortcuts.

They should update:

``` text
RGB wheel
center color preview
live RGB fixture values
```

They should not implicitly alter dedicated emitter faders unless a
specific palette/preset definition says so.

------------------------------------------------------------------------

# 24. Interaction Fidelity to LightKey

The user explicitly requests that this **look and function basically
identically to LightKey** where LightKey's design is successful.

Therefore:

-   preserve the large wheel-dominant layout,
-   preserve dedicated left Dimmer,
-   preserve dedicated right emitter faders,
-   preserve center preview,
-   preserve inner brightness/white-balance ring concept,
-   preserve direct, immediate manipulation,
-   preserve capability-driven visibility.

Aurora should adapt:

-   typography,
-   panel chrome,
-   accent colors,
-   spacing,
-   button styling,

to Aurora's established design system.

Do not copy proprietary artwork/assets.

The interaction pattern is the target.

------------------------------------------------------------------------

# 25. Responsive Layout

The Programmer may be:

-   docked,
-   resized,
-   floated in C5,
-   placed on a second monitor,
-   shown at different window sizes.

The color engine must adapt.

Priority order for layout:

``` text
1. Keep wheel usable and large
2. Keep Dimmer visible
3. Keep dedicated emitters visible
4. Preserve labels/readouts
5. Collapse nonessential whitespace
```

At narrower widths:

-   shrink wheel within sensible minimum,
-   reduce spacing,
-   allow emitter stack/grouping strategy if necessary.

Do not make the controls microscopic.

------------------------------------------------------------------------

# 26. C5 Floating Programmer Compatibility

The new Color Programmer must work identically when Programmer is:

``` text
docked
```

or:

``` text
floating in its own macOS window
```

Do not build separate Color Programmer implementations.

The same production `ProgrammerPanel` / extracted production surface
must render both.

Test the color wheel heavily in a detached C5 Programmer window.

------------------------------------------------------------------------

# 27. Data / Model Requirements

Before coding, Grok should inventory the current fixture color model.

Specifically locate:

-   RGB capability representation,
-   master dimmer capability,
-   White/Amber/UV channels,
-   generic fixture channel metadata,
-   palette/color model,
-   Programmer state representation,
-   resolved output state,
-   mixed-selection attribute presentation,
-   fixture profile/personality parsing.

The implementation plan must state whether Aurora already has a
first-class concept for:

``` text
dedicated color emitter
```

If not, add one in the appropriate model layer.

Do not put this logic exclusively inside SwiftUI.

------------------------------------------------------------------------

# 28. Suggested Domain Types

Conceptual only:

``` swift
enum ColorEmitterKind: Codable, Hashable {
    case red
    case green
    case blue
    case white
    case warmWhite
    case coolWhite
    case amber
    case uv
    case lime
    case cyan
    case custom(String)
}
```

And a capability representation such as:

``` swift
struct FixtureColorCapabilities {
    var rgb: Bool
    var emitters: Set<ColorEmitterKind>
    var supportsMasterDimmer: Bool
    var supportsWhiteBalance: Bool
}
```

Use the current Aurora architecture if equivalent types already exist.

Do not duplicate existing concepts.

------------------------------------------------------------------------

# 29. Programmer Attribute Presentation

The existing Programmer should expose a presentation model rather than
making the view interrogate raw DMX channels.

Conceptual:

``` text
ProgrammerColorPresentation
├── masterDimmer
├── rgb
│   ├── hue
│   ├── saturation
│   ├── brightness
│   └── whiteBalance
├── emitters[]
│   ├── White
│   ├── Amber
│   └── UV
└── mixed/partial capability metadata
```

This makes the UI testable and keeps fixture/profile quirks outside the
view.

------------------------------------------------------------------------

# 30. Dedicated Emitters and Palettes

Aurora's palette/preset system should be considered.

Decide explicitly whether a Color Palette can store:

``` text
RGB only
```

or:

``` text
RGB + dedicated emitter values
```

Recommended:

A full Color Palette may store emitter values when authored, while
RGB-only quick swatches modify only RGB.

This distinction should be reflected in the implementation plan.

Do not accidentally break existing palette semantics.

------------------------------------------------------------------------

# 31. Dedicated Emitters and Cue Storage

Cues must preserve the resulting Programmer output for:

-   White,
-   Amber,
-   UV,
-   future emitter channels,

using the existing cue attribute model.

Before implementation, verify this is already true.

If cue serialization currently only knows RGB color, this is a model
blocker and must be included in planning.

------------------------------------------------------------------------

# 32. Dedicated Emitters and Fixture Profiles

Fixture definitions must map physical channels to semantic emitters.

Example:

``` text
Channel 1: Dimmer
Channel 2: Red
Channel 3: Green
Channel 4: Blue
Channel 5: White
Channel 6: Amber
Channel 7: UV
```

Aurora should resolve:

``` text
Channel 5 → emitter.white
Channel 6 → emitter.amber
Channel 7 → emitter.uv
```

Do not rely solely on numeric channel order.

This will become especially important for the fixture-library
reverse-engineering work later.

------------------------------------------------------------------------

# 33. White Balance Semantics

This needs a deliberate implementation plan.

The control must not become a meaningless decorative half-ring.

Grok planning must answer:

1.  What internal parameter does White Balance control?
2.  What is its neutral midpoint?
3.  What does moving toward one end do mathematically?
4.  What does moving toward the opposite end do?
5.  Does it manipulate RGB only?
6.  Does it optionally use dedicated White when available?
7.  How does it behave on RGB-only fixtures?
8.  How does it behave on RGBW fixtures?
9.  How is it stored in Programmer/cues/palettes?

If Aurora's existing engine already has a white-balance abstraction, use
it.

If not, produce a proposed mathematical model for approval before
implementation.

------------------------------------------------------------------------

# 34. Brightness Semantics

Similarly define:

``` text
Color Brightness
```

as a color-domain value.

Recommended conceptual behavior:

``` text
RGB brightness = HSV Value / RGB scale
Master Dimmer = fixture-level output intensity
```

For example:

``` text
RGB wheel color:
R 100%
G 20%
B 0%

Color brightness 50%
→ RGB contribution:
R 50%
G 10%
B 0%

Master dimmer 80%
→ final fixture output scales according to Aurora's existing engine
```

Dedicated White/Amber/UV remain separately controlled before master
output scaling.

------------------------------------------------------------------------

# 35. Output Resolution Order

Document the intended conceptual order.

Example:

``` text
RGB wheel
    ↓
RGB brightness
    ↓
white-balance adjustment
    ↓
RGB emitter values

Dedicated emitter faders
    ↓
White / Amber / UV values

RGB + dedicated emitters
    ↓
Master Dimmer
    ↓
resolved fixture output
```

Do not enforce this exact order if it conflicts with Aurora's engine,
but the final plan must state the real order clearly.

------------------------------------------------------------------------

# 36. Performance

The wheel should feel immediate.

Requirements:

-   smooth pointer tracking,
-   no visible lag,
-   no unnecessary project serialization on every pointer sample,
-   no expensive image regeneration every frame,
-   no color-wheel bitmap creation per SwiftUI body update.

Use:

-   cached/generated gradient texture,
-   Canvas/Metal/CoreGraphics/SwiftUI Shape as appropriate,
-   lightweight math for pointer conversion.

The wheel should comfortably update at normal display refresh rates.

------------------------------------------------------------------------

# 37. Accessibility / Input

Support where practical:

-   VoiceOver labels for Dimmer/White/Amber/UV,
-   keyboard focus,
-   numeric percent text,
-   color preview accessibility value,
-   high-contrast marker visibility.

Do not compromise the workstation visual density to make every control
huge.

------------------------------------------------------------------------

# 38. Undo / Programmer Semantics

Follow Aurora's existing Programmer behavior.

Continuous drag:

``` text
mouse-down
→ live output changes continuously
→ drag
→ mouse-up
```

should not create hundreds of user-visible Undo steps if Programmer
actions are undoable.

Use existing edit coalescing patterns.

Do not invent an unrelated command architecture for this one component.

------------------------------------------------------------------------

# 39. Visual Design Details

The approved render uses:

-   deep charcoal Programmer background,
-   slightly lighter control cards,
-   purple Aurora focus/accent,
-   neutral thin dividers,
-   compact uppercase section labels,
-   bright but controlled color wheel,
-   white/amber/UV faders with emitter-specific track color,
-   percentage boxes at bottom,
-   minimal skeuomorphism.

Avoid:

-   glossy 2009-style knobs,
-   huge drop shadows,
-   excessive glow,
-   game-controller styling.

The wheel can be visually rich because it is inherently a color control.

The rest of the chrome remains restrained.

------------------------------------------------------------------------

# 40. Reference Image Fidelity

When implementing, compare the running production UI against:

``` text
Aurora_Programmer_Color_Reference.png
```

The acceptance criterion is not:

``` text
"all controls technically exist"
```

It is:

> **Launch Aurora, select an RGBWA+UV fixture/group, open Programmer →
> Color, and immediately recognize the approved reference layout.**

------------------------------------------------------------------------

# 41. Required Test Fixtures / Demo Personalities

Add or ensure deterministic test fixtures exist for:

``` text
RGB
RGBW
RGBA
RGBWA
RGBWA+UV
RGBWW/CW
RGBL
```

The actual fixture library may use real or synthetic personalities.

These are needed to prove capability-driven UX.

------------------------------------------------------------------------

# 42. Automated Tests

Add tests for:

## Capability presentation

``` text
RGB → no dedicated emitter faders
RGBW → White
RGBA → Amber
RGBWA → White + Amber
RGBWAUV → White + Amber + UV
```

## Stable emitter order

Verify deterministic ordering.

## Mixed selection

Verify common/partial capability computation.

## Mixed values

Verify indeterminate presentation and overwrite behavior.

## RGB wheel math

Test known pointer positions → expected hue/saturation.

## Brightness

Test RGB scaling.

## White balance

Test approved mathematical behavior.

## Center preview

Test preview representation derives from RGB color state.

## Dimmer independence

Changing master dimmer must not alter stored RGB hue/saturation/emitter
values.

## Emitter independence

Changing Amber must not silently rewrite RGB wheel position.

------------------------------------------------------------------------

# 43. Manual Acceptance Matrix

## RGB fixture

-   [ ] Select RGB fixture.
-   [ ] Color tab shows Dimmer + wheel.
-   [ ] No White/Amber/UV faders.
-   [ ] Move wheel.
-   [ ] Center preview updates live.
-   [ ] RGB output updates.

## RGBW fixture

-   [ ] White fader appears.
-   [ ] White moves independently.
-   [ ] RGB wheel remains unchanged when White moves.

## RGBA fixture

-   [ ] Amber fader appears.
-   [ ] Amber independently controls physical Amber emitter.

## RGBWA+UV fixture

-   [ ] White, Amber, UV all appear.
-   [ ] Each fader independently changes output.
-   [ ] Correct labels/order.
-   [ ] Dimmer controls overall brightness.

## RGB brightness

-   [ ] Select a saturated color.
-   [ ] Adjust inner brightness half-ring.
-   [ ] Hue remains stable.
-   [ ] RGB contribution changes.
-   [ ] Master Dimmer value does not move.

## White balance

-   [ ] Adjust left half-ring.
-   [ ] Color changes according to approved white-balance model.
-   [ ] Dedicated White fader does not unexpectedly move unless
    explicitly designed.

## Quick swatches

-   [ ] Click Red/Blue/etc.
-   [ ] Wheel marker moves.
-   [ ] center preview updates.
-   [ ] dedicated emitters stay untouched.

------------------------------------------------------------------------

# 44. C5 Multi-Window Acceptance

-   [ ] Dock Programmer.
-   [ ] Test all color controls.
-   [ ] Float Programmer to second monitor.
-   [ ] Same exact layout appears.
-   [ ] Continue dragging color wheel.
-   [ ] Main Stage updates live.
-   [ ] Redock.
-   [ ] all values remain synchronized.

No duplicate Programmer implementation.

------------------------------------------------------------------------

# 45. Production Screenshot Evidence

Capture actual Aurora screenshots for:

1.  RGB fixture selected.
2.  RGBW fixture selected.
3.  RGBWA+UV fixture selected.
4.  Mixed fixture selection.
5.  Floating Programmer window on second display.
6.  Inner brightness/white-balance ring actively adjusted.
7.  Center preview clearly visible.

Compare screenshot #3 directly against:

``` text
Aurora_Programmer_Color_Reference.png
```

------------------------------------------------------------------------

# 46. Implementation Planning Deliverable

Before coding, Grok should produce a detailed plan that includes:

``` text
Current code inventory
Model changes
Fixture capability changes
Programmer presentation changes
Color math
White-balance semantics
Mixed-selection semantics
Cue/palette persistence implications
SwiftUI component structure
Color wheel rendering implementation
Fader component reuse
Tests
Migration
Acceptance screenshots
```

Do not jump directly from this spec into implementation without
planning.

The user explicitly wants Grok Plan Mode to reason about this feature
first.

------------------------------------------------------------------------

# 47. Suggested Component Breakdown

Conceptual:

``` text
ProgrammerColorPanel
├── MasterDimmerControl
├── AuroraColorWheel
│   ├── HueRing
│   ├── ColorCharacterRing
│   │   ├── WhiteBalanceArc
│   │   └── BrightnessArc
│   └── ColorPreviewCenter
├── ColorSwatchRow
└── DedicatedEmitterFaderGroup
    ├── EmitterFader(White)
    ├── EmitterFader(Amber)
    └── EmitterFader(UV)
```

These should consume a common `ProgrammerColorPresentation`.

Do not put fixture-model parsing inside `AuroraColorWheel`.

------------------------------------------------------------------------

# 48. Suggested File Areas

Grok should inspect current names before finalizing paths, but likely
areas include:

``` text
Sources/AuroraUI/Programmer/
Sources/AuroraCore/Programmer/
Sources/AuroraModel/
Sources/AuroraEngine/
fixture profile / capability definitions
palette model
cue state model
```

Reuse existing controls where they already meet the approved appearance.

------------------------------------------------------------------------

# 49. Non-Goals for Initial Implementation

Do not expand this feature into:

-   CIE xy photometric color matching,
-   fixture calibration profiles,
-   spectral rendering,
-   automatic LED emitter optimization,
-   camera-based color measurement,
-   advanced color science presets,
-   per-manufacturer spectral databases.

Those may be valuable future features.

This phase is about a professional, direct, LightKey-style fixture color
Programmer.

------------------------------------------------------------------------

# 50. Future-Friendly Considerations

Architect so later Aurora can support:

``` text
RGBAL
RGBACL
RGBWW/CW
multi-white fixtures
calibrated emitter mixing
color temperature modes
Lee/Rosco gel emulation
XY color
HSI
```

But do not let future possibilities make the first implementation
bloated.

------------------------------------------------------------------------

# 51. Final Acceptance Standard

The implementation is ready when an operator can select an RGBWA+UV
fixture and use Aurora exactly as expected:

``` text
Set master brightness on left.

Pick RGB hue visually in the center.

See the chosen RGB color in the center preview.

Fine-tune RGB brightness and white balance on the inner ring.

Bring White up independently.

Add Amber independently.

Add UV independently.

Record/store the resulting look through normal Aurora Programmer/cue/palette workflows.
```

And it should visually look very close to the supplied approved render.

------------------------------------------------------------------------

# 52. Product Principle

Aurora should not force every modern LED fixture through an RGB-shaped
keyhole.

RGB is one color-mixing system.

White, Amber, UV, Lime, and other emitters are real physical sources and
deserve direct, predictable controls.

The Programmer should make that complexity feel simple:

> **Dim the fixture on the left. Build the color in the middle. Shape
> the dedicated emitters on the right.**

That is the target.
