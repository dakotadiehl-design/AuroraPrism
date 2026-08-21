# Aurora Design System Extraction Recommendations

## Purpose

This document defines the recommended process for extracting the existing Prism custom buttons and faders from the Prism/Aurora codebase into a reusable `AuroraDesignSystem` Swift package.

The goal is **not** to make Aurora Remote use Prism's desktop controls unchanged. The goal is to extract the reusable engineering foundation, preserve Prism's current appearance and behavior, and create a clean base from which touch-oriented Aurora controls can be built for Remote and other iPad/iPhone applications.

The extraction should be treated as a boundary-cleanup exercise first and a cross-platform design-system effort second.

---

## 1. Core architectural rule

The reusable library should own:

- Aurora-family design tokens
- shared colors
- typography
- spacing
- metrics
- animation constants
- reusable control state
- reusable normalized-value behavior
- fader geometry and value mapping
- button semantic styles
- accessibility behavior
- reusable icons that are truly family-wide
- platform-neutral interaction primitives

The library must **not** own:

- Prism programmer state
- fixture models
- DMX values or conversion logic
- MIDI routing
- show state
- commands or undo construction
- Prism-specific panel layout
- Prism-specific application routing
- Aurora Remote networking or ACP state
- product-specific screens
- feature-specific view models

The desired dependency direction is:

```text
SwiftUI / Apple platform frameworks
                │
                ▼
       AuroraDesignSystem
                │
        ┌───────┴────────┐
        ▼                ▼
     AuroraUI       Aurora Remote UI
        │
        ▼
      Prism
```

There must be no dependency from `AuroraDesignSystem` back into Prism feature modules.

---

## 2. Extract behavior before redesigning visuals

The existing Prism controls should be moved **without visual redesign during the initial extraction**.

This is important because extraction and redesign are two different kinds of work:

1. Extraction proves module boundaries, dependency ownership, access control, build integration, and source compatibility.
2. Redesign changes rendering, interaction behavior, touch sizing, and product presentation.

Combining both into one change makes regressions significantly harder to diagnose.

### Initial extraction rule

During the first pass:

- Preserve Prism's current button appearance.
- Preserve Prism's current fader appearance.
- Preserve existing public initializers where practical.
- Preserve keyboard behavior.
- Preserve accessibility behavior.
- Preserve drag and pointer behavior.
- Preserve density handling.
- Preserve control dimensions.
- Preserve label formatting unless the formatting itself is Prism-domain-specific.

Only make changes required to remove Prism-specific dependencies.

---

## 3. Recommended initial extraction set

Move the following files into the new package target, subject to dependency cleanup:

```text
Sources/AuroraUI/Components/AuroraButton.swift
Sources/AuroraUI/Components/AuroraFader.swift
Sources/AuroraUI/Components/AuroraControlDisplayValue.swift
Sources/AuroraUI/Components/ValueFaderGeometry.swift

Sources/AuroraUI/DesignSystem/AuroraAnimation.swift
Sources/AuroraUI/DesignSystem/AuroraAssetIcon.swift
Sources/AuroraUI/DesignSystem/AuroraColors.swift
Sources/AuroraUI/DesignSystem/AuroraDensity.swift
Sources/AuroraUI/DesignSystem/AuroraMetrics.swift
Sources/AuroraUI/DesignSystem/AuroraSpacing.swift
Sources/AuroraUI/DesignSystem/AuroraTypography.swift
```

Review `AuroraTokens.swift` separately.

Only move generic family-level tokens from that file. If it mixes generic design tokens with Prism panel chrome or feature-specific modifiers, split it before extraction.

---

## 4. Separate generic fader mechanics from Prism programmer layout

`ValueFaderGeometry` should become a pure control-geometry utility.

It may own:

- normalization to `0...1`
- clamping
- value-to-position conversion
- position-to-value conversion
- horizontal geometry
- vertical geometry
- thumb travel
- hit testing
- pointer drag offsets
- track-click seek behavior
- keyboard step values
- accessibility step values
- edge-case behavior for undersized controls

It must not own:

- programmer panel width
- color wheel positioning
- emitter layout
- programmer panel overflow
- fixture-specific geometry
- any layout rule involving unrelated Prism controls

Move Prism-specific layout logic into something such as:

```text
Sources/AuroraUI/Panels/Programmer/ProgrammerColorFaderLayout.swift
```

