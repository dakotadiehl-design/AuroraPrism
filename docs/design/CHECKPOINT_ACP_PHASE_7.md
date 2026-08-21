# Checkpoint — Prism ACP Phase 7 (explicit blackout safety control)

**Date:** 2026-08-20  
**Status:** **COMPLETE** — implementation, automated review, regressions, complete live Workbench validation, and independent safety review are satisfied

## Implemented

- Added two explicit Remote controls: `blackout_on` → `blackoutOn` and `blackout_off` → `blackoutOff`.
- ACP has no remote toggle-blackout binding. A repeated command sets the requested state and cannot oscillate it.
- Both commands require the authenticated Remote session, production readiness, `live_ephemeral` freshness, and an `authority_epoch` precondition.
- Both commands enter the existing command ledger before execution. Identical replay returns the original disposition without re-execution; reuse of an identity for the opposite operation returns `conflict`.
- Both commands execute through Prism's shared semantic `ControlActionRouter` using `.blackout` and `.blackoutOff`. ACP has no direct engine, output, programmer, or DMX mutation path.
- A same-state set returns `applied` with the existing revision and does not manufacture a state transition.
- Actual changes advance Prism's authoritative revision and are published through the existing `prism.performance.blackout` snapshot/delta path.
- ACP disconnect, failure, disablement, discovery changes, and service restart do not clear authoritative blackout.
- Prism's existing local blackout path remains independent of ACP availability.

## Separate clear authorization

- Added distinct ACP permissions `output.blackout.engage` and `output.blackout.clear`.
- An enrolled operator may engage blackout, but does not receive clear authority by implication.
- Clear authority is fail-closed by default and stored as a separate node-ID enrollment list.
- Prism Settings now exposes **Node IDs separately authorized to clear blackout**.
- A clear ID is effective only when the same ID is also enrolled as an operator.
- The Remote surface disables `blackout_off` and omits the clear permission when that separate grant is absent.
- A direct invocation without the separate grant is rejected as `blackout_clear_not_authorized`.

## State and audit behavior

- The Remote control snapshot exposes authoritative blackout truth on both explicit controls.
- `prism.performance.blackout` remains the canonical domain state.
- Applied engage records `blackout_engaged`; applied clear records `blackout_cleared`.
- Rejected/conflicting safety operations record `safety_state_unchanged`.
- Audit records retain authenticated principal, operation, disposition, and resulting epoch/revision.

## Protocol changes

- Extended ACP's Remote permission vocabulary with:
  - `output.blackout.engage`
  - `output.blackout.clear`
- Synchronized canonical, Python-packaged, and Swift schema packs and constants.
- Registry validation remains clean at 93 messages.

## Automated verification

- `PrismACPServiceTests`: **22 passed**, **0 failures**.
- Full Prism `swift test`: **1,016 passed**, **1 existing skip**, **0 failures**.
- Full ACP Swift `swift test`: **38 passed**, **0 failures**.
- Full ACP Python suite: **136 passed**, **0 failures**.
- ACP registry/schema-pack validation: **93 messages**, clean.
- `git diff --check`: clean for the Phase 7 implementation and protocol files.

Automated coverage includes explicit bindings, absence of a toggle binding, separate clear authorization, fail-closed default policy, replay without re-execution, opposite-operation identity conflict, safety audit outcomes, disconnect behavior, ACP stop/restart behavior, and authoritative blackout preservation.

## Live Workbench gate — complete

The complete live gate passed using controlled/null output. The run validated:

- explicit set-only engage and clear semantics with no toggle;
- dangerous/explicit-confirmation surface metadata;
- separate engage and clear permissions;
- unauthorized clear rejection without a state delta;
- authorized engage and clear with one authoritative revision each;
- identical replay and same-state commands without re-execution, oscillation, or false deltas;
- reconnect and ACP-disable preservation of active blackout;
- local blackout control independence from ACP availability;
- replacement-session command disposition recovery;
- clear-grant revocation while retaining operator and engage authority.

The final revocation run confirmed `output.blackout.engage` remained granted, `output.blackout.clear` was absent, `blackout_off` was disabled/unavailable, direct clear returned `blackout_clear_not_authorized`, no authoritative delta occurred, and blackout remained active.

Evidence:

- `/Users/dakota/code/AuroraCommunicationsProtocol/tools/acp-workbench/artifacts/prism-phase7-revoked-clear-live-2026-08-20.jsonl`

Validated procedure:

1. Verify the surface advertises `blackout_on` and `blackout_off`, contains no toggle binding, and marks both controls dangerous/explicit-confirmation.
2. With the Remote enrolled only as an operator, verify permissions include `output.blackout.engage` but not `output.blackout.clear`; `blackout_off` must be disabled.
3. Attempt an unauthorized `blackoutOff`; verify rejection and unchanged authoritative state.
4. Add that node ID to Prism's separate blackout-clear enrollment, apply/restart ACP, and verify both permissions are now granted.
5. From authoritative `blackout: false`, invoke `blackout_on` with a fresh delivery window and matching epoch. Verify `applied`, one revision advance, authoritative `blackout: true`, and blacked-out preview/null-or-test output.
6. Replay the identical command identity. Verify the original disposition is recovered, with no second execution or state delta.
7. Send a new `blackoutOn` while already blacked out. Verify `applied`, no oscillation, and no false state transition.
8. Disconnect and reconnect. Verify the first snapshot still reports `blackout: true`; reconnect must never clear it.
9. Stop/disable ACP while blacked out. Verify blackout remains active and local blackout control remains functional despite ACP being unavailable.
10. Re-enable ACP and confirm the first authoritative snapshot remains blacked out.
11. Invoke separately authorized `blackout_off`. Verify `applied`, one revision advance, and authoritative `blackout: false`.
12. Replay clear and send a new same-state clear. Verify neither oscillates state nor creates a false transition.
13. Revoke the clear grant, re-engage blackout, and verify a subsequent remote clear is rejected while blackout remains active.
14. Verify command disposition recovery after replacement-session reconnect for both engage and clear.

## Independent safety review gate — satisfied

On 2026-08-20, the user completed the independent review and explicitly approved the required blackout behavior, authorization separation, persistence, and replay handling. No P0/P1 findings were reported in:

- the explicit set-only semantics;
- separate clear authorization and settings persistence;
- command-ledger replay/conflict behavior;
- authoritative state and revision publication;
- local-control independence from ACP;
- reconnect, disablement, discovery failure, and restart behavior;
- audit provenance and safety outcomes.

The live Workbench gate and independent safety review are satisfied. Phase 7 is closed.

This approval applies only to the explicit blackout controls reviewed in this phase. Fog, strobe, blinders, bumps, flash controls, and all other safety-sensitive momentaries remain closed pending separate control-specific authorization, availability, lease, release, audit, implementation, and live-validation gates.
