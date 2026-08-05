# Aurora UI/UX Implementation Plan
## UI Mode Kickoff Specification for Grok

**Status:** UI planning baseline  
**Backend gate:** Closed, with residual backend fixes handled independently  
**Primary visual reference:** `Aurora_UI_UX_Design_Reference.pdf`  
**Authoritative backend contracts:** `docs/UI_BACKEND_CONTRACT.md`, `docs/STAGE_C_UI_STATE_HANDOFF.md`

---

# 1. Purpose

Aurora is entering its visual product-development phase. The backend architecture, lighting engine, control routing, persistence, output systems, MIDI/network input, song model, effects, diagnostics, remote control, and state-ownership boundaries already exist.

The goal of the UI phase is **not** to redesign Aurora's backend.

The goal is to turn the existing system into a polished professional macOS lighting-control application with a coherent visual language, fast workflows, excellent live-show ergonomics, and a clear separation between programming and performance.

The approved design direction is:

> **A modern macOS creative workstation for programming, and a calm stage-control cockpit for performing.**

Aurora may learn from successful workflow ideas in LightKey and other professional creative applications, but it must develop its own identity and must not copy another application's visual design.

---

# 2. Non-Negotiable Product Principles

## 2.1 Complexity available, not constantly visible

Aurora will become a powerful application. Power must not turn the main workspace into a wall of configuration.

Frequently used programming and show controls belong in the workspace.

Occasional configuration belongs in Settings.

Examples that should normally be tucked away:

- MIDI devices and mappings
- RTP-MIDI sessions
- OSC configuration
- Art-Net/sACN configuration
- Remote/web server configuration
- Plugins
- Logging preferences
- Advanced engine preferences

The main workspace should remain focused on creating and operating a show.

## 2.2 Build and Perform are different mental states

Aurora has two primary workspace modes.

### Build Mode

Dense, information-rich, editable, keyboard-friendly, and optimized for programming.

Typical content:

- Fixture/group browser
- Programmer
- Palette/preset shelf
- Cue list
- Inspector
- Effects
- Patch
- Song editor
- Universe monitor

### Perform Mode

Calm, highly legible, difficult to edit accidentally, and optimized for stage use.

Typical content:

- Current song
- Current section
- Current cue
- Next cue
- GO / BACK / STOP
- Output/MIDI/engine health
- Important warnings
- Compact show progress

The web/iPad remote should follow Perform Mode philosophy, not attempt to reproduce Build Mode.

## 2.3 Color is information

The application shell should use restrained dark charcoal surfaces.

Bright color should primarily represent:

- fixture output
- palettes
- selection
- active state
- warnings/errors
- Aurora brand accents

Do not cover the application in decorative purple gradients. Aurora accents should feel deliberate.

## 2.4 The UI must tell the truth

Do not create working-looking controls for backend behavior that is not implemented.

Respect `docs/UI_BACKEND_CONTRACT.md`.

Examples currently deferred include:

- automatic song progression
- Open DMX
- real ENTTEC serial enumeration
- project-level frame-rate override
- native iPad application

Unavailable functionality may be shown as clearly unavailable where useful, but must never masquerade as functional.

## 2.5 Live control must remain fast

Visual work must never insert `MainActor` latency into the established live control path.

The UI consumes presentation state and dispatches actions through the existing controller/router contracts.

Do not make UI views directly manipulate the lighting engine.

---

# 3. Architecture Rule for UI Development

Use the existing architecture.

`AuroraUI` should remain a reusable **design-system and pure-view library**.

Controller-aware screens and application composition belong in the macOS app target.

Conceptually:

```text
AuroraUI
  ├── Design Tokens
  ├── Reusable Components
  ├── Pure Panels
  ├── Pure Perform Views
  └── Visual Utilities

Aurora macOS App Target
  ├── Screen Composition
  ├── Controller Bindings
  ├── Window/Settings Scenes
  ├── AppKit Docking Integration
  └── Commands / Menus
```

Do not make `AuroraUI` depend on the executable target.

Do not bind every view to the complete `AppModel`.

Prefer focused controller/store bindings defined by `UI_BACKEND_CONTRACT.md`.

---

# 4. Approved Visual Direction

The approved north-star concept uses:

- very dark charcoal application background
- slightly lighter layered panels
- subtle separators rather than heavy borders
- native macOS typography
- restrained violet/indigo Aurora accent
- highly visual color/palette tiles
- clear selected-fixture state
- central programmer as the visual focus in Build Mode
- persistent but quiet health/status chrome
- large, unmistakable transport controls in Perform Mode
- rounded geometry used sparingly
- professional density rather than oversized consumer controls

The interface should feel closer to a professional Apple creative application than to a hardware console emulator.

Avoid:

