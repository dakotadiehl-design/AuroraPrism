# ACP → Prism Secure Read-Only Host Integration Plan

## Purpose

Integrate ACP's public Apple host lifecycle into Prism while preserving the strict read-only security boundary established for the first Prism ACP milestone.

The objective is to prove that Prism can operate as a fully provisioned, signed, mutually authenticated, restart-safe ACP host without exposing any path from ACP to Prism control or mutation systems.

This document is the implementation directive for that milestone.

## Repository and protocol baseline

Before changing Prism:

1. Record the exact ACP and Prism Git SHAs.
2. Verify the required APIs exist as public declarations in that ACP checkout.
3. Record the provider qualification manifest used by the signed Prism build.
4. Treat the recorded ACP checkout as read-only for this implementation.

Required public API:

```swift
ACPAppleHostFactory.openOrBootstrap(...)
host.makeFullServerListener(...)
host.makeEnrollmentService(...)
host.enrollmentRequestUpdates()
host.pendingEnrollmentRequests()
host.approveEnrollment(...)
host.rejectEnrollment(...)
host.cancelEnrollment(...)
host.trustedPeers()
host.revokePeer(...)
host.operationalStatus()
```

If a required capability is package-only, SPI-only, test-only, incomplete, or absent, stop and report the ACP gap. Do not reproduce it inside Prism using `@testable`, SPI, copied source, fixture credentials, direct Keychain manipulation, or Prism-owned cryptography.

Repository permissions for this milestone:

```text
Prism / Aurora:                 read and write
AuroraCommunicationsProtocol:   read only
AuroraRemote:                   read only
Other Aurora-family projects:   read only
```

## Architectural boundary

The production topology is:

```text
ACP discovery metadata
        ↓
ACP Apple Full listener
        ↓
Mutually authenticated TLS 1.3
        ↓
ACPFramedConnection
        ↓
ACPAuthenticatedConnection
        ↓
Authenticated ACPSession
        ↓
Prism read-only adapter
        ↓
Authoritative Prism state projections
```

There must be no ACP-originated path to:

- `ControlActionRouter`
- `ShowControlController`
- Aurora Engine
- Cue execution
- Grand Master mutation
- Blackout mutation
- Programmer mutation
- Navigation or transport control
- Busking
- Momentary controls
- Any other live-show mutation

Prism may publish current values of mutable state. ACP must not be able to change those values.

## Client compatibility boundary

The Secure Host Gate initially uses an ACP security/conformance client that accepts an observation-only capability set.

The existing Prism Remote capability preset requires mutation-related capabilities including `remote.control.invoke` and `remote.control.momentary`. Prism must not advertise those capabilities merely to make a client enter its normal ready state.

Native Aurora Remote compatibility is not a Secure Host Gate requirement unless Remote implements an explicit observation-only mode. Any such Remote change is outside this Prism implementation.

## Phase A — Public host adoption

Replace Prism's externally injected `ACPAppleFullProviderConfiguration` with an ACP-owned host created through:

```swift
let host = try await ACPAppleHostFactory.openOrBootstrap(
    configuration: hostConfiguration
)
```

Prism supplies only application-level configuration:

- Stable Prism node ID.
- Fresh process instance ID.
- Prism role and display name.
- Lowercase application-unique Keychain namespace.
- Keychain access group, when required.
- Qualified provider provenance.
- Secure Enclave preference.
- Explicitly approved non-hardware fallback policy.

The resulting `ACPAppleHost` remains owned by `PrismACPService`. Prism must not extract or independently persist private keys, authority material, certificates, raw Keychain references, trust anchors, or package-internal authority objects.

### Provider provenance

Prism must:

- Bundle the qualified provider manifest as a signed application resource.
- Load it without editing or regenerating it.
- Parse it with `ACPProviderProvenance(jsonData:)`.
- Verify it applies to the linked ACP provider revision.
- Fail closed when it is missing, damaged, mismatched, or unqualified.

Prism must not construct provenance from application constants.

### Bootstrap and recovery rules

`openOrBootstrap()` must preserve these distinct outcomes:

```text
Fresh installation + no prior ACP state
    → bootstrap is permitted

Existing installation + valid ACP state
    → reopen the existing host

Existing installation + inconsistent or damaged state
    → block ACP startup
```

