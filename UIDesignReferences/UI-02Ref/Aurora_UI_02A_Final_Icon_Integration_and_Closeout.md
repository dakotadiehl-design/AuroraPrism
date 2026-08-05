# Aurora UI-02A --- Final Polish, Icon Integration, and Closeout

**Status:** Final UI-02A cleanup before moving into full UI-02\
**Basis:** Review of the latest `Aurora_UI2A` revision\
**Primary objective:** Finish the icon/asset integration, verify the
production app presentation, and close UI-02A without expanding its
scope.

------------------------------------------------------------------------

# 1. Overall Assessment

The latest UI-02A revision represents the visual breakthrough we were
trying to achieve.

The new design system is now being used by the **actual running Aurora
application**, rather than existing primarily in the component gallery.

The production composition has moved toward:

``` text
AuroraBuildToolbar
        ↓
BuildWorkspaceHost
        ↓
AuroraAppStatusBar
```

and the old workspace shell is no longer the primary visual experience.

The current direction is approved.

Do **not** redesign UI-02A again.

This pass should focus on:

1.  fixing/validating AppIcon behavior
2.  properly packaging and integrating Aurora's custom lighting icons
3.  cleaning the asset catalog
4.  performing final running-app visual verification
5.  closing UI-02A

Then proceed into the broader UI-02 roadmap.

------------------------------------------------------------------------

# 2. AppIcon Configuration Appears Correct

The current project configuration already appears to contain the correct
Xcode AppIcon wiring.

Verify both:

``` text
project.yml
```

and:

``` text
Aurora.xcodeproj/project.pbxproj
```

continue to specify:

``` text
ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon
```

The asset catalog should contain:

``` text
App/Assets.xcassets/AppIcon.appiconset/
```

with all required macOS icon representations and a valid
`Contents.json`.

Do not change this configuration unless verification finds an actual
problem.

------------------------------------------------------------------------

# 3. Investigate macOS / Xcode AppIcon Caching Before Reworking Assets

If the correct Aurora AppIcon still does not appear in Finder, the Dock,
or the built application, first treat this as a possible build/cache
issue.

Perform a clean verification:

1.  Quit all running copies of Aurora.
2.  **Product → Clean Build Folder** in Xcode.
3.  Remove Aurora's DerivedData if necessary.
4.  Rebuild the application.
5.  Verify the newly built `.app`, not an older copy.
6.  Confirm the built bundle contains the compiled AppIcon resources.
7.  Launch the newly built application.
8.  Verify Finder/Dock presentation.

Also verify there is no conflicting legacy `CFBundleIconFile` or
equivalent override.

Do not regenerate the approved artwork merely because macOS is
displaying a cached icon.

------------------------------------------------------------------------

# 4. AuroraMark and AuroraWordmark

The approved brand assets should remain packaged as real image sets:

``` text
App/Assets.xcassets/
├── AuroraMark.imageset/
└── AuroraWordmark.imageset/
```

The current toolbar treatment using the Aurora mark with native `AURORA`
typography is appropriate.

Preferred permanent toolbar identity:

``` text
[AuroraMark]  AURORA
```

Use the full `AuroraWordmark` more selectively for:

-   welcome / no-project state
-   About Aurora
-   future splash/launch presentation
-   future web/iPad remote branding
-   documentation/marketing surfaces where appropriate

Do not stamp the Aurora logo into every panel.

------------------------------------------------------------------------

# 5. The Custom Lighting Icons Need Proper Xcode Asset Packaging

The remaining significant asset issue is the custom lighting icon
collection.

Raw SVG files placed inside a directory such as:

``` text
App/Assets.xcassets/VectorIcons/
```

are not, by themselves, equivalent to named Xcode image assets.

Convert the approved lighting SVGs that Aurora will use into proper
`.imageset` assets.

For example:

``` text
App/Assets.xcassets/IntensityIcon.imageset/
├── intensity.svg
└── Contents.json
```

The image set should preserve vector representation and use template
rendering where appropriate.

A representative `Contents.json` structure is:

``` json
{
  "images": [
    {
      "filename": "intensity.svg",
      "idiom": "universal",
      "scale": "1x"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  },
  "properties": {
    "preserves-vector-representation": true,
    "template-rendering-intent": "template"
  }
}
```

