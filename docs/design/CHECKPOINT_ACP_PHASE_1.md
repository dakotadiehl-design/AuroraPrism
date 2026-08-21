# Checkpoint — Prism ACP Phase 1

**Date:** 2026-08-19  
**Status:** Review-satisfied  
**ACP tag consumed:** `1.1.0-dev.1` (`2091bf3afbd61bea29c23d5e51480780ed0fc8d8`)

## Phase objective

Make XcodeGen the source of truth for the local `AuroraACP` package, add the `PrismACP` integration module, and stop starting the legacy TCP/HTTP remote.

## Files changed

- `Package.swift` — path pin to `../AuroraCommunicationsProtocol`, `PrismACP` product/target/tests
- `project.yml` — `AuroraACPPackage` + `AuroraACP` and `PrismACP` app dependencies
- `Aurora.xcodeproj` — regenerated; third generation produced no diff
- `Sources/PrismACP/*` — identity, lifecycle, loopback, no mutation capability
- `Sources/Aurora/Controllers/PrismACPController.swift`
- `Sources/Aurora/AppModel.swift` — ACP enable path; `remote.stopAll()` always
- `Tests/PrismACPTests/PrismACPServiceTests.swift`
- `docs/xcode-project.md`

## Tests and commands run

| Command | Result |
|---|---|
| `swift test --filter PrismACPTests` | **3 passed**, 0 failed |
| `swift test --filter PrismACPTests` also linked `Aurora` | app target compiled |
| `./Scripts/generate-xcodeproj.sh` ×2 then ×3 | AuroraACP present, `acp-framed-hello` absent, third pass clean |

## Review

1. Unauthorized input cannot reach Prism semantics: no mutation capability advertised; `submit` throws `mutationsNotAdvertised`.
2. No ACK-before-commit path exists yet (no mutations).
3–7. N/A for loopback-only foundation.
8. Disabled service is network silent (`loopback == nil`, discovery off).
9. `project.yml` is now the package owner; third XcodeGen pass was identical.
10. Legacy listeners are stopped in `AppModel.init` and `applyRemoteFromSettings`; they are not started.
11. `PrismACP` imports `AuroraACP` + `Foundation` only (plus diagnostics not currently used in sources). No `AuroraOutput`, SwiftUI, or engine types.
12. Loopback transports are created; no handshake-only claim.

No P0/P1. Deferred: LAN WebSocket/Bonjour (Phase 2), settings UI replacement (Phase 2+).

## Statement

Phase 1 is **review-satisfied**. Proceed automatically to Phase 2.
