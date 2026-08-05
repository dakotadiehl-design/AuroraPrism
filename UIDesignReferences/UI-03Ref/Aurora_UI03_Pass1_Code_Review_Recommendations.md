# Aurora UI-03 Pass 1 — Deep Code Review Recommendations

**Review date:** 2026-08-05  
**Reviewed artifact:** `Aurora_UI03_pass 1.zip`  
**Phase:** UI-03 — Fixture Browser + Programmer  
**Overall verdict:** **Strong pass, but do not close UI-03 yet.** The architecture and core semantics are mostly correct. Address the P1 items below, add the focused regression tests, then perform the macOS/Xcode verification pass. No redesign is required.

---

## Executive Summary

UI-03 has landed in the right architectural neighborhood. The new Programmer presentation projection is separated from engine truth, selection order is preserved, support and value state are correctly modeled as orthogonal concepts, Fan uses deterministic ordered center/spread semantics, Group selection now preserves fixture order, and Programmer mutations from palettes/MIDI/local tools have an explicit presentation refresh path.

The remaining problems are concentrated at the UI boundary:

1. **MIXED state is logically correct but still visually displays an arbitrary numeric control position.** This violates the core UI-03 requirement that mixed values never masquerade as a single fixture value.
2. **Align to First silently substitutes zero when the first capable fixture is untouched.** That can convert an unset reference into an unintended blackout / zero-position write.
3. **The Position pad cannot truthfully represent one-axis capability.** If only Pan or only Tilt is supported, the pad still appears two-dimensional and allows dragging the unsupported axis even though that write is discarded.
4. **The HSV color wheel appears for technical-color-only selections where it cannot actually write anything.** Example: Amber/UV/CMY-only capability can make `hasColor == true`, but the wheel only emits RGB(/W).
5. **High-rate Programmer edits trigger too many broad UI invalidations.** Color-wheel movement is particularly expensive because one gesture can perform 3–4 independent `applyCommon` operations, and every one refreshes the presentation and broadly invalidates `AppModel`.

These are fixable without changing the overall UI-03 design.

---

# P1 — Required Before UI-03 Closeout

## UI03-CR-01 — Mixed controls must not render a fake numeric value

### Problem

The presentation resolver correctly returns `.mixed`, but the controls still render their draft numeric state:

- `ProgrammerPanel.swift` intensity keeps the prior `draftIntensity` when state becomes mixed.
- `AuroraFader` always renders the numeric percentage and physical thumb position from its bound value.
- Pan/Tilt keep prior draft values when mixed, so `AuroraPositionPad` renders a concrete crosshair and degree readout.
- Technical color channels fall back to `draftRGB[attr] ?? state.displayValue ?? 0`, so a mixed channel can visually land at zero or a stale prior draft.
- HSV mixed color can retain the previous/default wheel thumb even though the composite state says mixed.

The label/chrome says MIXED, but the physical control says “this is the value.” That is exactly the ambiguity UI-03 was intended to eliminate.

### Required change

Add an explicit indeterminate/mixed visual mode to the relevant controls instead of encoding mixedness only in nearby labels.

Recommended direction:

```swift
AuroraFader(
    value: ...,
    displayState: .mixed   // or optional displayValue == nil
)
```

For mixed state:

- Show `MIXED` instead of a percentage.
- Do not position the thumb as though a real common value exists, or render the thumb using a clearly indeterminate treatment.
- First intentional drag establishes the new common value exactly as the current implementation already does.

For position:

- The pad should show an indeterminate crosshair/axis when Pan and/or Tilt are mixed.
- Do not display stale degree readouts as truth.

For HSV:

- Mixed RGB should not display a normal concrete wheel thumb derived from stale/default draft state.
- First intentional wheel interaction should establish a common RGB value.

### Acceptance tests

Add UI/component-level tests where practical, plus resolver-to-control behavior verification:

```text
mixed intensity -> control visibly indeterminate, not 0/previous value
mixed pan -> pan axis visibly indeterminate
mixed tilt -> tilt axis visibly indeterminate
mixed RGB -> color control visibly indeterminate
first drag from mixed -> all capable fixtures become common(newValue)
```

---

## UI03-CR-02 — Align to First must not invent 0 for an untouched reference

### Problem

Current code:

```swift
values[id] = snap.values[id]?[attribute] ?? 0
```

and:

```swift
let ref = values[first] ?? 0
```

Therefore:

```text
Fixture 1 capable, Programmer value untouched
Fixture 2 capable, Programmer value = 72%
Align to First
```

becomes:

```text
Fixture 1 = 0%
Fixture 2 = 0%
```

That zero is not the first fixture's Programmer value. It is a fabricated fallback.

