# Checkpoint — Phase H: Song/Section Integration (AFK)

**Date:** 2026-08-16  
**Status:** **COMPLETE**

## Shipped

- `AMESectionTransition.plan` — deterministic order:
  1. old section `onExitActions`
  2. update AME show context
  3. sequence reset policies (via `AMERuntime.updateShowContext`)
  4. new section `onEnterActions`
- `ControlActionRouter.transitionAMEShowContext` applies the plan live
- `ShowControlController.enterAMESection` host API
- Song musical defaults provenance (`songDefault` vs `projectDefault`) applied to MusicalEngine on song change

## Tests

- Exit-before-enter ordering
- Sequence reset on section entry
- Musical defaults provenance

## STOP

Section lifecycle is wired. Deeper SongDirector auto-progression remains deferred.