- skeuomorphic console surfaces
- excessive neon
- permanent giant button grids
- gaming UI aesthetics
- tiny unreadable labels
- excessive floating windows
- configuration controls occupying permanent workspace space
- generic stock SwiftUI appearance everywhere

---

# 5. Design System

Create the design system before redesigning all screens.

Recommended source organization:

```text
Sources/AuroraUI/
  DesignSystem/
    AuroraTokens.swift
    AuroraTypography.swift
    AuroraColors.swift
    AuroraSpacing.swift
    AuroraMetrics.swift
    AuroraAnimation.swift

  Components/
    AuroraPanel.swift
    AuroraPanelHeader.swift
    AuroraToolbar.swift
    AuroraButton.swift
    AuroraIconButton.swift
    AuroraStatusIndicator.swift
    AuroraSectionHeader.swift
    AuroraInspectorSection.swift
    AuroraPaletteTile.swift
    AuroraPresetTile.swift
    AuroraCueRow.swift
    AuroraFader.swift
    AuroraNumericField.swift
    AuroraEmptyState.swift
    AuroraSearchField.swift
    AuroraTransportButton.swift
```

Exact names may change to match code conventions.

## 5.1 Color tokens

Use semantic tokens rather than hard-coded RGB values throughout views.

Suggested roles:

- `surfaceBase`
- `surfacePanel`
- `surfaceRaised`
- `surfaceSelected`
- `separator`
- `textPrimary`
- `textSecondary`
- `textTertiary`
- `accent`
- `accentSubtle`
- `success`
- `warning`
- `critical`
- `disabled`

Fixture/palette colors are content and should not be forced into the brand palette.

## 5.2 Typography

Use native macOS system typography.

Define semantic roles:

- window title
- workspace title
- panel title
- section heading
- body
- secondary
- numeric readout
- cue number
- status
- compact label

Numbers used for DMX values, percentages, timing, cue numbers, and diagnostics should be easy to scan.

## 5.3 Spacing

Define a small spacing scale and use it consistently.

Do not hand-tune arbitrary padding in individual panels.

## 5.4 Interaction states

Every reusable interactive component must define:

- normal
- hover
- pressed
- selected
- focused
- disabled
- warning/error where applicable

Keyboard focus must remain visible.

---

# 6. Main Build Workspace

The default Build workspace should use a three-column creative-workstation structure.

```text
┌─────────────────────────────────────────────────────────────────────┐
│ Toolbar / Project / Workspace                         Health Status │
├───────────────┬─────────────────────────────────────┬───────────────┤
│ Browser       │ Programmer / Primary Editor         │ Inspector     │
│               │                                     │               │
│ Fixtures      │ Intensity | Color | Position | Beam │ Contextual    │
│ Groups        │                                     │ properties    │
│ Search        │                                     │               │
├───────────────┴─────────────────────────────────────┴───────────────┤
│ Palette / Preset Shelf                                              │
├─────────────────────────────────────────────────────────────────────┤
│ Cue / Song / Effects / Monitor lower workspace                      │
└─────────────────────────────────────────────────────────────────────┘
```

This is a default workspace, not a rigid layout.

Panels should eventually support saved layouts and professional docking behavior.

The existing SwiftUI split implementation may be used during transition, but the long-term architecture should permit AppKit-backed docking/tear-off behavior without rewriting panel contents.

---

# 7. Fixture & Group Browser

The browser is a primary selection surface.

Required:

- search
- fixtures and groups
- clear selection state
- multi-selection
- ordered selection/phase awareness
- compact fixture identity
- fixture status where useful
- disclosure groups
- drag/drop where semantically valid

Future view mode:

- stage-map fixture selection

Do not overload each row with every fixture attribute.

The browser answers primarily:

> What am I controlling?

---

# 8. Programmer

The Programmer is the visual center of Build Mode.

Attribute families:

- Intensity
- Color
- Position
- Beam
- Gobo
- Other/fixture-specific

The Programmer should favor high-level fixture semantics over raw DMX channels.

Raw DMX remains available in appropriate technical/monitoring contexts.

## 8.1 Intensity

Provide:

- large readable percentage/value
- precise numeric entry
- fader/slider
- Home/Locate/Highlight where appropriate
- clear indication of programmer ownership

## 8.2 Color

Color programming should be visually rich.

Provide appropriate controls based on fixture capability:

- color field/wheel
- hue/saturation/value
- RGB/RGBW/CMY channels when desired
- color temperature where supported
- recent colors
- color palettes

Do not force technical RGB controls on users who simply want to select amber.

## 8.3 Position

Provide:

- pan/tilt controls
- precise numeric entry
- visual position surface where useful
- position palettes
- Home/Center
- future stage-map integration

## 8.4 Beam/Gobo

Use visual representations wherever fixture definitions provide them.

Gobo palettes should visually represent gobos rather than only showing text such as `Gobo 3`.

---

# 9. Palettes and Presets

