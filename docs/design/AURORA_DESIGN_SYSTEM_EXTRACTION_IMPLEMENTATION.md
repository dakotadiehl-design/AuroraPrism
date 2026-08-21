# Aurora Design System Extraction — Implementation Directive

## 1. Purpose

Extract Aurora's custom fader, button, and the minimum design-system foundation they require from `AuroraUI` into a reusable Swift package module. The result must be consumable by Prism and other Aurora-family applications without copying source files, importing Prism application code, or linking a precompiled binary framework.

The implementation uses two controlled stages:

1. Create and validate an `AuroraDesignSystem` module inside the current Aurora package.
2. After the module boundary is proven, move that module into its own versioned Git repository.

The first stage is mandatory. It makes Prism the first consumer of the extracted API and exposes accidental dependencies before another application adopts it.

## 2. Desired outcome

At completion:

- `AuroraButton`, `AuroraButtonStyle`, and `AuroraFader` are declared by `AuroraDesignSystem`.
- Shared colors, typography, spacing, density, metrics, icons, display state, and fader geometry needed by those controls are declared by `AuroraDesignSystem`.
- `AuroraDesignSystem` depends only on Apple UI/system frameworks required by its implementation.
- It does not depend on `AuroraUI`, `AuroraModel`, `AuroraCore`, `AuroraEngine`, `AuroraMIDI`, `AuroraFixtureLib`, `AuroraDiagnostics`, `PrismACP`, or the Prism executable target.
- `AuroraUI` imports and consumes `AuroraDesignSystem`; it does not maintain duplicate implementations.
- The existing public behavior and visual appearance of the fader and button remain unchanged unless a change is explicitly called out in this directive.
- Pure behavior is covered by package tests, and visual/control states are represented in a component gallery.
- Other Aurora-family projects can consume a tagged Swift Package dependency and write `import AuroraDesignSystem`.

## 3. Non-goals

This change does not:

- Extract all of `AuroraUI`.
- Move programmer panels, fixture presentation, DMX behavior, show state, or application routing into the design system.
- Redesign the controls.
- Replace SwiftUI with AppKit controls.
- Introduce an XCFramework or binary distribution.
- Preserve compatibility with copied, independently modified versions of the controls.
- Change Prism's user-facing product name or the `.prism` document format.

## 4. Architectural decision

Use a source-based Swift Package library product named `AuroraDesignSystem`.

Do not copy the files into each application. Copying creates independent implementations that will drift in behavior, accessibility, appearance, and bug fixes. Do not use an XCFramework unless closed-source distribution becomes a separate requirement; binary packaging adds signing, architecture, debugging, and release overhead without helping internal Aurora-family reuse.

The intended dependency direction is:

```text
SwiftUI / AppKit
       │
       ▼
AuroraDesignSystem
       │
       ▼
    AuroraUI
       │
       ▼
 Prism application
```

No dependency arrow may point from `AuroraDesignSystem` back toward an application or feature module.

## 5. Current implementation inventory

### 5.1 Initial extraction set

Move these files into the new target as part of the first extraction:

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

Review `AuroraTokens.swift` separately. Move only the tokens or modifiers required by the extracted controls. Do not pull `AuroraPanelChrome` into the package merely because it shares a file with generic tokens. Split the file if necessary.

### 5.2 Types expected to become package API

The initial public API includes:

- `AuroraButton`
- `AuroraButtonStyle`
- `AuroraButtonStyleKind`
- `AuroraFader`
- `AuroraControlDisplayValue`
- `AuroraDensity` and the corresponding SwiftUI environment value/modifier
- `AuroraColor`
- `AuroraMetrics`
- `AuroraSpacing`
- `AuroraTypography`
- `AuroraAnimation`, if required by package controls
- `AuroraLightingIcon` and `AuroraAssetIcon`, if the fader retains named-icon support
- `ValueFaderMetrics`
- `ValueFaderGeometry`

Public status is not a requirement for every stored token. Keep implementation details internal unless family applications need to reference them directly.

## 6. Required boundary corrections

### 6.1 Separate programmer layout from generic fader geometry

`ValueFaderGeometry.swift` currently contains `ProgrammerColorFaderLayout`. Most of that type describes Prism's programmer/color-engine composition rather than the fader itself.

