# UI-03 Handoff — Fixture Browser + Programmer

**Date:** 2026-08-05  
**Status:** **UI-03 PASS 2 COMPLETE** (Pass 1 review closeout)  
**Depends on:** UI-02 / `ui-02-complete`  
**Tests:** 304 passing; Xcode Debug green  

---

## Delivered

| Area | Result |
|------|--------|
| **Presentation** | Dual-axis support × value; `hasRGBColor` / `hasTechnicalColor` split |
| **Store** | Projection only; no double `objectWillChange`; revision for draft re-sync |
| **Display state** | `AuroraControlDisplayValue` — value / mixed / unavailable on fader & pad |
| **Mixed UI** | Indeterminate MIXED (no fake %); first drag → common for capable |
| **Align** | Optional map; **no fabricated 0** when first capable untouched; button disabled |
| **Position pad** | Pan-only / tilt-only visual + interaction; per-axis mixed |
| **HSV** | Only when `hasRGBColor`; technical-only = channels only |
| **Batch write** | `Programmer.setMany([UUID:[String:Double]])` for color wheel |
| **Tools** | Locate, Home, Clear, Clear All, Fan (center+spread), Align to First |
| **Browser / Groups** | Ordered selection + order summary |
| **Inspector** | Programmer-owned attrs for single fixture |

---

## Locked semantics

```text
Fan:     center + spread + ordered capable fixtures; pan/tilt independent
Align:   Align to First = first capable in orderedFixtureIDs
Mixed:   ordinary drag establishes common value for all capable
Support: none | partial | all  (orthogonal to value)
Value:   untouched | common | mixed
```

---

## Verify

1. Open Demo Show → multi-select dimmer + RGB + movers  
2. Intensity mixed → drag → all capable become common  
3. Fan… → set center/spread → Apply Fan → order strip matches phase  
4. Align to First  
5. Clear vs Clear All  
6. MIDI CC intensity (if mapped) updates fader without reselect  
7. Palette apply refreshes Programmer  

---

## Explicit non-work (next phases)

| Phase | Owns |
|-------|------|
| UI-04 | Palette create/delete/record-ref |
| UI-05 | Cue edit/record |
| later | Inherited/palette-ref chrome when data is real; beam/gobo; stage map |

---

## Tests

- `ProgrammerAttributePresentationTests`  
- `ProgrammerGeometryFanAlignTests`  
- Full suite + Xcode Debug after closeout  
