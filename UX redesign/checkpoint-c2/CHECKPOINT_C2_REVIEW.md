# Checkpoint C2 — DESIGN Workspace Integration

**Status:** Implemented for visual review  
**Build:** Xcode Debug BUILD SUCCEEDED  
**Date:** 2026-08-14  
**Directive:** Lightkey UX Alignment · continuous programming + live Stage Preview

## Goal

```text
See rig → select → program → see result
```

without leaving the creative workspace.

## What landed

### Navigation
- Mode bar shows **DESIGN | PATCH | STAGE | PROFILES** (`program` case display name = Design)
- View menu: Design (⌃⌘1), Stage Preview toggle, Design Layout presets

### DESIGN layout (`BuildWorkspaceHost.programMainRow`)
```text
Fixtures/Groups | Stage Preview (hero) + Programmer deck | Inspector
                 + lower Palettes/Cues/Song/Diagnostics (collapsible)
```

### Stage Preview chrome
- Live `StageCanvasView` (shared with STAGE tab)
- Geometry **locked** (Edit Stage full tools → C3; STAGE tab for geometry now)
- Fit / zoom / Reveal / collapse
- Authoritative `appModel.stagePreviewSnapshot()`

### Layout system
- `WorkspaceLayout.designPreviewFraction` + `stagePreviewCollapsed` (schema v3)
- Drag split between Preview and Programmer
- Focus presets: Balanced · Programmer Focus · Preview Focus · Cue Focus

### Reveal on Stage
- Switches to **DESIGN**, expands preview, pans via `stageRevealFixtureID`

### Selection
- Stage canvas → `session.selectFixturesOrdered` + Inspector focus
- One selection authority shared with Browser / Groups / Programmer

## Screenshot package

`UX redesign/checkpoint-c2/`

| # | File |
|---|------|
| 1 | `01-design-no-selection.png` |
| 2 | `02-design-front-wash-group.png` |
| 3 | `03-design-movers-group.png` |
| 4 | `04-design-single-mover-stage.png` |
| 5 | `05-design-live-color.png` |
| 6 | `06-design-live-position.png` |
| 7 | `07-design-programmer-focus.png` |
| 8 | `08-design-preview-focus.png` |
| 9 | `09-design-lower-shelf-expanded.png` |

**Regenerate:** `Aurora.app --export-checkpoint-c2-shots`

## How to verify in app

1. Open Demo Summer Night (place fixtures on Stage if needed).
2. **DESIGN** — Stage Preview above Programmer; lower shelf visible.
3. Select group in Browser → highlight on Stage; Programmer updates.
4. Click fixture on Stage Preview → selection + Inspector.
5. Layout menu → Programmer Focus / Preview Focus / Cue Focus.
6. View → Hide Stage Preview / Stage Preview.
7. Programmer faders should refresh live look on Stage Preview (engine path).

## Explicitly not C2
- In-place Edit Stage in DESIGN (C3)
- Removing STAGE tab (C3+)
- Beam polish / Stage Area beauty (C4/D)
- Docking / multi-monitor

## STOP

Do **not** begin C3 until these screenshots and live app behavior are reviewed.

**Approve C2 → proceed C3 (Edit Stage in place) only.**
