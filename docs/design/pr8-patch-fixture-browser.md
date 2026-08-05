# PR8 — Patch View + Fixture Browser

| Field | Value |
|-------|--------|
| **PR** | PR8 |
| **Status** | Implemented |
| **Depends on** | PR6, PR7 |

## Delivered

- Seed `FixtureLibrary` loaded in `AppModel` and injected via `FixtureLibraryBox`
- Fixture Browser: search, select, **Patch Selected** into first/current universe
- Patch panel: universe picker, add universe, table, clone/remove/repatch
- Inspector: selected fixture details
- All mutations via PR6 commands (undoable)
