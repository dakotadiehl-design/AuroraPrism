# UI-10 Handoff — Web / iPad Remote

**Status:** Stabilized (post FirstPass review)

## Implemented

| Area | Notes |
|------|--------|
| requestId | **Required** on mutating HTTP/TCP; no server-side invent |
| Atomic reserve | `reserveRequestId` / `completeRequestId` (race-safe) |
| Protocol | protocolVersion on hello + snapshot; snapshotRevision; commandResult |
| CURRENT/NEXT | `RemoteCueSummaryDTO` rendered in web client |
| Web UI | Large GO, Back/Stop, song prev/next; no Fire cue 0/1 |
| PIN field | Placeholder only (no value="0000") |
| No Programmer (A8) | `setProgrammerAttribute` not on allow-list |
| Bind | Config applied before listeners; web port from settings; menu uses Settings authority |

## Security notes

- Remote disabled until Settings enable (restored on launch if enabled)  
- Mutating actions require auth token/session  
- No TLS — all-interfaces mode labeled honestly (not private-LAN filtered)  
- At-most-once GO via client requestId  

## Tests

`RemoteRequestIdRaceTests`, `RemoteWebServerTests` (missing requestId → 400)

## Checkpoint

Part of UI-08→11 + stabilization tree.
