# Checkpoint — Programmer Color Engine (LightKey-style)

**Spec:** `Aurora_Programmer_Color_Engine_LightKey_Style_Spec.md`  
**Reference:** `Aurora_Programmer_Color_Reference.png`  
**Date:** 2026-08-15  
**Status:** Implementation complete — **STOP for human visual acceptance**

---

## What shipped

### Domain (first-class authoring)
- `colorHue`, `colorSat`, `colorVal`, `colorWB` retained in Programmer state
- Derived `colorR/G/B` via `ColorMath.resolvedRGB` (WB isolated in ColorMath)
- Dedicated emitters: `colorW` / `colorA` / `colorUV` independent of wheel
- `Programmer` clamp ranges attribute-aware (hue 0…360, WB −1…1)

### Presentation
- `ProgrammerColorPresentation` + resolver (capability-driven emitters, mixed/partial)
- Legacy RGB-only looks → H/S/V with neutral WB; authoring promoted on edit

### UI
- Programmer tabs: Intensity | **Color** | Position | Beam | Effects
- `ProgrammerColorEngineView`: Dimmer | hero wheel | White/Amber/UV
- `AuroraProgrammerColorWheel`: hue ring, sat field, center preview, WB/brightness character ring, swatches
- Same panel for docked + C5 float

### Tests
- `ColorMathTests` — WB, brightness, batch, clamp
- `ProgrammerColorPresentationTests` — RGB/W/A/UV visibility, authoring retention, emitter independence

---

## Manual acceptance (human)

- [ ] RGB fixture: Dimmer + wheel, no W/A/UV  
- [ ] RGBWA+UV: all three emitters; independent of wheel  
- [ ] Inner brightness does not move Dimmer  
- [ ] WB ring restores after reselection (authoring retained)  
- [ ] Swatches do not zero emitters  
- [ ] Floating Programmer matches docked  
- [ ] Visual match vs `Aurora_Programmer_Color_Reference.png`

---

## STOP

> **Do not begin Advanced MIDI Engine until Color Engine is visually accepted.**
