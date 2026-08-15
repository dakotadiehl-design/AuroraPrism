# Checkpoint C4.2 — Stage Interaction Closeout

**Status:** Implemented for human review  
**Spec:** `UX redesign/Aurora_C4.2_Stage_Interaction_Closeout.md`  
**Build:** Xcode Debug BUILD SUCCEEDED · Stage interaction tests green  
**Date:** 2026-08-14  

## Root causes

### 1. Resize handle moved the object

**Cause:** The layout-object **body move** used `.highPriorityGesture` on the **entire** object `ZStack`, including the resize-handle children. Child resize gestures lost ownership; the parent drag treated handle presses as moves.

**Fix:**

- Explicit `StageTransformInteraction` ownership (`none | move | resize | rotate | aim | pan`).
- **Body-only** move gesture (content shape on artwork, not chrome).
- Resize/rotate handles are siblings with their own high-priority gestures.
- Move `onChanged` returns immediately when `activeTransform.blocksMove`.

### 2. Rotation slider not clickable

**Cause:** Edit Stage tools bar lacked exclusive layout/hit isolation relative to the expanding Stage canvas region (`GeometryReader` filling remaining space). Toolbar interaction could lose to canvas gesture regions in practice.

**Fix:**

- Tools bar is a **VStack sibling above** the canvas (not overlaid).
- `.fixedSize(horizontal: false, vertical: true)`, `.contentShape(Rectangle())`, `.zIndex(3)`, `.allowsHitTesting(true)`.
- Canvas `.clipped()` + `.zIndex(0)`.
- Slider min height / controlSize for reliable thumb hit targets.

### 3. Aim only via slider

**Cause:** C4.1 model had Stage aim, but no direct handle.

**Fix:** Aim handle on selected unlocked fixtures in Edit Stage (amber disc at beam tip). Drag updates `aimDirection` + `beamLength` live; one `UpdateStageLayoutCommand` on mouse-up. Pure math: `StageAimMath`.

---

## Transform arbitration (C4.2)

```text
1. toolbar / controls (host)
2. resize handle
3. rotation handle
4. beam aim handle
5. object/fixture move
6. Space-pan
7. empty-space marquee
```

`activeTransform` is the single source of truth for the current pointer drag.

Escape cancels any transient transform (resize / rotate / aim / move).

---

## Direct beam aim

- Visible only in **Edit Stage** when fixture selected and unlocked.
- Geometry: `aimDirection = atan2(dy, dx)`, `beamLength = distance` (Aurora convention).
- Edits **physical Stage aim** only — not Programmer Pan/Tilt.
- Movers: live Pan still composes via `StageBeamDirectionResolver`; handle does not write DMX state.
- Inspector Stage Aim remains and shares the same model.

## Direct object rotation handle

Implemented: ring handle above selection with stem; live rotate; one Undo commit. Center does not translate.

## Beam polish

Reduced dual hard wedge stacking; softer radial fill + lighter core with `plusLighter` blend; less “stained glass” when beams overlap.

---

## Tests (`StageInteractionC42Tests` + prior)

- Aim quadrants + handle round-trip  
- Transform blocks move during resize  
- NW opposite-corner fixed, zoom-aware resize, rotated resize  
- Rotation math  
- Aim Undo restores direction **and** length  
- Mover compose does not mutate physical aim  

---

## Manual acceptance (production)

See checklist in closeout §17. Priority:

1. Resize NW/NE/SW/SE — resizes only, never pure move  
2. Aim PAR by handle at vocalist — Undo restores  
3. Mover base aim + live Pan separation  
4. Rotation slider track + thumb  
5. Rotation handle on silhouette  
6. Gesture exclusivity: move / resize / rotate / aim / Space-pan  

---

## STOP

> **Do not begin C5** until C4.2 is approved.

**Approve C4.2 → proceed C5 only.**