Failure to load an existing identity must never silently create a replacement trust domain.

Tests must cover missing keys, missing certificates, key/certificate mismatch, damaged authority metadata, inconsistent trust-domain identifiers, corrupted provisioning records, invalid persistent references, and `resetRequired` state.

## Phase B — Public enrollment

Create the host-owned enrollment service:

```swift
let enrollment = try host.makeEnrollmentService(
    configuration: try ACPAppleEnrollmentServiceConfiguration()
)
let enrollmentEndpoint = try await enrollment.start()
```

Replace Prism's placeholder enrollment presentation model with a thin adapter over:

- `host.enrollmentRequestUpdates()`
- `host.pendingEnrollmentRequests()`
- `host.approveEnrollment(requestID:)`
- `host.rejectEnrollment(requestID:)`
- `host.cancelEnrollment(requestID:)`

The presentation model must retain `ACPEnrollmentAttemptID` as its opaque internal identifier. It must not replace it with a newly generated UUID or reconstruct it from presentation data.

Prism UI may receive only:

- Opaque request identifier.
- Sanitized peer summary.
- Safe presentation metadata.
- Enrollment state.
- Permitted local decisions.
- Sanitized failure information.

Prism may decide approve, reject, or cancel. ACP remains responsible for cryptographic validation, credential issuance and delivery, receipt verification, trust commit, ceremony state, and recovery.

Approval establishes ACP trust only. It grants no Prism show-control authority. All newly enrolled clients remain observation-only.

Enrollment and operational listeners remain separate lifecycle objects. Enrollment discovery must be distinguishable from operational discovery, and bootstrap secrets must never appear in Bonjour data or logs.

## Phase C — Host-owned authenticated listener

Use:

```swift
let listener = try host.makeFullServerListener(port: configuredPort)
```

The production transport is definitively:

```text
Network.framework TCP
    → TLS 1.3 with mutual authentication
    → ACPFramedConnection
    → HELLO exporter binding
```

It is not WebSocket or WSS. Prism must not start `ACPWebSocketListener`, advertise `ws://` or `wss://`, or introduce a WebSocket compatibility layer.

Only `ACPAuthenticatedConnection` values returned by the Full listener may become production sessions.

Before recording a session as active:

1. Confirm it originated from `ACPAppleFullServerListener`.
2. Create it with `connection.makeSession(local:)`.
3. Complete the ACP handshake.
4. Confirm only Prism's read-only capabilities were negotiated.
5. Never reconstruct the authenticated principal from Bonjour or HELLO claims.

Raw TCP/TLS connections are not authenticated Prism ACP sessions.

### Read-only capabilities

Advertise only capabilities Prism actually supports for observation, such as:

```swift
[
    ACPCapability(id: "remote.profile", version: "1.0"),
    ACPCapability(id: "state.live", version: "1.2"),
    ACPCapability(id: "system.health", version: "1.0"),
]
```

Do not advertise control invocation, momentary control, command replay, cue, blackout, Grand Master, navigation, transport, or busking capabilities.

## Phase D — Minimal state and mutation denial

The first secure qualification uses the smallest schema-valid read-only projection needed to prove:

```text
Authenticated session
    → read-only request
    → authoritative Prism projection
    → schema-valid response
```

Do not make the complete Prism Remote state model a prerequisite for the Secure Host Gate.

### Explicit inbound classification

Enumerate every Remote-profile message registered by the current ACP implementation and classify it as exactly one of:

```text
ALLOWED_READ_ONLY
REJECTED_MUTATION
PROTOCOL_INTERNAL
```

There must be no unclassified category. A future ACP message must fail closed until Prism explicitly classifies it.

Potential read-only/session messages include:

- `remote.hello`
- `state.request`
- `health.heartbeat`
- `session.goodbye`
- Required protocol and error messages

The exact allowlist must come from the recorded ACP registry and schemas.

Reject mutation families before application routing, including:

- `remote.control.invoke`
- Momentary begin, renew, end, and cancel
- Cue execution
- Navigation
- Transport
- Output, blackout, and Grand Master mutation
- Programmer mutation
- Busking
- Mutation replay and recovery
- Control-bearing resource activation
- Unknown or malformed control invocation

Rejected requests must:

- Receive a deterministic, schema-valid ACP error.
- Follow ACP correlation rules.
- Produce no Prism mutation.
- Produce no state revision caused by application mutation.
- Never touch `ControlActionRouter`.

