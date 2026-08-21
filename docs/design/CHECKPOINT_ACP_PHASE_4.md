# Checkpoint — Prism ACP Phase 4 (narrow semantic mutations)

**Date:** 2026-08-20  
**Status:** **COMPLETE** — GO, explicit cue fire, and Grand Master are review-satisfied and live-validated  
**Prism base commit:** `ce3fe8562b5c22a45a20bedb1f48e83dfdb733db` plus working-tree changes  
**ACP base commit:** `4d4bf57ae236891c41588073e0c68eb6c837ca6b` plus working-tree changes

## Implemented

- Production GO, explicit `performance.fire_cue`, and `output.master` use the shared `ControlActionRouter` boundary.
- Remote invocation requires completed readiness, server-owned operator enrollment, `cue.execute`, and `activate` interaction.
- GO and explicit cue fire require `authority_epoch` and `current_cue_id`; master requires `authority_epoch` and has no irrelevant cue dependency.
- Both actions are once-only commands with atomic reservation, retained terminal disposition, reconnect status lookup, and structured remote provenance.
- Live-ephemeral delivery metadata is enforced. Missing, malformed, future, or expired windows fail closed; expired commands are retained in the ledger and never execute.
- Explicit cue fire accepts a UUID and is restricted to the active cue list. Unknown/off-list targets do not advance authority revision.
- The Remote surface exposes GO and a narrow **Fire Next Cue** control bound to the already-published `prism.cue.next_cue_id`. Prism does not publish the complete cue catalog.
- The Remote surface exposes a bounded 0–1 **Grand Master** fader under the distinct `output.grand_master` permission. Its definition declares continuous, `latest_value_wins` delivery; individual invocations remain expiring `live_ephemeral` messages as required by the ACP invocation schema.
- Prism collapses dense master traffic in a bounded 8 ms admission window. Superseded commands receive a retained terminal `completed` disposition with `superseded_by_newer_value`; GO and cue fire bypass this window.
- Master execution uses `ShowAction.masterIntensity` through `ControlActionRouter`, refreshes presentation from the engine, advances one authoritative revision, and publishes the engine's authoritative master value.
- Authoritative cue state is read directly from `PlaybackController` for admission and publication, avoiding presentation/frame-snapshot races.
- Audit records include origin, operation, target, disposition, resulting epoch/revision, and safety classification.
- BACK, STOP, blackout, momentaries, raw programmer mutation, and raw DMX remain closed.

## Review findings and remediation

- Restricted cue fire from `set`/`adjust` to `activate` only.
- Added truthful host disposition: cue fire is `applied` only when the target becomes authoritative.
- Added expiry enforcement before semantic execution and retained `expired` status for replay/recovery.
- Rejected broad cue-catalog publication; Fire Next Cue uses existing state only.
- Confirmed no ACP shortcut reaches cue playback internals.
- Confirmed Prism has no existing semantic non-momentary look/busk action suitable for safe ACP exposure; no substitute programmer or engine shortcut was introduced.
- Corrected a review-time schema issue: `latest_value_wins` is surface delivery policy, not an invocation delivery enum.
- Extended atomic reservation and retained terminal disposition to master commands, including coalesced and cancelled admissions.

## Verification

- `swift test --filter PrismACPServiceTests`: **18 passed**.
- Full Prism `swift test`: **1,008 passed**, **1 existing skip**, **0 failures**.
- `git diff --check` for checkpoint files: clean.
- Live Grand Master validation set `1.0 → 0.73` at authoritative revision `1 → 2`, then restored `0.73 → 1.0` at revision `2 → 3`; both acknowledgements were `applied` and both published values matched Prism authority.
- ACP Workbench regression after live validation: **20 tests** and **3 scenario subtests** passed, with lint and static analysis clean.
- Evidence: `/Users/dakota/code/AuroraCommunicationsProtocol/tools/acp-workbench/artifacts/prism-grand-master-live-2026-08-20.jsonl`.

## Phase 4 closeout

The narrow semantic mutation gate is satisfied. Prism now has live-validated GO, explicit cue fire, and Grand Master control through one semantic authority path. Blackout, BACK, STOP, momentaries, raw programmer mutation, and raw DMX remain explicitly closed. The next directive phase is the production Swift Remote Profile authority audit and completion work; leased momentaries do not begin until that authority passes review.
