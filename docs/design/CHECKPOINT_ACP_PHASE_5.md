# Checkpoint — Prism ACP Phase 5 (production Remote authority)

**Date:** 2026-08-20  
**Status:** **COMPLETE** — implementation, automated review, and live Workbench validation satisfied

## Implemented

- Prism authenticates Remote identity against the established `ACPSession` node and instance; client role claims remain non-authoritative.
- Remote permissions are derived from Prism enrollment policy and readiness is invalidated when policy changes.
- Production surface delivery is capability-negotiated. Clients that negotiate and advertise `resource.transfer` receive a metadata-only layout report, a connection-bound chunked resource offer, bounded chunks, completion, verification, and explicit activation.
- Inline surface delivery remains only as a compatibility path for clients that did not negotiate production resource transfer. Matching cached SHA-256 values avoid retransmission.
- A transferred surface cannot become ready until its bytes are verified and activated. Activation fails if Prism's current surface hash changed during transfer.
- State requests retain the client's resource filter. Snapshots and subsequent deltas contain only subscribed resources.
- Per-session state delivery is ordered and bounded to 128 pending deltas. Overload fails closed by revoking readiness and requiring snapshot resynchronization rather than dropping or reordering revisions.
- Command disposition recovery remains keyed to the authenticated principal and survives replacement sessions.
- `ACPRemoteProductionAuthority` now retains bounded command fingerprints and rejects replacement-session reuse of a command identity for a different operation.
- The legacy `ACPRemoteAuthority` remains explicitly marked as a non-production simulator and is not used by Prism's production entry point.

## Review findings and remediation

- Resource transfer is enabled only when present in both session negotiation and Remote-advertised capabilities.
- Transfer IDs and lifecycle messages are bound to the authenticated connection and source node.
- Chunk size requests are clamped before integer conversion and output chunks are bounded to 32 KiB.
- Surface payloads are limited to 1 MiB for production transfer.
- SHA-256 covers the deterministic sorted JSON bytes that are actually transferred.
- Verification and activation are separate gates; an offer or completed transfer alone never enables mutation.
- State backpressure cannot consume unbounded memory and never coalesces revision deltas into an invalid revision chain.

## Verification

- `swift test --filter PrismACPServiceTests`: **19 passed**, **0 failures**.
- Full Prism `swift test`: **1,009 passed**, **1 existing skip**, **0 failures**.
- `swift test --filter ACPRemoteProductionTests`: **5 passed**, **0 failures**.
- Full ACP `swift test`: **38 passed**, **0 failures**.
- Python Remote host and Workbench engine integration: **9 tests** and **3 subtests passed**.
- `git diff --check`: clean.
- Live Workbench negotiated `resource.transfer` 1.2 and received a metadata-only layout report followed by `offer → accept → chunk → complete`.
- Workbench reconstructed **1,324 bytes** and verified SHA-256 `8cd1d6eaf1a993ceb8e5a8c4750acdb0613fe5c40fddcc6ee39e5cabfbc3f139`.
- Explicit resource activation returned `applied`; readiness became `ready` only after activation and authoritative state acknowledgement.
- Replacement-session cue-fire recovery returned the original `applied` disposition with zero additional deltas and no re-execution.
- Post-transfer control continuity passed: cue fire revision 2, GO revision 3, Grand Master set revision 4, and Grand Master restoration revision 5 with final value `1.0`.
- Evidence:
  - `/Users/dakota/code/AuroraCommunicationsProtocol/tools/acp-workbench/artifacts/prism-phase5-resource-transfer-live-2026-08-20.jsonl`
  - `/Users/dakota/code/AuroraCommunicationsProtocol/tools/acp-workbench/artifacts/prism-phase5-command-recovery-live-2026-08-20.jsonl`
  - `/Users/dakota/code/AuroraCommunicationsProtocol/tools/acp-workbench/artifacts/prism-phase5-command-continuity-live-2026-08-20.jsonl`

## Phase 5 closeout

The production Remote authority exit gate is satisfied. Phase 6 is unblocked and must begin with a harmless leased test momentary. Fog, strobes, blinders, bumps, flash controls, and other safety-relevant momentaries remain closed until every begin, renew, end, disconnect, expiry, shutdown, policy-revocation, and failed-release path passes review.
