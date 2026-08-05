# Aurora UI-01B --- Visual Identity Refinement Pass

**Status:** Required refinement before UI-02\
**Scope:** AuroraUI design system, reusable components, and UI-01
component gallery only\
**Do not begin UI-02 until this pass has been visually reviewed and
approved.**

------------------------------------------------------------------------

# 1. Why UI-01B Exists

UI-01 successfully established the architectural foundation requested
for Aurora's UI:

-   semantic design tokens
-   reusable SwiftUI components
-   density support
-   component interaction states
-   Programmer attribute-state concepts
-   component-gallery compositions
-   separation of `AuroraUI` from application/controller composition

This work should be preserved.

However, the first visual pass is **too conservative and too close to a
generic dark SwiftUI utility application** to become Aurora's permanent
visual language.

The problem is not that Aurora needs more decoration, more gradients, or
more purple.

The problem is that the current design does not yet have enough:

-   visual hierarchy
-   depth
-   precision
-   information rhythm
-   professional production-tool character
-   distinctive Aurora identity

The UI-01 checkpoint exists specifically so this can be corrected before
the visual system spreads across the application.

The target remains:

> **A premium professional macOS creative workstation for programming,
> with the precision of production/broadcast equipment and a calm
> stage-control cockpit for performance.**

Do not interpret this as a request for a gaming UI or a hardware-console
imitation.

------------------------------------------------------------------------

# 2. Preserve the Existing Architecture

UI-01B is a **visual refinement pass**, not a rewrite.

Preserve:

-   `AuroraUI` module boundaries
-   semantic token architecture
-   `compact / standard / performance` density model
-   reusable component approach
-   accessibility work
-   focused interaction-state handling
-   attribute-state concepts
-   realistic component-gallery compositions
-   SwiftUI preview infrastructure

Prefer changing shared tokens/components rather than introducing one-off
styling.

The goal is to improve the existing Lego bricks, not replace the Lego
system.

------------------------------------------------------------------------

# 3. Stronger Surface Hierarchy

The current dark surfaces are too close together visually.

Aurora needs a clearer hierarchy between:

``` text
application background
    ↓
workspace
    ↓
panel
    ↓
raised control surface
    ↓
selected / active surface
```

Refine the semantic surface tokens so those layers are immediately
understandable without becoming high-contrast boxes.

Requirements:

-   retain very dark charcoal as the foundation
-   avoid pure black for large working surfaces
-   give panels enough separation to read as deliberate work areas
-   use borders/separators selectively rather than outlining every
    object
-   use raised surfaces only where elevation or interaction actually
    matters
-   selected state should be clearer than a tiny luminance change

Do not solve hierarchy by simply making everything lighter.

------------------------------------------------------------------------

# 4. Reduce the Generic Rounded-Rectangle Look

The current component language relies too heavily on:

> rounded rectangle + text + subtle border

Aurora should use geometry according to function.

Recommended direction:

## Tight / technical geometry

Use tighter, more precise treatment for:

-   cue rows
-   fixture lists
-   inspectors
-   patch tables
-   diagnostics
-   numeric controls
-   technical status surfaces

## Softer visual objects

Allow more visual presence for:

-   palette tiles
-   preset tiles
-   major transport controls
-   large Programmer surfaces
-   empty/intro states

Do not apply the same corner radius and card treatment to every
component.

The interface should feel designed as an instrument, not assembled from
generic cards.

------------------------------------------------------------------------

# 5. Increase Professional Information Density

Build Mode should feel compact and capable.

Review:

-   control heights
-   row heights
-   vertical padding
-   panel-header height
-   section spacing
-   Inspector spacing
-   cue-row spacing
-   label/value relationships

`compact` density should be genuinely compact.

`standard` should still feel like professional desktop software.

`performance` remains intentionally large.

Avoid the contemporary consumer-app tendency toward oversized controls
surrounded by empty space.

