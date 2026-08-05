# Aurora UI-01C - Visual Target Implementation Brief

**Status:** Required visual correction before UI-02\
**Inputs:** The Aurora UI reference renders supplied with this brief\
**Scope:** UI-01 design system, reusable components, component gallery,
and visual compositions only

## Objective

The supplied renders are now the primary visual target for Aurora.

The previous UI-01/UI-01B work established useful architecture, but the
visible result remained too close to a generic dark SwiftUI utility
application. Do not discard the architecture. Refine the design system
until it can convincingly produce the supplied reference screens.

The target is:

> **A beautiful, modern, professional macOS creative application for
> lighting control: the clarity and polish of applications such as Logic
> Pro and Xcode, informed by the strong workflow ideas of professional
> lighting software, but more modular and distinctly Aurora.**

Aurora must not copy LightKey's visual design. We are interested in the
qualities that make a professional lighting application efficient:
strong information hierarchy, immediate fixture/cue context, visual
palettes, dense but readable workspaces, and fast access to creative
controls.

## How to Use the Renders

Treat the renders as **visual intent and hierarchy references**, not
pixel-perfect screenshots and not new backend specifications.

Extract and reproduce the design language:

-   dark charcoal layered workspace
-   clear application/workspace/panel hierarchy
-   professional information density
-   modular dockable panel feeling
-   restrained violet/indigo Aurora identity
-   fixture/show color used as meaningful content
-   visually dominant Programmer
-   compact fixture and cue data
-   purpose-built faders and transport controls
-   strong current/next state
-   visual palettes, looks, beam shapes, and gobos
-   calm status/health chrome
-   contextual Inspector
-   native macOS polish
-   clear Build vs Perform distinction

Do not copy accidental text, fixture names, numerical values, or any
visual artifact produced by image generation. Backend truth and
`UI_BACKEND_CONTRACT.md` remain authoritative.

## Primary Screen Targets

### 1. Build Mode - Main Workspace

This is the north star.

The Build workspace should feel like a modular creative workstation
rather than a collection of generic cards.

The reference demonstrates:

-   application toolbar and project identity
-   Build/Perform mode selection
-   fixture/group browser
-   Patch and other workspace tabs
-   central Programmer
-   contextual Inspector
-   visual palette/look shelf
-   professional cue list
-   cue/effect timeline or value visualization where supported
-   persistent but quiet engine/output/network health

The Programmer must be the visual center of gravity.

### 2. Programmer

Use the detailed Programmer render to guide the visual grammar for:

-   intensity
-   dimmer
-   position
-   color
-   beam
-   gobo
-   fixture selection
-   attribute ownership/state

Controls should look purpose-built for lighting work, not like stock
SwiftUI sliders and form fields.

Only expose capabilities supported by the backend and selected fixture
personalities.

### 3. Palettes and Presets

These should feel like creative objects.

Color palettes should visibly communicate color. Beam palettes should
communicate beam shape. Looks/presets should be richer visual objects
than ordinary buttons.

Preserve stable reference semantics from the model.

### 4. Cue Workflow

Cue rows should establish a fast scan path:

`state -> cue number -> name -> trigger/timing/status`

Current, next, selected, warning, and normal states must be immediately
distinguishable without turning the entire list into bright colored
blocks.

### 5. Perform Mode

Perform Mode is a stage cockpit.

It should be:

-   calm
-   large enough to read from distance
-   difficult to edit accidentally
-   transport-first
-   health-aware

GO must have significantly greater visual authority than ordinary
buttons.

Current cue, next cue, song/section, transport, masters, and critical
health are the primary content.

### 6. Settings - MIDI Mappings

This render demonstrates our "complexity available, not constantly
visible" principle.

MIDI mapping belongs in a polished native Settings environment with:

-   device/session context
-   mapping table
-   Learn/Test actions
-   contextual mapping Inspector
-   clear action/parameter/value mapping
-   application/project scope shown truthfully