The read-only adapter must have no dependency or callback involving control, output, engine, programmer, momentary-authority, or command-ledger types. Enforce this using both module-boundary tests and source scans.

## Secure Host Gate

The gate passes only when a signed Prism host demonstrates:

```text
Fresh host bootstrap
    → restart with the same identity and trust domain
    → enrollment request
    → explicit local approval
    → mutually authenticated TLS 1.3
    → exporter-bound authenticated HELLO/session
    → minimal read-only state
    → exhaustive mutation rejection
    → credential revocation
    → active transport closes
    → revoked credential cannot reconnect
```

No Prism control integration is required or permitted.

## Phase E — Revocation and trusted-peer presentation

Use only the public host API:

```swift
host.trustedPeers()
host.revokePeer(credentialID: ...)
host.operationalStatus()
```

Prism requests revocation through `host.revokePeer`. ACP owns credential-specific active transport termination through its revocation-aware transport. Prism observes session closure and removes presentation state; it must not build a duplicate credential-to-socket revocation system.

Revocation must:

1. Operate on authenticated credential identity.
2. Commit durably.
3. Close the matching active transport.
4. Prevent reconnect with the revoked credential.
5. Leave other authenticated viewers connected.
6. Preserve all Prism show and output state.
7. Produce sanitized diagnostics.
8. Survive Prism restart.

Never identify a session for revocation solely by its HELLO node ID.

## Phase F — Discovery and lifecycle

Discovery starts only after the secure host and operational listener are ready.

Startup order:

```text
1. Load and verify provider provenance
2. Open and validate ACP host
3. Start enrollment, when enabled
4. Start authenticated Full listener
5. Start Bonjour last
```

Externally visible shutdown order:

```text
1. Stop Bonjour
2. Stop accepting new operational sessions
3. Stop operational and enrollment listeners
4. Close remaining sessions
5. Release application references to the host graph
```

Disabling enrollment need not terminate existing authenticated observation sessions. Disabling ACP entirely must stop enrollment, operational listeners, discovery, and active sessions, leaving the network silent.

### Discovery blocker rule

`ACPAppleFullServerEndpoint` exposes a port and TLS requirement, while the general discovery model expects an endpoint URL. Before implementing Bonjour, confirm ACP's canonical discovery representation for framed ACP-over-TLS.

If ACP does not define that representation:

- Stop the discovery phase.
- Report the ACP gap.
- Do not invent a URI scheme.
- Do not publish custom Prism-only TXT vocabulary.
- Continue direct-address Secure Host qualification only if doing so does not weaken security.

Bonjour is metadata only. It must never carry credentials, permissions, bootstrap codes, certificates, tokens, or session secrets, and it must never be used for authentication or authorization.

## Discovery Gate

The gate passes when:

- ACP defines and Prism uses the canonical framed-transport representation.
- Operational and enrollment endpoints are correctly distinguished.
- TXT data contains no secret or authorization data.
- Bonjour begins only after its listener is ready.
- Listener failure removes the advertisement.
- ACP disablement makes Prism network silent.

The Discovery Gate may remain blocked on an ACP contract gap without invalidating direct-address Secure Host qualification.

## Phase G — Expanded read-only Prism state

After the Secure Host Gate, expand only namespaces backed by actual Prism authority:

- `show.project`
- `show.setlist`
- `show.selected_song`
- `show.current_song`
- `show.current_section`
- `show.next_section`
- `show.mode`
- `show.running`
- `show.progression`
- `look.catalog`
- `look.current`
- `look.preview`
- `output.grand_master`
- `output.blackout`
- `system.health`

Missing domains must be omitted or represented exactly as their schema prescribes. Do not invent placeholder show, song, look, cue, or output data.

State flows in one direction:

```text
Local Prism operation
    → authoritative Prism state changes
    → immutable ACP projection
    → observation client receives update
```

The reverse path does not exist.

## Phase H — Revisioned state synchronization

Implement:

- Stable authority epoch.
- Monotonically increasing authoritative revision.
- Initial snapshot.
- Event-driven deltas.
- Revision-gap detection.
- Snapshot resynchronization.
- Reconnect snapshot.
- Multi-viewer convergence.

Do not reintroduce fixed-interval polling.

