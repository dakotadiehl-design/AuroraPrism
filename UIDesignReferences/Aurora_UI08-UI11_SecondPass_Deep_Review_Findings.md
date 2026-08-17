# Aurora UI-08→UI-11 Second-Pass Deep Stabilization Review

**Review target:** `Aurora_08-11_SecondPass.zip`  
**Baseline:** UI-03→07 accepted checkpoint `64ed03e`  
**Purpose:** Second stabilization gate before UI-12 / visual polish  
**Overall verdict:** **SUBSTANTIALLY IMPROVED, BUT CHANGES STILL REQUIRED BEFORE POLISH**

---

# Executive Summary

This second pass is a **real improvement** over the first UI-08→11 implementation.

Many previously reported problems are genuinely fixed end to end:

- New Show now exits Welcome and opens a real empty Build workspace.
- MIDI health is structured instead of inferred from a string.
- Zero MIDI sources no longer mean green/healthy.
- MIDI inventory changes can update health on hotplug.
- Null output no longer counts as successful physical/network output.
- Patch now has search, presentation-only sorting, detailed overlap presentation, repatch, and atomic bulk offset.
- `BulkRepatchCommand` preflights the complete final patch before mutation.
- Diagnostics now has a real semantic snapshot type and published controller state.
- Remote Settings now owns enable/bind/ports/PIN more coherently.
- Remote startup is configured before listener start.
- Persisted Remote-enable state is restored at application startup.
- Web and TCP ports are both configurable.
- The shipped web remote now uses semantic CURRENT/NEXT and a GO-dominant layout.
- The web client now supplies request IDs.
- Request-ID reservation is atomic.
- Remote Programmer writes remain denied.
- Browser protocol version is sent and checked.
- UI-11 has named layout menu wiring, persisted layout models, visibility APIs, safe geometry clamps, and shutdown flush support.

This is no longer a case where entire phases are missing.

However, several **second-order correctness and truthfulness bugs** remain. These are exactly the kinds of problems that appear only after the basic feature exists:

1. Remote listener startup still reports success before Network.framework has actually reached `.ready`.
2. Diagnostics is only refreshed manually/on appearance, so its "live" status can become stale immediately.
3. Diagnostics currently confuses requested Local DMX state with actual Local DMX state and uses aggregate output health for every universe route.
4. HTTP remote polling does not refresh session activity, so a perfectly active monitoring client can later be reclaimed as idle.
5. The browser does not truly recover from server restart/token invalidation.
6. Remote command acknowledgements still report `snapshotRevision = 0` rather than meaningful resulting state.
7. UI-11 still does not capture real HSplitView divider movement; the persistence API exists but the live splitter never calls it.
8. The "Diagnostics" named layout selects a lower-panel type the actual Build lower region cannot render, so it falls back to Cues.
9. Workspace tool state and persisted layout state can diverge after document replacement.
10. Patch validation still does not visually expose all important invalid states such as out-of-bounds footprint/missing fixture definition.
11. A few settings still silently coerce invalid values or store security-sensitive PIN material in ordinary UserDefaults.

These should be resolved before UI-12, because UI polish on top of stale or misleading runtime semantics will make later fixes harder.

---

# Review Verification

## Static Swift parse

All production Swift files were parsed individually with:

```text
swiftc -frontend -parse
```

Result:

```text
213 production Swift files parsed
0 syntax failures
```

## Diff check

`git diff --check` found one documentation whitespace issue:

```text
docs/PROJECT_HANDOFF.md:57: trailing whitespace
```

Not a functional blocker, but clean it before checkpoint.

## Full tests

`swift test` was attempted.

Compilation progresses deeply through Aurora, then stops because this review environment is Linux and does not provide:

```text
Network
CoreMIDI
```

Representative failures:

```text
no such module 'Network'
no such module 'CoreMIDI'
```

Therefore macOS test claims cannot be independently reproduced here.

**Required after this fix pass:**

```text
full swift test on macOS
Xcode Debug build
manual remote/network/layout smoke
```

---

# Previous First-Pass Findings — Current Status

## ST-01 MIDI always green

**FIXED IN ARCHITECTURE**

