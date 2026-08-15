# Aurora Corrected Silhouette Kit — Grok Integration Guide

## Purpose

Replace the original Aurora silhouette artwork with this corrected package. The original kit accidentally derived some production assets from raster/contact-sheet material, causing labels and neighboring graphics to appear when objects were placed on Stage.

**Do not work around the old artwork with giant `visualBounds` masks. Replace it.**

## Compatibility rule

`Catalog.json` preserves the existing stable keys, for example:

- `stage.performers.vocalist_standing`
- `stage.performers.drummer_full`
- `stage.performers.guitarist_neutral`
- `stage.equipment.mic_stand`
- `stage.equipment.speaker_on_pole`
- `stage.truss.straight_short`
- `stage.truss.curved_left`
- `stage.audience.crowd_wide`

Existing show/project data should continue resolving by key.

## Source of truth

Production artwork comes only from:

```text
svg/<category>/<asset>.svg
png/1x/<category>/<asset>.png
png/2x/<category>/<asset>@2x.png
```

The contact sheet is documentation only. Never crop production assets from it.

## Replacement procedure

1. Back up/remove the currently bundled Stage silhouette resources.
2. Copy the corrected `svg/` and PNG directories into Aurora's Stage asset resources.
3. Replace the bundled catalog with this package's `Catalog.json`.
4. Preserve stable asset keys.
5. Prefer SVG/vector rendering in Stage Designer.
6. Use PNG only as fallback or thumbnail material.
7. Remove special-case clipping added solely to hide text/contact-sheet contamination from the original kit.
8. Retain generic normalized bounds support because user-imported media can still contain transparent padding.

## Bounds

All corrected assets are intentionally isolated and tightly framed. `visualBounds` is `(0,0,1,1)` because the file itself is the normalized visual footprint.

Do not reintroduce fixed square presentation for elongated artwork. Respect each asset's `intrinsicAspectRatio`.

For example:

- straight truss is wide and shallow,
- people are tall,
- crowd assets are wide,
- circular truss and disco ball are near-square.

## Default placement

Use `defaultStageSize` from the catalog where possible. It gives Stage-world defaults that match the type of object.

Maintain aspect ratio by default for all stock silhouettes.

## Tinting

Assets are authored white on transparent background so Aurora can tint them at runtime.

Recommended normal Stage behavior:

- Edit Stage: high-opacity neutral/light silhouette
- Live DESIGN: lower-opacity contextual silhouette so beams remain readable
- Selection: Aurora selection outline, not recoloring the source bitmap itself unless desired

## Transform behavior

These are normal Stage image/layout objects and must support C4/C4.2 behavior:

- select
- move
- live resize
- aspect-preserving resize by default
- rotate
- lock
- z-order
- delete
- one transform gesture = one Undo

## Verification checklist

- Place vocalist. No text appears.
- Place speaker on pole. No neighboring item appears.
- Place mic stand. No category heading appears.
- Place straight and curved truss. Selection bounds closely follow visible artwork.
- Place drummer and keyboardist together. Each is independent.
- Resize a performer. Aspect stays sensible.
- Rotate a truss. No oversized square raster frame becomes visible.
- Zoom Stage to 200%. Vector artwork remains crisp.

## Migration note

If Aurora cached thumbnails/rasterized Stage assets from the previous kit, invalidate/rebuild that cache when this corrected catalog is installed. Otherwise old contaminated thumbnails may continue to appear even after source resources are replaced.

## Do not

- Do not rename stable asset keys.
- Do not extract assets from the contact sheet.
- Do not flatten contact sheet labels into individual files.
- Do not use enormous visual bounds as a workaround for bad source images.
- Do not store absolute filesystem paths for these built-in resources.
