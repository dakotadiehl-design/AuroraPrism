# Checkpoint — Prism ACP Phase 6 (leased momentary controls)

**Date:** 2026-08-20  
**Status:** **COMPLETE** — implementation, automated review, and the complete live Workbench gate are satisfied; Phase 7 is unblocked while safety-relevant controls remain closed pending their own gates

## Implemented

- Added the harmless `lease_test` momentary to Prism's ACP Remote surface. It has no lighting, programmer, output, fog, strobe, blinder, bump, or DMX effect.
- Added a dedicated `PrismACPMomentaryAuthority` with durable hold records and a single release transaction shared by normal end, cancellation, disconnect, lease expiry, control removal, authorization removal, shutdown, and restart recovery.
- `momentary_begin` clamps requested leases to 250–2,000 ms, persists the hold before acknowledging it, and returns `activation_id`, a server-issued `lease_id`, `granted_lease_ms`, and `renew_before_ms`.
- Duplicate begin with the same activation identity returns the original lease without creating or applying another hold. Conflicting reuse is rejected.
- `remote.momentary.refresh` renews only an exact control, activation, lease, and authenticated-principal match.
- `momentary_end` and `momentary_cancel` require the exact server-issued lease and authenticated principal.
- Runtime expiry uses `ContinuousClock`; persisted wall-clock expiry is descriptive and is never used to extend a recovered hold.
- Persisted holds enter release recovery before Prism opens its ACP listener.
- Timer and lifecycle changes publish unsolicited `remote.control.state` events. Request-time snapshots remain `remote.control.snapshot` responses.
- A failed physical release remains represented as `release_pending: true` with `physical_active: true` or unknown. Prism never reports confirmed inactive without physical confirmation.
- ACP disabled remains network-silent and shutdown releases holds before listener/session teardown.

## Protocol corrections

- Added `requested_lease_ms` to `remote.control.invoke`.
- Added `idempotency_key` to `remote.momentary.refresh`.
- Synchronized canonical, Python, and Swift schema packs.
- Corrected momentary state publication to use the registry-authorized event type `remote.control.state`; `remote.control.snapshot` is response-only.

## Review findings and remediation

- All termination paths converge on the durable release transaction.
- Release intent is persisted before the physical release handler is called.
- A restart treats every persisted hold conservatively and releases it before accepting sessions.
- Disconnect cleanup occurs before the connection's Remote context is discarded.
- Removing an operator from policy revokes that principal's holds.
- Expiry runs independently of inbound ACP traffic.
- State publication is latest-value coalesced and rejects superseded hold snapshots.
- The Phase 6 surface exposes only the harmless test control. Safety-sensitive controls remain unavailable.

## Automated verification

- `PrismACPMomentaryAuthorityTests`: **4 passed**, **0 failures**.
- `PrismACPServiceTests`: **20 passed**, **0 failures**, including real WebSocket begin, duplicate begin, renew, wrong-lease rejection, and cancel.
- Full Prism `swift test`: **1,014 passed**, **1 existing skip**, **0 failures**.
- Full ACP Swift `swift test`: **38 passed**, **0 failures**.
- Full ACP Python suite: **136 passed**, **0 failures**.
- ACP registry/schema-pack validation: **93 messages**, clean.

Covered failure and lifecycle cases include normal end, gesture cancellation, lost/duplicate begin acknowledgement recovery, renewal, wrong lease, dirty disconnect, expiry without inbound traffic, control removal, authorization removal, shutdown, authority restart, persisted hold recovery, and physical release failure.

## Live Workbench gate

### Validated steps 1–8

The live Workbench run confirmed:

- `lease_test` is the only momentary control and has no dangerous or physical output effect.
- An 800 ms begin returned a stable activation ID, server lease ID, 800 ms grant, and 400 ms renew-before interval.
- Replaying the identical begin recovered the same lease without another activation.
- Exact-lease refresh was applied and extended the hold beyond its original deadline.
- Wrong-lease end was rejected while the hold remained active.
- Exact-lease cancel was applied and produced unsolicited confirmed-inactive state.
- Dirty disconnect released a second hold; the replacement session snapshot was inactive.
- A third hold expired without renewal or inbound traffic and emitted unsolicited confirmed-inactive `remote.control.state`.

Evidence:

- `/Users/dakota/code/AuroraCommunicationsProtocol/tools/acp-workbench/artifacts/prism-phase6-momentary-live-2-2026-08-20.jsonl`

### Validated step 9

Restart recovery passed with a staged persisted synthetic hold:

- Before the listener accepted an ACP session, Prism had loaded and released the hold and the production store contained `[]`.
- The listener became available only after recovery completed.
- The first Workbench session reached `ready`.
- Its first authoritative snapshot reported `lease_test` as enabled, available, confirmed, and inactive (`value: false`).
- Prism emitted no unsolicited active recovery event.
- The production hold store remained clean.

Evidence:

- `/Users/dakota/code/AuroraCommunicationsProtocol/tools/acp-workbench/artifacts/prism-phase6-step9-restart-recovery-2026-08-20.jsonl`

## Phase 6 closeout

The complete leased-momentary exit gate is satisfied and Phase 7 is unblocked. This does not authorize or enable fog, strobe, blinders, bumps, flash, blackout, or any other safety-sensitive control. Each remains closed until its own explicit authorization, availability, state-truth, retry, release, and safety-review gates pass.