`MIDIHealthSnapshot` now models:

```text
off
ready
warning
failed
```

and:

```text
running + 0 sources → off
running + >=1 source → ready
```

Toolbar/status/Perform consume the structured snapshot.

## ST-02 Null output green

**FIXED**

`NullOutputDriver` now reports:

```text
OutputHealthState.disabled
```

and disabled-only drivers are excluded from healthy aggregate output.

## DOC-01 New Show appears to do nothing

**FIXED**

Welcome is explicit:

```text
WorkspaceController.showsWelcomeScreen
```

New/Open/Demo call:

```text
enterDocumentWorkspace()
```

An empty active Show no longer implies Welcome.

## UI-09 basic Patch only

**MOSTLY FIXED**

Patch now includes:

```text
search
sort
sort direction
overlap details
bulk offset
atomic BulkRepatchCommand
route footer
```

Additional validation truthfulness remains; see PATCH-01.

## UI-10 old web client

**FIXED SUBSTANTIALLY**

The shipped web UI now has:

```text
CURRENT
NEXT
GO
Back
Stop
Song previous/next
health
request IDs
protocol version
empty PIN field
```

## Remote request-ID race

**FIXED AT BASIC RESERVATION LEVEL**

`reserveRequestId` atomically creates `.inFlight`.

Only `.execute` may run the action.

Additional lifecycle/retention issues remain; see REM-04.

## UI-11 no menu wiring

**PARTIALLY FIXED**

Named layouts and panel visibility are now exposed through the View menu.

Actual divider capture and Diagnostics-layout mismatch remain.

---

# P0 — Runtime Truth / Remote Reliability

## REM-01 — Remote reports "running" before listeners are actually ready

### Severity

**P0 for truthful remote operation**

### Files

```text
Sources/Aurora/Controllers/RemoteController.swift
Sources/AuroraRemote/RemoteHost.swift
Sources/AuroraRemote/RemoteWebServer.swift
```

### Current behavior

`RemoteController.setRemoteEnabled()` does:

```text
try remoteHost.start()
try web.start()
isActuallyRunning = true
remoteStatus = "Remote on ..."
```

This looks transactional, but Network.framework listener startup is asynchronous.

`NWListener.start(queue:)` returns before the listener has transitioned to:

```text
.ready
```

Port conflicts and some network failures arrive later through:

```text
listener.stateUpdateHandler
```

`RemoteHost` does have a state handler, but on failure it only changes its private `_isRunning`.

`RemoteWebServer` currently does **not** expose equivalent state failure to `RemoteController`.

Therefore this sequence is possible:

```text
RemoteController calls start()
→ both start() methods return
→ UI says Runtime: running
→ listener asynchronously fails because port is in use
→ controller still says running
```

It can also produce split truth:

```text
TCP dead
Web alive

or

TCP alive
Web dead
```

while the aggregate UI still claims Remote is running.

### Required fix

Promote listener lifecycle into explicit semantic state.

Conceptually:

```swift
enum RemoteListenerState {
    case stopped
    case starting
    case ready(boundEndpoint: String)
    case failed(String)
}
```

Both:

```text
RemoteHost
RemoteWebServer
```

should report:

```text
starting
ready
failed
stopped
```

to `RemoteController`.

`RemoteController.isActuallyRunning` should mean:

```text
required listener set is actually .ready
```

not merely:

```text
start() was called without synchronous throw
```

### Startup semantics

Preferred:

```text
requestedEnabled = true
TCP → starting
Web → starting

both ready
→ actualRunning = true

either fails
→ stop both
→ actualRunning = false
→ status = precise failure
```

If partial service is intentionally supported later, represent it explicitly. Do not silently operate half-started today.

### Tests

Inject listener lifecycle/factory behavior and verify:

```text
TCP ready + Web ready → running
TCP failed → both stopped, not running
Web failed → TCP stopped, not running
late async failure after initial start → controller updates to failed
port conflict → UI never remains "running"
```

### Manual test

```text
occupy TCP configured port
enable Remote
verify actual runtime reports failure

occupy Web port
enable Remote
verify both listeners end stopped
```

---

## REM-02 — Active HTTP polling does not refresh remote session activity

