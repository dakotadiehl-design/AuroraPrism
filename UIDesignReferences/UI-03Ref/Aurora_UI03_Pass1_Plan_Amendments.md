# UI-03 Pass 1 Closeout Plan — ChatGPT Amendments

## Status

**Plan verdict:** Approved with four targeted amendments.

The existing Grok implementation plan is sound and should remain the basis for UI-03 Pass 2. These amendments are intended to tighten semantics, UX truthfulness, test coverage, and implementation scope. They are **not** a redesign of UI-03 and should not expand into UI-04 or a broader AppModel/observation rewrite.

---

## Amendment 1 — Prefer a Display-State Enum for Indeterminate Controls

### Applies to
- CR-01 — Mixed indeterminate UI
- `AuroraFader`
- `AuroraPositionPad`
- HSV/color controls
- Technical-color faders

### Recommendation

Prefer a small semantic display-state enum rather than accumulating independent boolean flags such as `isMixed`.

Suggested shape:

```swift
enum AuroraControlDisplayValue: Equatable {
    case value(Double)
    case mixed
    case unavailable
}
```

Exact naming is flexible.

### Rationale

Mixed, unavailable, and concrete values are mutually meaningful display states. Encoding them explicitly:

- prevents contradictory combinations of flags;
- gives Aurora a reusable vocabulary across Programmer controls;
- makes control rendering more truthful and easier to test;
- leaves a clean seam for future control states without multiplying booleans.

The control's display state must remain separate from its mutation behavior. A `.mixed` control is still interactive.

### Required behavior

```text
.value(x)
  -> render the actual numeric position/value

.mixed
  -> render an indeterminate state
  -> do not imply a concrete owned numeric value
  -> first intentional interaction writes a common value

.unavailable
  -> render the control/axis as unavailable
  -> do not allow writes for that unsupported capability
```

### Scope guard

Do **not** turn this into a general UI state framework. A small reusable enum for Programmer controls is sufficient for UI-03.

---

## Amendment 2 — Make Pan-Only / Tilt-Only Truthful Visually, Not Just Behaviorally

### Applies to
- CR-03 — Position pad axis capability
- `AuroraPositionPad`
- `ProgrammerPanel`

The proposed interaction behavior is correct:

```text
Pan only  -> horizontal mutation only
Tilt only -> vertical mutation only
Both      -> normal XY mutation
```

However, the pad must also communicate this visually.

### Recommendation

For a Pan-only selection:

- emphasize the horizontal axis;
- clearly mute/remove the semantic meaning of the vertical axis;
- ignore vertical movement;
- do not present a normal-looking 2D target that merely happens to reject vertical writes.

For a Tilt-only selection:

- emphasize the vertical axis;
- clearly mute/remove the semantic meaning of the horizontal axis;
- ignore horizontal movement.

For Pan + Tilt:

- retain the full 2D position-pad presentation.

For an unsupported axis:

- make the axis look intentionally unavailable rather than simply dim or frozen at an arbitrary coordinate.

For a mixed supported axis:

- render that axis indeterminately until the first intentional movement establishes a common Programmer value.

### Acceptance addition

```text
[ ] Pan-only pad visually reads as a one-axis horizontal control
[ ] Tilt-only pad visually reads as a one-axis vertical control
[ ] Unsupported axis never appears to contain a meaningful numeric position
[ ] Both-supported selection retains normal 2D pad semantics
```

### Rationale

UI-03's central requirement is that the Programmer visually and semantically tells the truth. Behavioral filtering alone is insufficient if the control still visually implies two usable dimensions.

---

## Amendment 3 — Add Explicit Mixed → Interaction → Common Tests

### Applies to
- CR-01
- CR-05
- CR-06 / CR-07 test work

The existing proposed resolver tests correctly prove how mixed state is *detected*. Add focused tests proving how mixed state is *resolved by user interaction*.

### Required intensity test

Initial state:

```text
Fixture A intensity = 0.25
Fixture B intensity = 0.75

Resolved presentation:
intensity = mixed
```

Simulate/apply the equivalent of the user's first intentional intensity movement to `0.60`.

Expected:

```text
Fixture A intensity = 0.60
Fixture B intensity = 0.60

Resolved presentation:
intensity = common(0.60)
```

### Required RGB/color test

Create two RGB-capable fixtures with differing Programmer-owned RGB values.

Expected initial state:

```text
composite RGB display = mixed
```

Apply one color-wheel interaction using the new batched mutation path.

Verify:

```text
[ ] all capable fixtures receive the intended RGB values
[ ] the write occurs through one logical batch operation
[ ] one logical presentation refresh occurs for the event
[ ] subsequent presentation resolves to the expected common color
```

If RGBW fixtures participate, verify W behavior according to the existing UI-03 color semantics rather than inventing new RGBW conversion rules in this pass.

