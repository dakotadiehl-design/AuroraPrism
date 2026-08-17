# Aurora Programmer Color Engine - Final Closeout Pass

## Pass 2 Corrections Before Color Engine Acceptance

**Project:** Aurora Lighting Control\
**Reviewed checkpoint:** `Aurora_ColorEngine_Pass2.zip`\
**Phase:** Final Color Engine closeout\
**Status:** Small corrective pass required\
**STOP:** After implementation, tests, performance evidence, and
production screenshots. Do **not** begin the Advanced MIDI Engine
automatically.

------------------------------------------------------------------------

# 1. Executive Verdict

Color Engine Pass 2 is materially improved and the core architecture
should now be preserved.

The following Pass 1 issues have been corrected in production code and
should **not** be redesigned:

-   saturation is mapped into the visible saturation annulus,
-   White Balance uses coherent value/angle conversion helpers,
-   draft emitter state is rebuilt instead of blindly inherited,
-   mixed color preview has explicit handling,
-   Color Palette support has been expanded for Amber and UV,
-   H/S/V/WB remain first-class Programmer authoring attributes,
-   fixture-import matching is more specific,
-   soft color-authoring attributes are separated from physical
    emitters,
-   virtual emitter scaling exists for fixtures without a physical
    master dimmer,
-   physical and virtual intensity can share the canonical `intensity`
    semantic,
-   the LightKey-inspired Color Programmer layout remains the approved
    visual direction.

This is **not another Color Engine redesign**.

The remaining work is a focused semantic and integration closeout.

There are four concrete correctness issues plus one required performance
acceptance gate:

1.  Virtual intensity must be a global semantic capability, not a
    Color-tab-only special case.
2.  Untouched virtual intensity must display and behave as 100%, not
    display 0% while output behaves as 100%.
3.  Color Engine draft resynchronization must include Saturation,
    Brightness, and White Balance.
4.  Soft H/S/V/WB palette metadata must not be applied to fixtures that
    cannot author RGB color.
5.  High-frequency Color interaction must be measured in the production
    shell before acceptance.

------------------------------------------------------------------------

# 2. Preserve the Current Architecture

Do not undo the existing model.

Continue using:

``` text
Authoring color state:
    colorHue
    colorSat
    colorVal
    colorWB

        ↓

ColorMath / resolver

        ↓

Physical RGB:
    colorR
    colorG
    colorB

Dedicated physical emitters:
    colorW
    colorA
    colorUV
    future physical emitters

Semantic fixture intensity:
    intensity

        ↓

physical dimmer channel if present
OR
virtual emitter scaling if no physical dimmer exists
```

The important correction is that **semantic intensity must now be
recognized consistently throughout Aurora**.

------------------------------------------------------------------------

# 3. Fix 1 - Make Virtual Intensity a Global Semantic Capability

## 3.1 Current problem

Pass 2 correctly synthesizes effective `intensity` support in the Color
presentation for fixtures that:

-   produce light through color emitters,
-   but do not have a dedicated physical dimmer channel.

The Color tab therefore has a working virtual DIMMER.

However, other Programmer paths still determine target fixtures using
raw physical fixture capabilities.

Examples include code paths using:

``` swift
ProgrammerAttributePresentationResolver.capableFixtureIDs(
    attribute: "intensity",
    ...
)
```

If `capableFixtureIDs` only checks the raw fixture capability map, an
RGB-only fixture has no physical `intensity`.

This creates inconsistent semantics:

``` text
RGB-only fixture

Color tab:
DIMMER visible and functional

Intensity tab:
Intensity may appear semantically supported,
but apply/fan/align targeting can exclude the fixture
```

That is not acceptable.

------------------------------------------------------------------------

# 4. Required Intensity Principle

Aurora must have exactly one user-facing semantic:

``` text
intensity
```

The operator should not need to know whether the fixture implements that
intensity through:

``` text
a physical Dimmer channel
```

or:

``` text
virtual scaling of light-producing emitters
```

Therefore:

> Any Aurora subsystem asking "does this fixture support intensity?"
> must use **effective semantic capability**, not merely raw physical
> channel capability.

------------------------------------------------------------------------

# 5. Centralize Effective Capability Resolution

Do not scatter special cases such as:

``` text
if Color tab and RGB fixture then pretend intensity exists
```

through the UI.

Create or extend one canonical capability resolver.

Conceptually:

``` swift
effectiveCapabilities(for fixture)
```

or:

``` swift
effectiveCapableFixtureIDs(
    attribute: String,
    fixtureIDs: ...,
    project: ...
)
```

For `intensity`:

``` text
physical intensity/dimmer exists
→ supports intensity

no physical dimmer
but fixture has light-producing physical emitters
→ supports virtual intensity

neither condition
→ intensity unsupported
```

The exact API should fit the current Aurora architecture.

------------------------------------------------------------------------

# 6. Define Light-Producing Physical Attributes Centrally

Virtual intensity should scale only actual light-producing attributes.

The same canonical registry should be reusable by:

-   effective intensity capability,
-   virtual dimmer output resolution,
-   Global Show Control,
-   future fixture emitters.

Examples:

``` text
intensity / physical dimmer
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
future physical color emitters
```

Soft authoring metadata is **not** light-producing:

``` text
colorHue
colorSat
colorVal
colorWB
```

Neither are:

``` text
pan
tilt
zoom
focus
gobo
prism
speed
macro
```

Avoid multiple slightly different lists spread across modules if
practical.

------------------------------------------------------------------------

# 7. Apply Effective Intensity Everywhere

Audit every code path that manipulates or resolves `intensity`.

At minimum inspect:

``` text
Color tab DIMMER
Intensity tab
Fan
Align
Programmer attribute presentation
Programmer target resolution
cue application
palette/intensity application
remote control
MIDI mapping target resolution
future Advanced MIDI Engine hooks
global master
blackout
Stage/live preview resolved state
```

The immediate closeout must ensure existing Programmer paths are
coherent.

The future MIDI Engine should automatically benefit from the same
semantic capability resolver rather than needing another virtual-dimmer
exception.

------------------------------------------------------------------------

# 8. Intensity Tab Acceptance

For an RGB-only fixture with no physical dimmer:

``` text
select fixture
→ open Intensity tab
→ intensity control is usable
→ set 50%
→ RGB output becomes 50% of authored emitter output
```

Then:

``` text
open Color tab
→ DIMMER also reads 50%
```

Both tabs must edit the same canonical:

``` text
intensity
```

value.

No duplicated state.

------------------------------------------------------------------------

# 9. Fan and Align Acceptance

If Aurora supports Fan/Align operations for intensity, an RGB-only
virtual-dimmer fixture must participate exactly like a fixture with a
physical dimmer.

Example mixed selection:

``` text
Fixture A = moving head with physical dimmer
Fixture B = RGB PAR with virtual dimmer
Fixture C = RGBW bar with virtual dimmer
```

An intensity Fan/Align operation must target all three according to
normal capability rules.

At output:

``` text
A → physical dimmer
B → emitter scale
C → emitter scale
```

------------------------------------------------------------------------

# 10. Fix 2 - Untouched Virtual Dimmer Must Default to 100%

## 10.1 Current semantic mismatch

Pass 2 output resolution correctly treats missing virtual intensity as:

``` text
1.0
```

which means:

``` text
100%
```

This is correct.

However, the Color UI draft currently falls back to something equivalent
to:

``` swift
presentation.dimmer.displayValue ?? 0
```

This can create:

``` text
actual effective virtual intensity = 100%
displayed DIMMER                 = 0%
```

on an untouched RGB-only fixture.

This is dangerous and visually dishonest.

------------------------------------------------------------------------

# 11. Required Virtual Intensity Default

For a fixture whose intensity mode is:

``` text
virtual emitter scale
```