Aurora should be comfortable displaying a substantial amount of useful
show information on a MacBook screen.

------------------------------------------------------------------------

# 6. Strengthen Typography Hierarchy

The current typography system is structurally correct but should carry
more of the interface hierarchy.

Refine the distinction between:

-   workspace title
-   panel title
-   section heading
-   control label
-   primary value
-   secondary value
-   cue number
-   timing/value readout
-   status
-   tertiary metadata

Important numerical information should be especially easy to scan.

Examples:

``` text
82%
Cue 14.0
1.5 s
Universe 2
DMX 145
Pan 48.2°
```

Use monospaced or monospaced-digit treatment where it materially
improves scanning, but do not make the entire interface look like a
terminal.

------------------------------------------------------------------------

# 7. Give Aurora a Distinctive Identity

The violet accent is acceptable but currently behaves mostly as:

> purple = selected

Aurora needs a slightly stronger identity without becoming decorative.

Explore restrained brand treatments for:

-   major selection/focus
-   active Programmer ownership
-   primary transport emphasis
-   workspace/mode selection
-   key headers or active indicators
-   splash/about/icon contexts

A subtle violet/indigo relationship may be used where appropriate.

Do **not** introduce:

-   large decorative gradients across normal panels
-   glowing neon borders everywhere
-   animated aurora backgrounds in the working interface
-   excessive purple tinting of neutral surfaces
-   gaming-style RGB effects

The show itself should remain the primary source of vivid color.

Aurora's identity should be recognizable even when no logo is visible.

------------------------------------------------------------------------

# 8. Improve Panel Treatment

`AuroraPanel` is one of the most important components because it will
frame almost every future workspace.

Refine it so panels feel like professional workstation regions rather
than generic cards.

Consider:

-   more deliberate panel-header treatment
-   stronger title/value hierarchy
-   subtle header/body distinction
-   optional toolbar/action region
-   more precise separators
-   reduced dependence on rounded outer borders
-   visually clean panel adjacency

Panels should work both:

-   individually
-   tightly adjacent inside a dense workspace

The eventual application shell must not look like a dashboard made of
floating cards.

------------------------------------------------------------------------

# 9. Redesign the Fader as a Signature Professional Control

The fader deserves more visual character.

It should communicate:

-   current value immediately
-   travel/range clearly
-   precision
-   hover/focus
-   programmer ownership where relevant
-   disabled/unavailable state

Avoid making it look like a stock SwiftUI slider rotated vertically.

Explore a more instrument-like treatment:

``` text
value readout

  82
  ──
  │
  │
  ▰  ← deliberate handle
  │
  │
  │

label
```

The control should remain clean and modern, not skeuomorphic.

Both vertical and horizontal variants should share the same visual
grammar.

------------------------------------------------------------------------

# 10. Improve Cue Row Visual Grammar

Cue rows are central to lighting operation and should feel
purpose-built.

The row should establish a clear scan path:

``` text
STATE | CUE NUMBER | NAME | TIMING / FOLLOW / STATUS
```

Refine:

-   current cue treatment
-   next cue treatment
-   selected cue treatment
-   warning/broken-reference treatment
-   hover/focus
-   cue-number prominence
-   timing alignment
-   row separators
-   role indicators

Avoid turning every state into a full-row colored rectangle.

Current and next should be unmistakable while the list remains calm.

The cue list should resemble a professional sequence/control surface
rather than a generic list of buttons.

------------------------------------------------------------------------

# 11. Make Palette and Preset Tiles Richer

Palette tiles are one place where Aurora should become more visual.

## Color palettes

Use the actual palette color as meaningful content.

The tile should communicate:

-   color
-   name
-   selection/reference state
-   hover/focus
-   optional favorite/status metadata where supported

## Position palettes

Prepare a visual language capable of communicating:

-   center
-   drummer
-   audience
-   fan
-   stage-left/right
-   other spatial concepts