### Files

```text
Sources/AuroraRemote/RemoteWebServer.swift
Sources/AuroraRemote/RemoteSessionManager.swift
```

### Current behavior

`RemoteSessionManager` tracks:

```text
lastSeenAt
sessionIdleTTL = 120 sec
```

`authorize()` updates `lastSeenAt` when a command is executed.

But normal web monitoring polls:

```text
GET /api/snapshot
```

every 250 ms.

`handleSnapshot()` resolves the token and returns data but does **not** call:

```swift
sessions.touch(sessionId:)
```

So a web client can be continuously alive and watching the show for ten minutes while its server-side `lastSeenAt` remains the original login time.

Idle reclamation happens when another hello is processed.

Therefore:

```text
iPad A logs in
iPad A watches show for >120 sec without pressing anything
iPad B logs in
reclaimInactiveLocked() runs
iPad A is considered stale and removed
iPad A's next snapshot becomes unauthorized
```

That is incorrect session-liveness behavior.

### Required fix

Authenticated activity should refresh session activity.

At minimum:

```text
successful /api/snapshot
successful /api/command
TCP ping
TCP command
```

should touch the session.

Possible centralized approach:

```swift
sessionID(forToken:touching:)
```

or call:

```swift
sessions.touch(...)
```

after successful token validation.

### Tests

```text
snapshot activity refreshes lastSeenAt
active polling client is not reclaimed
truly idle client is reclaimed
command activity refreshes TTL
```

---

## REM-03 — Web client does not truly reconnect after server restart/token invalidation

### File

```text
Sources/AuroraRemote/Resources/Web/index.html
```

### Current behavior

`poll()` catches snapshot errors and then continues polling with the same token.

This handles a brief Wi-Fi outage **if the Mac server never restarted and the token remains valid**.

It does not handle:

```text
Remote Apply/Restart
Mac server restart
PIN regeneration
Kick All
server token invalidation
```

After those events:

```text
/api/snapshot → 401
poll continues forever with same dead token
UI says "Snapshot error"
```

The browser never returns to authentication or establishes a new session.

### Required fix

Distinguish:

```text
temporary transport/network failure
```

from:

```text
401/403 invalid session
protocol mismatch
server restart
```

For authorization/session loss:

```text
clear token
show auth card
hide operator controls
preserve entered PIN only if product intentionally wants that
require/reperform hello
```

For temporary network failure:

```text
retry snapshot
do not replay mutating commands
```

### Acceptance

```text
server restart → web UI returns to reconnect/auth state
Kick All → client visibly loses control
PIN regeneration → old client loses authorization
Wi-Fi blip → snapshot polling recovers without replaying GO
```

---

## REM-04 — Request-ID retention is not robustly ordered and is not cleared with session teardown

### File

```text
Sources/AuroraRemote/RemoteSessionManager.swift
```

### Current structure

```swift
recentRequestResults: [UUID: [String: RequestIdRecord]]
maxRecentRequestIds = 64
```

Trimming uses:

```swift
Array(map.keys.suffix(maxRecentRequestIds))
```

A Swift `Dictionary` is not an insertion-ordered request log contract.

Therefore this is not a deterministic "retain most recent 64 request IDs" implementation.

It may retain/drop arbitrary entries.

Also session cleanup paths remove:

```text
clients
command timestamps
tokens
```

but do not consistently remove:

```text
recentRequestResults[sessionId]
```

on:

```text
disconnect
kick
kickAll
reclaimInactive
```

That creates unnecessary retained state and makes the intended dedupe lifetime unclear.

### Why this matters

At-most-once dedupe is a safety mechanism.

Its retention policy should be deliberate and deterministic.

### Required fix

Use an explicit bounded ordered structure.

Example concept:

```text
per session:
  dictionary requestId → record
  ordered queue/deque of request IDs
```

On insert:

```text
append ID
if count > N:
    evict oldest completed ID
```

Do not evict an in-flight reservation solely to satisfy capacity.

On session teardown:

```text
remove all request dedupe state
```

### Tests

```text
oldest completed request evicted deterministically
newest request retained
in-flight request not accidentally evicted
disconnect clears request cache
kick clears request cache
idle reclaim clears request cache
```

