# Checkpoint C3.1 — Interaction Closeout

**Status:** Implemented for review  
**Build:** Xcode Debug BUILD SUCCEEDED  
**Date:** 2026-08-14  
**Spec:** `UIDesignReferences/Aurora_C3.1_Interaction_Closeout_Implementation_Spec.md`

## Goal

Make DESIGN/Stage feel immediate under the mouse **without** changing C1–C3 architecture:

1. Natural Stage pan  
2. Collapsible lower creative shelf  
3. Live fixture drag (one commit / one undo)

## What landed

### A — Camera pan (`StageCanvasView` + `StageCameraPan`)
- Pan = `panAtDragStart + gesture.translation` (no 0.015 compounding)
- DESIGN Live: empty-space drag pans
- Edit Stage: **Space + drag** pans (fixture move suppressed while Space held)
- Closed-hand cursor while actively panning
- Fit still resets camera; subsequent pan starts from fitted state

### B — Lower shelf collapse (`WorkspaceLayout.lowerShelfCollapsed`, schema v4)
- Collapse **does not** zero `bottomFraction` (height restored on expand)
- Thin restore strip when collapsed: current section · labels · chevron
- Expanded shelf has collapse chevron
- View menu: Collapse / Expand Lower Shelf
- Focus presets:
  - Balanced / Cue Focus → expand shelf  
  - Programmer Focus / Preview Focus → collapse shelf  

### C — Live multi-fixture drag
- Transient `StageFixtureDragState` (originals + world delta)
- Glyph follows pointer (`displayPosition`) during drag
- **No** `UpdateStageLayoutCommand` per pointer sample
- One command on mouse-up; multi-select shares snapped **delta** (group shape preserved)
- Zoom-aware: world delta = view translation / scale
- Locked fixtures never move; multi-select moves only unlocked
- Escape cancels transient drag

## Architecture preserved
- `StageCanvasView` shared surface  
- `project.stageLayout` sole geometry document  
- `DocumentSession` / undo for commits  
- Selection shared; geometry locked outside Edit Stage  

## Tests
| Suite | Result |
|-------|--------|
| `StageInteractionMathTests` | pan, zoom delta, group snap, display pos |
| `StageLiveDragC31Tests` | single/multi undo, lock |
| `DesignWorkspaceC2Tests` | lower shelf collapse persistence |

## Manual validation (production app)

Please confirm in launched Aurora (demo + placed fixtures):

- [ ] DESIGN empty-space pan tracks pointer ~1:1  
- [ ] Edit Stage: Space+drag pans; fixture drag without Space moves glyph live  
- [ ] Fit then pan has no jump  
- [ ] Collapse shelf → strip visible; expand → prior height  
- [ ] Single + multi drag live; Undo once restores full drag  
- [ ] Locked fixture does not move  

**Note:** Automated screenshots cannot fully prove live drag smoothness; hands-on is required.

## STOP

Do **not** begin **C4** visual polish until C3.1 interaction is approved.

**Approve C3.1 → proceed C4 only.**