## Gobo palettes

Prepare for actual gobo representation.

## Beam palettes

Prepare visual representation of:

-   open
-   narrow
-   wide
-   prism
-   other beam concepts

Presets should remain visually distinguishable from single-attribute
palettes.

These controls should feel like creative objects, not ordinary Settings
buttons.

------------------------------------------------------------------------

# 12. Make the Mini Programmer Visually Compelling

The UI-01 component gallery's Mini Programmer should become the primary
visual test of Aurora's Build-mode identity.

It should demonstrate:

-   clear panel hierarchy
-   selected fixture/group context
-   attribute-family navigation
-   a visually dominant primary editing area
-   intensity control
-   rich color control
-   position summary
-   attribute-state chrome
-   palette shelf
-   readable values

The composition should suggest the future Programmer rather than merely
arrange component examples.

When viewing the Mini Programmer, the reaction should be:

> **Yes, this could become Aurora.**

If the Mini Programmer still feels like a generic SwiftUI settings
panel, UI-01B is not finished.

------------------------------------------------------------------------

# 13. Strengthen the Mini Perform Composition

Perform controls should feel calmer and more confident.

Refine the Mini Perform composition around:

``` text
SONG / SHOW

CURRENT
Section
Cue

NEXT
Section
Cue

BACK       GO       STOP

ENGINE   OUTPUT   MIDI   NETWORK
```

Requirements:

-   GO visually dominates without looking cartoonishly oversized
-   current/next hierarchy is readable at distance
-   health indicators are quiet while healthy
-   warnings become prominent without covering transport
-   transport controls should feel like professional show controls
-   performance density must be clearly distinct from Build density

------------------------------------------------------------------------

# 14. Improve Status Indicators

Healthy status should be visually quiet.

Warnings and failures should escalate.

Avoid using identical bright colored dots for everything all the time.

Possible hierarchy:

``` text
healthy      subtle indicator + label
warning      amber + increased emphasis
critical     red + stronger emphasis
offline      clear inactive/disconnected treatment
```

The status system must remain readable without relying on color alone.

------------------------------------------------------------------------

# 15. Iconography

Use SF Symbols where they fit naturally.

However, establish a consistent icon treatment:

-   size
-   weight
-   alignment
-   active state
-   disabled state
-   icon-only button chrome
-   toolbar usage

Do not mix arbitrary symbol weights/styles.

Custom Aurora-specific icons may eventually be introduced for lighting
concepts where SF Symbols are inadequate.

Do not invent a large custom icon library during UI-01B.

------------------------------------------------------------------------

# 16. Selection and Focus Treatment

Selection and keyboard focus need more elegance.

Requirements:

-   selection and focus must be distinguishable
-   keyboard focus must remain accessible
-   selection should not rely only on a bright border
-   active Programmer ownership should have a recognizable Aurora
    treatment
-   selected rows should remain readable in dense lists

Use the accent deliberately.

Avoid outlining every selected item with a thick purple rounded
rectangle.

------------------------------------------------------------------------

# 17. Interaction Feedback

Hover/press feedback should feel immediate and precise.

Review animations and transitions for:

-   buttons
-   palette tiles
-   cue rows
-   faders
-   status changes
-   selection changes

Keep durations short.

Do not add decorative motion.

Aurora should feel responsive rather than animated.

------------------------------------------------------------------------

# 18. Component Gallery Requirements for UI-01B

Update the component gallery to show the refined design system in
context.

Required sections:

## A. Surface Hierarchy Board

Show together:

``` text
Base
Workspace
Panel
Raised
Selected
```

## B. Typography / Numeric Board

Show real Aurora examples:

``` text
Cue 14.0
82%
1.5 s
Universe 2
Pan 48.2°
DMX 145
```

## C. Control States

For major components show:

-   normal
-   hover
-   pressed
-   selected
-   focused
-   disabled
-   warning
-   critical

