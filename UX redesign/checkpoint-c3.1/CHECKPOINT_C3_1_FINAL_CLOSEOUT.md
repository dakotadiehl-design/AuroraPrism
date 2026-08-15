# C3.1 Final Closeout

**Status:** Implemented  
**Build:** SUCCEEDED  
**Date:** 2026-08-14  
**Addendum:** `UIDesignReferences/Aurora_C3.1_Final_Closeout_Addendum.md`

## Fixes

### 1. Space-key scope (critical)
`StageCanvasKeyState` now only **consumes Space** when:

1. At least one `StageCanvasView` is mounted (`retainCount > 0`), **and**
2. Pointer is **inside** Stage (`onHover` → `hoverCount > 0`), **and**
3. **Not** text-editing (`AuroraKeyboardGate.isTextEditingActive`)

Otherwise Space is passed through unchanged (text fields / search keep spaces).

Cursor: open-hand is **pushed** only when Stage claims Space; **popped** on release — never force global `NSCursor.arrow`.

### 2. Production-equivalent drag finalization tests
Extracted **`StageLayoutDragFinalizer`** — same path as `StageCanvasView.commitFixtureDrag`:

- `fixtureOrigins` (lock/hidden aware)
- `liveDelta` / `finalizedLayout` (zoom + group snap)
- Commit via one `UpdateStageLayoutCommand` + undo proven in tests

### 3. C4-ready interaction layer (no C4 features)
- Renamed core model to **`StageObjectDragState`** / **`StageWorldDragMath`**
- Fixture aliases retained for existing call sites
- Coordinate system ready for scenic/truss drag in C4 without re-deriving pan/zoom math

## Tests
| Suite | Coverage |
|-------|----------|
| `StageLayoutDragFinalizerTests` | single/multi/lock/snap/zoom/live=commit/no-op + undo |
| `StageInteractionMathTests` | pan, zoom, spacing, display |
| `StageLiveDragC31Tests` | command undo multi-move |

## Manual checklist (production app)

Please confirm:

- [ ] Text field: type `Front Wash Stage Left` with Stage visible — all spaces present  
- [ ] Edit Stage Space+drag pans over empty and over fixtures  
- [ ] Fixture drag without Space moves live; one Undo restores  
- [ ] Multi-drag keeps spacing; locked fixtures stay  
- [ ] Lower shelf collapse/expand still works  

## STOP

**C3.1 is final-closed after human approval of this note + manual Space/text regression.**  
Do **not** begin C4 until approved.
