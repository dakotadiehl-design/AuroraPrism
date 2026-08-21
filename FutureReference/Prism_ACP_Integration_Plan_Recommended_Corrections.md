# Prism ACP Integration Plan — Recommended Corrections Before Execution

## Purpose

This document updates the current **Prism ACP Integration — Sequential Implementation Plan** to reflect the actual project state at this checkpoint.

Current facts:

- The canonical Swift ACP implementation has already been converted into the root Swift package `AuroraACP`.
- The ACP package has already been added to the Prism Xcode project.
- Prism is still internally named **Aurora** in Xcode and related project identifiers due to the rebrand. In this document, the Xcode target `Aurora` means the Prism application.
- `AuroraACP` should be linked to the Xcode target `Aurora`.
- `acp-framed-hello` should remain unlinked from the app target.
- ACP is still intended to fully replace Prism’s legacy remote stack. There is no compatibility requirement for the old TCP/HTTP/PIN/browser implementation.

The existing Grok plan is fundamentally sound. The corrections below should take precedence where they conflict with that plan.

---

# 1. Do Not Repeat the Swift Package Conversion

The plan should not treat ACP as though it still needs to become a consumable Swift package.

That work is already complete.

Current canonical package state:

```text
AuroraCommunicationsProtocol/
├── Package.swift
├── Sources/
│   └── AuroraACP/
├── tests/AuroraACPTests/
├── python/
├── rust/
├── schema/
├── vectors/
└── docs/
```

Already completed:

- Root `Package.swift`
- Swift library product `AuroraACP`
- Consumer syntax:

```swift
import AuroraACP
```

- Consolidation of the old `ACPModel`, `ACPEncoding`, and `ACPSession` Swift modules
- Removal of the old `swift/` package tree
- Preservation of `acp-framed-hello`
- Root-level `swift build`
- Root-level `swift test`
- Schema-pack and registry drift checking
- Cross-language interoperability verification
- Dummy external package import verification

**Instruction to Grok:** treat the current package as the baseline. Do not restructure it again unless a concrete integration issue requires it.

---

# 2. Preserve the ACP Package Already Added to Prism

The package has already been added to the Prism Xcode project.

The intended Xcode package-product mapping is:

```text
AuroraACP          → Add to Target: Aurora
acp-framed-hello   → Add to Target: None
```

This is correct.

Remember:

```text
Xcode target name: Aurora
Product name:      Prism
```

Do not rename the `Aurora` application target as part of ACP integration.

Do not link `acp-framed-hello` into Prism. It remains an ACP interoperability fixture only.

Before modifying project/package configuration, inspect the current Xcode state and preserve the already-working package reference.

---

# 3. Correct the ACP Versioning Sequence

The current plan proposes creating `0.9.0-dev1` as the first ACP tag for Prism integration.

That no longer matches the actual project history.

The completed canonical Swift package should become the clean package baseline:

```text
AuroraACP package release: 1.0.0
ACP wire protocol:         1.2
```

These are separate version spaces.

The package version describes the implementation/library release:

```text
AuroraACP 1.0.0
AuroraACP 1.1.0
AuroraACP 1.1.1
AuroraACP 2.0.0
```

The wire version describes network compatibility:

```text
ACP 1.2
```

A package update does not automatically require a wire-protocol version change.

For example:

```text
AuroraACP 1.1.0
may still speak
ACP 1.2
```

## Recommendation

Before beginning new Prism/Remote ACP feature work:

1. Review the completed package-conversion checkpoint.
2. Commit any remaining package-conversion changes.
3. Tag the canonical package baseline as:

```text
1.0.0
```

4. Record the exact commit SHA.
5. Begin new ACP feature work from that known-good baseline.

If prerelease tags are desired for subsequent work, use something such as:

```text
1.1.0-dev.1
1.1.0-dev.2
1.1.0-rc.1
1.1.0
```

Do not relabel the completed package milestone as `0.9.0-dev1`.

---

# 4. Split the Existing Phase 0 Into Two Checkpoints

The current Phase 0 mixes two different jobs:

1. Freezing the working ACP package.
2. Adding substantial new ACP features required by Prism.

These should be separated.

---

## Phase 0A — Freeze the Existing AuroraACP Baseline

### Goal

Establish the already-completed Swift package conversion as an immutable checkpoint.

### Work

- Confirm the ACP working tree is clean.
- Re-run the existing package verification.
- Tag `1.0.0`.
- Record the tag and commit SHA.
- Confirm Prism still resolves the already-added package and can compile against `import AuroraACP`.
- Do not add new messages, transports, discovery behavior, or Remote semantics during this checkpoint.

