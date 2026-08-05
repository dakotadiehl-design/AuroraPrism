# PR6 — Patch Management Logic

| Field | Value |
|-------|--------|
| **PR** | PR6 |
| **Status** | Implemented |
| **Depends on** | PR2–PR5 |
| **Unblocks** | PR8 Patch View / Fixture Browser |

## Purpose

Addressing helpers on `ShowProject`, shared `PatchValidator`, and undoable patch commands (universe, embed, patch, repatch, clone, batch).

## Commands

- `AddUniverseCommand` / `RemoveUniverseCommand` (refuse if fixtures remain)
- `EmbedFixtureDefinitionCommand` (no-op if id present)
- `PatchFixtureCommand` (embed + add)
- `AddPatchedFixtureCommand` (uses validator; definition required)
- `RepatchFixtureCommand`
- `ClonePatchedFixtureCommand`
- `DocumentSession.patchFixtures([PatchRequest])` — one undo group

Core does **not** depend on `AuroraFixtureLib`; callers pass definitions.

## Helpers

`ShowProject.nextFreeAddress`, `canPlace`, `dmxSpan`, `patchConflicts`.
