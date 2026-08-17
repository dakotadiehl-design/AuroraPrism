# Aurora UI-08→UI-11 Third-Pass Final Commit Gate

**Review target:** `Aurora_08_11_ThirdPass.zip`  
**Baseline:** `64ed03e` — UI-04→07 accepted checkpoint  
**Purpose:** Decide whether UI-08→11 is stable enough to commit before beginning the next feature block  
**Verdict:** **VERY CLOSE — TWO SMALL PRE-COMMIT FIXES REQUIRED**

---

# Executive Summary

The third pass is substantially stable.

The broad UI-08→11 stabilization work is now in good shape:

- explicit Welcome state / New Show behavior is correct;
- MIDI health is structured and hotplug-aware;
- Null output no longer appears healthy;
- Patch has search/sort/row validation/bulk atomic repatch;
- Diagnostics updates live and now uses route-specific output truth;
- Local DMX requested/actual/availability state is separated;
- Remote listener state is asynchronous and truthfully reports `starting / ready / failed`;
- Remote HTTP snapshot polling touches session activity;
- stale/invalid browser auth returns to the authentication state;
- request-ID dedupe uses atomic reservation and deterministic ordered retention;
- request caches are cleaned during session teardown;
- Remote PIN is stored in Keychain, with legacy UserDefaults migration;
- Remote port validation no longer silently clamps;
- the browser client uses semantic CURRENT/NEXT and GO-dominant live controls;
- real workspace divider drags now update persisted split fractions;
- Diagnostics is now a real lower Build tool;
- document replacement keeps active tools aligned to the app-level layout;
- Patch surfaces missing definition, missing universe, invalid address, footprint overflow, and overlap;
- all 216 production Swift files pass `swiftc -frontend -parse`;
- `git diff --check` is clean.

There is **no reason for another broad UI-08→11 redesign**.

Before the checkpoint commit, fix the two localized issues below.

---

# BLOCKER 1 — WorkspaceLayoutStore Has a Debounce Race / Stale-Overwrite Path

## Severity

**P1 pre-commit**

This is localized, but it directly affects one of UI-11's advertised behaviors: persisted workspace layout.

## File

```text
Sources/AuroraUI/Workspace/WorkspaceLayoutStore.swift
```

## Current implementation

The store has global mutable state:

```swift
private static var pendingLayout: WorkspaceLayout?
private static var debounceWorkItem: DispatchWorkItem?
private static let debounceQueue = DispatchQueue(...)
```

`saveDebounced(...)` mutates `pendingLayout` from the caller, then a background queue later reads and clears it.

`save(...)` does not cancel/clear a pending debounced write.

## Failure example

```text
1. User drags divider.
2. saveDebounced(Layout A) is scheduled for +350 ms.
3. User immediately chooses "Reset Layout" or a named preset.
4. save(Layout B) writes the newer layout immediately.
5. The older debounced work item later runs.
6. It can write pending Layout A over Layout B.
```

A similar sequence can occur around:

```text
drag end
app quit
preset apply
reset layout
```

There is also unsynchronized access to:

```text
pendingLayout
debounceWorkItem
```

from the UI/MainActor side and `debounceQueue`.

`DispatchWorkItem.cancel()` alone is not a sufficient synchronization mechanism, and cancellation should not be assumed to prevent a scheduled block from ever executing unless the code explicitly guards generation/cancellation.

## Required fix

Serialize the persistence state.

The cleanest options are:

### Option A — MainActor store

Because workspace layout is UI/application preference state, make the pending/debounce coordinator MainActor-owned.

Use a cancellable `Task`:

```text
saveDebounced(layout)
  → cancel previous Task
  → store latest
  → Task.sleep(...)
  → if still current, save latest
```

Immediate `save(...)`, Reset, preset apply, and `flushPending()` must cancel the pending debounce before writing.

### Option B — Fully serialized private queue/lock

All reads/writes of:

```text
pending layout
pending generation
pending work item
```

must occur through one synchronized queue/lock.

Use a monotonically increasing generation so stale scheduled work cannot overwrite a newer immediate save.

## Required semantic rule

```text
newer layout state always wins
```

Immediate actions such as:

```text
Reset
Apply named layout
drag end
shutdown flush
```

must invalidate older pending debounce writes.

## Tests

Add deterministic tests:

```text
saveDebounced(A)
immediate save(B)
wait beyond debounce
load == B
```

```text
saveDebounced(A)
saveDebounced(B)
wait
load == B
```

```text
saveDebounced(A)
flushPending()
load == A
no later stale overwrite occurs
```

```text
rapid drag updates
→ final immediate drag-end save
→ persisted layout == final state
```

If test clocks/schedulers are useful, inject the debounce scheduler rather than relying on flaky sleeps.

---

# BLOCKER 2 — TCP Remote Reconnect Can Let an Old Connection Tear Down the New Session

## Severity

**P1 pre-commit remote reliability**

## Files

```text
Sources/AuroraRemote/RemoteHost.swift
Sources/AuroraRemote/RemoteSessionManager.swift
Sources/AuroraRemote/Resources/Web/index.html
```

## Existing good behavior

`RemoteSessionManager.handleHello(...)` deliberately reuses an existing session when the same:

```text
clientId
```

reconnects.

That is sensible.

## Current race

`RemoteHost` stores:

```text
connections[sessionID] = connection
```

When a connection finishes, its receive loop does:

```swift
sessions.disconnect(sessionId: sid)
connections[sid] = nil
```

Consider:

```text
TCP connection A authenticates
session = S

network hiccup starts

TCP connection B reconnects with same clientId
handleHello reuses session S
connections[S] = B

old connection A's close callback arrives afterward
A calls sessions.disconnect(S)
A clears connections[S]

new connection B is now attached to a session that A just destroyed
```

The next B command can fail authorization or the new connection becomes logically orphaned.

This is exactly the sort of overlap that can happen during Wi-Fi/network transitions.

## Required fix

A closing connection may only destroy the session if it is still the **current connection owner** for that session.

Use connection identity/generation.

Example conceptual rule:

```text
connections[sessionID] = (connectionID, connection)
```

On close:

```text
if connections[sessionID].connectionID == closingConnectionID:
    remove connection
    disconnect session
else:
    closing connection is stale
    do not touch the new session
```

You already maintain:

```text
sessionByConnection[ObjectIdentifier(connection)]
```

so use connection identity deliberately rather than deleting solely by `sessionID`.

Another valid design is to issue a new session ID on every TCP hello and explicitly supersede/cancel the old connection, but whichever model is used must be deterministic.

## Browser client ID follow-up

The web client currently creates:

```javascript
clientId: 'web-' + Math.random(...)
```

inside every `connect()` call.

So repeated Connect attempts create new sessions instead of benefiting from the existing same-client session reuse.

With:

```text
maxClients = 8
sessionIdleTTL = 120 sec
```

a user can generate several abandoned sessions during repeated reconnect/auth attempts and temporarily hit the client limit.

Make the browser client ID stable for at least the lifetime of the page.

Better:

```text
generate once at page load
```

or persist a random client ID in:

```text
sessionStorage / localStorage
```

depending on desired identity semantics.

Do not regenerate it on every Connect-button press.

## Tests

Add a host/session ownership regression test using an injectable connection identity seam if necessary:

```text
connection A owns session S
connection B supersedes A for same client/session
A closes
S remains valid for B
B command authorizes
B closes
S is then removed
```

Browser/session test:

```text
multiple reconnect attempts from same page reuse same clientId/session
client count does not climb on every Connect press
```

---

# NONBLOCKING CARRY-FORWARD 1 — Remote Command `snapshotRevision` Is Still a Pre-Refresh Revision

## Severity

**P2 — does not block the UI-08→11 commit**

The remote command protocol now returns a nonzero-looking:

```text
snapshotRevision
```

but command handlers execute against the current cached snapshot provider.

The remote snapshot is refreshed on the 0.2 s presentation timer.

For synchronous GO:

```text
dispatch GO
→ engine changes
→ command handler immediately asks currentSnapshotRevision()
→ cached remote snapshot may still be the pre-GO snapshot
→ ack returns old revision
```

For:

```text
songNext
songPrevious
```

the problem is stronger because those actions explicitly hop asynchronously to MainActor:

```swift
Task { @MainActor in
    performRemoteSong(...)
}
```

The command response can be sent before SongDirector has advanced at all.

## Why this is nonblocking today

The shipped browser does not rely on `snapshotRevision` to decide whether GO succeeded.

It continues polling authoritative server state.

At-most-once command execution is already protected by request IDs.

So actual live control remains safe.

## Recommended future cleanup

Either:

### A. Make command completion async and acknowledge after the action has actually applied

or:

### B. Stop describing the field as "resulting snapshot revision"

Return an acknowledgement ID only, and let the client wait for a later snapshot revision/state change.

Do not build future native remote logic on the assumption that the current field represents post-command state.

---

# NONBLOCKING CARRY-FORWARD 2 — Diagnostics Driver Ordering Should Be Stabilized

`OutputManager.healthSnapshots()` originates from a dictionary of drivers.

Diagnostics publishes:

```text
driverHealth
mirror route component list
```

using the resulting array order.

Dictionary iteration order should not become a presentation contract.

Sort diagnostic driver rows by a stable key such as:

```text
protocol + name + driverID
```

before publishing.

This avoids row jumping and unnecessary semantic snapshot churn when driver collections change.

Not a commit blocker.

---

# NONBLOCKING DOCUMENTATION — UI-11 Handoff Is Stale

## File

```text
UIDesignReferences/UI_11_Handoff.md
```

It still says:

```text
Native HSplitView does not push live divider drag positions back into the model
```

That is no longer true in this third pass.

`BuildWorkspaceHost` now owns explicit drag dividers and calls:

```swift
workspace.updateSplitFractions(...)
```

Update the handoff after Blocker 1 is fixed so future Grok sessions do not "fix" an already-fixed limitation.

---

# Third-Pass Regression Summary

## PASS — New Show / Welcome

Explicit workspace Welcome state remains correct.

## PASS — MIDI status

Structured MIDI health remains correct:

```text
0 sources != healthy
hotplug updates inventory
```

## PASS — Output status

Null output remains semantically disabled.

## PASS — Patch

Current Patch UI includes:

```text
search
sort
sort direction
overlap detail
per-row validation
missing definition
missing universe
invalid address
footprint OOB
bulk atomic address offset
```

`BulkRepatchCommand` now validates:

```text
changed fixtures
+
fixtures in affected old/new universes
```

which allows recovery from unrelated legacy invalid state elsewhere.

Good.

## PASS — Diagnostics live refresh

`DiagnosticsController.startLiveUpdates(...)` is started from `AppModel`.

Snapshot refresh is automatic rather than requiring manual Refresh.

## PASS — Diagnostics Local DMX truth

Snapshot now separates:

```text
localDMXRequested
localDMXEnabled
localDMXDeviceAvailable
runtime status
```

Good.

## PASS — Per-universe diagnostics

Universe rows are resolved by route:

```text
.none
.local
.artNet
.sACN
.mirror
```

rather than inheriting one global output health.

Good.

## PASS — Remote listener readiness

Both TCP and Web expose semantic listener lifecycle:

```text
stopped
starting
ready
failed
```

`RemoteController` only reports fully running when both required listeners are ready.

Late async listener failure tears down the service.

Good.

## PASS — Remote snapshot session activity

HTTP snapshot polling touches the session.

Good.

## PASS — Browser invalid-token recovery

401/403 moves browser back to auth instead of polling forever with a dead token.

Good.

## PASS — Request-ID retention cleanup

Request-ID cache now has explicit insertion order and is removed during:

```text
disconnect
kick
kickAll
idle reclaim
```

Good, subject only to Blocker 2's connection-ownership race.

## PASS — PIN security

Remote PIN now lives in Keychain.

Legacy plaintext UserDefaults is migrated and removed.

Good.

## PASS — Port validation

Settings now rejects invalid remote ports rather than silently clamping.

Good.

## PASS — Real layout interaction

Build now uses explicit draggable dividers and calls:

```text
updateSplitFractions(...)
```

Diagnostics is a real `BuildLowerTool`.

Good, subject to Blocker 1's persistence coordinator race.

## PASS — Document replacement vs app layout

