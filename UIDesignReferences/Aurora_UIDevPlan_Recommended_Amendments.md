# Aurora UI Development Plan --- Recommended Amendments

**Applies to:** `UIDesignReferences/UIDevPlan.md`\
**Purpose:** Focused amendments to Grok's UI development plan before
beginning UI-01\
**Disposition:** Keep the existing plan. Incorporate the changes below
rather than rewriting the roadmap wholesale.

------------------------------------------------------------------------

# 1. Design for Docking Early; Implement Advanced Docking Later

Keep **UI-11** as the phase where advanced docking, tear-off panels,
multi-display support, and richer workspace management are implemented.

However, add a **docking-compatible panel contract** to **UI-02**.

Every major panel introduced or redesigned from UI-02 onward should:

-   have a container-independent content root
-   avoid assuming a specific parent `HSplitView` / `VSplitView`
-   avoid assuming a fixed window or screen size
-   avoid directly owning workspace/window placement
-   accept focused dependencies rather than reaching through the
    workspace host
-   remain usable when hosted in a tab, split, separate window, or
    future AppKit docking container

Guiding rule:

> **Design for docking in UI-02. Implement sophisticated docking in
> UI-11.**

This avoids redesigning UI-03 through UI-09 around the current SwiftUI
split implementation and then having to restructure the panels when
professional docking arrives.

------------------------------------------------------------------------

# 2. Strengthen the UI-01 Visual Review Gate

The existing hard stop after UI-01 is correct and should remain.

Expand the UI-01 component gallery so it demonstrates Aurora's design
system in **realistic compositions**, not only isolated controls.

At minimum, the gallery should contain:

## 2.1 Mini Programmer

Demonstrate together:

-   panel surface/header
-   attribute-family navigation
-   fader
-   numeric field
-   selected/programmer-owned state
-   palette tiles
-   section headings
-   compact labels

## 2.2 Mini Cue List

Demonstrate:

-   normal cue
-   current cue
-   next cue
-   selected cue
-   warning/broken-reference cue
-   timing information
-   cue number typography

## 2.3 Mini Perform Transport

Demonstrate:

-   current cue
-   next cue
-   large GO
-   BACK
-   STOP
-   healthy status indicators
-   warning/failed status indicators

The gallery should also demonstrate component states including:

-   normal
-   hover
-   pressed
-   selected
-   focused
-   disabled
-   warning
-   critical

### Revised UI-01 gate

Before UI-02 begins, human review should approve not merely individual
components but whether those components **work together as Aurora**.

------------------------------------------------------------------------

# 3. Add Explicit UI Density Levels

Aurora needs different information densities without developing
unrelated visual systems.

Add semantic density concepts to the design system:

``` text
compact
standard
performance
```

## Compact

Intended for dense Build-mode information surfaces such as:

-   fixture lists
-   patch tables
-   cue lists
-   diagnostics
-   inspectors
-   technical tables

## Standard

Intended for normal programming controls such as:

-   Programmer
-   palette/preset shelves
-   Settings
-   editors

## Performance

Intended for:

-   Perform Mode
-   web/iPad remote
-   large transport controls
-   distance-readable current/next information

Components should use semantic density rather than arbitrary per-view
padding and sizing.

This is especially important to prevent stock SwiftUI spacing from
making professional Build surfaces unnecessarily oversized.

------------------------------------------------------------------------

# 4. Make Contextual Inspector Architecture a UI-02 Requirement

UI-02 currently includes an Inspector shell. Expand this into an
explicit interaction contract.

The Inspector answers:

> **What is selected, and what can I change about that thing?**

Examples:

``` text
Fixture selected
    → Fixture Inspector

Group selected
    → Group Inspector

Cue selected
    → Cue Inspector

Palette selected
    → Palette Inspector

Preset selected
    → Preset Inspector

Song selected
    → Song Inspector
```

If there is no meaningful selection, display either:

-   useful project/workspace context, or
-   a calm empty state

Do not turn the Inspector into a permanent collection of unrelated
controls.

Individual feature phases may add Inspector sections, but the
**selection → inspector-content architecture** should be established in
UI-02.

------------------------------------------------------------------------

# 5. Establish the Settings Shell Earlier

Keep **UI-08** as the phase where the complete Settings content is
implemented.

However, establish the **native macOS Settings shell and information
architecture during UI-02**, or immediately following UI-02 as a small
foundation slice.

The early Settings shell should establish:

-   native Settings scene/window
-   navigation model
-   Aurora design-system treatment
-   application-global vs project/show setting presentation
-   placeholders only where clearly marked unavailable
-   a stable location for configuration surfaces as they migrate out of
    the workspace

This supports the product principle:

> **Complexity available, not constantly visible.**

Individual Settings pages may then be populated during their relevant
phases.

For example:

-   MIDI configuration can migrate as Input UI matures
-   output configuration can mature with UI-09
-   remote configuration can mature with UI-10

UI-08 remains the consolidation/completion phase for Settings.

------------------------------------------------------------------------

# 6. Add Programmer Attribute-State Semantics to UI-03

Before implementing the redesigned Programmer, define how an attribute
visually represents its state.

At minimum, support the concepts:

``` text
untouched
programmer-owned
inherited / tracked
palette-referenced
mixed selection
unavailable
```

## Untouched

The Programmer has not taken ownership of this attribute.

## Programmer-owned

The Programmer currently owns/overrides the attribute.

This must be visually distinguishable without relying solely on color.

## Inherited / tracked

Where applicable, communicate that the displayed state originates from
playback/tracking rather than the Programmer.

## Palette-referenced

Where reference semantics are relevant, the UI should be capable of
indicating that a reusable palette/preset relationship exists rather
than implying a purely literal value.

## Mixed selection

If selected fixtures have different values, Aurora must not display an
arbitrary single value.

Example:

``` text
8 fixtures selected

4 = Red
4 = Blue

Color → MIXED
```

Controls should permit the operator to intentionally replace the mixed
state with a new common value.

## Unavailable

If an attribute is not supported by the selected fixture(s), the UI must
represent that truthfully.

For mixed fixture personalities, the Programmer should clearly
distinguish:

-   supported by all
-   supported by some
-   supported by none

Do not fabricate controls that imply unsupported capabilities.

------------------------------------------------------------------------

# 7. Add Fixture-Selection Scale Testing to UI-03

UI-03 acceptance should test more than small fixture selections.

Add a realistic scale case:

> Select approximately 80 fixtures across multiple fixture personalities
> and groups. The Fixture Browser and Programmer remain responsive,
> mixed-capability state is represented correctly, and the UI does not
> introduce high-rate broad invalidation.

This does not require premature optimization.

It establishes that large selections are a normal lighting-programming
workflow rather than an edge case.

------------------------------------------------------------------------

# 8. Strengthen Perform Mode as a Safety Boundary

UI-07 should treat Perform Mode as more than a visual layout.

While in Perform Mode:

-   show-structure editing should normally be unavailable
-   destructive programming actions should be unavailable or require an
    intentional transition to Build Mode
-   incidental dialogs must not obscure essential transport
-   GO/BACK/STOP must remain immediately available
-   warnings should escalate without taking control away from the
    operator

Guiding principle:

> **Perform Mode is an operational safety boundary as well as a visual
> mode.**

The operator should not be one stray click away from deleting,
renumbering, or structurally editing the show during a performance.

------------------------------------------------------------------------

# 9. Preserve a Future Show Lock Concept

Do **not** require implementation of Show Lock in the current roadmap
unless it naturally fits.

However, avoid architecture that prevents a future explicit lock state
such as:

``` text
🔒 SHOW LOCKED
```

A future Show Lock could prevent structural editing while allowing
approved live controls.

Potential future semantics:

-   lock cue/song structure
-   lock patch
-   lock palette/preset edits
-   permit GO/BACK/STOP
-   permit approved live programmer overrides
-   require intentional unlock before editing

This is a future-compatible design consideration, not a new backend
requirement for UI-01.

------------------------------------------------------------------------

# 10. Move the Production AppIcon Earlier

Move production Aurora AppIcon work from UI-12 to approximately
**UI-02/UI-03**.

The icon is already part of Aurora's approved visual identity and is
inexpensive to establish early.

UI-12 should still include a final icon/branding audit, but the
application should stop using placeholder identity relatively early in
the visual-development phase.

Suggested disposition:

``` text
UI-02 / UI-03
    → Install production AppIcon assets

UI-12
    → Final branding consistency audit
```

------------------------------------------------------------------------

# 11. Revised Phase Sequence

The overall roadmap remains good.

Recommended sequence:

``` text
UI-01
Design System
    • tokens
    • components
    • density system
    • realistic mini-compositions
    ↓
HARD VISUAL REVIEW


UI-02
Application Shell
    • project / dirty state
    • Build / Perform shell
    • health chrome
    • workspace host
    • contextual Inspector architecture
    • docking-compatible panel contract
    • Settings shell / information architecture
    ↓
SHELL REVIEW


UI-03
Fixture Browser + Programmer
    • fixture/group selection
    • attribute families
    • attribute-state semantics
    • mixed capability/value behavior
    • large-selection test


UI-04
Palettes + Presets


UI-05
Cue Workflow


UI-06
Song Mode


UI-07
Perform Mode
    • stage cockpit
    • operational safety boundary


UI-08
Full Settings Content / Consolidation


UI-09
Patch / Output / Diagnostics


UI-10
Web / iPad Remote


UI-11
Advanced Docking / Saved Layouts / Multi-display


UI-12
Final Product Polish
    • accessibility
    • keyboard audit
    • first-run
    • empty states
    • performance profiling
    • final branding consistency
```

------------------------------------------------------------------------

# 12. Revised UI-01 Acceptance Checklist

Add the following to the existing UI-01 acceptance criteria:

``` text
[ ] Semantic density system: compact / standard / performance

[ ] Mini Programmer composition in gallery
[ ] Mini Cue List composition in gallery
[ ] Mini Perform Transport composition in gallery

[ ] Normal state demonstrated
[ ] Hover state demonstrated
[ ] Pressed state demonstrated
[ ] Selected state demonstrated
[ ] Focused state demonstrated
[ ] Disabled state demonstrated
[ ] Warning state demonstrated
[ ] Critical state demonstrated

[ ] Components look coherent when combined, not merely in isolation

[ ] No product panels wholesale-redesigned yet

[ ] STOP for human visual review
```

------------------------------------------------------------------------

# 13. Revised UI-02 Acceptance Checklist

Add:

``` text
[ ] Major panel content roots are container-independent
[ ] Panels do not assume one specific split/window host
[ ] Contextual Inspector selection-routing architecture exists
[ ] Native macOS Settings shell exists
[ ] App-global vs project/show settings have a defined presentation convention
[ ] New screens do not depend on full AppModel when focused dependencies suffice
[ ] Existing functional panels can still run inside the new shell
[ ] Build and Perform chrome are visibly distinct without yet implementing full UI-07
```

------------------------------------------------------------------------

# 14. Revised UI-03 Acceptance Checklist

Add:

``` text
[ ] Programmer distinguishes untouched vs programmer-owned state
[ ] Mixed values are represented truthfully
[ ] Mixed fixture capabilities are represented truthfully
[ ] Unsupported attributes do not appear functional
[ ] Palette/reference state can be communicated where relevant
[ ] Large selection (~80 fixtures, multiple personalities) remains responsive
[ ] No high-rate broad SwiftUI invalidation introduced
```

------------------------------------------------------------------------

# 15. Revised UI-07 Acceptance Checklist

Add:

``` text
[ ] Perform Mode prevents accidental structural editing
[ ] Essential transport remains available during warnings/errors
[ ] No incidental modal can unnecessarily cover GO
[ ] Build-only commands are hidden, disabled, or require intentional mode transition
[ ] Architecture remains compatible with a future Show Lock
```

------------------------------------------------------------------------

# 16. Items That Should Remain Unchanged

The following parts of Grok's existing plan are approved and should
remain:

-   backend gate remains closed
-   `UI_BACKEND_CONTRACT.md` remains authoritative
-   `AuroraUI` remains pure/reusable and does not depend on the
    executable
-   focused controller/presentation bindings are preferred over full
    `AppModel`
-   UI does not insert `MainActor` latency into live control
-   structured presentation snapshots remain the UI contract
-   high-rate DMX is limited to dedicated monitor paths
-   visual references are intent, not pixel-perfect requirements
-   deferred features must not appear falsely functional
-   native macOS conventions should be used where beneficial
-   accessibility and keyboard operation are required
-   UI work proceeds in reviewable phases
-   **UI-01 remains a hard stop before the design language spreads**

------------------------------------------------------------------------

# 17. Immediate Instruction to Grok

Incorporate these amendments into `UIDesignReferences/UIDevPlan.md`.

Then implement **UI-01 only**.

Do not begin UI-02 until the UI-01 component gallery and realistic
mini-compositions have been reviewed and approved.

The first implementation milestone is not:

> "Aurora has a new skin."

It is:

> **"Aurora now has an approved visual language that is coherent enough
> to build the rest of the product from."**

Once that visual language is approved, proceed phase-by-phase according
to the amended roadmap.