---

## REM-05 — Command acknowledgement revision is still fake (`0`)

### Files

```text
Sources/AuroraRemote/RemoteHost.swift
Sources/AuroraRemote/RemoteWebServer.swift
Sources/AuroraRemote/RemoteMessages.swift
```

### Current TCP response

Every command returns:

```text
snapshotRevision: 0
```

including successful GO.

HTTP command responses do not include a meaningful resulting revision either.

The protocol type promises:

```text
snapshotRevision
```

but the runtime does not populate it.

### Required fix

Either:

### Option A — Implement the field truthfully

After command dispatch, return a meaningful server revision associated with current state.

or:

### Option B — Remove the field for now

Do not ship a field that appears meaningful but is always fake.

Given the current snapshot system already has monotonic revisions, implementing truth is preferable.

### Async song navigation caveat

`RemoteController` handles:

```text
songNext
songPrevious
```

by hopping to MainActor asynchronously.

Do not acknowledge a resulting state revision before the action has actually applied if the protocol claims it reflects resulting state.

---

# P0 — Diagnostics Is Still Not Live/Truthful Enough

## DIAG-01 — Diagnostics snapshot goes stale unless user presses Refresh

### Files

```text
Sources/Aurora/Controllers/DiagnosticsController.swift
Sources/Aurora/AppModel.swift
Sources/Aurora/Settings/AuroraSettingsRoot.swift
```

### Current behavior

Diagnostics snapshot is published:

```text
once during AppModel init
on Settings Advanced onAppear
when user presses Refresh
```

There is no diagnostics timer, controller subscriptions, or on-change pipeline.

Therefore the "operator diagnostics" section can instantly become stale after:

```text
MIDI hotplug
output failure
Art-Net enable/disable
ENTTEC disconnect
Remote client connect/disconnect
Remote startup failure
universe route edit
engine state change
```

This does not satisfy the planned semantic live Diagnostics surface.

### Required fix

Diagnostics should update automatically.

Preferred:

```text
important state transitions → immediate/on-change refresh
rates/counters → throttled timer (e.g. 2–5 Hz)
```

Do not rebuild the snapshot in SwiftUI body.

A `DiagnosticsController` timer or subscription coordinator is appropriate.

### Acceptance

Open Advanced/Diagnostics and then:

```text
plug MIDI → updates
enable Art-Net → updates
disconnect local DMX → updates
connect remote client → client count/status updates
edit route → route updates
```

without pressing Refresh.

---

## DIAG-02 — Local DMX "enabled" uses requested state, not actual state

### File

```text
Sources/Aurora/AppModel.swift
```

`buildDiagnosticsSnapshot()` currently sets:

```swift
localDMXStatus: settings.localDMX.requestedEnabled ? "requested" : "off",
localDMXEnabled: settings.localDMX.requestedEnabled,
```

This is explicitly the **preference/request**, not runtime truth.

Example:

```text
operator requested Local DMX
ENTTEC unplugged
actual driver unavailable
```

Diagnostics says:

```text
Local DMX enabled/requested
```

instead of distinguishing:

```text
requested: yes
actual: no
configured device unavailable
```

### Required fix

Diagnostics must include both dimensions where useful:

```text
requestedEnabled
actualEnabled
deviceAvailable
runtimeStatus
```

At minimum, `localDMXEnabled` must mean actual runtime enabled.

Use:

```text
output.localDMXEnabled
output.localDMXStatus
output.localDMXConfiguredDeviceAvailable
```

for runtime truth.

---

## DIAG-03 — Every universe gets the same aggregate output availability/health

### File

```text
Sources/Aurora/AppModel.swift
```

Current universe-row creation:

```swift
availability: out.aggregate.rawValue
runtimeHealth: out.statusLine
```

for **every** universe.

That means:

```text
U1 → Local DMX
U2 → Art-Net
U3 → None
```

can all display the same aggregate output state.

Worse:

```text
Art-Net ready
Local DMX disconnected
U1 configured Local
```

can make U1 inherit overall healthy output because some unrelated Art-Net driver is healthy.

This defeats the purpose of the routing diagnostics board.

