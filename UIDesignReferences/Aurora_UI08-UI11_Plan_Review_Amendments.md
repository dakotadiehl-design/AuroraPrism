# Aurora UI-08 through UI-11 Implementation Plan — Review Amendments

## Status

**Plan verdict:** **APPROVED WITH AMENDMENTS**

The existing `Aurora UI-08 through UI-11 Implementation Plan` is strong and should remain the controlling plan.

These amendments tighten Local DMX persistence safety, patch transaction semantics, diagnostic ownership, remote security and command delivery semantics, and UI-11 layout scope.

They are **not** a redesign of UI-08→11.

The required sequence remains:

```text
UI-08
  → checkpoint
UI-09
  → checkpoint
UI-10
  → checkpoint
UI-11
  → checkpoint
integration review package
  → STOP
```

Do not begin UI-12.

---

# Amendment 1 — Local DMX Persistence Must Prefer Hardware Identity Over Device Path

## Applies to

- UI-08 Output Settings
- Local DMX / ENTTEC persistence
- `AppSettingsStore`
- `OutputController`
- serial discovery

The plan currently allows:

```text
stable id / path fallback
```

A `/dev/cu.*` path is a connection endpoint, not a trustworthy long-term hardware identity.

Persist, when available:

```text
USB serial number
vendor/product identity
IOKit hardware identity
stable device identifier
```

The current `/dev/cu.*` path may be retained as the current endpoint, but must not by itself prove that the same physical device has returned.

On relaunch:

```text
saved hardware identity
        ↓
enumerate current devices
        ↓
matching device found
        → restore selection

matching device not found
        → show unavailable
        → actual Local DMX remains disabled
        → never silently select another serial device
```

If only a path is available, treat it as lower-confidence fallback behavior and document that limitation.

If the persisted preference says Local DMX should be enabled but the saved device is absent:

```text
requestedEnabled = true
actualEnabled = false
status = configured device unavailable
```

### Acceptance

```text
[ ] Stable hardware identity is preferred
[ ] Missing hardware never silently selects another serial device
[ ] Missing hardware never falsely reports Local DMX enabled
[ ] Matching reconnect can restore the intended selection
[ ] Path fallback is conservative and documented
```

---

# Amendment 2 — Bulk Patch Must Be Preflighted and Atomic Against the Final Proposed State

## Applies to

- UI-09 Patch
- bulk repatch
- clone/bulk operations
- command grouping

The plan proposes:

```text
bulk ops atomic (beginGroup/endGroup)
```

Command grouping alone is not enough if intermediate patch states are observable or temporarily invalid.

Example:

```text
Fixture A: address 1
Fixture B: address 10

operator swaps A and B
```

Sequential changes may transiently overlap even if the final patch is valid.

Before mutating the document:

```text
collect requested changes
        ↓
build proposed final patch
        ↓
validate final state
        ↓
if valid:
    apply as one logical transaction
else:
    mutate nothing
```

Prefer a purpose-built atomic command for real bulk patch changes.

If grouping is used internally, preflight must happen before the first mutation.

### Required semantics

```text
one user gesture
→ one Undo
→ one Redo
→ all-or-nothing failure
```

### Tests

```text
swap addresses atomically
valid final state with transient overlap succeeds
final overlap rejected with no mutation
mid-operation failure rolls back completely
one Undo restores complete original patch
```

---

# Amendment 3 — Diagnostics Should Consume a Dedicated Semantic Projection

## Applies to

- UI-09 Diagnostics
- engine/output/MIDI/remote status
- throttling and observation

Prefer:

```text
Engine / Output / MIDI / Remote
            ↓
DiagnosticsController / DiagnosticsSnapshot
            ↓
semantic throttled publication
            ↓
Diagnostics UI
```

Do not build the Diagnostics screen by repeatedly polling multiple controllers from SwiftUI `body`.

The view must not become the coordinator of diagnostic state.

A conceptual snapshot might include:

```text
engine
output drivers
universes
MIDI
remote
recent operator-relevant errors
```

Use on-change publication for important state transitions and low-rate throttling for counters/rates.

No raw packet/frame publication.

### Acceptance

```text
[ ] Diagnostics consumes focused semantic projections
[ ] SwiftUI body does not poll/mutate high-rate controllers
[ ] driver health transitions appear promptly
[ ] counters/rates are throttled
[ ] removed drivers/sessions disappear cleanly
```

---

# Amendment 4 — Output Routing Health Must Separate Route, Availability, and Runtime Health

## Applies to

- UI-09 Output Routing board
- Diagnostics
- `.mirror`
- Local DMX limitations

For each universe, distinguish:

```text
configured route
driver enabled state
destination/device availability
effective runtime health
```

Example:

```text
U1 → Local DMX
Device: ENTTEC USB Pro
Driver: Enabled
Health: Ready
```

versus:

```text
U1 → Local DMX
Device: saved ENTTEC unavailable
Driver: Disabled
Health: Not Routed
```

For `.mirror`, do not collapse all destinations into one unexplained status.

Example:

```text
Art-Net: Ready
sACN: Ready
Local DMX: Failed
Overall: Degraded
```

Until explicit logical-universe→physical-local-port mapping exists, keep the current limitation visible rather than implying arbitrary `.local` universes work.

---

# Amendment 5 — Lock Remote Security Defaults Before UI-10

## Applies to

- UI-08 Remote Settings
- UI-10 server
- PIN/auth
- bind behavior

The current phrase:

```text
prefer loopback or documented LAN bind — safe default
```

is too ambiguous.

At minimum:

```text
Remote server disabled by default
```

When enabling remote access, make network exposure explicit.

Recommended UX:

```text
Remote Access: Off

when enabled:
  Access:
    This Mac only
    Local Network
```

If LAN exposure is used, mutating actions must require an authenticated/authorized session.

Viewer/read-only sessions must not mutate show state.

Do not:

```text
put PIN in URLs
log PIN
return PIN in diagnostics/snapshots
expose PIN to the client after authentication
```

Review and document Host/Origin handling and cross-origin request behavior.

Do not use unauthenticated state-changing GET endpoints.

Do not claim TLS if TLS is not implemented.

---

# Amendment 6 — Remote Transport Commands Need At-Most-Once Semantics

## Applies to

- UI-10 Remote GO/BACK/STOP/song navigation
- reconnect
- acknowledgement
- multiple clients

This is a live-show safety requirement.

Failure scenario:

```text
iPad sends GO
server executes GO
Wi-Fi drops before acknowledgement
browser reconnects/retries
GO executes a second time
```

Prevent that.

Every mutating command should have a unique client request ID.

Conceptually:

```json
{
  "requestId": "uuid",
  "action": "go"
}
```

Maintain a bounded recent deduplication window per authenticated client/session.

If the same request is received again:

```text
return prior acknowledgement
do not execute again
```

On reconnect:

```text
state may resync
mutating commands must not be blindly replayed
```

If command outcome is ambiguous, resynchronize from server truth rather than automatically firing again.

Acknowledgements should include at least:

```text
requestId
accepted/rejected
relevant resulting server/playback revision or identity
```

### Tests

```text
duplicate GO request ID executes once
same action with new request ID executes again
lost acknowledgement + retry same ID executes once
reconnect does not replay queued GO
two clients can each deliberately issue distinct commands
```

---

# Amendment 7 — Version the Remote Snapshot and Command Contract

## Applies to

- UI-10
- `RemoteMessages`
- `RemoteSnapshot`
- embedded web client

UI-10 turns the remote boundary into a real product API.

Formalize a small protocol/API version.

Example:

```text
apiVersion: 1
snapshotRevision: N
```

Unsupported versions should fail truthfully rather than mysteriously.

The remote CURRENT/NEXT data should come from a pure semantic DTO derived from the same authority as `PerformanceCueSummary`.

Avoid creating an undesirable dependency where `AuroraRemote` imports Mac UI presentation types.

Prefer:

```text
semantic application/engine DTO
        ↓
Mac presentation
Remote presentation
```

---

# Amendment 8 — Remove “If Half-There and Free” Remote Programmer Scope

The current plan says the full Programmer is out of scope unless it is already half-built and easy.

Remove that exception.

For UI-10:

```text
Remote Programmer = OUT OF SCOPE
```

unless explicitly approved later.

Reason:

- capability filtering complexity
- high-frequency network mutations
- larger auth/safety surface
- substantial touch UX work
- not needed for a Perform remote

Keep UI-10 focused on a reliable live-performance remote.

---

# Amendment 9 — Freeze UI-11 Perform Layout Scope

The plan mentions named layouts including Perform while also saying Perform should preferably remain its dedicated shell.

Resolve that now.

For UI-11:

```text
Build mode = customizable/named layouts
Perform mode = dedicated fixed safety-oriented shell
```

Recommended named Build layouts:

```text
Programming
Patch
Song
Diagnostics
```

Do not make Perform dockable/customizable in this phase.

This preserves:

```text
CURRENT
NEXT
GO
BACK/STOP
health
```

without allowing a saved layout to hide critical live controls.

A future phase can deliberately introduce constrained Perform layouts if desired.

---

# Amendment 10 — Debounce Layout Persistence During Split Dragging

## Applies to

- UI-11 split fractions
- `WorkspaceLayoutStore`
- JSON/UserDefaults writes

Do not persist on every pixel of a divider drag.

