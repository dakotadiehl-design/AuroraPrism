# Checkpoint C3 — Edit Stage In Place

**Status:** Implemented for visual review  
**Build:** Xcode Debug BUILD SUCCEEDED  
**Date:** 2026-08-14  

## Goal

Arrange the physical plot **without leaving DESIGN**:

```text
Edit Stage → geometry tools + Unplaced rail
Done → geometry locks → continue programming same selection
```

Same `StageCanvasView` + `stageLayout` as Live preview. No second model.

## What landed

### State
- `WorkspaceController.stageEditActive`
- `enterEditStage()` / `exitEditStage()` / `toggleEditStage()`
- Expands Stage Preview; bumps preview fraction for room to arrange

### DESIGN chrome
| Mode | Geometry | Left rail | Tools |
|------|----------|-----------|--------|
| **Live** | locked | Browser / Groups | Fit, zoom, Reveal, **Edit Stage** |
| **Edit Stage** | unlocked | Unplaced / On Stage / Fixtures | Align, Distribute, Add, Remove From Stage, Rotation, Place All, Done |

### Canvas
- Live: `interactionMode = .programSelect`, `geometryEditingEnabled = false`
- Edit: `.editGeometry` + `geometryEditingEnabled = true` (drag, marquee, drop place)

### STAGE top-level alias
- Choosing **STAGE** → DESIGN + Edit Stage (mode bar highlights Stage while editing)
- Choosing **DESIGN** → exits Edit Stage

### View menu
- Edit Stage (⌃⌘E)
- Done Editing Stage

### Semantics preserved
```text
Remove From Stage → placement only (patch, groups, programming survive)
Exit Edit Stage → same selection, programming continues
```

## Screenshots

`UX redesign/checkpoint-c3/`

| File | Content |
|------|---------|
| `01-design-live-geometry-locked.png` | DESIGN Live · geometry locked |
| `02-edit-stage-unplaced-tray.png` | Edit Stage · Unplaced tray |
| `03-edit-stage-multi-selection.png` | Multi-select · edit tools |
| `04-edit-stage-exit-continue.png` | Done · back to programming |

**Regenerate:** `Aurora.app --export-checkpoint-c3-shots`

## Verify in app

1. Demo show → place fixtures if empty.
2. DESIGN → **Edit Stage** (or click STAGE tab).
3. Unplaced rail → Place All / drag to canvas.
4. Multi-select → Align / Distribute.
5. Remove From Stage → fixture remains patched; appears under Unplaced.
6. **Done** → Browser rail returns; Programmer full height; geometry locked.
7. Programmer continues on same selection.

## Tests
- `EditStageC3Tests` (3) + Stage placement / canvas tests green

## Explicitly not C3
- Visual polish of symbols / Stage Area beauty (C4)
- Live beam polish (D)
- Removing STAGE from mode bar permanently (optional later)

## STOP

Do **not** begin C4 until Edit Stage workflow is reviewed and approved.

**Approve C3 → proceed C4 (Stage visual polish) only.**
