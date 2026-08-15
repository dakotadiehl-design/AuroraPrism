# Checkpoint C4.3 — Stage Rendering & Interaction Stabilization

**Status:** Implemented for human review  
**Spec:** `UX redesign/Aurora_C4.3_Stage_Rendering_Interaction_Stabilization.md`  
**Build:** Xcode Debug / `swift test` Stage filters green  
**Date:** 2026-08-14  

## Defects addressed

### A — Drag ghosting / trailing copies

**Approach (spec):** single live visual + no implicit animation during transform; not more gesture/offset tweaking alone.

| Change | Detail |
|--------|--------|
| Absolute world `.position` | Live geometry from display point only (no committed position + offset twin) |
| No-animation policy | `.transaction { animation = nil }` on canvas while previews active; per-object while live |
| Compositing isolation | `StageLiveObjectCompositingModifier` / `StageTransformCompositingModifier` apply `compositingGroup` + `drawingGroup` while a transform is active |
| Fixture aim single beam | Active fixture IDs leave committed beam/glyph ForEach and render once in a transient stack |

Layout **object** ForEach identity is preserved (stable drag gestures). Fixtures use omit-from-committed + transient layer (no gesture ownership conflict with aim handle).

### B — Rotation slider live preview

| Change | Detail |
|--------|--------|
| `toolbarRotationPreview: [UUID: Double]` | Transient radians by object id (not document) |
| Slider `editing` callback | Begin → push preview; value changes → update preview; end → **one** `UpdateStageLayoutCommand` |
| Canvas consumes preview | `objectDisplayRotation` prefers canvas handle state, then toolbar preview, then document |
| Canvas handle → preview | Direct rotation handle writes the same preview map |

One slider drag = one Undo. No commit storm while dragging.

### C — Duplicate `View` menus

| Before | After |
|--------|--------|
| `CommandMenu("View")` (second top-level View) | Removed |
| Mode/workspace items inside View | **`CommandMenu("Workspace")`** |
| Visibility items | **`CommandGroup(after: .toolbar)`** into system View |

Structure: Aurora · File · Edit · **View** (one) · **Workspace** · Playback · MIDI · Remote · Output · Window · Help  

Shortcuts preserved (`⌘⌃1–4`, `⌘⌃P`, `⌘⌃E`, etc.).

---

## New / updated files

- `Sources/AuroraUI/Stage/StageEditInteractionState.swift` — pure single-render eligibility helpers  
- `Sources/AuroraUI/Stage/StageCanvasView.swift` — transient targets, compositing, rotation preview binding  
- `Sources/Aurora/Shell/BuildWorkspaceHost.swift` — live slider preview  
- `Sources/Aurora/AuroraApp.swift` — View / Workspace menus  
- `Tests/AuroraUITests/StageEditC43Tests.swift`  

---

## Tests

- `StageEditC43Tests` — committed/transient exclusivity, target unions, ownership blocks  
- Prior Stage interaction / catalog tests still green  

---

## Manual stress (production)

Per spec §11 / §20:

1. Rapid performer drag circles 10s @ 100/150/200% zoom — no trails  
2. Four-corner rapid resize — one object + one frame  
3. Rotation handle spin — one object  
4. Slider 0° → 45° → 90° live, Undo once  
5. PAR aim whip — one beam  
6. Menu bar: exactly one View, Workspace present  

---

## STOP

> **Do not begin C5** until C4.3 is approved.

**Approve C4.3 → proceed C5 only.**