an untouched/unowned intensity value must semantically resolve to:

``` text
100%
```

because 100% is the neutral multiplier.

The UI should therefore show:

``` text
DIMMER 100%
```

until the operator changes it.

------------------------------------------------------------------------

# 12. Physical vs Virtual Untouched State

Do not blindly change every unset physical intensity to 100% unless that
matches Aurora's existing Programmer semantics.

The presentation layer should know the effective intensity mode.

Conceptually:

``` swift
enum EffectiveIntensityMode {
    case physical(attribute: String)
    case virtualEmitterScale
    case unsupported
}
```

Then presentation can distinguish:

``` text
physical dimmer unset
→ preserve existing Aurora physical-intensity presentation semantics

virtual dimmer unset
→ effective/display value = 1.0
```

The exact representation can differ, but the distinction must exist
somewhere authoritative.

------------------------------------------------------------------------

# 13. Do Not Destructively Materialize 100% Unless Necessary

Preferred behavior:

``` text
virtual intensity absent from Programmer look
→ resolver interprets it as 1.0
→ UI displays effective 100%
```

Do not necessarily write:

``` text
intensity = 1.0
```

into every RGB fixture merely because it was selected.

Selection alone should not dirty the project or create Programmer
ownership if avoidable.

The UI can display an effective default without materializing an
authored value.

------------------------------------------------------------------------

# 14. First Interaction Must Be Continuous

Critical manual test:

``` text
untouched RGB-only fixture
output effectively 100%
DIMMER visually 100%

drag DIMMER slightly down to 95%
→ output moves smoothly from 100% to 95%
```

There must be no jump from:

``` text
100% physical output
```

to:

``` text
5% or some unrelated value
```

because the fader visually began at zero.

------------------------------------------------------------------------

# 15. Mixed Physical and Virtual Intensity Defaults

Selection:

``` text
Fixture A:
physical dimmer = 100%

Fixture B:
virtual intensity unset, effective 100%
```

Presentation should resolve this as:

``` text
common intensity = 100%
```

not mixed merely because one fixture explicitly stores 1.0 and the other
derives its neutral 1.0 virtually.

Compare **effective semantic values** where appropriate.

------------------------------------------------------------------------

# 16. Fix 3 - Complete Color Draft Resynchronization Identity

## 16.1 Current problem

`ProgrammerColorEngineView` uses a presentation identity to decide when
local SwiftUI draft state must be rebuilt.

Pass 2 identity includes some relevant state, such as:

-   fixture IDs,
-   Hue,
-   Dimmer,
-   emitter values,
-   mixed RGB state.

But it does not include all first-class authoring state.

Missing fields include:

``` text
colorSat
colorVal
colorWB
```

Therefore an external state change can occur without triggering a draft
rebuild.

------------------------------------------------------------------------

# 17. Example Failure

Current fixture selection remains unchanged.

External operation:

``` text
recall Color Palette
```

changes:

``` text
Hue = 220°     remains 220°
Saturation     changes
Brightness     changes
White Balance  changes
```

If the presentation identity only notices Hue and selection, SwiftUI
local drafts may remain stale.

The physical output can be correct while the wheel/ring shows old
values.

That breaks the central requirement:

> The Programmer must faithfully show how the current look was authored.

------------------------------------------------------------------------

# 18. Required Identity Coverage

At minimum, draft resynchronization must respond to changes in:

``` text
fixture selection identity
Hue
Saturation
Brightness / Value
White Balance
Dimmer
dedicated emitter values
mixed/unset state
partial capability state where it affects presentation
```

If continuing with a computed identity, include all of those.

------------------------------------------------------------------------

# 19. Preferred Longer-Term Approach

A cleaner approach may be to expose an explicit:

``` text
ProgrammerColorPresentation.revision
```

or stable semantic identity from the presentation store.

Then:

``` text
presentation revision changes
→ rebuild drafts
```

The revision must change only when state relevant to the Color Engine
changes.

