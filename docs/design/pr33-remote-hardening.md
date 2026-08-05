# PR33 — Remote Hardening

| Field | Value |
|-------|--------|
| **PR** | PR33 |
| **Status** | Implemented |
| **Depends on** | PR32 |

## Delivered

- Per-session command rate limit
- Kick single client + kick all
- Reject empty PIN when remote enabled
- Client cap enforcement tests
- Disable remote invalidates web tokens (web server stop clears tokens)
- Security-oriented unit tests

## Still host-operator responsibility

- Venue firewall / Wi-Fi isolation
- TLS (LAN HTTP v1 remains cleartext; document threat model)