## D. Palette Board

Show:

-   several color palettes
-   position examples
-   preset examples
-   selected/referenced state

## E. Cue Board

Show:

-   normal
-   current
-   next
-   selected
-   warning

## F. Mini Programmer

This is the main Build-mode visual acceptance composition.

## G. Mini Perform

This is the main Perform-mode visual acceptance composition.

------------------------------------------------------------------------

# 19. Visual Acceptance Criteria

UI-01B is approved only when the design system satisfies all of the
following:

``` text
[ ] Clearly more distinctive than stock dark SwiftUI

[ ] Stronger application/workspace/panel/control hierarchy

[ ] Professional Build-mode information density

[ ] Reduced generic rounded-card appearance

[ ] Typography carries meaningful hierarchy

[ ] Faders look purpose-built for Aurora

[ ] Cue rows look purpose-built for show control

[ ] Palette/preset tiles feel visual and creative

[ ] Selection/focus treatment feels deliberate

[ ] Aurora identity is recognizable but restrained

[ ] Purple/indigo accent is not overused

[ ] Fixture/palette/show color remains visually dominant over branding

[ ] Mini Programmer feels like the seed of the final Aurora workstation

[ ] Mini Perform feels like the seed of the final Aurora stage cockpit

[ ] Accessibility states remain intact

[ ] compact / standard / performance density distinction remains intact

[ ] Existing UI module architecture remains intact

[ ] No backend semantics changed merely for visual convenience
```

------------------------------------------------------------------------

# 20. What UI-01B Must NOT Do

Do not:

-   begin UI-02 application-shell replacement
-   redesign every existing Aurora panel
-   change backend domain semantics
-   move live-control routing onto `MainActor`
-   introduce large decorative animations
-   cover the application in gradients
-   imitate LightKey's visual design
-   imitate a physical lighting console literally
-   build a gaming-style interface
-   create a bespoke style for every individual component
-   abandon semantic tokens for local hard-coded colors
-   remove accessibility behavior to achieve appearance

------------------------------------------------------------------------

# 21. Reference Direction

Continue using the approved Aurora UI/UX Design Reference PDF and
north-star render.

Interpret the reference primarily through:

-   hierarchy
-   density
-   visual rhythm
-   Programmer dominance
-   restrained shell
-   visual palette content
-   calm status chrome
-   strong Perform transport

Do not attempt pixel-for-pixel reproduction.

The reference is a design target, not a screenshot specification.

------------------------------------------------------------------------

# 22. Implementation Strategy

Prefer the following order:

``` text
1. Refine surface/color tokens
2. Refine typography
3. Refine spacing/metrics/density
4. Refine AuroraPanel
5. Refine buttons and icon buttons
6. Refine faders/numeric controls
7. Refine cue rows
8. Refine palette/preset tiles
9. Refine status indicators
10. Refine attribute-state chrome
11. Rebuild Mini Programmer composition
12. Rebuild Mini Perform composition
13. Run accessibility/interaction-state review
14. STOP
```

Do not continue into UI-02.

------------------------------------------------------------------------

# 23. Required Handoff

When UI-01B is complete, provide:

1.  the updated repository
2.  screenshots of the full component gallery
3.  a screenshot of the Mini Programmer
4.  a screenshot of the Mini Cue List
5.  a screenshot of the Mini Perform composition
6.  a short summary of token/component changes
7.  confirmation that no backend domain semantics were changed

Then stop for visual review.

------------------------------------------------------------------------

# 24. Final Direction

The first UI pass is a successful **technical foundation**, but it is
not yet the visual language we want to propagate throughout Aurora.

Do not discard the work.

Refine it.

The desired result is not louder or more decorative. It is more
deliberate, more precise, more hierarchical, more recognizable, and more
appropriate for a professional lighting-control application.

The UI-01B checkpoint is complete when the component gallery makes us
want to build the rest of Aurora from those components.