Do not use a broad global app revision if that causes needless rebuilds.

This is preferred if it fits the current architecture cleanly.

------------------------------------------------------------------------

# 20. Avoid Draft Feedback Loops

The Color Engine still needs smooth local drag behavior.

Do not implement synchronization such that:

``` text
pointer sample
→ local draft changes
→ Programmer publishes
→ presentation refresh
→ draft rebuilt from model
→ gesture fights itself
```

Use the existing interaction/edit-session mechanism if one exists.

A useful policy is:

``` text
during active local drag:
    local draft is immediate interaction authority

external semantic change:
    resync when safe / when presentation revision changes outside same edit
```

Keep this simple and deterministic.

------------------------------------------------------------------------

# 21. Required External-Change Tests

With the same fixture selected:

1.  Set Hue/Sat/Val/WB.
2.  Recall a palette that changes only Saturation.
3.  Verify saturation thumb moves.
4.  Recall one that changes only Brightness.
5.  Verify brightness marker moves.
6.  Recall one that changes only WB.
7.  Verify WB marker moves.

Also test external changes from another production entry point if easy,
such as:

``` text
cue recall
remote command
Programmer command
```

The UI must not require changing selection to catch up.

------------------------------------------------------------------------

# 22. Fix 4 - Gate Soft Color Authoring Metadata by RGB Authoring Capability

## 22.1 Current problem

Color Palette filtering now allows:

``` text
colorHue
colorSat
colorVal
colorWB
```

through as soft authoring metadata.

That is correct for RGB-capable fixtures.

However, if these keys bypass capability filtering unconditionally,
Aurora can apply H/S/V/WB authoring metadata to a fixture that has no
meaningful RGB color-wheel capability.

Example:

``` text
dimmer-only conventional fixture
+
Color Palette containing H/S/V/WB
```

Aurora can end up writing meaningless soft color state and reporting a
palette application even though the fixture cannot produce that color.

------------------------------------------------------------------------

# 23. Define RGB Authoring Capability

Create/use one semantic test:

``` text
supportsRGBColorAuthoring
```

A fixture supports RGB authoring if Aurora can meaningfully resolve the
H/S/V/WB model into physical color output.

Typically:

``` text
physical Red + Green + Blue emitters available
```

or another explicitly supported color engine.

Do not assume:

``` text
any attribute beginning with "color"
```

means RGB authoring is valid.

A fixture with only:

``` text
White
```

or:

``` text
Amber
```

does not automatically support the RGB wheel.

------------------------------------------------------------------------

# 24. Palette Filtering Rule

For Color Palette application:

### Soft authoring attributes

``` text
colorHue
colorSat
colorVal
colorWB
```

apply only when:

``` text
target fixture supports RGB authoring
```

### Physical emitter attributes

``` text
colorR
colorG
colorB
colorW
colorA
colorUV
...
```

apply only when the target supports that physical emitter.

This preserves partial-capability behavior.

------------------------------------------------------------------------

# 25. Example Mixed Palette Application

Palette contains:

``` text
H/S/V/WB
White
Amber
UV
```

Selection:

``` text
Fixture A = RGBWA+UV
Fixture B = RGBW
Fixture C = White-only conventional LED
```

Expected:

### Fixture A

``` text
H/S/V/WB ✓
White ✓
Amber ✓
UV ✓
```

### Fixture B

``` text
H/S/V/WB ✓
White ✓
Amber ignored
UV ignored
```

### Fixture C

``` text
H/S/V/WB ignored
White ✓ if semantic White emitter is supported
Amber ignored
UV ignored
```

No meaningless RGB authoring metadata should be written to Fixture C.

------------------------------------------------------------------------

# 26. Palette Apply Result Reporting

If Aurora reports:

``` text
applied
partial
unsupported
```

for palette application, make sure soft metadata does not falsely make
an otherwise unsupported Color Palette look successfully applied.

Use the same capability-aware result semantics as physical attributes.

