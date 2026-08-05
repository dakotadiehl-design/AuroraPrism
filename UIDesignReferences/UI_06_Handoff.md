# UI-06 Handoff — Song Mode

**Date:** 2026-08-05  
**Status:** **UI-06 COMPLETE**  
**Depends on:** UI-05  
**Amendment:** A5 (entry nav secondary to GO)

---

## Delivered

| Area | Result |
|------|--------|
| Song CRUD | New / Delete / rename (Inspector) |
| Entries | + Selected Cue, + Cue List, Remove, reorder ↑↓ |
| Remove entry | Does not delete global cue |
| Load | SongDirector.load |
| Entry nav | ◀ Entry / Entry ▶ — labeled **not GO** |
| Missing targets | Warning color on entry detail |
| Automatic | Not offered (backend rejects) |

---

## A5 hierarchy

```text
GO = cue transport (primary, elsewhere)
Song Entry nav = secondary bordered buttons
```

---

## Key files

```text
Sources/AuroraUI/Panels/SongPanel.swift
Sources/AuroraUI/Panels/InspectorPanel.swift (SongInspectorContent)
Sources/Aurora/SongDirector.swift (unchanged orchestration)
```

---

## Next

UI-07 Perform cockpit + A6 transport≠health.

---

*End UI-06 handoff.*
