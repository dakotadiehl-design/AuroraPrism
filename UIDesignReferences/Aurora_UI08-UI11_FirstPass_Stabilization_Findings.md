# Aurora UI-08→UI-11 First-Pass Stabilization Review

**Review target:** `Aurora_08-11_firstpass.zip`  
**Baseline:** UI-03→07 accepted checkpoint `64ed03e`  
**Review focus:** correctness, truthfulness, feature completion, safety, and integration before UI polish  
**Overall verdict:** **CHANGES REQUIRED — DO NOT MOVE TO UI-12/POLISH YET**

---

# Executive Summary

The UI-08→11 first pass contains useful backend/foundation work, but several user-visible features are either incorrect, only partially wired, or described as complete in handoff documents even though the application does not yet expose the promised behavior.

This review intentionally prioritizes:

```text
works correctly
→ tells the truth
→ is fully wired
→ is testable
→ then polish
```

The two user-observed bugs are confirmed:

1. **Top-right MIDI/Output status indicators can show green when they should not.**
2. **New Show can appear to do absolutely nothing.**

In addition, this review found larger completion gaps:

- UI-09's professional Patch/Diagnostics work is mostly foundation, not an implemented UI.
- UI-10's backend protocol has improved, but the actual web/iPad client still uses the old contract and does not satisfy at-most-once GO semantics.
- UI-11's layout models/persistence exist, but the actual Build workspace does not consume them, so named layouts, visibility, and saved split geometry have little/no effect.
- Remote Settings has multiple authority/restart bugs and does not reliably start the server using the settings the UI displays.
- Remote command deduplication has a concurrency race.
- Persisted remote enable state is not applied at app startup.
- Local Network remote mode currently binds all interfaces, despite being presented as private/LAN access.
- MIDI health can remain stale after hotplug.

This is not a reason to redesign Aurora. The problems are concentrated in wiring, state truthfulness, and completing the promised phase scope.

---

# Verification Performed

## Static Swift parsing

All production Swift files parse successfully with:

```text
swiftc -frontend -parse
```

Result:

```text
PASS
```

## Diff whitespace/error check

```text
git diff --check
```

Result:

```text
PASS
```

## Full test suite

`swift test` was attempted.

The build reaches Aurora modules, then fails in this Linux review environment because Aurora correctly depends on macOS-only frameworks:

```text
Network
CoreMIDI
```

Representative errors:

```text
no such module 'Network'
no such module 'CoreMIDI'
```

Therefore the handoff claim of **344 green tests** cannot be independently verified here.

**Required after fixes:** run full `swift test` and Xcode Debug on macOS.

---

# P0 — Must Fix Before Calling UI-08→11 Functionally Complete

## ST-01 — MIDI health is green with zero MIDI sources

### Confirmed user report

The toolbar/status health mapper derives MIDI health by parsing:

```swift
midiStatus: String
```

Current logic:

```swift
if string contains error/fail
    warning
else if contains off or empty
    disabled
else
    healthy
```

After CoreMIDI starts successfully with no connected devices, `InputController` sets:

```text
MIDI: 0 sources
```

That string falls through to:

```text
healthy
```

So:

```text
0 MIDI devices
→ green MIDI indicator
```

### Required fix

Do not derive semantic health from a user-facing string.

Expose structured MIDI state.

Suggested shape:

```swift
struct MIDIHealthSnapshot: Equatable, Sendable {
    enum State {
        case off
        case ready
        case warning
        case failed
    }

    var state: State
    var connectedSourceCount: Int
    var lastError: String?
}
```

Then map:

```text
CoreMIDI unavailable/start failed → failed/warning
MIDI subsystem off → disabled
running + 0 sources → disabled/unknown, NOT healthy
running + >=1 source → healthy
```

Exact colors can follow Aurora design language, but green must mean a genuinely usable MIDI path.

### Hotplug requirement

`MIDIInputManager` reconciles sources on CoreMIDI setup notifications, but `InputController.midiStatus` is not notified when that inventory changes unless another event happens.

Add an inventory/status callback from `MIDIInputManager` to `InputController`, or another structured observation path, so:

```text
plug controller → indicator updates
unplug controller → indicator updates
```

without requiring a MIDI note to be sent.

### Tests

```text
running + 0 sources → not healthy
running + 1 source → healthy
start failure → failed/warning
hotplug add updates source count
hotplug remove updates source count
```