### Required fix

Resolve each universe against its configured route.

Per-universe row should derive:

```text
configured route
matching driver(s)
matching driver enabled state
matching destination availability
matching driver health
```

For:

```text
.none
```

show explicitly Disabled/No Route.

For:

```text
.local
```

use Local DMX state only.

For:

```text
.artNet
```

use Art-Net only.

For:

```text
.sACN
```

use sACN only.

For:

```text
.mirror
```

show component state and aggregate:

```text
ready / degraded / failed
```

based on the configured mirror destinations.

### Tests

```text
Art-Net healthy does not make .local universe healthy
.none reports no route
.local missing device reports unavailable
mirror with one failed driver reports degraded/failed as designed
```

---

# P0 — UI-11 Layout Is Still Not Fully Connected to Real User Resizing

## LAYOUT-01 — Actual split divider movement is not persisted

### Files

```text
Sources/Aurora/Shell/BuildWorkspaceHost.swift
Sources/Aurora/Controllers/WorkspaceController.swift
```

### Current improvement

`BuildWorkspaceHost` now reads:

```text
leadingFraction
trailingFraction
bottomFraction
```

to calculate `idealWidth` / `idealHeight`.

Good.

### Remaining bug

`WorkspaceController.updateSplitFractions()` exists.

But there are **no call sites** from the live Build workspace.

`HSplitView` can be manually dragged by the user, but that actual divider position is never observed and never written back to:

```text
WorkspaceLayout
```

Therefore:

```text
user drags divider
→ visual split changes
→ layout model unchanged
→ quit
→ restart
→ old ideal fraction restored
```

The manual smoke requirement:

```text
Resize Build → restart → restore
```

is still not implemented.

### Required fix

Use a split-view implementation that exposes divider positions or otherwise observe the resulting pane geometry.

On divider change:

```text
calculate normalized fraction
→ workspace.updateSplitFractions(...)
→ debounced save
```

On drag end:

```text
immediate/flush save
```

Do not merely set ideal widths.

---

## LAYOUT-02 — "Diagnostics" named layout cannot actually select Diagnostics

### Files

```text
Sources/AuroraUI/Workspace/WorkspaceLayout.swift
Sources/Aurora/Controllers/WorkspaceController.swift
Sources/Aurora/Shell/BuildWorkspaceHost.swift
```

### Current preset

Diagnostics preset uses:

```text
bottomTab = .console
visible console + universeMonitor
```

### Actual Build lower tools

`BuildLowerTool` only supports:

```text
Palettes
Cues
Song
```

`BuildLowerTool.fromLayoutTab(.console)` falls through to:

```text
.cues
```

Therefore:

```text
View → Layouts → Diagnostics
```

does not display Diagnostics.

It displays Cues.

The layout metadata says Console, but the actual host cannot render it.

### Required fix

Choose one coherent product model.

Recommended:

Expand Build lower tools to support an actual Diagnostics tool, e.g.:

```text
Palettes
Cues
Song
Diagnostics
```

and host a proper Diagnostics surface there.

That would also solve the current problem where Diagnostics primarily lives in Settings.

Alternative:

Remove the Diagnostics named layout until there is a real Diagnostics Build tool.

Do not leave a preset that lies.

---

## LAYOUT-03 — Visibility model includes panel IDs the current shell does not independently host

The layout visibility set still contains legacy/general panel IDs such as:

```text
console
universeMonitor
midi
effects
livePlayback
```

but current Option-A `BuildWorkspaceHost` has only coarse regions:

```text
left: Browser/Patch/Groups
center: Programmer
right: Inspector
lower: Palettes/Cues/Song
```

Some visibility entries therefore have no direct rendered panel effect.

Example:

```text
.universeMonitor visible
```

does not make Build show a Universe Monitor.

### Required fix

Align persisted layout semantics with current shell capabilities.

Prefer region/tool semantics that the host can actually render.

Avoid persisting meaningful-looking flags with no UI manifestation.

---

## LAYOUT-04 — Document replacement can desynchronize active tools from persisted layout

### Files

```text
Sources/Aurora/Controllers/WorkspaceController.swift
```

