# Checkpoint C5.1 — Multi-Monitor / Undockable Workspace Closeout

**Phase:** C5.1 corrective closeout  
**Status:** Implementation complete — **STOP for human production validation**  
**Do not begin C6 until this checkpoint is accepted.**

---

## Summary

C5.1 closes the deep-review gaps from the first C5 pass while preserving the architecture:

```text
one application state + multiple presentation hosts
```

### Delivered

| Area | Implementation |
|------|----------------|
| **Window coordinator** | `FloatingSurfaceWindowCoordinator` — exact `FloatSurfaceID ↔ NSWindow` registration; close/focus without title scanning |
| **Frame persistence** | `NSWindow.didMove/didResize/didChangeScreen` → `WorkspaceController.updateFloatingFrame` (debounced via `WorkspaceFloatStore`) |
| **Redock lifecycle** | `AppModel.redockSurface` docks state **and** closes the exact registered window |
| **User close vs quit** | `willClose` redocks only when `!appModel.isTerminating`; quit sets `isTerminating` before teardown and flushes float state |
| **Monitor recovery** | Per-screen `visibleFrame` + display ID (`NSScreenNumber`); gap-safe; shrink oversized windows |
| **Unified undock** | `AppModel.undockSurface` — same default frame path for panel chrome and View menu |
| **Surface reuse** | `BrowserWorkspaceSurface`, `CreativeShelfWorkspaceSurface`, `DesignStageSurface`, wrappers for Programmer/Inspector/Diagnostics |
| **Stage fidelity** | Floating Stage uses `DesignStageSurface` (production DESIGN chrome + `StageCanvasView`), **not** legacy `StagePanel` |
| **Shared Stage camera** | `WorkspaceController.designPreviewScale` / `designPreviewPan` |
| **Space reclaim** | Compact `CompactFloatRestoreChip` instead of full-geometry placeholders |
| **Store safety** | `WorkspaceFloatStore` is `@MainActor` with main-queue debounced saves |

---

## Window coordinator design

```text
AppModel.floatWindows: FloatingSurfaceWindowCoordinator
  register(window:for:)
  unregister / closeWindow / focusWindow
  onFrameChanged → workspace.updateFloatingFrame
  onUserCloseWhileFloating → workspace.redock (if still floating)
  isTerminating → skip redock on quit
```

`AuroraScreenIdentity` provides durable `display-<CGDirectDisplayID>` ids and default undock frames on `visibleFrame`.

---

## Close / redock / quit policy

| Event | Behavior |
|-------|----------|
| User clicks **Dock** | `redockSurface` → state docked + close exact window |
| User clicks window **red close** | `willClose` → redock (surface returns to main) |
| **App quit** | `isTerminating = true` → flush float frames → windows tear down **without** rewriting to docked |
| View menu **Dock in Main Window** | same as Dock button |

`onDisappear` no longer owns redock policy.

---

## Extracted production surfaces

| Surface | Docked host | Floating host |
|---------|-------------|-----------------|
| Browser | `BrowserWorkspaceSurface` (Fixtures + Groups, `leftTool`) | same |
| Creative Shelf | `CreativeShelfWorkspaceSurface` (`lowerTool`: Palettes/Cues/Song/Diagnostics) | same |
| Stage Preview | `DesignStageSurface` | same |
| Programmer / Inspector / Diagnostics | existing panels / registry | same wrappers |

Edit Stage **left rail** (`DesignStageEditRail`) remains in the main DESIGN host when editing; the floatable surface is the production canvas + chrome.

---

## Recovery algorithm

1. Prefer saved `screenID` if that display still exists.  
2. Else greatest intersection with any `visibleFrame`.  
3. Else primary screen.  
4. Clamp size into host visible frame; keep title bar reachable.  
5. Persist updated frame/id when recovery changes them.

---

## Tests

`WorkspaceFloatC5Tests` (16 tests, all passing):

- dock/float cycles, multi-surface independence, JSON round-trip  
- frame update reflection  
- recovery: gap, removed monitor, preferred screen, oversized, partial visibility  
- Browser/Shelf subtool contracts  
- hidden ≠ floating  
- quit-preserves-floating conceptual policy  
- MainActor store save/load  

**SPM:** `swift test --filter WorkspaceFloatC5Tests` — pass  
**Xcode:** `xcodebuild -scheme Aurora -destination 'platform=macOS' build` — pass  
**SPM app target:** `swift build --target Aurora` — pass  

---

## Manual acceptance (human)

Perform before closing C5:

### Single display
- [ ] Undock/redock each surface from chrome and View menu  
- [ ] Confirm float window **closes** on redock (no duplicate host)  
- [ ] Move/resize floats → quit → relaunch → positions restore  

### Surface fidelity
- [ ] Browser float: Fixtures **and** Groups; tool selection survives redock  
- [ ] Creative Shelf float: Palettes/Cues/Song/Diagnostics; selection survives  
- [ ] Stage float: DESIGN/Edit Stage UX (not StagePanel); camera survives undock  
- [ ] Programmer/Inspector track shared selection  

### Multi-monitor
- [ ] Float Stage + Programmer on display 2; program fixtures  
- [ ] Disconnect display 2 offline → relaunch → windows usable on remaining display  

### Space reclaim
- [ ] Browser/Inspector/Stage/Programmer floated → main workspace expands (compact chip only)

---

## STOP

> **C5.1 implementation is complete. Do not start C6 (Splash & Brand Fidelity) until human multi-monitor acceptance passes.**

If acceptance passes: **C5 CLOSED → proceed to C6.**
