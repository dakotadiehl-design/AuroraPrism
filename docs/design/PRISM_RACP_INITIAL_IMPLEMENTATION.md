# Prism rACP initial implementation

Prism embeds ReasonableACP at the exact revision pinned in `project.yml` and
`Package.swift`. The app target owns a thin adapter; protocol parsing, request
correlation, framing, connection limits, and TCP transport remain in rACP.

The service is disabled by default. Operators can enable it and select a port in
Settings → Remote. rACP uses plain TCP without authentication or encryption, so
the listener is intended for trusted production networks only.

When enabled, the same TCP listener is advertised as `_racp._tcp.local.`. The
DNS-SD instance name uses the app's display name, falling back to `Prism`, and is
presentation-only. Its TXT record
contains the discovery profile version plus the same persistent peer ID and peer
type used by Prism's rACP `HELLO`; TXT metadata is an untrusted discovery hint,
and `HELLO` remains authoritative. Capabilities are negotiated only through rACP
and are never included in DNS-SD metadata.

Static host/port connections remain supported. Discovery depends on multicast
DNS availability and may not cross VLANs or routed network boundaries without
additional network infrastructure. Failure to discover Prism therefore does not
imply that direct rACP connectivity has failed.

## Commands

- `cue.go`, `cue.back`, and `cue.stop`
- `output.grand_master.set` with a number from 0 through 1
- `output.blackout.set` with a Boolean
- `song.select` with a song UUID string

Commands are validated before reaching `ShowControlController`. They use the
same authoritative methods as local UI actions, ACK only after application, and
map rejected operations to rACP error codes.

## State

Clients can subscribe to `cue.current`, `cue.next`, `playback.state`,
`output.grand_master`, `output.blackout`, `song.current`, and `prism.status`.
Every payload carries Prism's authority epoch and semantic revision. A current
snapshot is sent after subscription and subsequent committed changes are pushed
event-first; frame polling is not used as the source of protocol state. The
`song.current` payload also includes the current section and entry position.
Transport revisions remain monotonic across authority-epoch changes, even though
Prism's semantic revision intentionally restarts for a replacement show.

## Lifecycle and verification

`PrismRACPService` owns the listener and all accepted connections, reports
starting/listening/failed state and connected-client count to settings and
diagnostics, and closes the listener and clients during shutdown or reconfigure.
The dedicated `AuroraRACPTests` scheme covers command validation, local/remote
parity, projection, persisted settings, real loopback TCP exchange, bind
failure, and shutdown disconnection.