### Verification

From the ACP repository root:

```bash
swift build
swift test
python3 scripts/check_registry.py
python3 scripts/freeze_vectors.py
python3 tests/interop/test_framed_cross.py --sdk swift --suite hello
python3 tests/interop/test_framed_cross.py --sdk swift --suite session
python3 tests/interop/test_framed_cross.py --sdk swift --suite remote
python3 tests/interop/test_framed_cross.py --sdk swift --suite negative
```

Preserve the current verified baseline:

```text
Swift tests: 22 / 22
Registry + vectors: 91 / 91
Python ↔ Swift interop: pass
Rust ↔ Swift session interop: pass
External import AuroraACP: pass
```

### Exit criterion

A known-good `AuroraACP 1.0.0` checkpoint exists before new protocol feature work begins.

---

## Phase 0B — ACP Prism/Remote Readiness Development

### Goal

Add the generic ACP capabilities that are genuinely required by Prism’s replacement architecture.

This is **feature development**, not package conversion.

The current plan’s candidate work remains appropriate:

- authority epoch and revision semantics for state
- `command.status_request`
- `command.status_report`
- command ledger semantics
- typed mutation preconditions
- capability versus availability
- provenance metadata
- priority/coalescing metadata
- semantic surface descriptors
- Swift session fail-closed fixes
- bounded handshake/request I/O
- stronger schema/registry admission
- established-session interoperability tests
- generic WebSocket transport
- discovery facilities
- later production Swift Remote authority

Do not change existing wire behavior merely for stylistic cleanup.

When this work reaches a stable checkpoint, create a new ACP package tag such as:

```text
1.1.0-dev.1
```

or another appropriate successor to `1.0.0`.

---

# 5. Distinguish Local Development From Immutable Release Pinning

The current plan says Prism must consume a tagged ACP revision but also proposes:

```swift
.package(path: "../AuroraCommunicationsProtocol")
```

Those are not the same guarantee.

A local path dependency means:

> Use whatever ACP source exists in this directory right now.

SwiftPM does not enforce a Git tag for a path dependency.

## During active development

A local package is desirable.

```text
AuroraCommunicationsProtocol
          ↑
          │ local package
          │
      Aurora / Prism
```

This lets ACP and Prism evolve together without publishing a package release for every small change.

For checkpoints, record:

```text
expected ACP tag
expected ACP commit SHA
```

and verify the sibling ACP checkout is actually at that revision.

## For stable/released Prism builds

Once ACP has a Git remote, use a Git-hosted package dependency pinned to an exact tested release or an explicitly approved semantic-version range.

Preferred release relationship:

```text
Prism release
    ↓
tested AuroraACP release
    ↓
immutable Git tag
```

Do not ship a release build whose ACP dependency is simply whatever happens to be in `../AuroraCommunicationsProtocol`.

---

# 6. Preserve the Prism Semantic Boundary

This is the most important invariant in the existing plan.

All remote mutations must flow through Prism’s existing semantic control architecture.

Correct:

```text
ACP network message
      ↓
AuroraACP
      ↓
PrismACPActionRouter
      ↓
ControlActionRouter
      ↓
authoritative Prism state
      ↓
lighting/output systems
```

Forbidden:

```text
ACP
 ↓
fixture state
 ↓
programmer internals
 ↓
DMX
```

Also forbidden:

```text
ACP → AuroraOutput
```

and:

```text
ACP → SwiftUI view mutation
```

ACP is an external semantic control protocol.

It is not a second lighting engine, a programmer API, or a direct DMX API.

---

# 7. Keep `PrismACP` as the Product Integration Layer

The current plan proposes a Prism-specific target/module named:

```text
PrismACP
```

Keep this.

This does not conflict with the Xcode application target still being named `Aurora`.

The intended layering is:

```text
Aurora target (Prism app)
├── existing Prism/Aurora modules
├── ControlActionRouter
├── AppModel
├── UI
└── PrismACP
      │
      └── AuroraACP package
```

`PrismACP` owns translation between ACP concepts and Prism concepts.

Generic ACP networking/session/Remote machinery must remain in `AuroraACP`.

Recommended Prism-owned roles include:

```text
PrismACPService
PrismACPConfiguration
PrismACPIdentityStore
PrismACPAuthorizationPolicy
PrismACPStateSource
PrismACPStatePublisher
PrismACPActionRouter
PrismACPAvailabilityProvider
PrismACPCommandLedger
PrismACPAuditStore
PrismACPRemoteAdapters
PrismACPDiagnostics
PrismACPController
```