`didReplaceDocument()` resets:

```text
leftTool = .browser
lowerTool = .cues
```

but does not update:

```text
layout.leadingTab
layout.bottomTab
```

Since layout is now explicitly app-level/persistent state, this creates divergence.

Example:

```text
apply Patch layout
layout.leadingTab = .patch

New Show
leftTool becomes .browser
layout.leadingTab remains .patch

quit/relaunch
leftTool restores .patch
```

The UI and persisted state disagree during the current session.

### Required decision

Either:

### Option A — Workspace layout persists across document replacement

Then do not reset layout-controlled tools on New/Open/Demo.

or:

### Option B — New/Open resets the layout

Then update and persist the corresponding layout fields too.

Do not maintain two conflicting truths.

Given UI-11 defines layout as application preference, **Option A is preferable**.

---

# P1 — Patch Validation Is Better, But Still Incomplete

## PATCH-01 — Existing invalid patch states are not fully surfaced

### File

```text
Sources/AuroraUI/Panels/PatchPanel.swift
```

Current banner only displays:

```text
overlapping patch ranges
```

The UI-09 scope also called for visible:

```text
out-of-bounds footprint
missing fixture definition/personality
invalid universe
other placement errors
```

Current table may show:

```text
Personality = —
End > 512
```

but does not explicitly label those rows invalid.

### Required fix

Create a patch-row validation projection.

For each fixture report issues such as:

```text
missing definition
footprint past channel 512
universe missing
address invalid
overlap
```

Use row chrome + concise issue summary.

Do not rely only on the repatch command rejecting future changes; operators must be able to understand an already-invalid show.

### Useful structure

```swift
struct PatchRowIssue {
    fixtureID
    severity
    message
}
```

The Patch UI can then show:

```text
warning icon
orange/red row
issue popover/banner
```

---

## PATCH-02 — Bulk preflight currently validates every fixture in the whole project

### File

```text
Sources/AuroraCore/Commands/BulkRepatchCommand.swift
```

Current preflight loops:

```swift
for fx in proposed.fixtures {
    try PatchValidator.validatePlacement(...)
}
```

This guarantees the **entire final project** is valid before any bulk repatch.

That is very safe for clean projects.

But it also means if a loaded/legacy show already contains an unrelated invalid fixture:

```text
Fixture Z missing definition
```

then trying to repair Fixture A may fail because Fixture Z remains invalid.

### Recommendation

Clarify intended recovery semantics.

A robust patch editor often needs to repair an invalid document incrementally.

Consider validating:

```text
all changed fixtures
+
all fixtures whose overlap/placement relationship is affected by the changes
```

while separately surfacing pre-existing unrelated validation issues.

Do not weaken final overlap safety.

This is not necessarily a blocker if Aurora guarantees invalid patch state can never be loaded, but current product validation suggests legacy/broken shows can exist.

Document the rule and test it.

---

# P1 — Remote Result / Client UX Hardening

## REM-06 — Web command retry treats all failures as retryable

### File

```text
Sources/AuroraRemote/Resources/Web/index.html
```

Current:

```javascript
try command
catch
    retry same requestId once
```

This is safe with respect to duplicate GO because request ID is reused.

But it retries:

```text
401 Unauthorized
403 not authorized
400 bad command
protocol/configuration failures
```

as though they were network failures.

### Required fix

Only retry transport-level or clearly transient failures.

For:

```text
401
403
protocol mismatch
validation error
```

do not retry.

Transition UI to the appropriate state.

---

## REM-07 — HTTP session polling/client count can remain stale without central cleanup timer

Session reclaim currently happens primarily around hello/reconnect.

Even after adding activity touch, stale sessions that simply disappear may remain until some later operation triggers reclamation.

### Recommendation

Have the Remote controller/session manager periodically reclaim idle sessions as part of the existing remote status/snapshot timer.

Then:

```text
client count
tokens
dedupe cache
```

self-heal without requiring a new login attempt.

---

# P1 — Security / Settings Truth

## SEC-01 — Remote PIN is still persisted in plaintext UserDefaults

### File

```text
Sources/Aurora/Controllers/AppSettingsStore.swift
```

Current:

```text
remotePIN
→ UserDefaults
```

This PIN authorizes live show control.

It is no longer logged, which is good.

But ordinary UserDefaults is not an appropriate long-term credential store.

### Required before product release

Move the PIN to:

```text
Keychain
```

or another appropriate secure credential store.

Settings can still display/regenerate it if product design requires.

If intentionally deferred beyond this stabilization pass, mark it explicitly as a **pre-release security blocker**, not polish.

---

## SET-01 — Remote port fields silently clamp invalid operator input

Current setters do:

```text
max(1, min(65535, input))
```

The UI-08 requirements specifically preferred validation over silent coercion.

Example:

```text
user enters 99999
Aurora silently stores 65535
```

### Required fix

Use draft text/int input plus validation.

Show:

```text
Port must be 1–65535
```

and do not apply until valid.

Do the same for any host/address fields where invalid configuration can create confusing runtime failures.

---

# P1 — Diagnostics Should Become the Shared Semantic Health Authority

The toolbar/status fixes are now good.

Do not reintroduce parallel health interpretation in Diagnostics.

Recommended consolidation:

```text
Output/MIDI/Remote semantic state
          ↓
shared typed projections
          ├─ toolbar
          ├─ status bar
          ├─ Perform
          └─ Diagnostics
```

`DiagnosticsSnapshot` should not downgrade typed state into free-form strings too early.

For example, prefer:

```text
MIDI state enum + count
```

over only:

```text
"MIDI: 2 sources"
```

This will simplify future UI polish and accessibility.

---

# P2 — Implementation / Cleanup Findings

## CLEAN-01 — `DiagnosticsController.publishSnapshot()` manually sends objectWillChange after @Published assignment

Current:

```swift
snapshot = snap
objectWillChange.send()
```

`@Published` already emits.

Remove redundant manual publish unless there is a proven special reason.

Similar redundant sends remain in some controller paths.

Do not make this a wide architecture cleanup now; fix obvious duplicates in touched code.

---

## CLEAN-02 — `InputController` has several redundant manual objectWillChange sends after @Published mutations

Not a blocker, but the structured health work is already touching this area.

Avoid double invalidation where practical.

---

## CLEAN-03 — Documentation whitespace

Fix:

```text
docs/PROJECT_HANDOFF.md line 57 trailing spaces
```

so:

```text
git diff --check
```

is clean before checkpoint.

---

# UI-11 Product Recommendation — Make Diagnostics a Real Build Tool

This is technically a design choice, but it solves multiple current inconsistencies at once.

The cleanest current workspace model would be:

```text
LEFT
Browser | Patch | Groups

CENTER
Programmer

RIGHT
Inspector

LOWER
Palettes | Cues | Song | Diagnostics
```

Then the Diagnostics named layout can truthfully select:

```text
lowerTool = Diagnostics
```

and render:

```text
driver health
universe route health
MIDI
Remote clients
validation
console/recent errors
```

This is more coherent than hiding operator diagnostics primarily inside Settings.

Keep Perform fixed.

---

# Tests Required for Third Pass

## Remote listener truth

```text
TCP async ready
Web async ready
TCP late failure
Web late failure
port collision
partial failure tears down both
actualRunning only true when required listeners ready
```

## Session liveness

```text
HTTP snapshot touches session
active polling client not reclaimed
idle client reclaimed
kick/disconnect clears dedupe state
```

## Request retention

```text
deterministic oldest-completed eviction
in-flight request protected
session cleanup removes request cache
```

## Command acknowledgement

```text
successful command returns meaningful revision
duplicate returns same completed result/revision
async song action ack reflects completed application or explicitly does not claim revision
```

## Diagnostics

```text
actual Local DMX false when requested but unavailable
per-universe local health ignores healthy Art-Net
.none reports not routed
mirror reports component truth
MIDI hotplug refreshes diagnostics automatically
Remote client connect/disconnect refreshes automatically
```

## Layout

```text
real divider movement updates layout fraction
persist/relaunch restores real divider position
Diagnostics named layout displays Diagnostics, not Cues
document replacement does not desync active tool vs stored layout
```

## Patch

