# Checkpoint C4.4 — Ghosting Root-Cause Fix

**Status:** Implemented for human review  
**Spec:** `UX redesign/Aurora_C4.4_Ghosting_Root_Cause_Fix.md`  
**Date:** 2026-08-14  

## 1. Why C4.3 did not eliminate layout-object ghosting

C4.3 applied the committed/transient **split only for fixtures**.  
Layout objects (`StageLayoutObject`) stayed in a single persistent `ForEach` and moved by updating live `.position` on that same view hierarchy. Comments claimed “rendered once,” but the **C4.3 invariant** required:

```text
active transform → leave committed visual hierarchy → only transient layer paints artwork
```

That was never true for performers/truss/images. Additionally, live `drawingGroup()` / `compositingGroup()` on moving image-backed views was a likely contributor to trails, not a cure.

## 2. Were layout objects kept in the committed ForEach?

**Yes (pre-C4.4).** All non-hidden layout objects rendered through one `ForEach` with live geometry applied in place.

## 3. Gesture-ownership strategy

**Approach B — invisible gesture proxy (chosen).**

| Layer | Contents |
|-------|----------|
| **Committed host** | Always present for each layout object at **committed** geometry. Owns move/resize/rotate gestures. When transient: **no artwork** (clear hit targets + optional invisible handle hits only). When inactive: full committed artwork + chrome. |
| **Transient visual** | Only when `transientLayoutObjectIDs` contains the id. Artwork + **visual** chrome at **live** geometry. `allowsHitTesting(false)`. |

Why B: canvas-owned drag (Approach A) would require a larger marquee/gesture rewrite; proxies keep existing drag finalizers while allowing the committed **artwork** to disappear without killing the gesture host.

## 4. Committed/transient exclusivity

Enforced via existing pure helpers:

- `StageEditRenderEligibility.shouldRenderInCommittedLayer`
- `StageEditRenderEligibility.shouldRenderInTransientLayer`
- `transientLayoutObjectIDs` (move drag, resize, rotate, toolbar rotation preview)

Committed artwork is drawn **only** when committed-eligible. Transient artwork is drawn **only** when transient-eligible. Never both.

## 5. `drawingGroup()` removal

**Removed** from the live layout-object / Stage-transform path:

- deleted `StageTransformCompositingModifier`
- deleted `StageLiveObjectCompositingModifier`
- no world-level `drawingGroup` while transforming

Transient layer uses ordinary SwiftUI rendering + layer-boundary `.transaction { animation = nil }` only.

## 6. AppKit transient surface

**Not required / not used** for this pass. Pure SwiftUI committed/transient split + proxy gestures.

## 7–10. Manual matrix

Run production stress per spec §24 (20s circular drag, multi-select, imported image, resize/rotate/aim regression). Record results in review notes after hands-on pass.

## Automated tests

- `StageEditC43Tests` extended: multi-object exclusivity, cancel restores committed eligibility  
- Prior Stage tests still green  

## Build

Xcode / `swift build` SUCCEEDED after C4.4 changes.

---

## STOP

Do **not** begin C5 until C4.4 ghosting is accepted after production stress recording.

**Approve C4.4 → proceed C5 only.**