Palettes and presets are first-class model objects, not cosmetic shortcut buttons.

The UI must preserve reference semantics.

## 9.1 Palette shelf

Color palettes should display their actual color.

Position palettes should use recognizable positional/stage iconography where possible.

Gobo palettes should show the gobo representation.

Beam palettes should communicate narrow/wide/open/prism/etc. visually.

Primary interaction:

- click: apply to current programmer selection
- context menu: edit, rename, duplicate, delete, favorites where supported
- drag/drop only where semantically defined

Do not invent modifier-key behavior without specification.

## 9.2 Presets

Presets may represent larger reusable looks.

They should be visually distinguishable from single-attribute palettes.

The UI should make it clear whether a cue stores literal values or references reusable objects when that distinction matters.

---

# 10. Cue List

The Cue List must be extremely readable.

Each row should communicate, without clutter:

- cue number
- name
- current/next state
- fade timing
- delay/follow where relevant
- warning/broken-reference state
- tracking/cue-only state where useful

Current cue and next cue must be visually unmistakable.

Editing should remain efficient by keyboard.

The redesigned UI must not expose inert model fields.

---

# 11. Song Mode

Song Mode organizes performance. It is not a second lighting engine.

Song Mode should feel more musical and structural than a raw cue table.

Conceptual hierarchy:

```text
Song
  Intro
    Cue 1.0
  Verse
    Cue 2.0
  Chorus
    Cue 3.0
  Solo
    Cue 4.0
```

Provide:

- title
- artist
- notes/annotations
- ordered entries
- current/next section
- referenced cue/cue-list state
- manual navigation

Do not expose Automatic progression as functional until backend completion semantics exist.

---

# 12. Perform Mode

Perform Mode should intentionally remove most programming controls.

Goals:

- readable from several feet away
- touch-friendly
- safe
- minimal
- fast
- health-aware

Primary information:

```text
SHOW / SONG

CURRENT
Section
Cue number + cue name

NEXT
Section
Cue number + cue name

[ BACK ]      [       GO       ]      [ STOP ]

ENGINE   OUTPUT   MIDI   NETWORK
```

No modal dialog should unnecessarily block GO during a show.

Warnings should become visually prominent without obscuring essential transport.

Perform Mode consumes `PerformanceSnapshot`.

Do not observe high-rate DMX frame data in general Perform views.

---

# 13. Web / iPad Remote

The remote should share Perform Mode's information hierarchy.

It is not a miniature Build workspace.

Design priorities:

- very large touch targets
- current/next cue
- song/section
- GO/BACK/STOP
- health indicators
- connection state
- optional simple approved overrides

The Mac and remote must agree semantically because both consume the same performance-state concepts.

---

# 14. Status & Health Chrome

Use quiet status indicators when healthy.

Example:

```text
● ENGINE   ● DMX   ● MIDI   ● NETWORK
```

Healthy status should not demand attention.

Warnings/errors should escalate visually.

Use `OutputPresentationSnapshot` for output health.

Do not build new UI against transitional compatibility strings when structured presentation state exists.

---

# 15. Settings Architecture

Use a native macOS Settings window.

Suggested navigation:

```text
General
Appearance

Control
  MIDI
  RTP-MIDI
  OSC
  Keyboard

Output
  Local DMX
  Art-Net
  sACN

Remote
  Web Interface
  Security
  Connected Clients

Plugins
  Installed
  Permissions / Configuration

Advanced
  Engine
  Diagnostics
  Logging
```

Not every setting belongs to the application-global Settings store.

The UI must distinguish:

- application-global settings
- project/show settings
- workspace-local settings

Do not silently move project semantics into global preferences for convenience.

MIDI mappings should be neatly tucked away here rather than permanently occupying the main workspace.

---

# 16. Diagnostics

Diagnostics should feel professional rather than developer-only.

Provide:

- engine health
- output health
- MIDI activity
- network state
- validation issues
- performance metrics
- logs

Use typed diagnostics where available.

The Console remains available, but normal operators should not need to read logs to understand whether Aurora is healthy.

---

# 17. Patch Workspace

Patch should optimize repetitive work.

Provide:

- universe
- address
- fixture
- mode/personality
- collision warnings
- search/filter
- batch operations
- duplicate/clone workflows

Universe-number uniqueness and patch validation should be surfaced clearly.

Patch errors should be understandable without inspecting JSON or console logs.

---

# 18. Workspace & Docking

Aurora should support multiple workspace arrangements.

Initial named concepts:

- Programming
- Patch
- Song
- Perform
- Diagnostics

Long term:

- resize panels
- hide/show panels
- tab compatible panels
- tear-off panels
- multi-display
- save/restore layouts

Panel content should remain reusable regardless of container.

Avoid designing views that assume one fixed screen size.

---

# 19. Menus, Commands, Keyboard

