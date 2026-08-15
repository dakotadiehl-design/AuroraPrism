# Checkpoint C1 — Shared Stage Renderer Architecture

**Status:** Implemented for architecture review  
**Build:** Xcode Debug BUILD SUCCEEDED  
**Date:** 2026-08-14  
**Directive:** Lightkey UX Alignment · C1 before DESIGN full layout (C2)

## Goal

Prove Stage is a **reusable visualization surface**, not owned exclusively by the STAGE tab.

## What landed

### New
| File | Role |
|------|------|
| `Sources/AuroraUI/Stage/StageInteractionMode.swift` | `.programSelect` / `.editGeometry` / `.panOnly` |
| `Sources/AuroraUI/Stage/StageCanvasView.swift` | Shared canvas: grid, scenic, fixtures, beams, selection, gated geometry |
| `Sources/AuroraUI/Stage/StageCanvasCamera` (in same file) | Fit Stage / Fit Selection helpers |

### Refactored
| File | Change |
|------|--------|
| `StagePanel.swift` | Thin host: Unplaced rail + Edit/Live chrome + **StageCanvasView** |
| `BuildWorkspaceHost.swift` | **PROGRAM** embeds same `StageCanvasView` above Programmer (geometry **locked**) |

### Architecture rules enforced in code
- One `project.stageLayout`
- One `appModel.stagePreviewSnapshot()` path for both hosts
- Geometry mutations only when `geometryEditingEnabled && interactionMode == .editGeometry`
- Selection still via `DocumentSession` / `onSelectFixtures`
- No second lighting engine

## How to verify in the app

1. Open **Demo Summer Night**.
2. **PROGRAM** — Stage Preview strip above Programmer; click fixtures on preview → selection updates Programmer/Inspector.
3. **STAGE** — full rail + Edit/Live still works; same fixtures/geometry as Program preview.
4. Edit placement only on STAGE Edit (or later C3); Program preview must **not** move fixtures when dragging (geometry locked).

## Tests
- `StageCanvasArchitectureTests` (3) — shared layout, preview IDs, place/remove preserves patch/groups  
- `StagePlacementCommandTests` — green  
- `FixtureLifecycleTests` — green  

## Screenshot package

Captured via production `StageCanvasView` / `StagePanel` composites  
(`Aurora.app --export-checkpoint-c1-shots` → this directory):

| # | File | What it shows |
|---|------|----------------|
| 1 | `01-program-shared-stage-preview.png` | PROGRAM-style host: Stage Preview strip above Programmer, geometry locked |
| 2 | `02-program-stage-selection.png` | Same host with fixture selection from Stage canvas |
| 3 | `03-stage-tab-shared-canvas.png` | STAGE tab host: Unplaced rail + chrome around **same** StageCanvasView |
| 4 | `04-stage-canvas-geometry-locked.png` | Isolated canvas · `programSelect` · geometry locked |
| 5 | `05-stage-canvas-edit-geometry.png` | Isolated canvas · `editGeometry` path (shared surface) |

Demo show fixtures placed via `PlaceAllUnplacedCommand` for a readable rig.  
Preview look from shared `StagePreviewBuilder` (amber washes, movers pan/tilt).

**Regenerate:**  
`Aurora.app --export-checkpoint-c1-shots`  
→ container Application Support `Aurora/checkpoint-c1/` (copy into this folder)

## Explicitly not C1
- Full DESIGN proportions / collapse presets (C2)  
- In-place Edit Stage in DESIGN (C3)  
- Beam polish / Stage Area beauty (C4/D)  
- Renaming Program → Design in nav (C2)

## STOP

Do **not** begin C2 (full DESIGN workspace integration) until this architecture proof is reviewed.

**Approve C1 → proceed C2 only.**