------------------------------------------------------------------------

# 27. Fix 5 - Perform the Required High-Frequency UI Performance Acceptance

This is an acceptance gate, not necessarily a large code change.

The Post-C6 hardening pass explicitly identified Programmer interaction
as a future high-frequency invalidation risk.

Pass 2 improves some local behavior, but the observable chain still
appears capable of propagating:

``` text
ProgrammerPresentationStore.objectWillChange
→ AppModel.objectWillChange
```

at wheel-drag frequency.

That may invalidate much more of the shell than necessary.

------------------------------------------------------------------------

# 28. Instrument the Production App

In a DEBUG-only build, measure during continuous Color manipulation:

``` text
AppModel.objectWillChange rate
ProgrammerPresentationStore.objectWillChange rate
ProgrammerColorEngineView refresh/rebuild rate
ProgrammerPanel body evaluations
BuildWorkspaceHost body evaluations
StageCanvasView body evaluations
Fixture Browser body evaluations if practical
Inspector body evaluations if practical
```

Do not ship permanent noisy logging.

Use signposts/counters or another lightweight debug mechanism.

------------------------------------------------------------------------

# 29. Required Interaction Tests

Measure at least:

``` text
10-second Hue drag
10-second Saturation drag
10-second Brightness drag
10-second White Balance drag
10-second DIMMER drag
10-second dedicated emitter fader drag
```

Run with:

``` text
Stage Preview visible
normal docked Programmer
```

and:

``` text
floating Programmer on a second display
Stage visible in main window
```

if multi-monitor hardware is available.

------------------------------------------------------------------------

# 30. Performance Acceptance Standard

The primary standard is user-visible behavior:

-   pointer tracking is smooth,
-   fixture output updates live,
-   Stage Preview updates live,
-   no obvious shell hitching,
-   Browser does not flicker,
-   Inspector does not visibly churn,
-   floating Programmer remains responsive,
-   CPU usage is reasonable for continuous manipulation.

If instrumentation shows broad shell invalidation at every pointer
sample but the app remains smooth, record the numbers.

If it is excessive or produces measurable UI cost, localize the
observation path before acceptance.

------------------------------------------------------------------------

# 31. Preferred Observation Architecture

The desired high-frequency path remains:

``` text
Color pointer sample
    ↓
Programmer mutation
    ↓
Color value presentation
    ↓
Color Engine UI + Stage/output
```

Unrelated surfaces should not require full semantic recomputation for
each sample.

Stable capability information such as:

``` text
supports White
supports Amber
supports UV
physical vs virtual intensity mode
partial capability
```

does not change because Hue moved by 1 degree.

Keep capability resolution out of the hottest path where practical.

------------------------------------------------------------------------

# 32. Automated Test - Effective Virtual Intensity Capability

Fixture:

``` text
RGB
no physical dimmer
```

Assert:

``` text
effective intensity capability = supported
```

Raw physical capability may still correctly report:

``` text
no physical dimmer
```

These are distinct questions.

------------------------------------------------------------------------

# 33. Automated Test - Intensity Tab Virtual Fixture

For an RGB-only fixture:

``` text
Intensity tab set intensity = 0.4
```

Expected Programmer state:

``` text
intensity = 0.4
```

Expected physical output:

``` text
all light-producing RGB emitters × 0.4
```

Expected Color tab:

``` text
DIMMER = 40%
```

------------------------------------------------------------------------

# 34. Automated Test - Untouched Virtual Dimmer

Fixture:

``` text
RGB
no physical dimmer
no authored intensity value
```

Expected:

``` text
effective intensity = 1.0
display DIMMER = 100%
output scale = 1.0
```

Selecting the fixture must not need to write an explicit
`intensity = 1.0` merely to display correctly.

------------------------------------------------------------------------

# 35. Automated Test - First Virtual Dimmer Move

Starting from untouched virtual intensity:

``` text
effective = 1.0
```

Set:

``` text
intensity = 0.95
```