---

## ST-02 — Null output driver makes Output look green even when no real output exists

### Confirmed user report

`OutputManager` always contains `NullOutputDriver`.

When the engine starts, the Null driver runs.

Because it does not provide a special semantic health snapshot, `OutputManager.healthSnapshots()` treats:

```text
Null driver + isRunning
```

as:

```text
ready
```

`OutputPresentationSnapshot` then sees an active ready driver and reports aggregate:

```text
healthy
```

Therefore Aurora can display:

```text
Output ● green
```

while output is literally being discarded.

### Required fix

Null output is not a successful physical/network output path.

Make its semantic health:

```text
disabled / null-only
```

even if its internal discard sink is running.

Preferred:

```text
NullOutputDriver conforms to OutputHealthReporting
→ state = .disabled
```

or explicitly exclude Null from aggregate output health.

Do not detect this through driver name strings.

### Expected UI semantics

```text
No real drivers active
→ Output disabled/gray

Art-Net active and ready
→ Output green

ENTTEC active and ready
→ Output green

configured driver degraded
→ Output warning

configured driver failed/disconnected
→ Output failed
```

### Tests

```text
Null only → aggregate disabled
Null + Art-Net ready → healthy
Null + failed Art-Net → failed
Null + Local DMX ready → healthy
```

---

## DOC-01 — “New Show” is visually a no-op because Welcome is inferred from empty project contents

### Confirmed user report

`ContentView.showWelcome` is currently inferred from:

```text
Build mode
AND project.fixtures.isEmpty
AND project.cueLists.isEmpty
AND documentURL == nil
```

`New Show` creates:

```text
empty project
no document URL
```

which satisfies the exact same condition.

Therefore:

```text
Welcome
→ click New Show
→ new empty document created
→ ContentView decides this still means Welcome
→ screen appears unchanged
```

The button is technically executing, but from the operator perspective it does nothing.

This also conflates two different concepts:

```text
application Welcome state
```

and:

```text
a valid empty untitled show document
```

They are not the same state.

### Required fix

Represent Welcome explicitly as workspace/application state.

Example:

```swift
@Published var showsWelcomeScreen: Bool
```

or an equivalent document lifecycle state.

Desired behavior:

```text
app launch with no chosen document
→ Welcome

Welcome → New Show
→ create empty Untitled Show
→ dismiss Welcome
→ show Build workspace

Welcome → Open
→ dismiss Welcome after successful open

Welcome → Demo
→ dismiss Welcome after successful demo load
```

An empty active Show must be allowed to display the normal Build/Patch workflow.

Do not infer Welcome from fixture/cue counts.

### Tests

```text
initial empty launch → Welcome
New Show → Build workspace state
New Show produces empty active document
open empty saved show → Build, not Welcome
Demo → Build
```

---

# P0 — UI-09 Is Not Implemented to Its Declared Scope

## UI09-01 — Professional Patch UI was not built

The UI-09 plan called for:

```text
professional patch table
search/filter/sort
visible validation
bulk atomic operations
routing board
operator diagnostics
```

The handoff now says:

```text
Foundation COMPLETE
```

and explicitly admits:

```text
Full Patch table redesign not implemented
existing PatchPanel remains usable
```

Current `PatchPanel` remains essentially the earlier basic panel:

```text
Universe picker
Add Universe
Clone
Remove
Addr / End / Name / Personality table
basic Repatch sheet
one generic overlap-count warning
```

Missing from the phase's actual product scope:

```text
search
filter
sort controls
detailed conflict/validation presentation
professional routing board
bulk repatch UI using BulkRepatchCommand
occupancy/address visualization
clear footprint/OOB diagnostics
```

### Important

`BulkRepatchCommand` is useful and its preflight design is good.

But it is currently **foundation code with no real user workflow using it**.

### Required fix

Finish the UI-09 functional Patch workflow before polish.

At minimum:

```text
[ ] Search
[ ] presentation-only sort
[ ] meaningful validation rows/messages
[ ] repatch/bulk repatch UI uses atomic command
[ ] conflict identifies fixtures/addresses, not just count
[ ] route visibility per universe
```

Do not silently reorder `ShowProject.fixtures` when table sorting.

---

## UI09-02 — `DiagnosticsSnapshot` exists but Diagnostics does not consume it

A new:

```text
DiagnosticsSnapshot
```

type was added.