The design-system package should never expose a public type named after Prism's programmer.

---

## 5. Make display state domain-neutral

`AuroraControlDisplayValue` is appropriate for the shared package if it remains generic.

Recommended shape:

```swift
public enum AuroraControlDisplayValue: Equatable {
    case value(Double)
    case mixed
    case unavailable
}
```

Generic computed properties may include:

```swift
public var isInteractive: Bool
public var concreteValue: Double?
```

Do not keep convenience APIs that directly accept Prism programmer state.

For example, a factory that converts fixture/programmer state into `AuroraControlDisplayValue` should live in Prism's UI layer:

```text
Sources/AuroraUI/Adapters/
    AuroraControlDisplayValue+Programmer.swift
```

This keeps the package unaware of Prism's data model.

---

## 6. Split button semantics from product-specific appearance

The package should preserve Prism's existing `AuroraButton` during extraction, but its API should be examined for semantic concepts that can later support multiple presentations.

Good shared semantics include:

```swift
primary
secondary
quiet
destructive
selected
disabled
```

Avoid public APIs that directly encode a Prism-only screen or workflow.

The design system should eventually distinguish between:

- semantic meaning
- interaction state
- rendering style
- platform presentation

This will allow Prism to retain desktop-oriented controls while Remote introduces touch-oriented controls built on the same family foundation.

---

## 7. Do not force Prism controls onto iPad

Aurora Remote should be the second consumer of the package, but it should **not** be required to use the Prism controls visually unchanged.

The package should support two presentation families:

### Desktop controls

Optimized for:

- mouse
- trackpad
- keyboard
- hover
- compact workstation layout
- information density

### Touch controls

Optimized for:

- iPad
- iPhone
- large hit areas
- touch-first interaction
- glance readability
- live-performance operation
- minimal accidental activation

Both families should share underlying tokens and reusable mechanics where appropriate.

---

## 8. Add a dedicated touch-control stage before finalizing the package API

Recommended execution order:

### Stage A: Extract Prism controls unchanged

1. Add the `AuroraDesignSystem` package target.
2. Move generic tokens.
3. Move `AuroraButton`.
4. Repair imports.
5. Build Prism.
6. Verify visual parity.
7. Move generic fader geometry.
8. Move `AuroraFader`.
9. Repair programmer-specific dependencies.
10. Run unit and UI/gallery verification.

### Stage A.5: Add touch controls

Before moving the package into a standalone repository, add the initial touch-oriented control family.

The Remote raster sheet should be the visual north star.

Recommended initial touch components:

```text
AuroraTouchButton
AuroraTransportButton
AuroraGoButton
AuroraTouchFader
AuroraMasterFader
AuroraChip
AuroraStatusIndicator
AuroraTouchSegmentedControl
AuroraToolbarButton
AuroraDangerButton
```

The exact public names may be refined during implementation, but the conceptual separation should remain.

### Stage B: Standalone repository

Only after Prism and Aurora Remote both consume the same in-repository package successfully should the package move to its own Git repository.

This makes Aurora Remote the portability proof.

---

## 9. Cross-platform support should become an explicit requirement

The previous extraction plan allowed the package to remain macOS-only initially. That is acceptable for Stage A.

It is not sufficient for the completed reusable package because Aurora Remote is an iPad application.

Recommended platform sequence:

### Stage A

```swift
platforms: [
    .macOS(.v14)
]
```

### Stage A.5 and later

Add iPadOS/iOS support at Remote's actual deployment target.

For example:

```swift
platforms: [
    .macOS(.v14),
    .iOS(.v18)
]
```

Do not advertise platform support merely because the package compiles once.

Each supported platform should have:

- successful package build
- control gallery build
- interaction verification
- accessibility verification
- relevant automated tests

---

## 10. Isolate platform-specific behavior

Any AppKit dependency must be isolated.

Use patterns such as:

```swift
#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit
#endif
```

Prefer platform-neutral SwiftUI APIs where possible.

Platform-specific behavior may include:

- keyboard focus
- hover
- cursor behavior
- pointer handling
- tactile touch behavior
- iPad keyboard shortcuts
- macOS key events

Do not silently remove behavior on iPad simply to make compilation succeed.

Instead, define equivalent platform behavior where it makes sense.

---

## 11. Reuse fader mechanics, not necessarily fader rendering

