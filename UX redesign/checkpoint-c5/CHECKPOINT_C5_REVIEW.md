# Checkpoint C5 — Multi-Monitor / Undockable Workspace

**Status:** Implemented for human review  
**Roadmap:** `UIDesignReferences/Aurora_C4_C5_C6_UX_Redesign_Roadmap.md` §10–17  
**Build:** `swift build` + Xcode Debug SUCCEEDED  
**Date:** 2026-08-14  

## What landed

### C5A — Detachable surfaces
Floatable (same production content, not cloned models):

| Surface | Host |
|---------|------|
| Browser | Fixture / Groups left rail |
| Stage Preview | DESIGN stage / StagePanel |
| Programmer | DESIGN programmer deck |
| Inspector | Trailing inspector |
| Creative Shelf | Lower cues/palettes/song/diagnostics |
| Diagnostics | Console panel in float host |

### C5B — Presentation state
- `FloatSurfaceID`, `PanelPresentationKind` (`.docked` / `.floating` / `.hidden`)
- `WorkspaceFloatState` + `WorkspaceFloatStore` (UserDefaults `aurora.workspace.float.v1`)
- Persists kind + window frame + screen id
- Architected for future presets (C5F) without shipping a preset editor

### C5C — Real macOS windows
- `WindowGroup(id: "float-surface", for: FloatSurfaceID.self)` in `AuroraApp`
- `FloatingSurfaceWindow` hosts `PanelRegistry` / Stage content with shared `AppModel`
- Natural multi-monitor, Spaces, focus, Retina (system windows)

### C5D — Undock / redock UX
- **Move to Window** on panel chrome + Stage Preview + View menu
- **Dock in Main Window** in floating window ⋯ menu + View menu
- Closing a floating window **redocks** (documented policy; does not destroy project state)
- Main shell shows `FloatedSurfacePlaceholder` with **Dock Here**

### C5E — Monitor recovery
- `recoverFloatingWindows(to:)` clamps frames into visible screen union on launch
- Floating window `onAppear` re-centers if key window is off-screen

### C5F — Preset readiness
- Clean float map separate from lighting show document
- No full preset UI (deferred by roadmap)

## How to verify

### Single display
1. DESIGN → ⋯ / macwindow on Inspector → Move to Window  
2. Confirm placeholder + independent window  
3. Program fixtures; selection updates in both windows  
4. Dock in Main Window / close float → redocks  
5. Quit/relaunch → floating windows restore  

### Two displays
1. Float Stage Preview and Programmer to second display  
2. Edit Programmer; Stage/Inspector stay live  
3. Redock; restart with both monitors  

### Display removal
1. Float to external monitor, quit, disconnect, relaunch  
2. Windows appear on remaining display  

## Tests
`WorkspaceFloatC5Tests` — dock/float, multi-surface, off-screen recovery, JSON round-trip, catalog completeness  

## Policy note (C5D close)
**Closing a floating window redocks** the surface into the main shell (does not hide permanently).

## STOP

> **STOP for human review before C6** (splash fidelity).

**Approve C5 → proceed C6 only.**