But `DiagnosticsController` still only owns:

```text
consoleLog
validationIssueCount
DiagnosticsStore
```

There is no published diagnostics snapshot, no build/update timer, and no Diagnostics panel consuming it.

The handoff itself says:

```text
DiagnosticsSnapshot not yet fully hosted
```

That means amendment A3 was not actually completed.

### Required architecture

Wire:

```text
Engine
Output
MIDI
Remote
Project validation
      ↓
DiagnosticsController
      ↓
@Published DiagnosticsSnapshot
      ↓
Diagnostics UI
```

The snapshot should distinguish:

```text
configured output route
driver enabled
destination available
runtime health
```

For `.mirror`, expose component health rather than one mystery light.

### Diagnostics UI minimum

Provide an operator-useful surface showing:

```text
Engine running / rate
Output aggregate
driver health
universe route + availability
Local DMX
Art-Net
sACN
MIDI
Remote server/client count
validation issues
last meaningful errors
```

Do not force the operator to read raw Console logs to diagnose routine configuration.

---

# P0 — UI-10 Remote Is Only Half Migrated to the New Contract

## UI10-01 — The shipped web client does not send request IDs

Backend HTTP accepts:

```text
requestId
```

but makes it optional.

If absent, the server generates a new UUID.

The shipped `index.html` currently sends:

```javascript
await api('/api/command', { action });
```

No request ID.

Therefore if a request is retried:

```text
first GO → server-generated ID A
retry GO → server-generated ID B
```

and both are considered distinct.

The advertised:

```text
at-most-once GO
```

is **not true for the actual web/iPad client**.

### Required fix

Client generates one UUID/request ID per deliberate operator press:

```text
press GO
→ create requestId
→ send command
→ retry same request only with same requestId
```

Server must require a nonempty request ID for mutating HTTP commands.

Do not silently generate one server-side when the client omits it.

---

## UI10-02 — Deduplication check/record has a race

Current flow:

```text
takeRequestIdIfNew()
→ if absent
→ authorize
→ execute action
→ rememberRequestId()
```

`takeRequestIdIfNew()` only checks whether the ID exists.

It does not atomically reserve it.

Two simultaneous duplicate requests can both:

```text
check → absent
check → absent
execute GO
execute GO
```

before either remembers the result.

### Required fix

Create one atomic operation in `RemoteSessionManager`, e.g.:

```text
reserve request ID
```

with states such as:

```text
new/reserved
completed(result)
duplicate/inFlight
```

Only the request that successfully reserves an unseen ID may execute.

After execution, record final result.

### Tests

Use concurrent requests:

```text
20 simultaneous requests with same requestId
→ action handler called exactly once
```

This is a live-show safety test.

---

## UI10-03 — Web UI still renders the old cue model

Backend now supplies:

```text
currentCue
nextCue
songTitle
sectionLabel
snapshotRevision
protocolVersion
```

The actual HTML still renders:

```javascript
cueIndex
cueName
```

and does not show true CURRENT/NEXT.

It also still contains old controls:

```text
Next
Fire cue 0
Fire cue 1
```

This is not the touch-oriented Perform remote planned for UI-10.

### Required fix

Build the actual Perform remote now, before cosmetic polish.

Minimum live layout:

```text
Show / Song
CURRENT
NEXT
large GO
Back
Stop
secondary Previous/Next Song Entry
output/connection health
```

Remove developer/demo buttons such as:

```text
Fire cue 0
Fire cue 1
```

unless they are deliberate final product controls.

GO must be visually dominant.

---

## UI10-04 — Browser protocol version negotiation is not actually implemented

TCP hello contains `protocolVersion`.

HTTP `/api/hello` does not accept a browser protocol version; the server simply calls session hello using the server's current version.

The browser also ignores:

```text
snapshot.protocolVersion
```

So the browser cannot discover an incompatible API correctly.

### Required fix

Web hello sends:

```text
protocolVersion
```

Server validates it.

Client rejects/shows a clear upgrade mismatch when incompatible.

---

## UI10-05 — PIN field ships pre-populated with `0000`

Current HTML:

```html
value="0000"
```

The product generates six-digit random PINs, so shipping a fake default PIN is misleading.

Remove the default value.

Use placeholder only.

---

# P0 — Remote Settings Do Not Reliably Control the Server They Describe

## REM-01 — Remote listener starts before Settings port/bind configuration is applied

