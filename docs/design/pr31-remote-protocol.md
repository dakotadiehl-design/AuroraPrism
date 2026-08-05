# PR31 — Remote Protocol & Session Core

| Field | Value |
|-------|--------|
| **PR** | PR31 |
| **Status** | Implemented |
| **Depends on** | PR3–4, PR10–11 |

## Delivered

- SPM target `AuroraRemote` → Core + Model only
- `remoteProtocolVersion = 1` JSON message codec
- `RemoteSessionManager`: PIN auth, roles (viewer/operator), session lock, client limits
- `RemoteCommand` allow-list → `RemoteShowAction` (maps to app `ShowAction` at host)
- `RemoteHost` TCP/HTTP skeleton (enable off by default)
- Unit tests: codec, PIN fail, viewer cannot fire, operator allow-list

## Architecture

Remote is a **Core client**, not a second engine. Host app bridges actions into existing `AppModel.perform` / engine APIs.
