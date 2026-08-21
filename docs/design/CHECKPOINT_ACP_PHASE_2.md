# Checkpoint — Prism ACP Phase 2 (read-only LAN foundation)

**Date:** 2026-08-19  
**Status:** Review-satisfied for lifecycle/discovery mapping  
**ACP tag:** `1.1.0-dev.1`

## Implemented

- `PrismACPService` can start `ACPWebSocketListener` when `loopbackOnly` is false.
- Bonjour advertiser (`_acp._tcp`) with TXT `nid`/`iid`/`url`/`role`/`sec` and **no PIN/token**.
- `Info.plist` Bonjour type `_acp._tcp` and local-network copy updated to ACP.
- Discovery still does not authenticate.
- Mutation capabilities remain empty.

## Tests

`swift test --filter PrismACPTests` — 5 passed (includes Bonjour TXT and no-mutation).

## Residual

In-process Network.framework WebSocket client/server echo previously hung; Phase 2 does not claim Python↔Swift live WS interop. Default configuration remains loopback-only so enablement does not bind LAN until settings opt into it.

## Statement

Phase 2 lifecycle/discovery mapping is review-satisfied. Proceed to Phase 3.
