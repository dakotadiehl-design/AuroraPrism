# Checkpoint C4 — Stage Designer & Visual Polish

**Status:** Implemented for human review  
**Build:** Xcode Debug BUILD SUCCEEDED · `swift test` C4 filters green  
**Date:** 2026-08-14  
**Roadmap:** `UIDesignReferences/Aurora_C4_C5_C6_UX_Redesign_Roadmap.md`  
**Assets:** `Silhouette Kit/Aurora_Silhouette_Kit` → bundled `Sources/AuroraUI/Resources/StageAssets`

## What landed (all subphases)

### C4A — Unified object interaction
- `StageLayout` schema **v2**: `objects: [StageLayoutObject]` (+ legacy `scenic` migrate/encode)
- Kinds: `shape`, `stockImage`, `importedImage`, `text`
- Select / multi-select / live drag / lock / delete for layout objects
- **Resize** via SE handle (live preview + one Undo commit; center-fixed; min size 8)
- **Rotate** via Edit Stage object property slider (degrees → radians)
- **Duplicate** from context menu and Edit Stage chrome
- Geometry **locked** outside Edit Stage
- Finalizer moves fixtures **and** objects (one commit / one Undo)

### C4B — Stage Object palette
- Edit Stage left rail tab **Objects**
- Sections: Performers · Audience · Equipment · Truss · Special · Shapes
- Thumbnails + display names from catalog
- Place → object selected for immediate move/resize
- Shapes: Rectangle, Rounded Rect, Ellipse, Triangle, Line, Stage Area, Text

### C4C — Silhouette Kit integration
- `StageStockCatalog` loads `Catalog.json` from `Bundle.module`
- `StageStockGlyphView` renders PNG 1x/2x (SVG masters retained in bundle)
- Documents store **stable `assetKey` only**
- Missing key → soft placeholder (no crash)
- White tint / catalog opacity — no baked purple
- Kit coverage: vocalists, guitarists, bassists, keyboardists, drummer/kit, DJ, audience variants, mic/music/speaker stands, truss set, disco ball

### C4D — Custom image import
- Edit Stage palette → **Import Image…**
- Copies into Application Support `Aurora/stage-media/`
- `mediaRef` on object; same drag / resize / lock / opacity / z-order as stock

### C4E — Z-order
- Context menu + Arrange menu: Front / Back / Forward / Backward
- Stable `zIndex` on each layout object

### C4F — Visual polish
- Charcoal stage base under grid (not temporary brown wash)
- Selection accent outlines; lock badges; restrained SE resize handle
- Live look atmosphere preserved at low opacity under objects
- Object property strip: Opacity + Rotation while objects selected

## Acceptance checklist

| # | Criterion | Status |
|---|-----------|--------|
| 1 | Place truss / stage area | Yes (stock truss + Stage Area shape) |
| 2 | Later select and move | Yes (live drag) |
| 3 | Resize / rotate | Yes (SE handle + rotation slider) |
| 4 | Undo transform in one op | Yes (`UpdateStageLayoutCommand`) |
| 5–6 | Drummer + other silhouettes | Yes (kit catalog) |
| 7 | Move and resize images | Yes |
| 8 | Import custom image | Yes |
| 9 | Opacity + lock | Yes (slider + lock chrome/menu) |
| 10 | Z-order arrange | Yes |
| 11 | Program with stage context | Yes (DESIGN preview + Edit Stage) |
| 12 | Pan / zoom / Fit without fighting objects | Yes (C3.1 Space-pan scope) |

## How to verify (musician-context)

1. DESIGN → **Edit Stage** (or STAGE tab alias)  
2. Left rail **Objects** → place Drummer Full, Keyboardist Standing, Guitarist Neutral, Vocalist Mic  
3. Drag live · SE resize · Opacity/Rotation strip · Arrange · Duplicate · Undo once  
4. **Import Image…** → lock → Done  
5. Program a look — silhouettes stay, lights dominant, no accidental move  
6. Save/reopen → `assetKey` / sizes restore  

## Tests
- `StageLayoutC4Tests` (migration, assetKey round-trip, undo)  
- `StageObjectDragC4Tests` (object drag + resize finalizer, lock/min size)  
- `StageStockCatalogTests` (bundled catalog loads)  

## Explicit deferrals / follow-ups (non-blocking)
- SVG-native rendering (PNG 1x/2x path live; SVG masters in bundle)  
- Multi-corner resize / rotation handles on-canvas (SE + slider sufficient for C4)  
- Project-package embedded media (import uses App Support path today)  
- Kit gaps vs roadmap wishlist: dedicated lighting-stand / riser glyphs (use Stage Area + equipment stands)  

## STOP

Do **not** begin **C5** (multi-monitor / undock) until C4 is approved.

**Approve C4 → proceed C5 only.**
