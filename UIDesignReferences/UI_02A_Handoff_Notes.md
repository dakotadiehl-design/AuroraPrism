# UI-02A Handoff Notes — COMPLETE

**Date:** 2026-08-05  
**Status:** **UI-02A COMPLETE**

## How to review (final)

1. Open `Aurora.xcodeproj`, Run (Debug).
2. Demo **Summer Night Show** auto-loads in DEBUG when empty, or **File → Open Demo Show** (`⇧⌘D`).
3. Confirm lighting icons on Programmer / palette kinds / inspector capabilities.
4. Compare to `UIDesignReferences/Renders/DesignOverview.png` (Build Mode).

---

## Production path

```text
AuroraBuildToolbar → BuildWorkspaceHost → AuroraAppStatusBar
```

- Legacy host: `LegacyWorkspaceView` (not used on launch)
- Demo: `ShowProject.demoSummerNight()` via real session load

---

## Brand & AppIcon

| Asset | Status |
|-------|--------|
| **AppIcon** | `AppIcon.appiconset` + `ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon`; built app contains `AppIcon.icns` |
| **AuroraMark** | Toolbar: `[AuroraMark] AURORA` via `AuroraBrandViews` |
| **AuroraWordmark** | Packaged; reserved for welcome/About (not forced into toolbar) |

If Dock/Finder still shows an old icon: clean DerivedData and rebuild the **new** `.app` (cache), do not regenerate artwork.

---

## Custom lighting icons

### Masters preserved

```text
App/DesignAssets/VectorSources/   # original SVG masters (14 files)
App/DesignAssets/BrandMasters/
App/DesignAssets/DocumentIcons/
App/DesignAssets/MenuBar/
App/DesignAssets/Source/
```

### Packaged Xcode imagesets (`App/Assets.xcassets/`)

| Asset name | Used in running UI (UI-02A) |
|------------|------------------------------|
| IntensityIcon | Programmer fader label, fixture chips |
| DimmerIcon | Inspector capabilities |
| PositionIcon | Position palette tiles |
| PanTiltIcon | Programmer position pad header, inspector |
| ColorWheelIcon | Programmer color header, inspector |
| BeamIcon | Programmer beam well, beam palettes, inspector |
| GoboIcon | Gobo matrix header, gobo palettes |
| PrismIcon | Packaged (available) |
| IrisIcon | Packaged (available) |
| StrobeIcon | Packaged (available) |
| SmokeIcon | Packaged (available) |
| LaserIcon | Packaged (available) |
| GrandMasterIcon | Packaged (available; no GM control in Build shell yet) |
| PixelMapIcon | Packaged (available) |

### Icon API

- `AuroraAssetIcon` — **lightweight**: `Bundle.main` lookup, template rendering, size only  
- Callers apply `.foregroundStyle(...)` for semantic state  
- SF Symbols remain for generic actions (New/Open/Save, search, checkmarks)

---

## Catalog hygiene

`Assets.xcassets` contains only compile targets: AppIcon, AccentColor, Mark, Wordmark, `*Icon.imageset`.  
Raw SVG dump and master PNGs removed from the catalog after copying to DesignAssets.

---

## Verification

- `swift test` — **264** passed  
- Xcode Debug build — **succeeded** (no imageset errors)  
- Backend / domain semantics — **unchanged**  
- Build workspace hierarchy — **not redesigned** in this closeout  

---

## Remaining visual discrepancies (non-blocking)

| Area | Note |
|------|------|
| Workspace tool tabs under Programmer | Render shows Patch/Groups… strip; not required to restructure 02A |
| Full Perform cockpit | Placeholder only (later UI-02) |
| Settings / MIDI surface | Later UI-02 |
| Grand Master / unused icons | Packaged for later use |
| Welcome wordmark empty state | Optional polish later |

---

## Direction after UI-02A

> **Aurora's actual running application uses the new visual language.**

Next work builds outward (remaining UI-02 surfaces) when requested — do not reopen UI-02A redesign.