Aurora is a professional macOS application.

Use native menu commands and keyboard shortcuts.

Important actions should not require mouse-only workflows.

Examples:

- GO
- BACK
- STOP
- Record
- Update
- Undo/Redo
- Search
- Show/Hide panels
- Switch workspace/mode

Destructive commands require appropriate confirmation without disrupting live performance unnecessarily.

---

# 20. Accessibility & Usability

Do not rely on color alone to indicate critical state.

Support:

- keyboard navigation
- visible focus
- VoiceOver labels for meaningful controls
- adequate contrast
- scalable text where practical
- reduced-motion behavior
- large Perform targets

---

# 21. Animation

Animation should communicate state, not decorate the application.

Appropriate:

- panel transitions
- selection transitions
- palette application feedback
- cue transition progress
- health-state changes

Avoid:

- continuous decorative aurora animations in the working UI
- slow transitions that delay interaction
- animated effects that consume attention during performance

The splash/about experience may use richer Aurora branding.

---

# 22. Implementation Phases

## UI-01 - Design System Foundation

Build tokens and reusable components.

Do not redesign every panel simultaneously.

Acceptance:

- semantic colors
- typography
- spacing
- panel components
- buttons
- status indicators
- palette tiles
- cue rows
- faders
- previews

## UI-02 - Application Shell

Create:

- top toolbar
- project title/dirty state
- Build/Perform mode switching
- health chrome
- workspace container
- sidebar/browser shell
- inspector shell

## UI-03 - Fixture Browser + Programmer

Redesign fixture/group selection and Programmer.

This is the first complete high-value workflow.

Acceptance workflow:

> Select fixtures → set intensity/color/position → apply palette → observe programmer state.

## UI-04 - Palettes / Presets

Build visual shelves and editors.

Respect stable-reference semantics.

## UI-05 - Cue Workflow

Redesign Cue List, cue inspector, recording/update flow, current/next state.

## UI-06 - Song Mode

Build musician-oriented song organization and manual progression.

## UI-07 - Perform Mode

Build the Mac performance cockpit from `PerformanceSnapshot`.

## UI-08 - Settings

Move configuration complexity out of the main workspace.

MIDI mappings are a priority Settings surface.

## UI-09 - Patch / Output / Diagnostics

Build professional technical workspaces.

## UI-10 - Web Remote

Bring Perform semantics to the web/iPad surface.

## UI-11 - Docking / Workspace Polish

Upgrade workspace hosting toward professional docking/multi-display behavior.

## UI-12 - Final Product Polish

- icon
- splash/about
- empty states
- first-run experience
- keyboard polish
- accessibility
- performance profiling
- visual consistency audit

---

# 23. Rules for Grok During UI Implementation

1. Do not modify backend domain semantics merely to make a view easier to write.
2. If a backend contract is insufficient, document the missing contract before changing it.
3. Keep each UI phase independently buildable and reviewable.
4. Add SwiftUI previews for reusable components and pure views.
5. Do not bind high-frequency engine frame buffers into broad SwiftUI observation.
6. Prefer focused controllers/presentation snapshots.
7. Do not reintroduce global workspace invalidation.
8. Use semantic design tokens rather than scattered literals.
9. Do not invent features that are marked deferred.
10. Do not redesign all screens in one giant PR.
11. Preserve keyboard usability.
12. Keep live-control dispatch on the established low-latency path.
13. Use native macOS behavior where it improves familiarity.
14. Treat the PDF renders as visual intent, not pixel-perfect implementation requirements.
15. When visual intent conflicts with backend truth or usability, preserve backend truth and flag the design conflict.

---

# 24. First Grok Task

Begin with **UI-01 only**.

Create the Aurora design-system foundation and a small component gallery/preview surface.

Do not yet replace all existing panels.

The first PR should establish:

- semantic color tokens
- typography roles
- spacing/metrics
- panel surfaces
- primary/secondary/icon buttons
- status indicator
- section headers
- palette tile
- cue row
- fader/numeric control styling
- transport button
- reusable empty state

Use the approved dark professional direction from the PDF.

After UI-01, stop for visual review before continuing to UI-02.

This checkpoint is intentional. Aurora's visual language should be approved before it spreads across the entire application.

---

# 25. North-Star Acceptance Test

When Aurora's UI redesign is complete, a new user should be able to look at the application and answer quickly:

1. What show is open?
2. What fixtures am I controlling?
3. What are they currently doing?
4. What cue is active?
5. What happens next?
6. Is the engine/output/MIDI/network healthy?
7. Where do I go to program?
8. Where do I go to perform?
9. Where do I configure occasional systems such as MIDI mappings?
10. Can I recover from a mistake without hunting through the interface?

During a live performance, Aurora should feel calm.

During programming, Aurora should feel powerful.

That contrast is the central UX idea.
