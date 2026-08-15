# Checkpoint C4.1 — Stage Designer Closeout

**Status:** Implemented for human review  
**Spec:** `UX redesign/Aurora_C4.1_Stage_Designer_Closeout_Spec.md`  
**Build:** Xcode Debug BUILD SUCCEEDED · `swift test` C4/C4.1 filters green  
**Date:** 2026-08-14  

## Review defects addressed

| # | Issue | Fix |
|---|--------|-----|
| A | Objects palette clipped at 220 pt / 6-item segmented control | Removed fixed width; horizontal **category chip strip**; adaptive grid fills rail |
| B | Resize undiscoverable (8 pt SE only) | **4-corner transform frame** (7 pt markers, 14 pt hit); live resize; one Undo; aspect policy |
| C | Loose stock/truss selection bounds | Catalog **visualBounds** + **defaultStageWidth/Height**; glyph crop; truss near-square defaults |
| D | Lightsaber Capsule beams / Pan-only | **Wedge beams** from Stage aim; static fixtures work without Pan; mover compose via resolver |

## Model / schema

### `StageFixturePlacement` (C4.1)

| Field | Meaning |
|-------|---------|
| `rotation` | Body/glyph orientation on plot |
| `aimDirection` | Physical beam direction (radians) |
| `beamSpread` | Full fan angle (radians) |
| `beamLength` | Visualization reach (Stage units) |
| `beamVisible` | Draw beam |

- Legacy decode supplies defaults (`aimDirection = -π/2`, medium spread/length, visible).  
- New places use `StageFixturePlacement.placed(..., category:)` with §8 family defaults.  
- **Not** DMX channels — Inspector labels them Stage Aim.

### Catalog schema v2 (additive)

Optional per asset: `visualBounds`, `defaultStageWidth`, `defaultStageHeight`, `intrinsicAspectRatio`.  
**Stable keys unchanged.** Source kit + bundled `StageAssets/Catalog.json` updated in lockstep.

## Architecture notes

### Resize (C4.1)

- Corners: NW / NE / SW / SE; opposite corner fixed in local axes.  
- Aspect: stock/import/truss **preserve by default**; shapes **free by default**; **Shift inverts**.  
- Rotated objects: translation unrotated into local axes; frame rotates with object.  
- Cursors: macOS 15+ diagonal frame resize; older → crosshair.

### Beams

- Pure math: `StageBeamGeometry` (wedge points / path).  
- Composition: `StageBeamDirectionResolver.renderedAimRadians(...)`  
  - Static: `aimDirection` only.  
  - Mover: `aimDirection + f(livePan, panRange)`.  
  - **TODO(C4.x):** personality-defined Pan/Tilt ranges when `FixtureDefinition` exposes them — do not hardcode range inside `StageCanvasView`.  
- Layering: base → layout objects → **beams** → fixture glyphs → selection.  
- Intensity 0 → no beam; color from live preview; length from placement.

### Inspector

- Single fixture on Stage → **Stage Aim** section (Direction / Spread / Length / Show beam).  
- Slider commits on edit-end (one Undo per gesture).

## Tests (green)

- `StageBeamC41Tests` — wedge math, resolver static/mover, placement round-trip, legacy defaults, category spreads  
- `StageObjectDragC4Tests` — drag + multi-corner resize, min size, lock, aspect  
- `StageStockCatalogC41Tests` — bounds/defaults, truss footprint, palette sections  
- Existing C4 layout/catalog tests  

## Manual acceptance (production app)

Use checklist in closeout spec §20. Priority paths:

1. Edit Stage → Objects: narrow window, all categories, Import Image  
2. Place vocalist → 4 handles → resize live → Undo  
3. Place curved truss → tight frame (not huge empty box)  
4. Place static PAR → Stage Aim toward performer → color/intensity → wedge beam without Pan  
5. Place flood → wider than PAR  
6. Mover → live Pan steers beam; intensity 0 hides  

Screenshots: capture into this folder when validating on hardware:

1. palette normal / narrow  
2. resizable performer  
3. tight truss bounds  
4. static PAR beam  
5. flood beam  
6. mover beam  
7. populated stage  

## Explicit deferrals

- Line/truss **endpoint** handles  
- Canvas **direct aim handle** (Inspector is C4.1 minimum; model ready)  
- SVG-native rendering  
- Project-package embedded import media  
- Personality pan/tilt range fields on `FixtureDefinition`  

## STOP

> **Do not begin C5** until C4 / C4.1 receives human approval.

**Approve C4.1 → proceed C5 only.**