This conflicts with the UI-03 truthfulness rules and makes Align capable of unexpectedly blacking out intensity or slamming pan/tilt to the normalized minimum.

### Required change

Choose and document one truthful behavior. Recommended v1 behavior:

**Disable / no-op Align when the first capable reference has no Programmer-owned value.**

That keeps Align firmly inside the Programmer layer and avoids unexpectedly reading playback/tracked values that UI-03 does not yet model.

Suggested API:

```swift
public static func alignToFirst(
    fixtureIDs: [UUID],
    values: [UUID: Double]
) -> [UUID: Double]? {
    guard let first = fixtureIDs.first,
          let ref = values[first]
    else { return nil }
    return align(fixtureIDs: fixtureIDs, value: ref)
}
```

UI behavior:

```text
no capable fixture -> Align disabled
first capable fixture untouched -> Align disabled (or explicit no-op)
first capable fixture owned -> Align enabled
```

If Aurora later gains effective/tracked-value presentation, Align could intentionally align to the effective output value, but that should be a separate semantic decision.

### Required tests

Add:

```text
first capable has value -> all capable align to it
first selected unsupported, second capable has value -> second becomes valid reference
first capable untouched -> no fabricated zero write
unsupported fixtures remain untouched
```

---

## UI03-CR-03 — Position pad must support Pan-only and Tilt-only selections truthfully

### Problem

`ProgrammerPanel` displays `AuroraPositionPad` whenever either Pan **or** Tilt is supported:

```swift
if pres.pan.isSupported || pres.tilt.isSupported {
    AuroraPositionPad(...)
}
```

But `AuroraPositionPad` always exposes both axes and writes both bindings during drag:

```swift
pan = ...
tilt = ...
```

The parent suppresses the unsupported engine write, but the unsupported axis still moves visually and its degree readout changes.

So a Pan-only fixture can present a draggable Tilt axis that appears functional even though it does nothing. This violates:

> Unsupported attributes do not appear functional.

### Required change

Teach `AuroraPositionPad` independent axis capability:

```swift
supportsPan: Bool
supportsTilt: Bool
panIsMixed: Bool
tiltIsMixed: Bool
```

Behavior:

- Pan-only: horizontal interaction only; Tilt indicator/readout visibly unavailable.
- Tilt-only: vertical interaction only; Pan indicator/readout visibly unavailable.
- Both: normal 2D pad.
- Mixed per axis: show that axis as indeterminate until first intentional movement.

Do not solve this merely by ignoring the unsupported binding in the parent. The visual control itself needs truthful affordances.

---

## UI03-CR-04 — Do not show an operative HSV wheel for non-RGB color capability

### Problem

`ProgrammerAttributePresentation.hasColor` is true if **any** known technical color attribute is supported:

```swift
colorR/colorG/colorB/colorW || !technicalColorAttributes.isEmpty
```

This means Amber, UV, Cyan/Magenta/Yellow, etc. can cause `colorControls` to appear.

But `applyHSV()` only produces RGB or RGBW:

```swift
ColorMath.programmerAttributes(from: rgb, includeWhite: includeW)
```

Then `applyCommon` filters to fixtures that support those RGB(/W) attributes.

For a technical-color-only selection, the HSV wheel can therefore be fully interactive while producing no meaningful fixture writes.

### Required change

Split the concepts:

```text
hasVisualRGBColorControl
hasTechnicalColor
```

Recommended presentation helpers:

```swift
var hasRGBColor: Bool {
    colorR.isSupported || colorG.isSupported || colorB.isSupported
}

var hasTechnicalColor: Bool {
    !technicalColorAttributes.isEmpty
}
```

Then:

- Show HSV wheel only when the selection has an RGB-capable mapping the wheel actually controls.
- Show Technical Color independently for W/A/UV/CMY/etc.
- Do not imply conversion support that Aurora has not actually implemented.

If CMY-to-RGB interaction is desired later, implement an explicit conversion/mapping policy rather than silently presenting a dead RGB wheel.

### Required tests

Add fixture personalities for:

```text
RGB only
RGBW
Amber/UV only
CMY only
mixed RGB + non-RGB color fixtures
```

Verify the visible control family and capable writes for each.

---

## UI03-CR-05 — Collapse high-rate color edits into one Programmer mutation / one presentation refresh

### Problem

`applyHSV()` currently does:

```swift
for (k, v) in attrs {
    applyCommon(attribute: k, value: v)
}
```

`applyCommon()` performs:

```text
capability-map rebuild
Programmer.setMany
onChanged()
```

and `onChanged()` maps to:

```text
refreshProgrammerPresentation()
notifyUI()
```

The presentation store itself is cascaded back into `AppModel.objectWillChange`.