The strongest candidate for shared implementation is the fader engine.

The reusable core should own:

```text
normalized value
clamping
geometry
drag tracking
track seek
editing lifecycle
display state
value formatting
accessibility increment/decrement
```

Then platform-specific controls can render those mechanics differently.

Example conceptual split:

```text
ValueFaderGeometry
        │
        ├── AuroraFader          ← Prism/macOS presentation
        │
        └── AuroraTouchFader     ← Remote/iPad presentation
```

This provides behavioral consistency without requiring desktop and touch applications to look identical.

---

## 12. Recommended editing lifecycle API

Both desktop and touch faders should expose a generic editing lifecycle.

For example:

```swift
onEditingChanged: (Bool) -> Void
```

or equivalent beginning/ending callbacks.

The design-system component should report editing state.

The consuming application should decide:

- whether to start an undo transaction
- whether to send a Prism command
- whether to transmit ACP state
- whether to debounce or coalesce values
- whether to commit a final value

The design system must never create Prism commands itself.

---

## 13. Preserve normalized values at the package boundary

Keep reusable faders normalized to:

```text
0.0 ... 1.0
```

The caller should map domain ranges into that normalized interval.

Examples:

```text
DMX 0...255         → caller mapping
Pan -270...270°     → caller mapping
Percentage 0...100  → caller mapping
Audio -∞...+10 dB   → caller mapping
```

This avoids contaminating the design system with application semantics.

A generic range-based convenience initializer may be added later if genuinely useful, but normalized behavior should remain the underlying primitive.

---

## 14. Resource handling

Avoid `Bundle.main` for package-owned resources.

If the library later contains images:

```swift
Bundle.module
```

must be used.

Where practical, prefer:

- SwiftUI shapes
- SF Symbols
- code-drawn geometry
- scalable vector resources

Do not make Remote depend on Prism's application asset catalog.

Aurora-family branding assets may eventually belong in the design-system package only if they are genuinely shared.

---

## 15. Tests to move into the package

Move generic fader tests from `AuroraUITests` into `AuroraDesignSystemTests`.

Required coverage should include:

- clamp below zero
- clamp above one
- normal in-range values
- vertical round-trip geometry
- horizontal round-trip geometry
- zero travel
- undersized travel
- drag offset preservation
- pointer hit testing
- track-click seek
- fine keyboard increment
- normal keyboard increment
- coarse keyboard increment
- accessibility increment
- mixed-value first edit
- unavailable-state interaction
- density-based geometry
- label abbreviation
- Unicode labels
- unusual whitespace
- small abbreviation limits

Prism-specific programmer-layout tests must remain in `AuroraUITests`.

---

## 16. Build a component gallery before adopting controls in Remote

Do not replace all of Remote's current SwiftUI controls immediately.

First create an isolated touch-control gallery.

The gallery should reproduce the Remote raster-sheet language and include:

### Buttons

- primary
- secondary
- quiet
- destructive
- transport
- selected
- disabled
- pressed
- active/latched
- icon-only
- icon + text

### GO control

- normal
- pressed
- disabled
- disconnected
- active-ready state if applicable

### Faders

- horizontal
- vertical
- minimum
- midpoint
- maximum
- disabled
- mixed
- unavailable
- custom accent
- compact
- standard
- performance/touch density

### Supporting controls

- Quick Look chip
- status indicator
- segmented control
- toolbar control
- blackout/danger state

Approve these visually before screen-wide integration.

---

## 17. Remote raster sheet is the visual specification

The Prism control gallery is the parity surface for Stage A.

The Aurora Remote raster sheet is the visual specification for Stage A.5.

Codex should not interpret the raster sheet loosely as inspiration. It should derive explicit implementation tokens from it, including:

- corner radii
- border treatment
- background elevation
- accent usage
- glow intensity
- typography hierarchy
- icon scale
- pressed-state displacement or luminance
- selected state
- disabled state
- danger state
- touch-target size
- fader track thickness
- thumb geometry
- spacing between icon and label

Once approved, those values should live as package tokens rather than being scattered as magic numbers through Remote.

---

## 18. Touch-target policy

Do not solve layout problems by shrinking controls.

Remote is a live-performance application.

Touch controls should prioritize:

- forgiving hit areas
- strong visual hierarchy
- legibility at arm's length
- low accidental activation risk
- predictable pressed feedback

A visually compact surface may still use a larger invisible hit area.

