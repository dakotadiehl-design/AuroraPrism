# UI-04→UI-07 Integration Closeout

**Date:** 2026-08-05  
**Status:** Pre-commit pass complete (Final Pre-Commit Review Fixes applied)

---

## ENTTEC / Local DMX (software)

| Item | Status |
|------|--------|
| USB Pro framed protocol | Implemented |
| macOS raw serial transport (termios) | Implemented |
| Device discovery (serial candidates) | Implemented — labeled Serial/Likely DMX, not false-confirmed ENTTEC |
| Settings device select + enable | Implemented |
| **Universe route UI (U1 → Local DMX)** | Implemented via `UpdateUniverseRoutingCommand` |
| Serial sandbox entitlement | `com.apple.security.device.serial` added |
| Transport open ownership | Driver-only open (no controller pre-open) |
| Failed start → not enabled | Fixed |
| U1-only physical map | Documented in UI (UI-09 for multi-universe map) |
| Device selection persistence | Deferred to **UI-08** |
| Physical hardware verification | **Pending** operator test |

Demo show remains `protocolHint: .none` (safe).

---

## Integration CR status

| ID | Status |
|----|--------|
| CR-01…10, 12, 14, 15 | Pass |
| CR-11 Inspector resync | **Fixed** — uses `DocumentSession.documentGeneration` |
| CR-13 Git checkpoint | After this pass: one clean integration commit recommended |
| Preset Apply capability | **Fixed** (same filter as palette) |

---

## Operator path (Local DMX smoke)

```text
Settings → Output
  → Rescan / pick serial device
  → Enable Local DMX
  → Project Universes: U1 → Local DMX
  → GO / program fixtures
```

**Not** Open DMX.

---

## STOP

No UI-08 until clean commit. UI-08 owns Settings persistence for Local DMX selection.

---

*End closeout.*