Perform the following split:

- Keep normalized value conversion, travel, pointer hit testing, drag offsets, clamping, keyboard steps, and accessibility steps in `ValueFaderGeometry`.
- Move panel sizing, emitter-region overflow, minimum programmer width, and color-wheel relationships into `AuroraUI/Panels/Programmer/ProgrammerColorFaderLayout.swift`.
- Replace the fader's use of `ProgrammerColorFaderLayout.displayLabel` with a package-neutral label formatter.

Preferred package-neutral API:

```swift
public enum AuroraControlLabelFormatter {
    public static func abbreviated(_ label: String, maximumCharacterCount: Int = 10) -> String
}
```

Alternatively, keep label abbreviation private to `AuroraFader` until another component needs it. Do not expose a type whose name refers to Prism's programmer panel from the reusable package.

### 6.2 Make display state domain-neutral

`AuroraControlDisplayValue` is conceptually reusable, but its documentation and convenience factories must not describe or accept programmer-domain state.

Keep these generic cases:

```swift
case value(Double)
case mixed
case unavailable
```

Keep generic properties such as `isInteractive` and `concreteValue`. Move `from(attributeState:isMixed:displayValue:untreatedDefault:)` into `AuroraUI` because it translates Prism/application state into a design-system display value.

The application adapter may be an extension in `AuroraUI`, for example:

```text
Sources/AuroraUI/Adapters/AuroraControlDisplayValue+Programmer.swift
```

### 6.3 Keep product behavior outside the control

The reusable fader may own:

- Rendering and animation
- Pointer, keyboard, hover, focus, and accessibility interaction
- Normalized `0...1` value behavior
- Vertical and horizontal axes
- Mixed and unavailable rendering
- Density and explicit channel-height behavior
- Accent color and value formatting
- Editing lifecycle callbacks
- Generic ownership/active-state chrome if the terminology is made neutral

The reusable fader must not own:

- Fixture or emitter models
- Programmer selection rules
- Command or undo construction
- DMX conversion or output
- MIDI routing
- Prism logging
- Panel sizing involving unrelated controls

Callers remain responsible for mapping domain values to a normalized binding and for committing commands at the end of editing.

### 6.4 Platform boundary

The current package supports macOS 14 and the fader uses macOS-oriented keyboard handling. The first reusable release may remain macOS 14+.

Do not claim iOS, iPadOS, or visionOS support until the code compiles and interaction behavior is tested on those platforms. If cross-platform support is later required, isolate AppKit code behind `#if canImport(AppKit)` and provide platform-equivalent key/focus behavior rather than silently dropping functionality.

## 7. Stage A — in-repository module extraction

### 7.1 Establish a safe baseline

Before moving files:

- Record the current build and test status.
- Preserve unrelated worktree changes; do not reset or overwrite them.
- Prefer a focused branch such as `codex/aurora-design-system-extraction` when branch creation fits the active workflow.
- Capture reference screenshots for the fader gallery and button states so visual parity can be evaluated after the move.

This repository may contain concurrent work. File moves and manifest edits must be rebased or applied carefully around existing changes, especially changes to `Package.swift`, `project.yml`, and `Aurora.xcodeproj/project.pbxproj`.

### 7.2 Add the library product and target

Add this product to `Package.swift`:

```swift
.library(name: "AuroraDesignSystem", targets: ["AuroraDesignSystem"]),
```

Add this target before `AuroraUI`:

```swift
.target(
    name: "AuroraDesignSystem"
),
```

Add `AuroraDesignSystem` to the dependency list of `AuroraUI`:

```swift
.target(
    name: "AuroraUI",
    dependencies: [
        "AuroraDesignSystem",
        // existing dependencies
    ]
)
```

The Prism executable normally receives the module transitively through `AuroraUI`. Add a direct executable dependency only if files in `Sources/Aurora` directly import `AuroraDesignSystem`. Prefer explicit direct dependencies over relying on transitive imports.

### 7.3 Create the target layout

Use this structure:

```text
Sources/AuroraDesignSystem/
├── Components/
│   ├── AuroraButton.swift
│   ├── AuroraControlDisplayValue.swift
│   ├── AuroraFader.swift
│   └── ValueFaderGeometry.swift
├── Formatting/
│   └── AuroraControlLabelFormatter.swift       # if exposed
├── Icons/
│   └── AuroraAssetIcon.swift
└── Tokens/
    ├── AuroraAnimation.swift
    ├── AuroraColors.swift
    ├── AuroraDensity.swift
    ├── AuroraMetrics.swift
    ├── AuroraSpacing.swift
    └── AuroraTypography.swift
```

Swift Package targets discover source files recursively, so no per-file manifest declarations are necessary.

Move files rather than copying them. There must never be two production declarations of the same public type.

### 7.4 Repair imports and access control

After the move:

- Add `import AuroraDesignSystem` to every `AuroraUI` or Prism source file that uses an extracted symbol.
- Do not use `@_exported import AuroraDesignSystem`; consumers should declare the modules they use.
- Ensure initializers and properties required by consuming applications remain `public`.
- Keep rendering helpers, shapes, and implementation-only constants `private` or internal.
- Do not broaden access control merely to make tests convenient. Prefer testing through public behavior or `@testable import AuroraDesignSystem`.

Use compiler errors to discover consumers, then use `rg` to confirm there are no unresolved references or duplicate declarations.

### 7.5 Preserve source compatibility

During Stage A, keep existing call sites working whenever possible:

```swift
AuroraFader(value: $value, label: "Dimmer")

Button("Build") { ... }
    .buttonStyle(AuroraButtonStyle(kind: .primary))

AuroraButton("Delete", kind: .destructive) { ... }
```

Avoid renaming public controls during extraction. Boundary corrections may relocate convenience functions, but they should not change the primary fader and button initializers unless a current parameter is genuinely application-specific.

### 7.6 Update XcodeGen configuration

`project.yml` identifies the root Swift package as `AuroraPackage`. Because `AuroraUI` consumes `AuroraDesignSystem` internally, no application-level product entry is required unless application-target files import the module directly.

If a direct dependency is needed, add:

```yaml
- package: AuroraPackage
  product: AuroraDesignSystem
```

Treat `project.yml` as the Xcode project source of truth. Regenerate the project using the repository's documented generation command rather than manually maintaining divergent `.pbxproj` structure.

## 8. Stage A testing and verification

### 8.1 Add the test target

Add:

```swift
.testTarget(
    name: "AuroraDesignSystemTests",
    dependencies: ["AuroraDesignSystem"]
),
```

Create:

```text
Tests/AuroraDesignSystemTests/
├── AuroraControlDisplayValueTests.swift
├── AuroraControlLabelFormatterTests.swift
└── ValueFaderGeometryTests.swift
```

Move the existing `Tests/AuroraUITests/ValueFaderGeometryTests.swift` into the new test target. Keep programmer-layout tests in `AuroraUITests` after splitting `ProgrammerColorFaderLayout` out of the generic geometry file.

### 8.2 Required unit coverage

Test at minimum:

- Clamp below zero, within range, and above one
- Vertical value-to-position and position-to-value round trips
- Horizontal value-to-position and position-to-value round trips
- Zero or undersized travel areas
- Pointer hit testing and drag offset preservation
- Track-click seek behavior
- Fine, normal, and coarse keyboard increments
- Accessibility increment size
- Mixed-value first keyboard edit
- Interactive behavior of value, mixed, and unavailable display states
- Density-specific metrics
- Label abbreviation, including short labels, long single words, multiple words, whitespace, Unicode, and very small limits

Button rendering is primarily visual, but its public semantic kinds and construction must at least compile in a package smoke test.

### 8.3 Component gallery

Keep the existing Aurora component gallery as the visual acceptance surface during Stage A. Add or retain examples for:

- Button: primary, secondary, destructive, and quiet
- Button: normal, selected, disabled, and custom-label content
- Fader: vertical and horizontal
- Fader: zero, midpoint, full, mixed, unavailable, disabled, focused, and owned/active
- Fader: compact, standard, and performance density
- Fader: custom accent and custom value formatter
- Fader: short, long, and icon-bearing labels

Preview-only code may remain in `AuroraUI` initially. A standalone package gallery can be added during Stage B.

### 8.4 Verification commands

Run the narrowest checks first, followed by the full package suite:

```bash
swift test --filter AuroraDesignSystemTests
swift test --filter AuroraUITests
swift test
```

Then regenerate and build the Xcode project through the repository's standard workflow. If the application has a documented `xcodebuild` scheme, build both Debug and Release configurations.

### 8.5 Visual parity gate

Compare pre-extraction and post-extraction captures at identical size, scale, appearance, density, and state. The extraction passes when there is no unintended difference in:

- Control dimensions and alignment
- Gradients, borders, shadows, indicators, and glow
- Typography and label truncation
- Hover, press, selection, disabled, focus, mixed, and unavailable appearance
- Fader thumb position and track fill
- Pointer drag behavior and keyboard editing

## 9. Stage A acceptance criteria

Stage A is complete only when all of the following are true:

- `swift build` succeeds.
- `swift test` succeeds, or any unrelated pre-existing failure is documented with evidence.
- Prism builds from the regenerated Xcode project.
- The component gallery demonstrates visual parity.
- `AuroraDesignSystem` has no Aurora feature-module dependencies.
- `AuroraUI` contains no duplicate fader, button, token, or geometry implementation.
- Programmer-specific layout code remains in `AuroraUI`.
- All direct consumers import `AuroraDesignSystem` explicitly.
- The new design-system tests own generic control behavior.

## 10. Stage B — standalone package repository

Start Stage B only after Stage A is accepted.

### 10.1 Repository structure

Create a dedicated repository, recommended name `AuroraDesignSystem`:

```text
AuroraDesignSystem/
├── Package.swift
├── README.md
├── CHANGELOG.md
├── LICENSE                         # according to organization policy
├── Sources/
│   └── AuroraDesignSystem/
└── Tests/
    └── AuroraDesignSystemTests/
```