Where appropriate:

```swift
.contentShape(...)
```

or equivalent techniques should enlarge interaction zones without bloating the visual design.

---

## 19. Separate semantic danger from constant visual alarm

Destructive or live-safety controls such as blackout should have a dedicated semantic style.

However, they do not need to display full-alert red continuously.

Recommended behavior:

- idle: restrained dark red/maroon treatment
- pressed: stronger contrast
- active blackout: unmistakable high-attention state
- disabled/disconnected: clearly non-interactive

The library should support this state transition generically.

---

## 20. Avoid the "one button to rule them all" API

Do not create a single giant initializer with dozens of styling flags.

Avoid APIs that trend toward:

```swift
AuroraButton(
    primary: true,
    compact: false,
    touch: true,
    transport: true,
    destructive: false,
    glowing: true,
    ...
)
```

Prefer semantic component types or carefully scoped styles.

A component should describe its role clearly.

---

## 21. Explicit import rule

Every target that directly uses design-system symbols should explicitly import:

```swift
import AuroraDesignSystem
```

Do not use:

```swift
@_exported import AuroraDesignSystem
```

Explicit imports keep module ownership clear and prevent invisible dependency coupling.

---

## 22. Stage A acceptance criteria

Stage A is complete when:

- `AuroraDesignSystem` exists as an in-repository Swift package target.
- Prism builds.
- Prism tests pass.
- Existing Prism controls look unchanged.
- Existing Prism interactions behave unchanged.
- Generic fader behavior belongs to the design-system target.
- Programmer-specific layout remains in `AuroraUI`.
- No design-system source imports Prism feature modules.
- No duplicate production declarations exist.
- Generic tests have moved to the new test target.

---

## 23. Stage A.5 acceptance criteria

Stage A.5 is complete when:

- `AuroraDesignSystem` compiles for macOS and iPadOS/iOS.
- A touch-oriented control family exists.
- The touch controls use the approved Remote raster-sheet language.
- Remote has a standalone component gallery.
- The gallery has been visually approved.
- Generic fader behavior is shared rather than reimplemented.
- Platform-specific code is isolated.
- Accessibility works on iPad.
- Touch targets are appropriate for live use.
- Remote can consume the controls without importing Prism application modules.

---

## 24. Stage B acceptance criteria

Move the package to its own repository only when:

- Prism consumes the package successfully.
- Aurora Remote consumes the same package successfully.
- Neither application carries a local fork or copied control implementation.
- Both applications pass their build and test suites.
- The package has CI.
- The package has a changelog.
- The package has versioned tags.
- Resources load correctly from the package.
- No application-domain dependency has entered the package.

---

## 25. Recommended Codex execution order

Use this sequence:

1. Establish current Prism build/test baseline.
2. Capture Prism component-gallery reference screenshots.
3. Add in-repository `AuroraDesignSystem` product and target.
4. Move generic design tokens.
5. Extract `AuroraButton`.
6. Repair imports and access control.
7. Build and visually verify Prism buttons.
8. Split `ProgrammerColorFaderLayout` out of generic fader geometry.
9. Move `ValueFaderGeometry`.
10. Move `AuroraControlDisplayValue`.
11. Move `AuroraFader`.
12. Migrate generic tests.
13. Run Prism package tests.
14. Regenerate the Xcode project from `project.yml`.
15. Build Prism Debug and Release.
16. Confirm visual parity.
17. Add iPadOS/iOS platform support.
18. Add touch-control components.
19. Build the Remote component gallery.
20. Review the gallery against the Remote raster sheet.
21. Integrate approved controls into Remote.
22. Validate real iPad interaction.
23. Move `AuroraDesignSystem` into its standalone repository.
24. Tag the first reusable prerelease.
25. Update Prism and Remote to consume the tagged package.

---

## 26. Final principle

The desired result is **shared Aurora DNA, not identical controls everywhere**.

Prism and Remote should share:

- visual vocabulary
- color system
- typography
- semantic states
- interaction consistency
- geometry code where appropriate
- accessibility behavior
- tested control mechanics

They should be free to differ in:

- touch sizing
- information density
- pointer behavior
- hover behavior
- control proportions
- fader rendering
- transport layout
- performance-focused presentation

The library should make Aurora-family applications look and behave related without forcing a desktop workstation and a touch remote to pretend they are the same interface.