Verify the exact Xcode asset-catalog format during implementation/build
rather than blindly assuming this sample is sufficient.

Once packaged, SwiftUI should be able to reference a stable named asset
such as:

``` swift
Image("IntensityIcon")
```

and apply Aurora semantic styling.

------------------------------------------------------------------------

# 6. Recommended Lighting Icon Asset Names

Package the approved SVGs with stable semantic Xcode asset names.

Recommended mappings include:

  Source artwork       Xcode asset
  -------------------- -------------------
  `intensity.svg`      `IntensityIcon`
  `dimmer.svg`         `DimmerIcon`
  `position.svg`       `PositionIcon`
  `pan-tilt.svg`       `PanTiltIcon`
  `color-wheel.svg`    `ColorWheelIcon`
  `beam.svg`           `BeamIcon`
  `gobo.svg`           `GoboIcon`
  `prism.svg`          `PrismIcon`
  `iris.svg`           `IrisIcon`
  `strobe.svg`         `StrobeIcon`
  `smoke.svg`          `SmokeIcon`
  `laser.svg`          `LaserIcon`
  `grand-master.svg`   `GrandMasterIcon`
  `pixel-map.svg`      `PixelMapIcon`

If additional approved icons exist, package them only when they have a
clear Aurora UI use.

Do not create duplicate names or parallel icon systems.

------------------------------------------------------------------------

# 7. Custom Icons vs SF Symbols

Use a simple rule.

## Prefer SF Symbols for generic application actions

Examples:

``` text
Add
Delete
Search
Save
Open
Settings
Refresh
Back/forward navigation
Disclosure
Close
```

These benefit from native macOS familiarity.

## Prefer Aurora custom icons for lighting-specific concepts

Examples:

``` text
Intensity
Dimmer
Pan/Tilt
Position
Color Wheel
Beam
Gobo
Prism
Iris
Strobe
Grand Master
Pixel Mapping
Smoke/Haze
Laser
```

These are part of Aurora's professional lighting vocabulary.

The goal is not to maximize custom-icon usage.

The goal is to give Aurora a recognizable lighting-specific visual
language while remaining a polished macOS application.

------------------------------------------------------------------------

# 8. Integrate the Custom Icons Into the Actual Running UI

Do not stop after packaging the imagesets.

Use the approved custom icons in the real UI-02A workspace where they
improve clarity.

Priority locations include:

### Programmer

Use custom icons for attribute families such as:

``` text
Intensity
Color
Position
Beam
Gobo
```

where appropriate.

### Programmer controls

Use relevant lighting icons for:

-   pan/tilt
-   dimmer
-   beam
-   gobo
-   prism
-   iris
-   strobe

### Fixture / palette surfaces

Use lighting-specific icons where they help distinguish object type or
capability.

### Masters / output

Use `GrandMasterIcon` where a Grand Master control is represented.

Do not replace clear textual labels with unexplained icons.

Icon + label is often preferable for professional controls.

------------------------------------------------------------------------

# 9. Keep Icon Treatment Consistent

Define or reuse a shared Aurora icon treatment.

Keep consistent:

-   nominal icon sizes
-   alignment
-   template rendering
-   semantic foreground colors
-   selected state
-   hover state
-   disabled state
-   warning/critical treatment where relevant

Avoid each panel inventing its own icon size and tint.

Where possible, create a small reusable icon view/style rather than
scattering magic numbers throughout the UI.

------------------------------------------------------------------------

# 10. Clean the Asset Catalog

The Xcode asset catalog should primarily contain actual compiled
asset-catalog resources.

Avoid leaving source/master artwork as loose files inside
`Assets.xcassets` if Xcode does not need them there.

Recommended organization:

``` text
App/
├── Assets.xcassets/
│   ├── AppIcon.appiconset/
│   ├── AccentColor.colorset/
│   ├── AuroraMark.imageset/
│   ├── AuroraWordmark.imageset/
│   ├── IntensityIcon.imageset/
│   ├── DimmerIcon.imageset/
│   ├── PositionIcon.imageset/
│   ├── PanTiltIcon.imageset/
│   ├── ColorWheelIcon.imageset/
│   ├── BeamIcon.imageset/
│   ├── GoboIcon.imageset/
│   ├── PrismIcon.imageset/
│   ├── IrisIcon.imageset/
│   ├── StrobeIcon.imageset/
│   ├── GrandMasterIcon.imageset/
│   └── ...
│
└── DesignAssets/
    ├── BrandMasters/
    ├── VectorSources/
    ├── DocumentIcons/
    ├── MenuBarSources/
    └── Source/
```