`applyRemoteFromSettings()` currently does:

```text
1. appModel.setRemoteEnabled(true, pin: ...)
   → RemoteController reads existing config
   → starts TCP listener
   → starts Web listener

2. THEN mutate RemoteSessionManager config:
   port = Settings port
   bindPolicy = Settings access mode
```

Changing the config after the listeners start does not rebind them.

Therefore Settings may say:

```text
TCP port 9000
Local Network
```

while the server is still listening on:

```text
old/default port
old/default bind
```

### Required fix

Configuration must be applied **before** listeners start.

Create one authoritative operation, conceptually:

```swift
remote.applyConfiguration(config, enabled: Bool)
```

which:

```text
validates config
stops old listeners if required
updates session config
starts listeners using that config
publishes actual bound endpoints
rolls back on failure
```

Do not mutate live server config out-of-band after startup.

---

## REM-02 — `remoteWebPort` Setting is ignored

`AppSettingsStore` persists:

```text
remoteWebPort
```

Settings displays it.

But `RemoteController` constructs:

```swift
RemoteWebServer(... port: 8743)
```

and status strings hard-code:

```text
Web :8743
```

So the setting is not authoritative.

### Required fix

Either:

```text
make remoteWebPort a real editable/applicable setting
```

or:

```text
remove the fake persisted setting and explicitly fix web port at 8743
```

Do not expose configuration that does nothing.

---

## REM-03 — TCP port edits do not restart/rebind the active server

The Settings TextField setter saves:

```text
remotePort
```

but does not reapply/restart the remote server.

So the UI changes but runtime does not.

Prefer explicit:

```text
Apply / Restart Remote
```

or validated commit-on-focus/end that performs safe reconfiguration.

---

## REM-04 — Persisted “Remote enabled” is not applied on app launch

`AppSettingsStore` loads:

```text
remoteAccessEnabled
```

but `AppModel.init()` never starts Remote based on it.

Therefore after relaunch:

```text
Settings says Enable remote control = ON
runtime RemoteController says Remote: off
server is off
```

This is a direct configuration/runtime truth mismatch.

### Required fix

After AppModel composition is ready:

```text
if persisted remote enabled
→ apply persisted config through authoritative RemoteController config API
```

If start fails:

```text
requested enabled may remain true
actual running false
status explains failure
```

Keep requested-vs-actual semantics explicit, similar to Local DMX.

---

## REM-05 — Remote menu bypasses Settings authority

The macOS `Remote` command menu currently calls:

```swift
appModel.setRemoteEnabled(...)
```

directly.

It does not update:

```text
AppSettingsStore.remoteAccessEnabled
mode
port
PIN
```

Therefore there are two control paths:

```text
Settings-owned configuration
and
runtime menu-owned configuration
```

They can disagree.

### Required fix

All Remote enable/disable entry points must call one authoritative configuration API.

Menu action should change the same application preference/runtime configuration as Settings.

---

## REM-06 — Partial remote startup can leave one listener running after reported error

Current startup sequence:

```text
try remoteHost.start()
try web.start()
catch → status = error
```

If TCP starts successfully and Web startup fails:

```text
catch executes
but TCP host is not stopped
```

Aurora can report:

```text
Remote: error
```

while a control listener is still active.

### Required fix

Startup must be transactional.

On any failure:

```text
stop TCP
stop Web
invalidate tokens/session as appropriate
actualRunning = false
status = error
```

Add tests with injected failing Web/TCP listener factories if necessary.

---

## REM-07 — “Local Network” currently means all interfaces

`RemoteBindPolicy.privateLAN` maps to:

```swift
nil
```

which means all interfaces.

This may include interfaces beyond private LAN, such as VPN or other configured interfaces.

Yet Settings presents:

```text
Local Network
```

and says to use private networks only.

### Required fix

Either implement actual interface/address restriction for local/private ranges, or rename/present the behavior truthfully as:

```text
All Interfaces
```

with an explicit warning.

Do not promise private-only binding when code uses wildcard binding.

---

# P0 — UI-11 Layout Functionality Is Not Connected to the Workspace

## UI11-01 — Saved split fractions are never used by `BuildWorkspaceHost`

`WorkspaceLayout` now contains:

```text
leadingFraction
trailingFraction
bottomFraction
```

`WorkspaceController` exposes:

```text
updateSplitFractions(...)
```