Expected:

``` text
output changes continuously to 95%
```

No zero-based jump.

------------------------------------------------------------------------

# 36. Automated Test - Mixed Physical/Virtual Effective Value

Fixture A:

``` text
physical intensity = 1.0
```

Fixture B:

``` text
virtual intensity absent
effective = 1.0
```

Expected presentation:

``` text
common intensity = 1.0
not mixed
```

Then set 0.5 and verify:

``` text
A physical dimmer = 0.5
B virtual emitter scale = 0.5
```

------------------------------------------------------------------------

# 37. Automated Test - Fan/Align Effective Intensity

Use a selection containing:

``` text
physical-dimmer fixture
virtual-dimmer RGB fixture
```

Run supported intensity Fan/Align operations.

Verify both participate.

This test is important because it catches Color-tab-only special casing.

------------------------------------------------------------------------

# 38. Automated Test - Draft Resync Saturation

Same selection, external presentation update:

``` text
Hue unchanged
Saturation changes
```

Expected:

``` text
Color Engine saturation draft/marker updates
```

------------------------------------------------------------------------

# 39. Automated Test - Draft Resync Brightness

Same selection:

``` text
Hue unchanged
Brightness changes
```

Expected:

``` text
brightness ring updates
```

------------------------------------------------------------------------

# 40. Automated Test - Draft Resync White Balance

Same selection:

``` text
Hue unchanged
WB changes
```

Expected:

``` text
WB ring marker updates
```

------------------------------------------------------------------------

# 41. Automated Test - Palette Metadata Capability Gate

Fixture:

``` text
no RGB capability
```

Palette:

``` text
colorHue
colorSat
colorVal
colorWB
```

Expected:

``` text
soft authoring metadata is not applied
```

Add cases for:

``` text
RGB fixture → metadata applies
RGBW fixture → metadata applies
White-only fixture → metadata does not apply
```

------------------------------------------------------------------------

# 42. Regression Tests From Pass 1 Must Remain

Do not lose existing coverage for:

-   saturation annulus endpoints,
-   WB value/angle round-trip,
-   deterministic draft reset,
-   mixed preview,
-   RGBWA+UV palette round-trip,
-   importer specificity,
-   Global Master not mutating soft authoring state,
-   virtual dimmer RGB scaling,
-   virtual dimmer RGBWA+UV scaling,
-   physical dimmer no double scaling,
-   mixed physical/virtual output,
-   docked/floating Programmer reuse.

------------------------------------------------------------------------

# 43. Manual Acceptance - RGB-Only Fixture

Use a real or synthetic RGB fixture with no physical dimmer.

Verify:

-   [ ] Color tab shows DIMMER.
-   [ ] Initial DIMMER reads 100%.
-   [ ] Fixture is full authored brightness at 100%.
-   [ ] Drag DIMMER to 50%.
-   [ ] Fixture fades smoothly.
-   [ ] RGB wheel position does not change.
-   [ ] Switch to Intensity tab.
-   [ ] Intensity reads 50%.
-   [ ] Change to 25%.
-   [ ] Switch back to Color.
-   [ ] DIMMER reads 25%.
-   [ ] Restore 100%.
-   [ ] Original authored RGB color returns exactly.

This is the key virtual-dimmer acceptance test.

------------------------------------------------------------------------

# 44. Manual Acceptance - Mixed Physical and Virtual Fixtures

Select:

``` text
moving head with physical dimmer
+
RGB PAR without physical dimmer
```

Verify:

-   [ ] one coherent intensity value is presented,
-   [ ] DIMMER changes both,
-   [ ] physical fixture uses real dimmer,
-   [ ] RGB PAR scales emitters,
-   [ ] no double dimming,
-   [ ] Fan/Align intensity operations include both where applicable.

------------------------------------------------------------------------

# 45. Manual Acceptance - External Palette Resync

Keep fixture selection unchanged.

Recall palettes that independently change:

``` text
Saturation
Brightness
White Balance
```