Names may be adjusted to existing project conventions, but the architectural roles should remain.

---

# 8. Avoid Duplicate Package Declarations

Because `AuroraACP` has already been added manually in Xcode, Grok must inspect how the Prism project is generated before editing package dependencies.

Potential bad outcome:

```text
manual Xcode package reference
+
Package.swift dependency
+
project.yml dependency
```

all trying to own the same package relationship.

There should be **one authoritative mechanism for the application build**.

If `project.yml` or XcodeGen owns the `.xcodeproj`, the generator configuration must eventually preserve the package reference so regenerating the project does not erase the manually-added ACP dependency.

## Required procedure

Grok should:

1. Inspect the current `.xcodeproj`.
2. Inspect `project.yml`.
3. Determine whether project generation owns package dependencies.
4. Preserve the package already added by the user.
5. If generator configuration must be updated, make it reproduce the same:

```text
AuroraACP → Aurora
```

linkage.

6. Ensure:

```text
acp-framed-hello → None
```

7. Regenerate the project if appropriate.
8. Confirm the package dependency survives regeneration.
9. Build Prism again.

Do not blindly add another ACP dependency declaration.

---

# 9. Keep the Read-Only First Milestone

Do not enable live control merely because ACP connects.

The safe sequence remains:

```text
ACP lifecycle
    ↓
identity/session
    ↓
read-only state
    ↓
snapshot/delta recovery
    ↓
LAN lifecycle
    ↓
only then mutations
```

At the first LAN milestone, advertise only the appropriate read-only behavior:

```text
HELLO
NEGOTIATE
SUBSCRIBE
STATE_SNAPSHOT
STATE_DELTA
HEARTBEAT
GOODBYE
```

No live mutation capability should be advertised yet.

---

# 10. Keep Event-Driven State Publication

The current plan correctly replaces the legacy 200 ms `RemoteSnapshot` timer.

Preserve that decision.

Bad:

```text
every 200 ms
    ↓
rebuild state
    ↓
send snapshot
```

Correct:

```text
semantic state commit
    ↓
revision changes
    ↓
wire-safe projection changes
    ↓
publish delta
```

Recommended initial Prism state domains remain:

```text
prism.show
prism.performance
prism.cue
prism.output
prism.health
```

Do not serialize private Prism domain objects directly onto the wire.

Use integration-layer DTOs/projections.

---

# 11. Preserve `authority_epoch` + `revision`

Keep the proposed state-consistency model.

Example:

```text
Show A loaded
epoch = A
revision = 1

GO
epoch = A
revision = 2

Master changed
epoch = A
revision = 3

Show B loaded
epoch = B
revision = 1
```

A delta should identify:

```text
authority_epoch
base_revision
revision
changes
```

A client must resynchronize when:

```text
authority_epoch != local authority_epoch
```

or:

```text
base_revision != local revision
```

Never guess through missing state.

---

# 12. Keep the Narrow Mutation Rollout

The existing gradual rollout is good.

Recommended order:

```text
1. GO in test/non-live contexts
2. explicit cue fire
3. safe non-momentary look/busk action if a semantic action already exists
4. master intensity with coalescing
5. production GO after ledger + precondition validation
6. production Remote Profile authority
7. harmless leased momentary
8. blackout
9. other safety-relevant momentaries only after separate review
```

Do not add raw programmer mutation during this migration.

In particular, do not create ACP calls such as:

```text
setFixtureChannel(...)
setDMX(...)
setProgrammerAttribute(...)
```

as part of this work.

---

# 13. Preserve Command Ledger, Preconditions, and Provenance

These features should remain in the plan.

## Command ledger

A retried command must not perform the action twice.

Example:

```text
GO command id 123
```

must never produce:

```text
Cue 17 → Cue 18
Cue 18 → Cue 19
```

merely because an ACK was lost.

## Preconditions

A GO request should be able to assert the state the client believes exists:

```text
authority_epoch = A
current_cue_id = 17
```

If Prism has already advanced:

```text
precondition_failed
```

and no action occurs.

## Provenance

Extend the Prism semantic boundary so actions can identify where they came from without introducing ACP-specific logic into the lighting engine.

Example sources:

```text
local_ui
remote
conductor
midi
music_engine
automation
bridge
system
```

Local and remote actions should share the same semantic boundary.

---

# 14. Keep Capability and Availability Separate

This distinction is important.

Capability:

```text
Prism supports remote GO.
```

Availability:

```text
Remote GO may be used right now.
```

Possible unavailability reasons include:

```text
no_show_loaded
not_armed
output_offline
permission_denied
wrong_mode
sync_required
interlock_active
resource_unavailable
```

Clients should not infer temporary usability merely because a capability exists.

---

# 15. Preserve the Production Remote Authority Boundary

The existing Swift `ACPRemoteAuthority` simulator should not quietly become the production Prism server.

Keep the rule:

```text
AuroraACP
└── generic production Remote authority

Prism
└── product adapters only
```

Prism may inject implementations such as:

```text
PrismRemotePolicy
PrismRemoteSurfaceProvider
PrismRemoteActionRouter
PrismRemoteStateSource
PrismRemoteHoldPersistence
```

but Prism should not implement a second session/lease/subscription/transfer engine.

The production Remote authority phase should remain a hard audit checkpoint.

---

# 16. Keep Bonjour Platform-Specific Without Polluting ACP Core

Prism needs Bonjour discovery on Apple platforms.

That is appropriate, but ACP remains a cross-platform protocol.

Prefer this conceptual separation:

```text
AuroraACP
├── discovery semantics
├── service identity
└── generic discovery abstraction

Apple-specific implementation
└── Bonjour / Network.framework
```

If the Apple implementation can live cleanly in the same Swift package behind platform-scoped code, that is acceptable.

If Apple-specific assumptions begin spreading through ACP core, split the implementation into a companion such as:

```text
AuroraACPDiscovery
```

Do not over-engineer this preemptively. The important requirement is that ACP discovery semantics remain portable.

---

# 17. Keep Momentary Safety Semantics

The lease/release model in the current plan is strong and should remain.

Before fog, strobe, blinders, bump, flash, or other safety-sensitive momentaries are exposed, test the mechanism with a harmless momentary.

If release fails, Prism must not publish a false inactive state.

Correct:

```text
release_pending = true
physical_active = true
```

or:

```text
release_pending = true
physical_active = unknown
```

Incorrect:

```text
physical_active = false
```

unless Prism has actually confirmed the physical state is inactive.

Required test cases include:

- normal END
- dirty disconnect
- lease expiry
- Prism shutdown
- authorization removal
- surface replacement
- restart
- persisted hold recovery
- simulated release failure

No safety-relevant momentary should ship before all release paths are green.

---

# 18. Keep Blackout Late and Prefer Explicit State

The current blackout phase remains appropriate.

Prefer remote semantics such as:

```text
blackoutOn
blackoutOff
```

instead of:

```text
toggleBlackout
```

Explicit commands are easier to make idempotent and retry-safe.

Required behavior:

- duplicate blackout does not oscillate state
- reconnect does not clear blackout
- discovery failure does not affect local blackout
- ACP failure does not block local blackout
- authoritative state reports blackout truth
- clearing blackout is explicitly authorized and audited

---

# 19. Legacy Remote Must Still Be Fully Deleted

The end state remains unchanged.

There is no compatibility requirement.

After cutover, remove:

```text
AuroraRemote
RemoteHost
RemoteWebServer
RemoteSessionManager
RemoteProtocolClient
RemoteClientMessage
RemoteServerMessage
RemoteCodec
RemoteSnapshot
RemoteShowAction
remotePIN
8742
8743
/api/hello
/api/command
/api/snapshot
bundled browser remote
legacy PIN/session credentials
legacy snapshot polling
```

Do not leave a disabled compatibility listener.

Do not migrate old PINs into ACP enrollment.

Do not retain ports 8742/8743 as hidden settings.

Final rule:

```text
Prism remote networking = ACP only
```

---

# 20. Revised High-Level Phase Sequence

Use the detailed Grok plan as the implementation basis, but update its top-level sequence to:

```text
Phase 0A
Freeze canonical AuroraACP package
→ tag 1.0.0

Phase 0B
Implement missing generic ACP Prism/Remote facilities
→ test
→ new ACP prerelease/release tag

Phase 1A
PrismACP foundation
→ preserve existing Xcode AuroraACP dependency
→ identity/lifecycle/loopback
→ no control

Phase 1B
Read-only LAN ACP
→ WebSocket
→ Bonjour
→ snapshot/delta
→ ACP disabled = network silent

Phase 2
Event-driven authoritative Prism state

Phase 3
Narrow semantic mutations
→ ledger
→ preconditions
→ provenance
→ availability
→ coalescing

Phase 4
Production Swift Remote Profile authority
→ generic authority stays in ACP
→ Prism adapters only

Phase 5
Leased harmless momentary
→ failure-safe release model

Phase 6
Blackout and safety review

Phase 7
Delete legacy AuroraRemote completely

Final gates
→ source
→ runtime
→ architecture
→ interoperability
→ safety
```