But `BuildWorkspaceHost` still uses hard-coded frames:

```text
left: ideal 220, max 300
programmer min 420
inspector ideal 210, max 300
bottom ideal 200, max 300
```

It never reads the saved fractions.

It never writes split positions after HSplitView/VStack resizing.

Therefore:

```text
save layout
restart
```

does not restore actual operator split geometry.

### Required fix

Wire the real workspace to layout state.

If native `HSplitView` does not expose divider fractions conveniently, use an appropriate split implementation that can observe/persist divider positions.

The real UI, not only the model, must drive:

```text
workspace.updateSplitFractions(...)
```

---

## UI11-02 — Panel visibility state is not respected by Build workspace

`WorkspaceLayout.visiblePanels` and:

```swift
workspace.isVisible(...)
```

exist.

But `BuildWorkspaceHost` does not conditionally show/hide its actual columns/regions based on that state.

The View menu does not expose visibility controls either.

This means toggling stored visibility has no practical effect on the main workspace.

### Required fix

Wire visibility deliberately.

At minimum:

```text
Fixture/left region
Inspector
lower region
```

must have supported hide/show semantics if the feature is part of UI-11.

Do not allow hiding the Programmer if the product requires it to remain the center of gravity.

---

## UI11-03 — Named layout presets have no user-facing wiring

`WorkspaceController` implements:

```text
applyNamedBuildLayout
resetLayout
```

but no normal application UI/menu invokes them.

The handoff itself says:

```text
Menu wiring for every preset — API ready
```

That means named layouts are not yet a feature, only an API.

### Required fix

Add a View/Workspace menu or toolbar menu:

```text
Layouts
  Programming
  Patch
  Song
  Diagnostics
  Reset Layout
```

Applying a preset must actually alter visible tools/geometry in Build.

---

## UI11-04 — Named preset fields do not correspond to current `BuildWorkspaceHost`

`WorkspaceLayout` still carries generic legacy-style fields:

```text
leadingTab
centerTab
bottomTab
```

But modern Build uses:

```text
BuildLeftTool
fixed Programmer center
Inspector right
BuildLowerTool
```

For example the "Patch" preset creates:

```text
leadingTab = patch
centerTab = fixtureBrowser
bottomTab = universeMonitor
```

yet current Build center is always Programmer and lower tools are Palettes/Cues/Song.

This is a model/UI impedance mismatch.

### Required fix

Align the layout model to the actual current workspace.

Possible modern representation:

```text
leftTool: BuildLeftTool-equivalent stable ID
lowerTool: BuildLowerTool-equivalent stable ID
inspectorVisible
lowerVisible
leadingFraction
trailingFraction
bottomFraction
```

Avoid persisting layout concepts the current shell cannot render.

Keep `AuroraUI` host-agnostic if module boundaries require a neutral semantic enum.

---

## UI11-05 — Debounced layout persistence is not flushed on application shutdown

`WorkspaceLayoutStore` has:

```text
flushPending()
```

but it is not called by application lifecycle code.

Once real divider dragging is wired, a final adjustment followed quickly by quit can be lost.

### Required fix

Flush pending layout storage during orderly shutdown/termination.

---

# P1 — UI-08 Settings Is Still Incomplete Functionally

## UI08-01 — Art-Net / sACN configuration is not actually in Settings

The UI-08 plan called for Output Settings containing:

```text
Art-Net configuration
sACN configuration
Local DMX
enable/disable
destinations
```

Current Settings shows:

```text
Network drivers
"Enable Art-Net / sACN from the Output menu."
```

The actual controls remain in the macOS Output menu.

This is functional elsewhere, but it means **Full Settings Content is not complete**.

### Recommendation

Move/rehost the existing real controls into Settings:

```text
Art-Net enable
destination
broadcast/unicast semantics

sACN enable
multicast/unicast target
```

The Output menu can remain as quick actions.

One authority, multiple presentations.

---

## UI08-02 — RTP-MIDI and OSC are still placeholders

Control Settings explicitly says:

```text
RTP-MIDI session UI is not configured
OSC reserved for a later Settings pass
```

Yet both already have real runtime functionality in Aurora menus/controllers.

Before claiming Full Settings complete, expose the existing controls in Settings.

Do not invent new protocol architecture.

Simply rehost existing configuration/status cleanly.

---

## UI08-03 — Appearance density preference is stored but not applied