Prefer:

```text
live drag
→ update in-memory layout immediately
→ debounce/coalesce persistence
```

Force-save at suitable boundaries such as:

```text
drag end
window/app lifecycle boundary
layout preset change
```

### Acceptance

```text
[ ] split dragging remains smooth
[ ] storage is not written hundreds of times per second
[ ] final geometry reliably persists
[ ] corrupt layout recovery remains safe
```

---

# Amendment 11 — Layout Restore Must Be Screen-Aware and Use Safe Geometry

Persist normalized layout semantics where possible.

For splits, prefer validated fractions over fragile absolute pixel values.

Restore flow:

```text
load layout
→ validate schema
→ clamp to current window/screen
→ ensure usable panel geometry
→ fallback to defaults if irrecoverable
```

If a previous monitor is absent, Aurora must remain reachable on an available screen.

This requirement does not require implementing full multi-display support.

---

# Amendment 12 — MIDI Settings Rehosting Must Not Change MIDI Ownership

The plan says:

```text
move mappings UI from permanent workspace into Settings
```

That is a presentation move only.

Mappings remain:

```text
ShowProject.midiMappings
```

Therefore they:

```text
are project scoped
dirty the show
save with the show
use document commands/undo
```

The Settings UI should mark this section clearly as:

```text
PROJECT
```

If there is no active document, mapping controls need truthful disabled/empty behavior.

---

# Amendment 13 — Make UI-09 Test/Identify an Explicit Decision, Not “If Cheap”

Current language makes Test/Identify optional if partially present.

For autonomous implementation, decide during inspection:

### If a safe Identify abstraction already exists

Implement a narrowly scoped Identify function and test it.

### If not

Explicitly defer it.

Do not invent a second test-output engine during UI-09 merely because the feature looks convenient.

Document the decision in `UI_09_Handoff.md`.

---

# Amendment 14 — Patch Sorting Must Be Presentation-Only Unless Domain Order Is Explicitly Editable

UI-09 search/sort must not silently reorder `ShowProject.fixtures`.

Unless the domain already defines fixture collection order as a user-editable property:

```text
search/sort
→ presentation projection only
```

Patch edits mutate fixture fields, not collection order.

If explicit fixture ordering is later desired, give it a dedicated domain command and UX.

---

# Updated Acceptance Additions

## UI-08

```text
[ ] Local DMX persistence prefers stable hardware identity
[ ] Missing persisted device remains unavailable/disabled
[ ] Remote server disabled by default
[ ] Network exposure is explicit
[ ] Control authentication does not expose/log PIN
[ ] MIDI mappings remain project-owned despite Settings location
```

## UI-09

```text
[ ] Bulk patch validates complete proposed final state
[ ] Bulk patch is all-or-nothing and one Undo
[ ] Diagnostics uses semantic projection/controller
[ ] Routing distinguishes configuration, availability, and health
[ ] `.mirror` reports component-driver truth
[ ] Patch sorting/filtering does not mutate document order
[ ] Identify is explicitly implemented or explicitly deferred
```

## UI-10

```text
[ ] Remote Programmer remains out of scope
[ ] Mutating requests have unique request IDs
[ ] Duplicate request ID cannot execute GO twice
[ ] Reconnect never blindly replays transport commands
[ ] Remote API/snapshot contract is versioned
[ ] CURRENT/NEXT use shared semantic DTO
[ ] Mutating control requires authenticated/authorized session
```

## UI-11

```text
[ ] Build layouts are customizable
[ ] Perform remains dedicated fixed safety shell
[ ] Layout persistence is debounced/coalesced
[ ] Restore clamps to current screen/window geometry
[ ] Missing-monitor geometry cannot strand the workspace
[ ] Layout remains app preference, not ShowProject state
```

---

# Revised Autonomous Execution Rule

Proceed with the original UI-08→11 implementation plan plus these amendments.

For each phase:

```text
implement
→ focused tests
→ full macOS swift test
→ Xcode Debug
→ manual smoke
→ self-review
→ handoff
→ clean Git checkpoint
→ next phase
```

Stop on a major architecture or safety conflict.

Hard stop after UI-11.

---

# Final Verdict

The original plan is **architecturally strong and approved**.

The most important additions are:

1. safe Local DMX identity persistence;
2. true final-state atomic bulk patching;
3. dedicated Diagnostics projection;
4. explicit remote exposure/authentication defaults;
5. at-most-once remote GO semantics;
6. versioned remote protocol;
7. strict UI-10 scope;
8. fixed Perform layout scope in UI-11;
9. debounced and screen-safe layout persistence.

**APPROVED TO IMPLEMENT UI-08→UI-11 WITH THESE AMENDMENTS.**

Do not begin UI-12.
