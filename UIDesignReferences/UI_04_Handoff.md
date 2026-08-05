# UI-04 Handoff — Palettes + Presets

**Date:** 2026-08-05  
**Status:** **UI-04 COMPLETE**  
**Depends on:** UI-03 / `ui-03-complete`  
**Tests:** 313 passing (`swift test`)  
**Amendments:** A1 (Record Ref thin), A2 (mixed never silent)

---

## Delivered

| Area | Result |
|------|--------|
| **Create** | `+ Color` / `+ Pos` / `+ Int` / `+ Look` from Programmer |
| **Create policy** | `PaletteCreate` — common only; refuse empty; no fabrication |
| **Mixed (A2)** | Status always reports skipped mixed attrs by display name |
| **Apply** | Tile click → `setMany` + presentation refresh; selection required |
| **Look apply** | `PaletteResolver` then setMany; empty/overlap truthful |
| **Delete** | Confirm; palette ref count + site summaries |
| **Rename** | Inspector name/notes → `UpdatePalette` / `UpdatePreset` on commit |
| **Record Ref (A1)** | Existing `targetCuesForPaletteRecord` + `recordPaletteRef` only |
| **Commands** | `UpdatePresetCommand` added |
| **Demo** | Summer Night Looks seeded with real multi-fixture levels |

---

## Locked semantics

```text
Create:  common values only; mixed skipped + status; refuse if none
Apply:   Programmer literals only (does not dirty document)
Record:  paletteRefs on cue; never bakes values
Delete:  no cascade rewrite of cue refs
```

---

## Key files

```text
Sources/AuroraModel/PaletteCreate.swift
Sources/AuroraCore/Commands/GroupCommands.swift  (UpdatePresetCommand)
Sources/AuroraUI/Panels/PalettesPanel.swift
Sources/AuroraUI/Panels/InspectorPanel.swift
Sources/Aurora/Shell/BuildWorkspaceHost.swift
Sources/AuroraModel/ShowProject+DemoSummerNight.swift
Tests/AuroraModelTests/PaletteCreateTests.swift
```

---

## Explicit non-work (next)

| Phase | Owns |
|-------|------|
| UI-05 | Cue list/cue CRUD, record/update from Programmer, fade/delay |
| UI-06 | Song entry editor |
| UI-07 | Perform cockpit |

---

## Verify

1. Demo → Palettes lower tool → Looks apply with selection  
2. Program color → + Color → mixed multi-fixture → status lists skipped  
3. Record Ref with cue selected vs fallback  
4. Rename in Inspector → Undo  
5. Delete referenced palette → warning lists sites  

---

*End UI-04 handoff — proceed to UI-05.*