Do not move MIDI configuration back into the permanent Build workspace.

### 7. Web / iPad Remote

The remote follows Perform Mode semantics.

It is not a miniature Build workspace.

Priorities:

-   current/next
-   GO/BACK/STOP
-   approved looks/overrides
-   masters where supported
-   health/connection state
-   large touch targets

### 8. Patch, Effects, and Output Configuration

The additional reference board shows intended visual directions for
these later surfaces.

Use these as future targets only. Do not implement UI-09 during UI-01C.

They demonstrate the same design language applied to technical data:
dense, modular, precise, and visually understandable.

## Visual Rules

### Surface hierarchy

The user should immediately perceive:

`application -> workspace -> panel -> control surface -> active/selected state`

Do not rely on nearly identical shades of black.

### Geometry

Do not make every element the same rounded rectangle.

Use tighter geometry for tables, cue rows, inspectors, lists, and
technical controls. Reserve softer cards for objects that benefit from
visual presence.

### Density

Maintain the semantic density system:

-   `compact` for lists, tables, inspectors, diagnostics
-   `standard` for creative programming
-   `performance` for stage operation

### Typography

Create a strong hierarchy for titles, panel headers, labels, values, cue
numbers, timing, and status.

Use monospaced digits where useful for scanning values.

### Aurora identity

Use violet/indigo deliberately, not everywhere.

Aurora should be recognizable without turning neutral workspace surfaces
purple.

### Color

Color is information.

Fixture output, palettes, looks, health, warnings, and active states may
use color. Decorative color should remain restrained.

### Controls

Faders, cue rows, palette tiles, transport buttons, and status
indicators must feel purpose-built for Aurora.

Avoid stock SwiftUI appearance.

## Required UI-01C Work

Refine the existing UI-01 components so the component gallery can
reproduce the design language shown in the renders.

At minimum revisit:

-   surface/color tokens
-   typography
-   spacing and density
-   panel/header treatment
-   workspace/tab treatment
-   buttons
-   icon buttons
-   faders
-   numeric fields
-   cue rows
-   palette tiles
-   preset/look tiles
-   status indicators
-   attribute-state indicators
-   transport controls
-   empty states
-   selection/focus treatment

## Required Component Gallery Compositions

The gallery must contain polished versions of:

1.  Build Mode mini-workspace
2.  Detailed Programmer
3.  Palette/preset shelf
4.  Cue list
5.  Perform cockpit
6.  MIDI Mapping Settings

The goal is to prove the design system can create the supplied visual
language before it spreads through the real application.

## Important Constraints

Do not:

-   begin UI-02
-   rewrite backend architecture
-   invent unsupported functionality
-   copy LightKey pixel-for-pixel
-   treat generated text/data in the renders as authoritative
-   introduce MainActor latency into live control
-   bind broad UI observation to high-rate DMX frames
-   replace semantic tokens with one-off styling
-   cover Aurora in gradients or neon
-   build a gaming UI
-   make every panel a floating rounded card

## Acceptance Test

UI-01C is ready for review when:

-   the component gallery is immediately recognizable as the same
    product family as the supplied renders
-   the Build composition feels like a professional creative workstation
-   the Programmer has clear visual dominance
-   palettes and looks feel creative and visual
-   cue rows feel purpose-built for show control
-   Perform Mode feels like a stage cockpit
-   MIDI Settings feels organized and native
-   the design is visibly more distinctive than stock dark SwiftUI
-   Aurora identity is present but restrained
-   backend contracts remain unchanged

## Required Handoff

When complete, provide:

-   updated repository
-   full component-gallery screenshots
-   Build Mode composition screenshot
-   Programmer screenshot
-   Cue List screenshot
-   Perform Mode screenshot
-   MIDI Settings screenshot
-   summary of design-token/component changes
-   confirmation that backend domain semantics were not changed

Then **STOP for visual review**.

Do not proceed to UI-02 until the visual checkpoint is explicitly
approved.