Verify the visible wheel/ring state changes immediately.

No selection toggle should be required to refresh the UI.

------------------------------------------------------------------------

# 46. Manual Acceptance - Non-RGB Palette Target

Select a fixture without RGB color-wheel capability.

Apply a Color Palette containing H/S/V/WB metadata.

Verify:

-   [ ] Aurora does not write meaningless H/S/V/WB state,
-   [ ] supported dedicated emitter values may still apply,
-   [ ] apply-result status accurately reflects partial/unsupported
    behavior.

------------------------------------------------------------------------

# 47. Production Screenshot Evidence

After fixes, provide screenshots of the actual running Aurora
application showing:

1.  RGB-only fixture with virtual DIMMER at 100%.
2.  Same fixture at approximately 30-50%.
3.  Intensity tab showing the same semantic value.
4.  RGBWA+UV fixture in the approved Color layout.
5.  Non-neutral WB state.
6.  Mixed physical/virtual intensity selection if visually useful.
7.  Floating Programmer with live Stage visible.

The main RGBWA+UV screenshot should still be compared against:

``` text
Aurora_Programmer_Color_Reference.png
```

Do not visually redesign the approved wheel during this pass.

------------------------------------------------------------------------

# 48. Required Checkpoint Report

At completion, Grok should provide a concise but technical checkpoint
covering:

``` text
effective intensity capability architecture
all intensity entry points audited
virtual intensity default semantics
draft presentation identity/revision fix
palette soft-metadata capability gate
performance instrumentation method
measured invalidation counts/rates
automated test results
native build results
manual acceptance results
production screenshots
```

Also list every production file modified.

------------------------------------------------------------------------

# 49. Native Build Gate

Run Aurora's canonical macOS validation, including at minimum:

``` text
swift test
swift build --target Aurora
xcodebuild -scheme Aurora -configuration Debug build
```

or the repository's current equivalent.

Run any app-target/Xcode tests required for SwiftUI/AppKit behavior.

No Color Engine acceptance based solely on package tests.

------------------------------------------------------------------------

# 50. Final Acceptance Criteria

The Color Engine can be accepted when all of the following are true:

-   [ ] virtual intensity is a global semantic capability,
-   [ ] Color and Intensity tabs edit the same intensity value,
-   [ ] Fan/Align do not exclude virtual-dimmer fixtures,
-   [ ] untouched virtual Dimmer displays 100%,
-   [ ] first Dimmer movement is continuous from 100%,
-   [ ] mixed explicit/implicit 100% intensity resolves coherently,
-   [ ] Saturation external changes resync,
-   [ ] Brightness external changes resync,
-   [ ] WB external changes resync,
-   [ ] soft H/S/V/WB palette metadata is gated by RGB authoring
    capability,
-   [ ] dedicated physical emitters retain partial-capability behavior,
-   [ ] all Pass 1 regression tests still pass,
-   [ ] Color interaction remains smooth under production
    instrumentation,
-   [ ] docked and floating Programmer remain identical,
-   [ ] native tests/build pass,
-   [ ] production screenshots remain visually faithful to the approved
    reference.

------------------------------------------------------------------------

# 51. STOP CONDITION

After these fixes:

> **STOP and return the Color Engine final checkpoint for human review.
> Do not begin Advanced MIDI Engine implementation.**

The expected next step is final Color Engine acceptance.

Only after explicit approval should Aurora move into the Advanced MIDI
Engine.

------------------------------------------------------------------------

# 52. Product Principle

The operator should be able to think in lighting concepts, not fixture
implementation details.

For intensity, Aurora's contract is simply:

``` text
DIMMER means "make this fixture brighter or darker."
```

If the fixture manufacturer gave Aurora a physical dimmer channel, use
it.

If the fixture is an RGB PAR with nothing but emitter channels,
synthesize the same behavior by scaling those emitters.

That distinction belongs inside Aurora.

It should never leak into the operator's workflow.
