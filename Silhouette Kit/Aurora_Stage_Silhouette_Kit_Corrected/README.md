# Aurora Stage Silhouette Kit — Corrected

This package replaces the original Aurora Stage Silhouette Kit artwork.

## Important correction

Every file under `svg/` and `png/` is now an **isolated individual asset**. No category headings, labels, neighboring objects, contact-sheet fragments, or raster-sheet text are embedded in production assets.

The `Catalog.json` stable asset keys are preserved so existing Aurora C4 integrations can replace artwork without changing project references.

The contact sheet under this package is documentation only and must never be used as an asset source.
