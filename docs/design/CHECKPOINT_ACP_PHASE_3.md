# Checkpoint — Prism ACP Phase 3 (event-driven state)

**Date:** 2026-08-19  
**Status:** Review-satisfied for first populated domains

## Implemented

- `PrismACPAuthoritativeState` projects `prism.show`, `prism.performance`, `prism.cue`, `prism.output`, `prism.health` with `authority_epoch` + `revision`.
- `ShowControlController` advances revision on GO/BACK/STOP/fire and can replace the epoch.
- Legacy 200 ms `RemoteSnapshot` timer is unreachable: `AppModel` never calls `RemoteController.setRemoteEnabled`.

## Tests

Snapshot domain names + delta apply covered in `PrismACPServiceTests.testAuthoritativeSnapshotProjectsStableDomains`.

## Statement

Phase 3 projector + commit-boundary revision is review-satisfied. Narrow mutation mapping exists but is **not advertised**.