`didReplaceDocument` now keeps tools aligned with persisted app-level layout rather than resetting to Browser/Cues.

Good.

---

# Static / Build Gate

## Swift syntax

```text
216 production Swift files
216 parsed successfully
0 parse failures
```

## Git diff validation

```text
git diff --check
PASS
```

## Swift package

`AuroraModel` builds successfully in this review environment.

The full package cannot compile here because this is Linux and Aurora requires:

```text
CoreMIDI
Network
```

for macOS-only targets.

The resulting failure is environmental, not a detected source error.

---

# Required macOS Gate After These Two Fixes

Before the checkpoint commit:

```text
[ ] full swift test
[ ] Xcode Debug build
[ ] launch app
```

Remote abuse test:

```text
[ ] enable Remote
[ ] connect web client
[ ] reconnect repeatedly; client count remains sane
[ ] native/TCP reconnect does not get destroyed by old connection close
[ ] GO remains one press = one action
[ ] server restart returns web client to auth
```

Layout abuse test:

```text
[ ] drag divider
[ ] immediately apply Patch layout
[ ] wait > debounce window
[ ] quit/relaunch
[ ] Patch layout remains persisted, not stale dragged layout

[ ] drag divider
[ ] immediately Reset
[ ] wait
[ ] restart
[ ] Reset remains persisted

[ ] drag divider
[ ] quit immediately
[ ] final position persists
```

If those are green:

```text
COMMIT UI-08→11
```

---

# Commit Recommendation After Mini-Fix

Suggested checkpoint message:

```text
UI-08 through UI-11 complete with stabilization hardening
```

or:

```text
Complete UI-08–11 configuration, diagnostics, remote, and workspace layouts
```

Do not mix the next feature work into this commit.

---

# After the Commit — Next Feature Block

The accepted architecture is now in a good position to move beyond the numbered UI foundation.

Two explicitly desired next features are:

## 1. Stage Spatial / 2D Live View

The Future Features document already reserves model-owned spatial metadata:

```text
X
Y
Z
orientation
role
coverage region
```

and calls out semantic spatial behavior such as:

```text
Sweep from stage left to stage right
Ripple outward from the drummer
```

as well as visualization.

The next design pass should turn this into an explicit 2D Stage/Live View specification without prematurely implementing full 3D tracking.

Recommended first scope:

```text
2D stage canvas
fixture placement
fixture orientation
group/role labels
live intensity/color indication
moving-head pan/tilt visualization where meaningful
selection synchronized with Fixture Browser/Programmer
stage spatial metadata stored in ShowProject
no second lighting engine
```

This spatial model should also become the foundation for later:

```text
spatial ripples
stage-left/right sweeps
drummer-centered effects
rig adaptation
performer tracking
```

## 2. Advanced MIDI Performance Engine

This should now be treated as a major Aurora differentiator, not another simple mapping-panel enhancement.

The current architecture already preserves useful seeds:

```text
rich MIDIEvent
sourceID
velocity / CC scalar
open action keys
ControlActionRouter live path off MainActor
semantic fixture attributes
Song/section state
```

The feature should be planned as layers:

```text
MIDI parse
→ event normalization
→ rule/condition matching
→ reusable behaviors
→ envelopes / temporary overrides
→ safety/rate limiting
→ engine application
```

Initial advanced scope should consider:

```text
note on/off
velocity
CC
program change
pitch bend
channel pressure
poly pressure
source device
song/section/cue conditions
modifier conditions
one event → multiple actions
temporary intensity/color overrides
attack/hold/decay envelopes
drum-oriented behaviors
panic/reset
runaway/stuck-note protection
event/rule debug visualization
global Performance MIDI enable
```

Do not implement Advanced MIDI as hundreds of special-case `ShowAction` enum cases.

Introduce a reusable behavior/rule layer.

---

# Final Gate

**Current third pass:** nearly ready.

**Required before commit:** Blocker 1 + Blocker 2 only.

After those fixes and a green macOS build/test:

> **APPROVED TO COMMIT UI-08→11 AND START THE NEXT FEATURE BLOCK.**

Do not spend another broad stabilization cycle on UI-08→11 unless the macOS/manual gate exposes a new functional defect.
