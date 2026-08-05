# UI-02 Shell Handoff — GATE CLOSEOUT COMPLETE

**Date:** 2026-08-05  
**Status:** **UI-02 COMPLETE — FINAL GATE CLOSED**  
**UI-03 may begin when the user asks.**

---

## What UI-02 delivered

| Phase | Result |
|-------|--------|
| **02B Inspector** | Explicit `WorkspaceController.inspectorFocus` (fixture/multi/group/cue/palette/preset/song/project). Does not clear Programmer fixture selection. |
| **02E Build nav** | **Option A:** Left Browser\|Patch\|Groups · Center **Programmer always** · Lower Palettes\|Cues\|Song · Right Inspector |
| **02F Perform** | `PerformWorkspaceShell` — Current/Next via `PerformanceCueSummary`, GO/BACK/STOP, shared health; UI-07 structural seed |
| **02C Settings** | Native `Settings { AuroraSettingsRoot }` — thin real MIDI; app/project scope headers; frame-rate commit on slider end |
| **02D Contract** | `docs/UI_PANEL_CONTRACT.md` — host-agnostic content, no duplicate panels |
| **02G Welcome** | `WelcomeEmptyView` with Wordmark + New/Open/Demo when empty (no DEBUG auto-demo) |
| **Hardening** | Deep-review P0/P1 closed — see `UI-02Ref/Aurora_UI_02_Hardening_Implementation_Plan.md` |

UI-02A visual language **preserved** (not redesigned).

---

## Hardening guarantees (operator-visible)

| Behavior | Rule |
|----------|------|
| Cue row single click | Select + inspect only — **does not fire** |
| Cue row double click | Fire once (plus context-menu Fire / GO) |
| Transport shortcuts | Suppressed while text/value editing owns focus |
| Perform chrome | Hides New / Open / Import (toolbar + menus); Save may remain |
| Current / Next | Resolved `PerformanceCueSummary` — real `Cue.number`, Song targets truthful |
| Inspector CURRENT | Requires matching cue id or list+index |
| Fixture browser click | Explicit inspect focus (sticky cue focus ends) |
| Document replace | `didReplaceDocument` + `documentEpoch`; panels self-heal |
| Dirty New/Open/Demo | Await explicit save result before continuing |
| Demo | Explicit only; universe `protocolHint: .none`; fixed cue UUIDs |
| Health | Shared `AuroraShellHealthSnapshot` (no fake Network disabled) |
| Build ↔ Perform | Presentation only — does not stop playback |
| Live list edit | `updateProject` rebinds by **cue UUID**, not index |
| Deleted active cue/list | Stage look kept; index -1 / idle; UI does not invent substitute CURRENT |
| CURRENT presentation | Never falls back to unrelated `cueLists.first` |

---

## How to verify

1. Run Aurora (Debug does **not** auto-load demo; use Welcome or `⇧⌘D`, or `--load-demo-show`).  
2. **Build:** left tools; Programmer center; lower Palettes/Cues/Song; single-click cue inspects; double-click fires.  
3. **Perform:** no New/Open; Current/Next numbers match real cues.  
4. **Settings:** frame-rate commits on release; Output shows APPLICATION vs PROJECT.  
5. **Empty:** New Show → welcome surface.

---

## Deferred restoration (explicit)

| Phase | Owns |
|-------|------|
| **UI-03** | Programmer Fan / Align / Clear All / technical RGB-W |
| **UI-04** | Palette/preset create, delete, rename, record-ref |
| **UI-05** | Full cue list edit / record / update workflow |

---

## Build navigation hierarchy

```text
Mode:        BUILD | PERFORM          (toolbar)
Left tools:  Browser | Patch | Groups
Center:      PROGRAMMER               (never replaced)
Lower tools: Palettes | Cues | Song
Right:       Contextual Inspector
```

---

## Verification

- `swift test` — macOS product environment  
- Xcode Debug build  
- Backend domain semantics — **unchanged**  

---

## Next

**UI-03** — Fixture Browser + Programmer attribute-state semantics and scale — only when user asks.
