# Checkpoint — Programmer Color Engine 1.1 Closeout

**Spec:** `Aurora_Programmer_Color_Engine_1.1_Closeout.md`  
**Date:** 2026-08-15  
**Status:** Implementation complete — **STOP for human visual acceptance**

---

## Fixes landed

| ID | Fix |
|----|-----|
| **A** | Saturation mapped to **visible annulus** (character ring outer → hue ring inner); thumb uses inverse |
| **B** | Single WB angle convention in `ColorMath` (`whiteBalanceAngleDegrees` / `whiteBalance(fromAngleDegrees:)`) for gesture + marker |
| **C** | `rebuildDrafts(from:)` rebuilds all drafts on selection/identity change — no stale White/Dimmer/HSV |
| **D** | Mixed center preview uses presentation mixed visual (quartered + MIXED); not draft-derived solid color |
| **E** | Color palette keys include authoring H/S/V/WB + colorA/UV (+ WW/CW/Lime/Cyan); apply keeps authoring through capability filter |
| **F** | Importer: Warm/Cool White before White; UV/Ultraviolet; Lime; Cyan |
| **G** | `GlobalShowControl.isColorEmitter` excludes authoring keys; explicit physical registry |
| **H** | Virtual dimmer: RGB fixtures get intensity capability; `MergeStub.resolveOutputAttributes` scales all physical emitters by intensity when no physical dimmer channel |
| **I** | `noteProgrammerUIChanged()` refreshes presentation only (no full-shell `notifyUI` per pointer sample) |

## Architecture preserved

Authoring `colorHue/Sat/Val/WB` → ColorMath → physical RGB; dedicated emitters independent; Dimmer = physical **or** virtual via same `intensity` attribute.

## Tests

- `ColorEngineCloseout11Tests` — annulus geometry, WB round-trip, virtual dimmer, global master safety  
- Expanded `FixtureImporterTests` — emitter name specificity  
- Prior Color Engine presentation/math tests still pass  

## Manual acceptance

- [ ] Drag pastel/low sat colors on annulus  
- [ ] WB cool/warm marker tracks drag side  
- [ ] Switch fixtures: no stale White/Dimmer  
- [ ] Mixed selection: MIXED center, not previous color  
- [ ] Color palette RGBWA+UV round-trip  
- [ ] RGB-only fixture: Dimmer scales output without rewriting authored RGB  
- [ ] Color drag does not thrash whole shell  

## STOP

> **Do not begin Advanced MIDI Engine until Color Engine 1.1 is accepted.**