Use a minimal manifest:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AuroraDesignSystem",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "AuroraDesignSystem",
            targets: ["AuroraDesignSystem"]
        ),
    ],
    targets: [
        .target(name: "AuroraDesignSystem"),
        .testTarget(
            name: "AuroraDesignSystemTests",
            dependencies: ["AuroraDesignSystem"]
        ),
    ]
)
```

Do not add Aurora application packages as dependencies to make the move compile. A dependency request in that direction indicates that the boundary is incomplete.

### 10.2 Preserve history where practical

Prefer extracting the relevant paths with Git history rather than starting with an unexplained source dump. A history-filtering workflow may be used in a temporary clone, followed by path normalization in the new repository. Do not rewrite the active Aurora repository's history.

If preserving file history is disproportionately complex, make the first package commit clearly reference the Aurora source commit from which it was extracted.

### 10.3 Local integration first

Place local checkouts beside one another during integration:

```text
Parent/
├── Aurora/
└── AuroraDesignSystem/
```

Temporarily change Aurora's root manifest to:

```swift
dependencies: [
    .package(path: "../AuroraDesignSystem"),
    // existing dependencies
]
```

Then change target dependencies to the external product form:

```swift
.product(
    name: "AuroraDesignSystem",
    package: "AuroraDesignSystem"
)
```

Remove `Sources/AuroraDesignSystem` and `Tests/AuroraDesignSystemTests` from the Aurora repository only after the local external dependency builds and all tests pass. This removal is expected and should occur in the same migration change so there is still one source of truth.

### 10.4 Versioned integration

After local validation:

1. Push the package repository.
2. Run its tests in CI.
3. Tag the first reusable prerelease, such as `0.1.0`.
4. Replace Aurora's local path with the repository URL.
5. Resolve dependencies and run Aurora's full verification again.

Example production dependency:

```swift
.package(
    url: "git@github.com:YOUR-ORGANIZATION/AuroraDesignSystem.git",
    from: "0.1.0"
)
```

Use the organization's actual HTTPS or SSH convention. Do not commit developer-specific absolute paths.

## 11. Adoption by another Aurora-family application

The second application is the portability proof.

For the first adopter:

1. Add the tagged package dependency.
2. Add the `AuroraDesignSystem` product to the appropriate UI target.
3. Import the module explicitly.
4. Build a small gallery before integrating controls into feature screens.
5. Exercise keyboard, pointer, accessibility, density, and disabled states.
6. Report any requested API change back to the package; do not fork or copy the source.

Do not reach `1.0.0` until Prism and at least one other Aurora-family application consume the same tagged package without local patches.

## 12. Versioning and release policy

Use semantic versioning:

- `0.1.x`: extraction and API refinement
- `0.2.0`, `0.3.0`, and similar: intentional prerelease API changes
- `1.0.0`: stable API used by at least two family applications
- Patch: compatible fixes and visual corrections
- Minor: backward-compatible components, states, or configuration
- Major: breaking source or behavioral changes

Each release must include:

- A Git tag
- Passing package tests
- A changelog entry
- Notes about intentional visual changes
- The minimum supported platform and Swift tools version

Applications should normally depend on a compatible version range rather than a branch. Branch dependencies are acceptable only for short-lived coordinated development.

## 13. API evolution rules

Follow these rules after extraction:

- Prefer additive initializer defaults over new mandatory parameters.
- Treat colors, spacing, metrics, and interaction behavior as versioned API even when the compiler cannot detect their change.
- Use semantic configuration rather than exposing internal shapes or gradient layers.
- Keep domain mapping in adapters owned by the consuming application.
- Add a regression test for every geometry or interaction bug.
- Add a gallery state for every significant visual mode.
- Deprecate before removing public API after `1.0.0`.
- Avoid application-specific terminology in public names and documentation.

## 14. Risks and mitigations

### Accidental dependency expansion

Risk: moving a control pulls most of `AuroraUI` into the new module.

Mitigation: move only direct design foundations; use parameters or application adapters for domain behavior. Reject dependencies on feature modules.

### Token ownership ambiguity

Risk: moving shared tokens breaks unrelated `AuroraUI` components.

Mitigation: make `AuroraUI` depend on and import `AuroraDesignSystem`. Shared tokens should have one owner, even if many existing components use them.

### Visual regression during a file-only move

Risk: environment defaults, access control changes, or resource lookup alter rendering.

Mitigation: capture reference states, preserve default density, and perform image-based visual comparison.

### Resource lookup failure

Risk: package icons or images are loaded from the wrong bundle after Stage B.

Mitigation: prefer SF Symbols or code-drawn assets where appropriate. For package resources, declare them in `Package.swift` and load them from `Bundle.module`, never `Bundle.main`.

### Concurrent manifest or project edits

Risk: active changes to `Package.swift`, `project.yml`, or the generated Xcode project are overwritten.

Mitigation: make narrow edits, preserve unrelated lines, regenerate from `project.yml`, and inspect diffs before committing.

### Premature cross-platform promise

Risk: listing iOS support while keyboard/focus behavior remains macOS-specific.

Mitigation: publish macOS 14+ initially and add platforms only with compile and interaction tests.

## 15. Suggested commit sequence

Keep the migration reviewable with focused commits:

1. `Add AuroraDesignSystem target and tests`
2. `Move shared design tokens into AuroraDesignSystem`
3. `Extract Aurora button into AuroraDesignSystem`
4. `Separate programmer layout from generic fader geometry`
5. `Extract Aurora fader into AuroraDesignSystem`
6. `Migrate AuroraUI and Prism imports`
7. `Add component gallery coverage and verify visual parity`
8. `Move AuroraDesignSystem to standalone package repository` — Stage B only
9. `Consume tagged AuroraDesignSystem package from Aurora`

Every commit should build where practical. Do not mix unrelated application work into these commits.

## 16. Definition of done

The overall initiative is complete when:

- The standalone `AuroraDesignSystem` repository is the only owner of the shared control implementations.
- Prism consumes a tagged package version.
- At least one additional Aurora-family application consumes the same package version without copied code or a private patch.
- Package and application tests pass.
- The component gallery confirms expected rendering and interaction.
- Package documentation shows installation and basic button/fader examples.
- The changelog and semantic-versioning policy are in place.
- No application-domain dependency has entered the reusable package.

## 17. Recommended first implementation checkpoint

Implement Stage A through the button extraction before moving the fader:

1. Add the module and test target.
2. Move the required tokens.
3. Move `AuroraButton` and repair imports.
4. Build and visually verify buttons.

This checkpoint validates module wiring and token ownership with the smaller control. Continue with the more coupled fader only after the button checkpoint is clean.