Therefore a single color-wheel update can perform 3 or 4 complete refresh/invalidation cycles, and hue/saturation are two separate SwiftUI `onChange` sources during the same drag.

This is contrary to the UI-03 acceptance requirement:

> No high-rate broad SwiftUI invalidation introduced.

### Required change

Batch multi-attribute Programmer edits.

Preferred engine API:

```swift
func setMany(_ values: [UUID: [String: Double]])
```

or a Programmer transaction API that acquires the lock once and writes all selected fixture/channel values.

Then HSV interaction should:

1. Resolve capabilities once.
2. Build all RGB(/W) writes.
3. Mutate Programmer once.
4. Refresh Programmer presentation once.
5. Emit one UI invalidation.

Also review whether local Programmer controls need `AppModel.notifyUI()` at all after `ProgrammerPresentationStore` becomes the focused observation source. Broad AppModel invalidation should be reserved for surfaces that genuinely depend on the mutation.

### Additional cleanup in the same area

`ProgrammerPresentationStore.refresh()` uses `@Published` for both `presentation` and `revision`, **then manually calls**:

```swift
objectWillChange.send()
```

`@Published` already emits observation. The manual send creates redundant notifications and should be removed unless there is a documented reason.

Likewise, consider whether both `presentation` and `revision` need publishing. A single immutable presentation snapshot with stable identity/versioning may be enough.

### Verification

Instrument or log body/update counts during a continuous color-wheel drag over ~80 fixtures. Confirm there is one logical presentation refresh per gesture event, not 3–4+ broad cascades.

---

# P2 — Strongly Recommended

## UI03-CR-06 — Add missing mixed/partial resolver coverage

The resolver tests are a good start, but `testPartialCommonAndMixed()` never actually tests the mixed case. The second half resets exactly the same single-capable value and then does nothing:

```swift
prog.values = [fMH: ["pan": 0.3]]
_ = common
```

Add an actual second moving-head fixture so these cases are covered:

```text
partial support + two capable + same values -> partial/common
partial support + two capable + different values -> partial/mixed
partial support + one capable owned + one capable untouched -> partial/mixed
all support + some owned + some untouched -> all/mixed
```

That last case is especially important because `resolveAttribute` intentionally treats owned + untouched as mixed.

---

## UI03-CR-07 — Add integration tests for ordered selection -> Fan/Align

Geometry unit tests prove the math, and presentation tests prove support/value state, but there is still a seam between:

```text
SelectionManager orderedFixtureIDs
-> capableFixtureIDs
-> ProgrammerPanel operation
-> Programmer state
```

Add focused integration tests for:

```text
ordered selection [A,B,C] -> Fan maps phase A..C
ordered selection [C,B,A] -> Fan reverses result
unsupported fixture in middle -> capable order remains relative [A,C]
group fixtureIds order -> selection order -> fan order
Align skips unsupported leading fixture and uses first capable reference
```

This protects the core reason ordered selection was added.

---

## UI03-CR-08 — Remove dead technical-color resolver code

`ProgrammerAttributePresentationResolver.resolve()` contains a loop at roughly lines 119–129 that computes `st`, checks several conditions, but never mutates `tech` or produces any result. It is immediately replaced by the actual filter assignment below.

Delete the dead loop. It makes color capability logic look more complex than it is and creates uncertainty about intended W/extras behavior.

---

## UI03-CR-09 — Make capability lookup cheaper and less repetitive

`capabilityMap()` repeatedly does:

```swift
project.fixtures.first(where: { $0.id == id })
```

and resolution repeatedly scans attributes. At ~80 fixtures this is probably still acceptable, but UI-03 explicitly has a responsiveness requirement and these functions are called during interactive edits.

Recommended low-risk improvement:

- Build a local `[UUID: PatchedFixture]` dictionary once per resolve.
- Resolve the capability map once per UI operation and reuse it across all attributes.
- For HSV/batched operations, reuse the same capability map rather than recomputing it once per color channel.

This is not a reason to introduce a persistent cache yet. Keep it local and deterministic unless profiling proves otherwise.

---

## UI03-CR-10 — Clarify composite Color state semantics

`compositeColorState()` currently returns `.common(0)` whenever supported color parts are neither mixed nor all untouched:

```swift
if parts.contains(where: \.isMixed) { ... }
if parts.allSatisfy(\.isUntouched) { ... }
return ProgrammerAttributeState(support: support, value: .common(0))
```

That `.common(0)` is not a real common color value; it is a sentinel used only to obtain programmer-owned chrome.

Avoid putting fabricated data into a state type whose `.common(Double)` means a real value.

Recommended options:

- Introduce a separate family-level visual-state resolver.
- Or determine `AuroraAttributeVisualState` directly for the Color family without manufacturing `.common(0)`.