## Observation Host Gate

The gate passes when:

- Every published namespace is schema-valid and authority-backed.
- Local cue, Grand Master, blackout, and show-state changes are observable.
- ACP cannot change any published value.
- Multiple viewers converge on the same revision.
- Revision gaps force resynchronization.
- Reconnect begins from an authoritative snapshot.
- Exhaustive mutation-denial tests remain green.
- Native Aurora Remote is tested only if it supports an explicit observation-only mode.

## Diagnostics and UI

Prism may display:

- Disabled, starting, secure/read-only, blocked, or failed state.
- Host provisioning status.
- Node ID.
- Operational and enrollment ports.
- Credential expiration status.
- Renewal readiness, currently unsupported.
- Enrollment state and pending requests.
- Trusted clients.
- Revocation state.
- Sanitized ACP errors.

The UI must clearly state **Observation only**.

Prism must fail closed when the credential expires. It must not imply automatic renewal exists while ACP reports renewal as unsupported.

Diagnostics must not log bootstrap secrets, private keys, SPAKE secrets, raw Keychain persistent references, session secrets, complete credentials, or sensitive transcript material.

## Signed-host qualification

Package tests alone are insufficient. Qualification must run inside the signed Prism application or signed test host.

Verify:

- Secure Enclave selection where applicable.
- Non-exportable Keychain fallback only when explicitly permitted.
- Private-key non-exportability.
- Persistent identity reload.
- SPKI/signing agreement.
- Provider provenance validation.
- Entitlement and Keychain access-control failures.
- Missing and corrupted identity behavior.
- Mutually authenticated TLS 1.3.
- Authenticated HELLO and exporter binding.
- Enrollment approval, rejection, cancellation, and expiry.
- Restart recovery.
- Credential revocation.
- Active transport termination after revocation.

## Required mutation-denial matrix

Using an authenticated, enrolled client, attempt:

- GO
- Back
- Stop
- Grand Master change
- Blackout set and clear
- Momentary begin, renew, end, and cancel
- Navigation
- Transport
- Busking
- Programmer mutation
- Unknown control invocation
- Malformed control invocation

Every attempt must produce:

```text
schema-valid deterministic rejection
    + zero Prism mutation
    + zero ControlActionRouter invocation
```

## Deferred trust reset

Trust reset does not block the initial Secure Host Gate unless ACP qualification requires it.

When implemented, it must use:

```text
host.planLocalSecurityReset()
    → present exact consequences
    → explicit local confirmation
    → platform-local authentication
    → complete ACP network shutdown
    → host.executeLocalSecurityReset(plan)
```

Trust reset must never be remotely invocable and must remain separate from show-document or asset reset.

## Immediate implementation sequence

1. Record ACP and Prism SHAs.
2. Verify every required public API.
3. Verify and package qualified provider provenance.
4. Confirm framed TLS transport and discovery contract.
5. Replace externally injected host material with `ACPAppleHost`.
6. Exercise clean first-run bootstrap.
7. Verify restart preserves identity and trust domain.
8. Integrate public enrollment with opaque ACP identifiers.
9. Start the host-owned authenticated listener.
10. Implement minimal schema-valid state.
11. Implement exhaustive message classification and mutation denial.
12. Integrate public trusted-peer inspection and revocation.
13. Run signed-host, TLS, HELLO, exporter, enrollment, restart, and revocation qualification.
14. Declare the Secure Host Gate only when all requirements pass.
15. Implement canonical discovery, or report its ACP blocker.
16. Expand authority-backed read-only Prism state.
17. Implement snapshot and delta synchronization.
18. Run multi-viewer and reconnect convergence tests.
19. Declare the Observation Host Gate.
20. Leave every ACP-originated control path disabled.

## Final architectural rule

ACP owns:

- Security lifecycle.
- Provisioning and enrollment.
- Credential custody.
- Authentication.
- Trust and revocation.
- Secure transport.

Prism owns:

- The information it chooses to expose.
- Authoritative application state.
- Read-only state projection.
- Local presentation and human decisions.

The immediate objective is to prove that ACP's public host interface gives Prism a production-quality secure front door while Prism remains an observation-only host. A future control milestone may consider authenticated principals, Prism-owned authorization policy, `authorizeAndConsume`, and `ControlActionRouter`; that work is explicitly out of scope here.