### Optional useful extension

Where practical, add the same semantic test for position:

```text
mixed Pan -> first horizontal movement -> common Pan
mixed Tilt -> first vertical movement -> common Tilt
```

### Rationale

Resolver tests alone prove:

```text
Programmer data -> presentation
```

These tests close the loop:

```text
mixed Programmer data
        ↓
mixed presentation
        ↓
user interaction
        ↓
batched Programmer mutation
        ↓
common presentation
```

That is the actual user-facing UI-03 contract.

---

## Amendment 4 — Keep Observation Cleanup Conservative in Pass 2

### Applies to
- CR-05 — Batch mutation + observation
- `ProgrammerPresentationStore`
- Programmer/AppModel notification path

Proceed with the important batching work:

```swift
public func setMany(_ values: [UUID: [String: Double]])
```

and use one logical mutation for multi-channel operations such as HSV/RGB changes.

Also remove clearly redundant manual `objectWillChange.send()` calls when `@Published` assignment already provides the required notification.

### Do not over-expand this work

Do **not** use UI-03 Pass 2 as an opportunity to redesign AppModel observation or aggressively remove `revision` unless its redundancy is proven by the implementation and tests.

The preferred order is:

```text
1. Batch multi-fixture/multi-attribute writes.
2. Ensure one presentation refresh per logical gesture event.
3. Remove obviously redundant duplicate notifications.
4. Preserve revision/draft synchronization if it is still serving a clear purpose.
5. Defer broader AppModel observation architecture changes.
```

If `revision` is genuinely unnecessary after the change and removal is trivial and well-covered, it may be removed. Otherwise, retain it for UI-03 closeout.

### Performance acceptance addition

During the approximately 80-fixture continuous color-wheel test, verify:

```text
[ ] one logical Programmer batch per gesture event
[ ] one logical presentation refresh per gesture event
[ ] no visible wheel/thumb lag
[ ] no obvious UI stutter
[ ] no repeated console-warning storm
[ ] no runaway CPU behavior that persists after the gesture ends
```

Formal performance instrumentation is **not required** for UI-03. This is a functional/manual sanity check that the batching change produces the intended behavior.

---

## Additional Scope Guard — Do Not Over-Generalize `setMany`

The proposed API:

```swift
public func setMany(_ values: [UUID: [String: Double]])
```

is acceptable for UI-03.

Do not expand this pass into designing a generalized typed mutation/transaction framework unless an implementation blocker genuinely requires it.

A future Aurora engine phase may reasonably introduce concepts such as:

```text
ProgrammerMutation
FixtureAttributeMutation
ProgrammerTransaction
```

but UI-03 only needs a clear and efficient batched mutation seam.

Use the simplest implementation that satisfies the current semantics.

---

## Updated UI-03 Pass 2 Acceptance Additions

Add these items to the existing closeout checklist:

```text
[ ] Programmer controls use an explicit semantic display state where practical
[ ] Mixed controls do not imply a concrete owned numeric value
[ ] First intentional interaction from mixed establishes a common value
[ ] Pan-only position control is visually and behaviorally horizontal-only
[ ] Tilt-only position control is visually and behaviorally vertical-only
[ ] Unsupported position axes do not display fake meaningful coordinates
[ ] Explicit test covers mixed intensity -> interaction -> common intensity
[ ] Explicit test covers mixed RGB -> batched interaction -> common RGB
[ ] Multi-channel color interaction uses one logical Programmer mutation
[ ] Approximately 80-fixture continuous color drag remains visually responsive
[ ] Observation cleanup remains local to the Programmer path
[ ] No broad AppModel observation rewrite is introduced
[ ] No unnecessary generalized transaction framework is introduced
```

---

## Implementation Direction

Proceed with the original UI-03 Pass 1 Closeout Implementation Plan, incorporating these four amendments.

The desired Pass 2 remains:

1. Fix CR-01 through CR-05.
2. Complete CR-06 through CR-13 as planned.
3. Incorporate the amendments in this document.
4. Run the focused tests.
5. Run full `swift test` on macOS.
6. Build/run Xcode Debug.
7. Complete the manual visual/performance checklist.
8. Produce **UI-03 Pass 2** for final code review.
9. **Stop after UI-03 Pass 2. Do not begin UI-04 until explicitly requested.**

No redesign of the existing dual-axis presentation model, ordered selection model, Fan center/spread behavior, or ProgrammerPresentationStore-as-projection architecture is requested.

## Final Gate

These amendments do not change the previous assessment of the implementation plan:

**APPROVED TO IMPLEMENT WITH AMENDMENTS.**

The objective remains simple: after Pass 2, the Aurora Programmer should tell the truth both **semantically** and **visually**, while maintaining a clean and efficient mutation/refresh path.