---

# 21. Updated PR Sequence

## PR 0 — Freeze AuroraACP 1.0.0

**Repository:** `AuroraCommunicationsProtocol`

- No new feature work.
- Verify the completed package conversion.
- Commit.
- Tag `1.0.0`.
- Record SHA.
- Re-run the existing package/interoperability gates.

## PR 1 — ACP Prism/Remote Readiness

**Repository:** `AuroraCommunicationsProtocol`

Implement the missing generic protocol facilities required by the Prism integration.

Do not combine this with another package-layout rewrite.

Tag a new ACP prerelease/release when green.

## PR 2 — PrismACP Foundation

**Repository:** `Aurora`

- Inspect the already-added `AuroraACP` Xcode dependency.
- Preserve `AuroraACP → Aurora`.
- Preserve `acp-framed-hello → None`.
- Ensure project-generation configuration preserves the dependency.
- Add `PrismACP`.
- Add `PrismACPController`.
- Stop starting the legacy remote.
- Advertise no mutation capability.

## PR 3 — Read-Only ACP LAN

- WebSocket
- Bonjour
- subscriptions
- snapshot/delta
- lifecycle
- network-silent disable

## PR 4 — Event-Driven Prism State

- authority epoch/revision
- state projections
- semantic commit publication
- remove live polling

## PR 5 — Narrow Semantic Control

- `ControlActionRouter` provenance
- command ledger
- preconditions
- availability
- GO/cue/master rollout
- no blackout
- no programmer

## PR 6 — Production Remote Authority

Primary implementation remains in `AuroraACP`.

Prism provides adapters only.

## PR 7 — Leased Momentaries

Harmless test momentary first.

Full lease/release failure testing.

## PR 8 — Blackout Safety

Explicit, idempotent blackout semantics.

## PR 9 — Delete AuroraRemote

Remove the old protocol, UI, credentials, listeners, tests, ports, routes, and compatibility remnants.

---

# 22. Add an Xcode Project-Regeneration Gate

Because the ACP dependency has already been added manually in Xcode, add this verification gate:

1. Build Prism with `AuroraACP` linked.
2. If `project.yml` is authoritative, regenerate the Xcode project.
3. Reopen the regenerated project.
4. Confirm `AuroraACP` is still present.
5. Confirm `AuroraACP` is still linked to target `Aurora`.
6. Confirm `acp-framed-hello` is not linked.
7. Confirm Prism still compiles with:

```swift
import AuroraACP
```

Project regeneration must not silently remove the package dependency.

---

# 23. Final Architectural Contract

The migration is successful only if the final product can be described this simply:

```text
Remote / Conductor / other ACP client
                ↓
               ACP
                ↓
           AuroraACP
                ↓
            PrismACP
                ↓
      ControlActionRouter
                ↓
      authoritative Prism state
                ↓
       Prism lighting systems
```

There is one remote network protocol.

There is one semantic mutation boundary.

There is one authoritative state.

There is no copied ACP source.

There is no direct ACP-to-DMX path.

There is no private Prism protocol hidden inside ACP.

There is no legacy remote stack after cutover.

---

# 24. Instruction to Grok

Use the existing **Prism ACP Integration — Sequential Implementation Plan** as the detailed implementation source, with the corrections in this document taking precedence where they conflict.

Most importantly:

1. Do not repeat the completed `AuroraACP` package conversion.
2. Preserve the `AuroraACP` dependency already added to the Prism Xcode target `Aurora`.
3. Keep `acp-framed-hello` unlinked from the Prism application.
4. Freeze the completed package baseline as `AuroraACP 1.0.0` before starting new ACP feature work.
5. Treat WebSocket, discovery, command status, preconditions, provenance, and production Remote authority as new ACP feature development after that baseline.
6. Distinguish local-development package consumption from immutable release pinning.
7. Ensure `project.yml` / Xcode project regeneration preserves the package dependency.
8. Preserve the `AuroraACP → PrismACP → ControlActionRouter → authoritative state` boundary.
9. Do not redesign working ACP wire behavior merely because ACP is being integrated into Prism.
10. Complete the migration through full legacy deletion.
11. Stop only when the final source, runtime, architecture, interoperability, and safety gates are green.
