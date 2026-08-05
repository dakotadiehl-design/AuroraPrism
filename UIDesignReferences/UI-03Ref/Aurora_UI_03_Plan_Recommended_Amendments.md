# Aurora UI-03 --- Recommended Amendments to Fixture Browser + Programmer Plan

**Applies to:**
`UI-03 — Fixture Browser + Programmer — Implementation Plan`\
**Disposition:** **Approve with minor amendments before
implementation.**

The proposed UI-03 architecture, sequencing, scope boundaries, and
product direction are sound. These amendments are intended to remove
ambiguity around Fan/Align behavior, strengthen the Programmer
presentation contract, improve external synchronization, and make the
acceptance gate more representative of real show-programming use.

Do **not** redesign the UI-02 shell during this work.

------------------------------------------------------------------------

# 1. Lock Fan Semantics Before Coding

The current plan intentionally restores Fan, but its proposed v1
behavior is still ambiguous.

Do not leave the implementation to choose between unrelated
interpretations such as:

``` text
fan from 0...1
fan between current min/max
fan around a center
fan from first to last
```

Define Fan as a stable Aurora programming operation before implementing
the controls.

## Required principles

Fan must:

-   operate on `orderedFixtureIDs`
-   preserve deterministic fixture phase/order
-   operate only on fixtures supporting the active attribute
-   never invent unsupported attributes
-   treat Pan and Tilt as independent attributes
-   remain deterministic when fixture personalities differ

## Recommended v1 model

Represent Fan conceptually as:

``` text
center
+
spread
+
ordered selection
```

For fixture count `N`, calculate a normalized position across the
ordered selection and distribute the requested attribute around the
center.

Conceptually:

``` text
fixture 1     fixture 2     fixture 3     fixture 4     fixture 5

  -1            -0.5           0            +0.5           +1
   \______________ spread around center _________________/
```

This provides a foundation that can later support richer fan curves
without replacing the underlying concept.

## Mixed values

If the selected fixtures already contain meaningful values, Aurora may
derive an initial center/spread from them where unambiguous.

If the attribute is untouched, do **not** silently invent a `0...1`
range merely because no current value exists.

The UI should establish an intentional center/spread when the user
invokes Fan.

## Position

For Position Fan:

``` text
Pan  -> independent fan operation
Tilt -> independent fan operation
```

Do not implicitly couple them unless a later UI explicitly provides a 2D
position-fan tool.

------------------------------------------------------------------------

# 2. Make Align Semantics Explicit

If v1 Align means:

> set all capable selected fixtures to the first selected fixture's
> value

then say so in both implementation and UI semantics.

Prefer terminology such as:

``` text
Align to First
```

or an equivalent tooltip/help label.

The first fixture is determined by:

``` text
orderedFixtureIDs.first
```

not Set iteration or project fixture order.

## Required behavior

``` text
Fixture 1 = 40%
Fixture 2 = 72%
Fixture 3 = 10%

Align to First

Fixture 1 = 40%
Fixture 2 = 40%
Fixture 3 = 40%
```

Only capable fixtures are modified.

If the first selected fixture does not support the active attribute,
resolve the first **capable** fixture in ordered selection, or disable
Align if no valid reference exists.

Document the chosen rule and test it.

------------------------------------------------------------------------

# 3. Separate Capability Support From Value State

The proposed `AttributeSelectionState` is directionally correct, but
support and value ownership are independent dimensions.

Avoid creating an enum that eventually needs cases such as:

``` text
partialMixed
partialUntouched
partialCommon
allMixed
allCommon
...
```

Prefer two orthogonal concepts.

Example:

``` swift
enum AttributeSupportState: Equatable {
    case none
    case partial
    case all
}

enum ProgrammerValueState: Equatable {
    case untouched
    case common(Double)
    case mixed
}

struct ProgrammerAttributeState: Equatable {
    var support: AttributeSupportState
    var value: ProgrammerValueState
}
```

Then:

``` swift
struct ProgrammerAttributePresentation: Equatable {
    var orderedFixtureIDs: [UUID]

    var intensity: ProgrammerAttributeState

    var pan: ProgrammerAttributeState
    var tilt: ProgrammerAttributeState

    var colorR: ProgrammerAttributeState
    var colorG: ProgrammerAttributeState
    var colorB: ProgrammerAttributeState
    var colorW: ProgrammerAttributeState
}
```

Names may differ to fit the existing model.

The important requirement is:

> **Capability support and Programmer value state must not be
> conflated.**

This will make later palette/inherited/reference states substantially
easier to add.

------------------------------------------------------------------------

# 4. Define Mixed-Value Editing Behavior Explicitly

The plan correctly says Aurora must never show the first fixture's value
as if it represents a mixed selection.

Also define what happens when the operator edits a mixed control.

## Recommended behavior

For:

``` text
Fixture A = 20%
Fixture B = 50%
Fixture C = 80%
```

Programmer displays:

``` text
Intensity: MIXED
```

When the user intentionally moves the Intensity fader:

``` text
first intentional movement
    ↓
establishes a common value
    ↓
all capable selected fixtures receive that value
```

Example:

``` text
User drags to 63%

A = 63%
B = 63%
C = 63%

state -> programmerOwned/common(0.63)
```

Do not unexpectedly preserve relative offsets during an ordinary fader
drag.

Relative/offset editing can be a separate future interaction if desired.

The same principle should apply to other ordinary multi-edit controls
unless Fan or another explicit geometry operation is active.

------------------------------------------------------------------------

# 5. Prefer a Focused ProgrammerPresentationStore Over a Magic Epoch

The proposed epoch mechanism is acceptable as a fallback, but a focused
observable presentation store is preferred if it can be implemented
cleanly.

Conceptually:

``` text
Programmer
      ↓
ProgrammerPresentationStore
      ↓
ProgrammerPanel
```

The store can observe or be explicitly refreshed by Programmer mutation
sources such as:

``` text
local UI edits
MIDI
palette application
Locate
Home
Clear
Clear All
Fan
Align
future plugin/control inputs
```

The store should derive its presentation from:

``` text
Programmer snapshot
+
ordered selection
+
fixture definitions/capabilities
```

rather than becoming another source of Programmer truth.

## Rule

``` text
Programmer = source of truth
ProgrammerPresentationStore = observable projection
SwiftUI controls = presentation + temporary drag drafts
```

Avoid creating:

``` text
programmerEpoch += 1
```

calls throughout unrelated parts of the application unless the
focused-store approach proves disproportionately invasive.

------------------------------------------------------------------------

# 6. External Programmer Mutation Must Be a First-Class Acceptance Case

UI-03 must prove that the visible Programmer stays synchronized when
something other than the mouse changes Programmer state.

Required example:

``` text
1. Select fixture(s)
2. Programmer Intensity displays 25%
3. MIDI CC changes Programmer Intensity to 70%
4. Visible Aurora fader/readout changes to 70%
5. User did not reselect fixtures
```

Also verify refresh after:

``` text
palette apply
Locate
Home
Clear
Clear All
Fan
Align
```

The UI must not become a stale copy of engine state.

------------------------------------------------------------------------

# 7. Make Selection Order Inspectable When Fan Depends on It

Preserving `orderedFixtureIDs` internally is necessary but not always
sufficient.

If Fan produces different results based on fixture selection order, the
operator needs a way to understand that order.

Do not necessarily add permanent large order badges to every fixture
row.

Possible lightweight approaches:

``` text
Selection: 8 fixtures
Order: 1 → 2 → 3 → ... → 8
```

or temporary order indicators while Fan is active.

Another option is subtle numbered badges only for the selected fixtures
when a phase-sensitive tool is engaged.

## Requirement

> When Fan behavior depends on selection order, Aurora must provide a
> practical way for the operator to inspect that order.

The exact visual treatment can be chosen during implementation.

------------------------------------------------------------------------

# 8. Capability Badges in Fixture Browser Are Optional, Not Mandatory

The proposed Browser badges such as:

``` text
RGB
MH
DIMMER
```

may be useful, but they can also create visual clutter.

Treat C3 as conditional.

The Fixture Browser's primary responsibilities are:

``` text
find fixtures
understand fixture identity
select fixtures
understand selection
```

The Programmer is the primary place for detailed capability truth.

Add Browser capability badges only if they remain visually quiet and
improve fixture discrimination.

Do not sacrifice Browser scanability to expose every capability.

------------------------------------------------------------------------

# 9. Technical Color Controls Must Follow Real Fixture Attributes

Do not assume every color-capable fixture is RGBW.

The secondary technical color area should be generated from real
supported attributes.

Examples:

``` text
RGB fixture
    R G B

RGBW fixture
    R G B W

RGBA fixture
    R G B A

RGBWA+UV fixture
    R G B W A UV

CMY fixture
    C M Y

other personality
    only the attributes Aurora actually knows/supports
```

For UI-03, it is acceptable to support only the technical color models
currently represented by the backend.

But do not display a fake `W` fader merely because `colorW` exists in a
generic presentation structure.

Capability truth wins over visual symmetry.

------------------------------------------------------------------------

# 10. Strengthen the 80-Fixture Performance Acceptance

Do not test only:

``` text
80 identical fixtures
```

Use a representative mixed rig.

Suggested stress scenario:

``` text
80 selected fixtures

multiple fixture definitions
multiple personalities where supported
some intensity-only
some RGB/RGBW
some moving heads
mixed position capability
mixed color capability

Fixture Browser search/filter active

Programmer presentation recompute

fader interaction

Fan/Align operation
```

## Performance goal

A pure presentation resolver microbenchmark is useful, but the
product-level requirement is:

> **Programmer interaction remains perceptually immediate.**

In particular:

``` text
dragging Intensity
moving Position
changing color
selecting a large group
```

must not visibly hitch because Aurora is repeatedly rescanning
definitions or rebuilding the entire application shell.

Cache definition/capability information where appropriate.

Avoid O(n²) work in high-frequency interaction paths.

------------------------------------------------------------------------

# 11. Add a Programmer Visual Review Gate

UI-03 is the first phase where Aurora's visual system and real
programming semantics deeply intersect.

Add a screenshot/manual visual review before declaring UI-03 complete.

Required review states:

## A. Single fixture

Show:

``` text
normal capability presentation
owned vs untouched state
technical controls where appropriate
```

## B. Multi-fixture, same values

Show:

``` text
common value presentation
selection count
```

## C. Mixed values

Show:

``` text
mixed state
no fabricated first-fixture value
```

## D. Partial capability

Example:

``` text
moving head + dimmer + RGB fixture
```

Verify:

``` text
partial support is understandable
unsupported fixtures do not receive fake values
```

## E. Fan / Align

Show:

``` text
ordered selection
active attribute
resulting mixed/fanned state
```

## F. Large selection

Show approximately:

``` text
80 fixtures selected
```

Verify that the interface remains visually coherent and responsive.

The review is not another shell redesign.

It is a UI-03 quality gate.

------------------------------------------------------------------------

# 12. Preserve the Proposed Wave Structure

The implementation sequence is good and should remain approximately:

``` text
Wave A
Presentation contract
Ordered selection
Fan order semantics

        ↓

Wave B
Programmer truthfulness
Mixed state
External synchronization
Clear All
Fan
Align
Technical color

        ↓

Wave C
Fixture Browser depth
Selection summary
Large-selection behavior

        ↓

Wave D
Light Inspector / palette refresh integration

        ↓

Wave E
Tests
Performance verification
Visual review
Documentation
macOS build
```

Do not begin UI-04 or UI-05 opportunistically.

------------------------------------------------------------------------

# 13. Additional Tests

Add or strengthen tests for:

``` text
SUPPORT / VALUE STATE

all support + untouched
all support + common
all support + mixed

partial support + untouched
partial support + common
partial support + mixed

no support
```

Fan:

``` text
ordered selection determines phase
reverse selection reverses fan result
unsupported fixture skipped
single fixture behaves deterministically
Pan and Tilt fan independently
```

Align:

``` text
align uses first capable fixture in ordered selection
unsupported fixtures untouched
mixed -> common after align
```

Mixed editing:

``` text
mixed intensity
user sets explicit value
all capable -> common(newValue)
```

External mutation:

``` text
Programmer changed externally
presentation recomputes without selection change
```

Scale:

``` text
80 mixed fixtures
presentation resolves correctly
```

------------------------------------------------------------------------

# 14. Revised UI-03 Acceptance Checklist

UI-03 is complete when:

``` text
[ ] Fixture/group selection preserves ordered fixture IDs

[ ] Selection order is inspectable when using Fan

[ ] Programmer support state and value state are modeled independently

[ ] Untouched is truthful

[ ] Common value is truthful

[ ] Mixed value never displays first fixture as representative truth

[ ] Partial support is truthful

[ ] Unsupported attributes are not invented

[ ] Editing a mixed ordinary control establishes a common explicit value

[ ] Clear Selection works

[ ] Clear All works and is visually distinct

[ ] Fan has defined deterministic center/spread semantics

[ ] Fan uses ordered selection

[ ] Fan skips unsupported fixtures

[ ] Align semantics are explicit and deterministic

[ ] Position Fan treats Pan/Tilt independently

[ ] Technical color controls reflect actual supported channels

[ ] MIDI/external Programmer changes refresh the visible UI without reselect

[ ] Palette/Locate/Home/Clear/Fan/Align changes refresh presentation

[ ] Fixture Browser remains visually scannable

[ ] Browser capability badges are used only if they improve clarity

[ ] ~80 mixed fixtures remain responsive during selection and programming

[ ] No new high-frequency whole-shell invalidation is introduced

[ ] Programmer remains ephemeral until record

[ ] UI-02 shell geometry remains unchanged

[ ] Visual review passes for single/common/mixed/partial/Fan/large-selection states

[ ] Unit tests pass

[ ] macOS Xcode Debug build passes
```

------------------------------------------------------------------------

# 15. Final Direction

The UI-03 plan is approved with these amendments.

The key principle for this phase is:

> **The Programmer must tell the truth about the entire selected rig,
> not merely display controls for the first selected fixture.**

UI-03 should make Aurora understand and communicate:

``` text
what is selected
what those fixtures support
what the Programmer owns
what is mixed
what is untouched
what order fixtures are in
what an edit will affect
```

while remaining fast enough that the Programmer feels like an instrument
rather than a configuration form.

Once these semantics, interactions, performance behavior, and visual
states are solid:

> **Close UI-03. Do not drift into UI-04 or UI-05.**