`DesignAssets` may live elsewhere in the repository if another location
fits the project structure better.

The principle is:

> **Source artwork and compiled Xcode assets should not be casually
> mixed together.**

Do not delete approved source artwork. Move it to an appropriate
source/design-assets location if it does not belong inside the asset
catalog.

------------------------------------------------------------------------

# 11. Do Not Disturb the UI-02A Breakthrough

The current production workspace direction is approved.

Do not use this cleanup pass as an excuse to restructure the Build
workspace again.

Preserve the new hierarchy:

``` text
Fixture Browser  |  PROGRAMMER  |  Inspector
─────────────────────────────────────────────
Palettes / Looks |  Cue List / show workflow
```

with:

-   Aurora toolbar above
-   Programmer as visual center of gravity
-   purposeful panel chrome
-   quiet health/status information
-   real palette/cue presentation
-   Aurora identity integrated into the shell

Only make visual changes necessary to finish icon/asset integration or
correct obvious defects.

------------------------------------------------------------------------

# 12. Final UI-02A Visual Verification

After icon integration and asset cleanup, launch the **actual Aurora
application** with the deterministic populated demo project.

Verify:

``` text
[ ] New Build workspace is the production UI path

[ ] Legacy workspace does not appear during normal launch

[ ] Aurora AppIcon appears correctly in the built app

[ ] AuroraMark appears correctly in the toolbar

[ ] AuroraWordmark resolves correctly where used

[ ] Custom lighting icons resolve from Assets.xcassets

[ ] Programmer uses appropriate Aurora lighting icons

[ ] Icons remain sharp at normal and Retina scaling

[ ] Template icons respond correctly to semantic tint/state

[ ] No missing-image placeholders appear

[ ] SF Symbols remain in appropriate generic-action roles

[ ] Asset catalog builds without warnings/errors related to the new imagesets

[ ] Demo show remains functional

[ ] Programmer/fixture/palette/cue behavior remains functional

[ ] Backend/domain semantics remain unchanged
```

------------------------------------------------------------------------

# 13. Final Screenshot Review

Before closing UI-02A, capture the actual running application with the
populated demo project.

Compare it against the approved Build Mode reference in these areas:

``` text
Toolbar / Aurora identity
Surface hierarchy
Programmer prominence
Navigation hierarchy
Panel treatment
Fixture Browser density
Palette richness
Cue-list grammar
Inspector hierarchy
Status / health chrome
Lighting-specific icon language
Overall creative character
```

Document only meaningful remaining discrepancies.

Do not invent a numeric similarity percentage.

------------------------------------------------------------------------

# 14. UI-02A Closeout Handoff

When this cleanup is complete, provide:

1.  updated repository
2.  running-app screenshot with the populated demo project
3.  confirmation that the AppIcon is visible correctly
4.  confirmation that AuroraMark resolves correctly
5.  confirmation that AuroraWordmark resolves correctly
6.  list of custom lighting icons converted into Xcode imagesets
7.  list of custom lighting icons actually used in the running UI
8.  confirmation that the asset catalog builds cleanly
9.  short list of any remaining visual discrepancies
10. confirmation that backend/domain semantics were unchanged

Then mark:

> **UI-02A COMPLETE**

and stop.

Do not expand this closeout pass into the rest of UI-02.

------------------------------------------------------------------------

# 15. Direction After UI-02A

Once the above is verified, UI-02A should be considered complete.

The key objective of UI-02A has been achieved:

> **Aurora's actual running application now uses the new visual
> language.**

The next phase can move forward from that foundation rather than
continuing to revisit the initial visual-system problem.

UI-02 should build outward from the successful real-workspace
implementation into the remaining application surfaces and workflows.

------------------------------------------------------------------------

# Final Instruction

Do not redesign UI-02A again.

Finish the icon pipeline, verify the AppIcon, integrate the approved
lighting-specific assets, clean the asset catalog, perform one final
running-app review, and close the phase.

Then we move forward.
