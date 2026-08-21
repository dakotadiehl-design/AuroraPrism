# Checkpoint — Prism ACP Phase 8 (legacy deletion)

**Date:** 2026-08-20  
**Status:** **COMPLETE** — source, documentation, build, automated regression, and runtime removal gates satisfied

## Deleted

- `Sources/AuroraRemote/**`
- `Tests/AuroraRemoteTests/**`
- `RemoteController.swift`, `RemotePINKeychain.swift`
- `AuroraRemote` package product, app dependency, and test targets

## Replaced

- Settings Remote tab → ACP enable, Bonjour, WebSocket port `27421`, network scope
- Remote menu → Enable/Disable ACP, revoke clients
- Diagnostics snapshot remote fields now read `PrismACPController`
- Old PIN/port defaults are cleared and never imported into ACP enrollment

## Source and documentation gate

No matches for `AuroraRemote`, `RemoteHost`, `RemoteWebServer`, `RemoteSessionManager`, `RemoteProtocolClient`, `RemoteCodec`, `RemoteSnapshot`, `RemoteShowAction`, `remotePIN`, `8742`, `8743`, or `/api/hello|command|snapshot` remain under production `Sources/`, `Tests/`, `Package.swift`, `project.yml`, app metadata, README, or active setup/architecture documentation.

The active Xcode and system-design documents now describe ACP as Prism's only remote stack. Historical PR/design records may retain clearly historical descriptions of the deleted system.

## Runtime removal gate

The freshly built Debug `Prism.app` was launched and inspected as process `75869`:

- no process listened on TCP `8742` or `8743`;
- direct requests to `/api/hello` on both legacy ports failed to connect (`HTTP 000`);
- no browser remote or legacy HTTP route was served;
- with ACP disabled, TCP `27421` was also closed and no `_acp._tcp` service was advertised.

The Phase 5–7 live Workbench transcripts separately prove that enabled Prism exposes its configured ACP endpoint and that ACP disable/reconnect behavior preserves authoritative state. Phase 6 proves disabling/stopping ACP releases leased holds safely. Together these satisfy the enabled and disabled runtime cases without restoring any legacy compatibility path.

## Tests

`xcodebuild -project Aurora.xcodeproj -scheme Aurora -configuration Debug -derivedDataPath /tmp/prism-phase8-derived CODE_SIGNING_ALLOWED=NO build` — **succeeded**.

`swift test --filter 'PrismACPTests|AuroraPackageSmokeTests|LoggingSettingsAndDomainTests'` — **37 passed**, **0 failures**.

`git diff --check` for the Phase 8 documentation changes — clean.

## Statement

Phase 8 is complete. Prism has one remote stack, one security model, and one network boundary: ACP. No legacy source, target, credential migration, listener, HTTP route, bundled browser client, or active documentation path remains.