The existing code is visually serviceable, but semantically muddy and likely to become a trap when UI-04 adds palette/reference state.

---

## UI03-CR-11 — Consider replacing repeated project scans in view rendering

Several UI paths repeatedly do:

```swift
project.fixtures.first(where: { $0.id == id })
```

for selected-name strings, order strips, and fixture chips. With 80 fixtures this is still manageable, but these are recomputed during SwiftUI body updates.

A local fixture-name dictionary computed once per presentation/view pass would be cleaner and reduce incidental work during high-rate Programmer updates.

Do this only as a small cleanup. Do not introduce a heavyweight caching layer.

---

# P3 — Cleanup / Maintainability

## UI03-CR-12 — Remove unused parameters and temporary artifacts

Several functions accept `pres` but do not meaningfully use it, or retain temporary variables solely to silence warnings:

```swift
applyFan(_ pres: ...)
let first = capable.first
_ = first
```

Clean these up after behavior is corrected. The code will read more clearly when the semantic contract is visible from the function signature.

---

## UI03-CR-13 — Tighten comments around “projection only” observation

The new `ProgrammerPresentationStore` is conceptually good: it is a projection and not a second source of truth. Preserve that explicitly.

I recommend adding one short architectural comment stating:

```text
Programmer remains authoritative.
ProgrammerPresentationStore may be discarded/rebuilt at any time.
No edits are ever applied to the presentation snapshot itself.
```

This helps prevent UI-04/UI-05 from accidentally turning the store into mutable parallel state.

---

# What Looks Good and Should Be Preserved

These parts of UI-03 are aligned with the approved plan and should not be rewritten while fixing the above:

- `AttributeSupportState` and `ProgrammerValueState` are correctly orthogonal.
- Owned + untouched capable fixtures resolve to MIXED rather than pretending a common value exists.
- Capability filtering is based on fixture definitions, not guesses from Programmer values.
- Fan center/spread math is deterministic and selection-order dependent.
- Fan filters capable fixtures before applying geometry.
- Pan and Tilt are separate Fan families.
- Selection order is exposed in the Programmer and fixture browser.
- Group selection uses `selectFixturesOrdered(group.fixtureIds, extending: false)`.
- Clear Selection and Clear All are distinct operations.
- Technical color is derived from actually supported channel attributes.
- Palette mutation callbacks now refresh Programmer presentation.
- MIDI `.programmerAttribute` actions refresh Programmer presentation.
- Inspector now exposes Programmer-owned values for an inspected fixture.
- The new presentation store is a derived projection rather than replacing engine Programmer truth.

---

# macOS Verification Required

The review container is not macOS. `swift test` cannot complete here because the package imports Apple-only frameworks:

```text
CoreMIDI
Network
```

The failure observed during review is therefore environmental, not evidence of a UI-03 compile failure.

Before closeout, run on the development Mac:

```bash
swift test
```

and the Xcode Debug build used by the project workflow.

Then manually verify:

```text
1. Single fixture, untouched intensity/color/position
2. Multiple fixtures, common owned values
3. Multiple fixtures, genuinely mixed values
4. Owned + untouched capable fixtures -> MIXED
5. Partial capability selection
6. Pan-only personality
7. Tilt-only personality
8. RGB fixture
9. RGBW fixture
10. technical-color-only fixture (Amber/UV or CMY)
11. Fan forward/reverse order
12. Align with first capable owned
13. Align with first capable untouched
14. Clear selected vs Clear All
15. MIDI CC mutation refresh
16. Palette mutation refresh
17. ~80-fixture selection while continuously dragging intensity/position/color
```

Pay special attention to whether MIXED controls visually imply a value and whether color-wheel dragging causes noticeable UI churn.

---

# Recommended Closeout Order

1. **Fix mixed/indeterminate control rendering.**
2. **Fix Align-to-First untouched reference semantics.**
3. **Add independent Pan/Tilt capability to the position pad.**
4. **Separate RGB-wheel availability from technical color availability.**
5. **Batch HSV writes and remove redundant broad observation notifications.**
6. Add the missing resolver/integration tests.
7. Perform small resolver/view cleanup items.
8. Run full macOS SwiftPM + Xcode tests.
9. Perform the manual 80-fixture / mixed-capability visual pass.
10. Only then mark UI-03 complete and proceed to UI-04.

---

# Final Gate Recommendation

**UI-03 Pass 1: CONDITIONALLY ACCEPTED, CHANGES REQUIRED.**

This is a good implementation and the core design is sound. I do **not** recommend backing it out or restructuring the phase. Fix the five P1 items, add the targeted tests, verify on macOS, and UI-03 should be in strong shape for closeout.