`AppSettingsStore.preferredDensity` exists and persists.

No production view reads it.

Therefore it is currently dead configuration.

Either:

```text
wire it into `.auroraDensity(...)`
```

or remove/defer the preference until it actually changes the UI.

Do not keep settings that appear real but do nothing.

---

# P1 — Remote Protocol / Security Hardening

## REM-08 — Web command requestId must be required, not optional

Current HTTP server does:

```text
missing requestId
→ generate UUID server-side
```

That makes deduplication impossible for retrying clients.

Reject mutating command requests without a request ID.

---

## REM-09 — HTTP command response lacks the promised resulting revision

TCP `commandResult` includes:

```text
snapshotRevision
```

but currently sends `0`.

HTTP response has no snapshot revision at all.

The UI-10 amendment required acknowledgement tied to resulting server/playback truth.

After dispatch, provide a meaningful revision or return a snapshot/state identity that lets the client determine the command outcome.

Do not pretend `0` is a real revision.

---

## REM-10 — Remote PIN is persisted in plaintext UserDefaults

`remotePIN` is stored directly in:

```text
UserDefaults
```

This is functional but weak for a credential that authorizes real show control.

Recommended before product polish:

```text
Keychain
```

or another appropriate secure credential store.

At minimum, document the current storage limitation clearly if deferred.

Never log it.

---

# P1 — MIDI State Can Stay Stale After Hotplug

As described in ST-01, CoreMIDI inventory changes happen inside `MIDIInputManager`, but `InputController` has no callback that updates its published semantic state.

Fix this as part of structured MIDI health.

---

# P1 — Handoff Documents Overstate Completion

Current handoffs say:

```text
UI-08 COMPLETE
UI-09 Foundation COMPLETE
UI-10 COMPLETE for Perform remote scope
UI-11 COMPLETE
```

But:

```text
UI-09 core UI is not implemented
UI-10 web client still uses old protocol/UX
UI-11 is mostly data model/API with no host wiring
```

Update handoffs after this stabilization pass.

Do not call a phase complete when only its foundation exists.

This matters because future Grok sessions use these files as project memory.

---

# P2 — Additional Functional/Quality Findings

## Q-01 — Remote port TextField silently clamps invalid values

The plan called for validation rather than silent coercion.

Current setter:

```swift
max(1, min(65535, v))
```

A typed invalid value can silently become another port.

Prefer validated draft input with an explicit error.

---

## Q-02 — Remote PIN copy says “shown once,” but it remains visible

Settings displays the saved PIN whenever remote is enabled.

Change copy or change behavior.

Do not say "shown once" if it is continuously retrievable.

---

## Q-03 — Output/MIDI top-right status should share the same semantic health used by Diagnostics

Once structured MIDI and real DiagnosticsSnapshot are implemented, avoid another duplicate mapping layer.

Recommended:

```text
controller semantic health
      ↓
shared projection
      ├─ toolbar
      ├─ status bar
      ├─ Perform
      └─ Diagnostics
```

Do not let each UI independently interpret strings.

---

# What Is Good in This Pass

The following work should be retained.

## Settings / Local DMX

- requested-vs-actual Local DMX enable is a good model
- no silent fallback when configured local device is absent
- stable-identity preference field exists
- project universe routing remains command/undo based
- Local DMX limitation is presented truthfully

## Patch foundation

- `BulkRepatchCommand` validates proposed final patch before mutation
- address swaps can be represented atomically
- one command gives one Undo
- final overlap rejection is tested

## Remote backend direction

- remote is disabled by default in app settings
- Remote Programmer is denied by allow-list
- semantic CURRENT/NEXT DTO exists
- protocol version exists in TCP codec
- request IDs exist in backend protocol
- PIN no longer appears in runtime status/log strings
- viewer/operator authorization remains centralized

## Perform/layout scope

- Perform remains its dedicated fixed shell
- layout persistence is kept out of ShowProject
- layout schema/fallback/clamping direction is correct

These foundations do not need replacement; they need end-to-end wiring.

---

# Required Stabilization Order

Recommended order before any UI-12 polish work:

```text
1. Fix New Show / explicit Welcome state

2. Fix semantic health
   - MIDI structured state
   - MIDI hotplug updates
   - Null output not healthy
   - shared toolbar/status/Perform mapping

3. Fix Remote Settings authority
   - one config API
   - apply config before start
   - actual persisted startup behavior
   - real ports/bind policy
   - transactional startup
   - menu uses same authority

4. Finish remote at-most-once semantics
   - client request IDs
   - atomic request reservation
   - no automatic command replay
   - meaningful acknowledgements

5. Replace legacy web client with real UI-10 Perform remote
   - CURRENT/NEXT
   - GO-dominant touch UI
   - remove demo fire buttons
   - protocol-version handshake

6. Finish UI-09
   - professional Patch workflow
   - detailed validation
   - wire BulkRepatchCommand
   - wire DiagnosticsSnapshot/DiagnosticsController
   - routing + health dashboard

7. Finish UI-11
   - real split geometry integration
   - visibility
   - named preset menu
   - align layout model with current Build shell
   - persist/restore real geometry
   - flush on shutdown

8. Finish UI-08 functional Settings gaps
   - Art-Net/sACN
   - RTP-MIDI
   - OSC
   - apply/remove density setting truthfully

9. Update handoffs to match reality

10. Full macOS test + Xcode Debug

11. Manual operator smoke

12. Only then consider UI-12 / UI polish
```

---

# Required Tests to Add

## New Show

```text
welcome → New Show → active Build state
empty active show does not imply Welcome
Open empty show → Build
```

## Health

```text
0 MIDI sources not healthy
MIDI hotplug changes health
Null-only output disabled
real ready output healthy
failed configured output failed
```

## Remote Settings

```text
configured TCP port is actual bound port
configured Web port is actual bound port
loopback mode binds loopback
LAN mode behavior matches UI promise
runtime start failure leaves no listener running
persisted enabled setting restores runtime on launch
menu enable and Settings remain synchronized
```

## Remote at-most-once

```text
HTTP missing requestId rejected
duplicate sequential request executes once
duplicate concurrent request executes once
retry after lost acknowledgement executes once
new request ID executes a second deliberate GO
reconnect does not replay old mutating commands
```

## UI-09

```text
BulkRepatchCommand is exercised by actual UI/domain action seam
validation details identify conflicting fixtures
DiagnosticsSnapshot publication updates after output/MIDI/remote changes
```

## UI-11

```text
applying named layout changes actual Build state
resized splits persist and restore
panel visibility affects actual workspace
reset restores real default
pending persistence flushed on shutdown
```

---

# Manual macOS Stabilization Checklist

## Shell

```text
[ ] launch with no MIDI devices → MIDI not green
[ ] plug MIDI device → MIDI turns healthy without sending note
[ ] unplug MIDI device → health updates
[ ] Null-only output → Output not green
[ ] enable working Art-Net/sACN/ENTTEC → Output healthy
```

## Document

```text
[ ] launch → Welcome
[ ] click New Show → normal empty Build workspace appears
[ ] patch first universe/fixture from new empty show
[ ] New Show from populated dirty show prompts correctly
```

## Remote

```text
[ ] enable This Mac only → verify listener bound loopback
[ ] change TCP/Web ports → verify actual listeners move
[ ] relaunch with Remote enabled → runtime and Settings agree
[ ] force Web port conflict → no leftover TCP control listener
[ ] connect iPad → no default PIN filled in
[ ] CURRENT/NEXT match Mac
[ ] one GO press advances exactly one cue
[ ] interrupt Wi-Fi around GO → reconnect does not double-GO
```

## Patch / Diagnostics

```text
[ ] search/filter fixture patch
[ ] see exact overlap conflict
[ ] atomic multi-fixture repatch
[ ] Undo restores all
[ ] diagnostics show meaningful driver/MIDI/remote state
```

## Layout

```text
[ ] apply Programming/Patch/Song/Diagnostics layout from UI
[ ] actual workspace changes
[ ] resize real dividers
[ ] relaunch → geometry restores
[ ] reset layout
[ ] Perform remains fixed and GO reachable
```

---

# Final Gate

## Current first-pass verdict

**NOT READY FOR UI-12 / POLISH.**

This pass has several strong foundations, but too many functional surfaces are incomplete or misleading to move into cosmetic polish.

The guiding rule for the next Grok pass should be:

> **No new cosmetic work. Finish wiring, state truthfulness, command safety, settings authority, and promised phase functionality first.**

After the stabilization fixes, run a second deep review of UI-08→11.

Only after that review is clean should Aurora move into UI-12 Product Polish.