```text
OOB footprint visible in row validation
missing definition visible
missing universe visible
legacy unrelated invalid fixture recovery behavior documented/tested
```

## Settings validation

```text
invalid TCP/Web port rejected visibly
valid port applies
```

---

# Manual macOS "Kick the Tires" Checklist

## New Show / shell

```text
[ ] launch to Welcome
[ ] New Show → Build immediately
[ ] New empty Show can add Universe/fixtures
[ ] save/reopen empty Show stays Build, not Welcome
```

## MIDI / Output health

```text
[ ] no MIDI devices → not green
[ ] plug MIDI → health changes without sending note
[ ] unplug → health changes
[ ] Null only → Output off
[ ] Art-Net ready → Output green
[ ] ENTTEC ready → Output green
[ ] disconnect ENTTEC → health changes promptly
```

## Remote startup truth

```text
[ ] occupy TCP port, enable Remote → runtime shows failed
[ ] occupy Web port, enable Remote → both services end stopped
[ ] change port + Apply → actual bound endpoint changes
[ ] Remote menu and Settings stay synchronized
```

## Remote client

```text
[ ] connect iPad
[ ] watch >3 minutes without commands
[ ] connect second client
[ ] first client remains valid
[ ] GO once → exactly one cue
[ ] kill Wi-Fi during GO → no double fire
[ ] restart Remote server → browser returns to reconnect/auth state
[ ] Kick All → browser loses operator access visibly
```

## Diagnostics

```text
[ ] open Diagnostics
[ ] toggle Art-Net without pressing Refresh → updates
[ ] unplug ENTTEC → correct local state updates
[ ] connect MIDI → updates
[ ] connect remote client → connected count updates
[ ] U1 Local does not inherit health from unrelated Art-Net
```

## Patch

```text
[ ] search fixtures
[ ] sort by name/address/end
[ ] sort does not change document order
[ ] overlap details identify fixtures
[ ] create/inspect OOB fixture condition
[ ] missing definition visibly reported
[ ] bulk offset multiple fixtures
[ ] Undo restores all
```

## Layout

```text
[ ] View → Layouts → Programming
[ ] Patch
[ ] Song
[ ] Diagnostics actually shows diagnostics
[ ] drag left divider
[ ] drag inspector divider
[ ] resize lower region
[ ] quit immediately
[ ] relaunch → exact/near-exact layout restored
[ ] New Show does not unexpectedly change persistent workspace layout
[ ] Perform always remains fixed and GO reachable
```

---

# Recommended Fix Order

```text
1. REM-01 async listener readiness/failure propagation
2. REM-02 session activity touch
3. REM-03 real reconnect/auth recovery
4. DIAG-01 automatic diagnostics updates
5. DIAG-02 actual vs requested Local DMX
6. DIAG-03 per-universe route-specific health
7. LAYOUT-01 real splitter persistence
8. LAYOUT-02 make Diagnostics layout real
9. LAYOUT-03/04 align layout model with current shell + document replacement
10. REM-04 deterministic dedupe retention/cleanup
11. REM-05 meaningful command revision
12. PATCH-01 complete invalid-patch visibility
13. SET-01 validation
14. SEC-01 Keychain or explicit pre-release security blocker
15. cleanup/documentation
16. macOS full test + Xcode
17. manual abuse test
18. deep review again
```

---

# Final Gate

## Current verdict

**DO NOT MOVE TO UI-12 YET.**

This second pass is significantly closer.

The first-pass foundational holes are mostly closed.

The remaining issues are now the more valuable kind to find before polish:

```text
async runtime lies
stale semantic projections
session lifecycle edge cases
layout persistence not connected to real interaction
named layout/model mismatches
route-specific diagnostic truth
```

Those should be corrected while the implementation is still structurally fresh.

## Architectural verdict

**KEEP THE CURRENT ARCHITECTURE.**

No broad rewrite is requested.

## Next target

After the fixes above:

```text
UI-08→11 should be functionally complete
→ run final stabilization review
→ only then begin UI-12 Product Polish
```

The goal for the next pass is not "add more features."

It is:

> **Make every existing control, status, remote action, diagnostics row, and persisted layout mean exactly what it says.**
