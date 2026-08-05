# PR34 — Native iPad Companion (Scaffold)

| Field | Value |
|-------|--------|
| **PR** | PR34 |
| **Status** | Scaffold / protocol client only |
| **Depends on** | PR31–33 |

## Decision

The monorepo remains **`platforms: [.macOS(.v14)]`**. A full SwiftUI `AuroraPad` app target would require iOS platform support, signing, and distribution choices that must not be half-done.

This PR delivers:

1. **`RemoteProtocolClient`** — shared client helper (hello, command encode, snapshot decode) usable by a future iOS app or tests  
2. Design acceptance of **same protocol** as web/TCP  
3. Explicit non-delivery of an App Store–ready iPad binary in this package  

## Follow-up (separate effort)

- New Xcode project or multi-platform package with `iOS` + `macOS`  
- SwiftUI live-ops screens reusing `RemoteProtocolClient`  
- Distribution (TestFlight / Ad Hoc / enterprise)

## Acceptance for this scaffold

- [x] No second engine  
- [x] Client speaks protocol v1  
- [x] Unit tests for client encode/decode path  
- [x] Document that native Pad UI ships later  
