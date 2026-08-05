# UI-07 Handoff — Perform Mode

**Date:** 2026-08-05  
**Status:** **UI-07 COMPLETE**  
**Depends on:** UI-06  
**Amendments:** A5 (GO dominant), A6 (health ≠ transport)

---

## Delivered

| Area | Result |
|------|--------|
| CURRENT / NEXT | PerformanceCueSummary distance-readable |
| Song context | Title + current entry label |
| Transport | Large GO / BACK / STOP — **not** health-gated |
| Song entry nav | Secondary chevron buttons; explicit “not GO” copy |
| Health | Engine / Output / MIDI informational |
| Validation | Banner when issues > 0; transport still available |
| Phase line | playbackPhase when not idle |
| Safety | Toolbar already hides New/Open in Perform (UI-02) |
| Path | Same appModel.go/back/stop / SongDirector as Build |

---

## A6 principle

```text
playback capability ≠ health color
Nonfatal output/MIDI/validation does not disable GO
```

---

## Key files

```text
Sources/Aurora/Shell/PerformWorkspaceShell.swift
Sources/Aurora/Shell/AuroraBuildToolbar.swift (existing Perform safety)
```

---

## STOP

UI-07 is the hard stop. Do **not** begin UI-08.

Integration review target: UI-03 → UI-07 operator chain + hardware smoke readiness.

---

*End UI-07 handoff.*
