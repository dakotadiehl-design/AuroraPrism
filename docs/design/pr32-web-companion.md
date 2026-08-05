# PR32 — Web Companion (Live Ops)

| Field | Value |
|-------|--------|
| **PR** | PR32 |
| **Status** | Implemented |
| **Depends on** | PR31 |

## Delivered

- Static web UI (`index.html`) for GO/Stop/Back, cue fire, song next/prev, status
- `RemoteWebServer` HTTP on separate port (default **8743**) using same `RemoteSessionManager` + codec concepts
- PIN via query/header; session cookie-ish token in memory
- Mac Remote menu still enables host; status shows web URL
- No second engine

## Protocol note

TCP newline JSON remains for native clients (PR31). Web uses HTTP JSON endpoints that call the same session manager authorize path.
