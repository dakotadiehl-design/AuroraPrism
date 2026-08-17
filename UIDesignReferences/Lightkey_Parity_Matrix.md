# Aurora Lightkey-Parity Matrix (Pass-1 completion — remaining wave)

**Date:** 2026-08-13  
**Baseline:** Full Pass-1 Audit Gap Report remediation (working tree)  
**Schema:** `ProjectPackage.currentSchemaVersion = 3`

| ID | Requirement | Status | Evidence | Notes / residual |
|----|-------------|--------|----------|------------------|
| P0-A | 2D Stage Designer / Live Preview | **Partial+ / near PASS** | Center Stage workspace; Unplaced/Place All; Remove From Stage; marquee; adaptive beams; Reveal; resolved snapshot | Further beam polish; smart guides deferred |
| P0-B | Fixture Profile Editor | **Partial+ / near PASS** | Build→Profiles; validate; user library; cell blocks | Wheel slot visual editor polish |
| P0-B+ | Generic/raw parameters | **Partial+** | Editor + Programmer Generic faders | Function-range pickers polish |
| A1 multi-cell | Multi-cell fixtures | **Partial+ / near PASS** | Compile `attr@cellN`; cellChase effect; output tests | Stage per-cell chrome optional |
| P0-C | Patch completion | **Partial+ / near PASS** | Center Patch workspace; wrapped universe grid; PATCH-click/Next Free/drag plan; List admin | Profile-card drag polish; mode multi-personality UI |
| P0-D | Programmer | **Partial+ / near PASS** | Beam / Strobe / Generic | Gobo slot grid polish |
| P0-E | Palettes + portable library | **Partial+ / near PASS** | `.auroralib` export/import (File menu); merge command | Nested folder UI polish |
| P0-F | Cue lists / playback | **Partial+ / near PASS** | Reorder/duplicate/timing editor | Loop notes polish |
| P0-G | Effects | **Partial+ / near PASS** | pulse/chase/wave/rainbow + positionCircle/colorStep/cellChase/beamPulse; phase/spread/direction | Preset library polish |
| P0-H | Song Mode | Mostly complete | Song panel + cursor | — |
| P0-I | Global live controls | **PASS-ready** | Master semantics; BO/Freeze/Blind/Panic/Clear/MIDI; tests | Safe Look deferred |
| P0-J | Advanced MIDI | **Partial+ / near PASS** | Rules; behaviors+AHDR/ADSR; drums; safety limiter; feedback output; expressive events | Encoder modes / 14-bit polish; motorized devices |
| P0-K | Unified external control | **Partial+** | ExternalControlLog + Diagnostics | Filters/test-invoke polish |
| P0-L | Output diagnostics | **Partial+ / near PASS** | Universe Monitor semantic attribution | — |
| P0-L+ | Fixture health | **Partial+** | Diagnostics fixture health rows | Physical reachability N/A offline |
| P0-M | Persistence | **Partial+ / near PASS** | schema v3 behaviors/drums/feedback | — |
| P1-D | Web Remote | **Partial+ / near PASS** | Master + Blackout | — |
| A5 | Preview↔output parity | **Partial+ / near PASS** | Resolved-path tests | — |
| A6 / Wave 9 | Formal verification | **READY TO RUN** | Matrix mostly near-PASS; `swift test` green | Operator hardware smoke still required |

**Honest residual (not full commercial Lightkey clone):** custom keyboard shortcuts UI, OSC discovery docs, full MIDI feedback device profiles, 3D/AI/cloud (explicitly deferred).

**Gate:** Software parity path for pre-smoke is substantially complete. Hardware smoke + Wave 9 operator checklist remain before claiming full PASS.
