# UI-05 Handoff — Cue Workflow

**Date:** 2026-08-05  
**Status:** **UI-05 COMPLETE**  
**Depends on:** UI-04  
**Tests:** 319 passing  
**Amendments:** A3 (Update immediate), A4 (array-order playback)

---

## Delivered

| Area | Result |
|------|--------|
| **Ordering (A4)** | Documented + tested: `CueList.cues` array = GO order; `Cue.number` display only |
| **List CRUD** | + List / Delete List (`RemoveCueListCommand`) |
| **Cue CRUD** | + Empty, Delete (confirm), Record, Update |
| **Record** | `programmer.captureLevels()` → append cue |
| **Update (A3)** | Immediate level replace; no modal; undoable; timing preserved |
| **Fire** | Explicit Fire + double-click; single-click select only |
| **Inspector** | Editable name, number, fade in/out, delay, tracking |
| **Engine path** | Mutations via commands → existing `applyProjectUpdate` |

---

## Locked

```text
Playback order = array order
Cue.number = display metadata
Update = levels only unless fields edited
Delete may confirm; Update must not
```

---

## Key files

```text
Sources/AuroraUI/Panels/CueListPanel.swift
Sources/AuroraUI/Panels/InspectorPanel.swift (CueInspectorContent)
Sources/AuroraCore/Commands/RemoveCueListCommand.swift
Tests/AuroraEngineTests/PlaybackOrderingAuthorityTests.swift
```

---

## Next

UI-06 Song Mode — entry editor; entry nav secondary to GO (A5).

---

*End UI-05 handoff.*
