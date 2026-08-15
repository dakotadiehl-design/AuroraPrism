# C4.5 Final C4 Closeout — Acceptance Note

**Status:** Implemented  
**Date:** 2026-08-14  
**Spec:** `UX redesign/Aurora_C4.5_Final_Closeout.md`

## Fix A — Project-portable Stage imports

| Before | After |
|--------|--------|
| Absolute App Support paths in `mediaRef` | Package-relative `media/stage/<uuid>.ext` |
| Not portable across machines | Embedded in `.aurora` on save |
| `NSImage(contentsOfFile: absolute)` | Resolve via package root + staging + legacy absolute |

### Implementation
- `StageMediaSupport` — import, staging, package-relative validation, resolve, materialize/migrate
- `ProjectPackage.writePackageContents` — materializes Stage media into `media/stage/` and rewrites absolute refs
- `RegisterMediaAssetCommand` — registers `MediaAssetRef` on the show
- `WorkspacePanelContext.packageURL` — for resolution while open
- Canvas imported-image view uses `StageMediaSupport.resolveFileURL`

### Tests
`StageMediaSupportTests`: staging → first save embed, portable package copy, Save As, legacy absolute migration, missing media safe

## Fix B — Stock infrastructure completeness

Added stable keys (isolated white silhouettes, PNG 1x/2x + SVG):

- `stage.equipment.lighting_stand` — Lighting Stand  
- `stage.equipment.riser_platform` — Riser / Platform  

Catalog asset count: **35**. Bundled + source corrected kit updated.

## C4.4 / earlier regressions

Ghosting Approach B, live rotation, single View + Workspace menus — **not reopened**.

## Deferred (do not block C5)

- Personality Pan/Tilt physical ranges  
- SVG-native Stage rendering  
- Line/truss endpoint handles  
- Media garbage collection  

---

## C4 CLOSED

When production portability checklist (§11 of C4.5 spec) and ghost-free Stage edit checks pass in the app:

> **C4 is CLOSED. Proceed to C5 Multi-Monitor / Undockable Workspace.**

**STOP auto-start of C5 until human confirms production portability test.**
