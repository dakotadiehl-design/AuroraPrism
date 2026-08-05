# Aurora Deep Code Review — Required Fixes Before UI Phase

**Review date:** 2026-08-05  
**Repository reviewed:** `Aurora(1).zip`  
**HEAD:** `068e161` — *Refresh handoff next-work and git arc after full roadmap*  
**Scope:** Full static review of the repository through PR34, including model, core, engine, MIDI/RTP-MIDI/OSC, output, fixture library, remote control, plugins, UI shell, tests, and design documentation. Linux-vs-macOS build limitations were intentionally treated as environmental rather than Aurora defects unless they exposed an architectural issue.

---

## Executive Summary

Aurora is in much better shape than the speed of implementation would suggest. The codebase still reflects the intended modular design:

```text
AuroraModel
    ↓
AuroraCore / AuroraEngine / AuroraFixtureLib
    ↓
AuroraOutput / AuroraMIDI / AuroraRemote
    ↓
AuroraUI
    ↓
Aurora app target
```

The repository is approximately 13.6k lines of Swift/test code, has a clean incremental Git history through PR34, and retains meaningful module boundaries. The engine, output abstraction, cue model, palette-reference model, MIDI parsing, and remote protocol are real implementations rather than UI-only scaffolding.

However, several issues should be fixed **before Aurora is trusted with a live show** and preferably before the UI overhaul begins. The highest-risk issues are:

1. **Saving an existing `.aurora` project is destructive and non-atomic.** It can erase the existing package before the new package is safely written, and it currently recreates an empty `media/` directory, risking media loss.
2. **There is no reliable saved/dirty-state model and no unsaved-changes protection.** Saving never clears `isDirty`, and New/Open/Quit can discard work without a save prompt.
3. **Removed universes can continue transmitting stale DMX.** `OutputManager` retains universe buffers forever and `LightingEngine.load(project:)` never reconciles removed universes.
4. **Cue-only behavior does not match the design intent stated in the master architecture.** A cue-only target currently resolves only its stored values, allowing unspecified attributes to fall back to defaults/home instead of preserving the previous stage look.
5. **MIDI control currently jumps to `MainActor` before invoking show actions.** That conflicts with Aurora's own low-latency architecture goal and can make drum-triggered lighting sensitive to UI load.
6. **Remote control binds broadly, ships with an obvious `0000` PIN workflow, uses cleartext HTTP/TCP, and lacks authentication-attempt rate limiting.** This is acceptable as a development scaffold but not yet a safe venue-network feature.

None of these require a rewrite. The architecture is good enough that each can be corrected in its owning subsystem.

---

# Priority Definitions

| Priority | Meaning |
|---|---|
| **P0** | Fix before trusting Aurora with real show/project data or live DMX |
| **P1** | Fix before serious rehearsal/beta use; important correctness, latency, or architecture issue |
| **P2** | Harden during/after UI work; quality, maintainability, validation, diagnostics |
| **P3** | Nice-to-have / future expansion |

---

# P0 — Must Fix Before Live Use

## P0-1 — Project save is destructive and non-atomic

**Files:**
- `Sources/AuroraModel/ProjectPackage.swift:68-109`
- `Sources/Aurora/AppModel.swift` save path

Current behavior:

```swift
if fm.fileExists(atPath: url.path) {
    try fm.removeItem(at: url)
}

try fm.createDirectory(at: url, ...)
// write files...
```

The existing show is deleted **before** the replacement is known to be writable and complete.

### Failure scenario

1. User has `Haywire.aurora` containing a valid show.
2. User presses Save.
3. Aurora deletes `Haywire.aurora`.
4. Disk write fails, process crashes, disk fills, permission changes, or a JSON write throws.
5. The previous valid show is already gone.

This violates the reliability goal for mission-critical live software.

### Required fix

Implement transactional/atomic package saving:

```text
Haywire.aurora
      ↓
write Haywire.aurora.tmp-<UUID>
      ↓
validate complete temporary package
      ↓
fsync/close as practical
      ↓
atomically replace Haywire.aurora
      ↓
remove backup/temp only after success
```

On macOS, prefer `FileManager.replaceItemAt(...)` or another filesystem-atomic replacement strategy. Preserve the original package until the replacement is complete.

### Required tests

- Existing valid package survives an injected write failure.
- Successful save replaces the old package.
- Temporary package cleanup occurs after failure.
- Save to a new destination works.
- Saving repeatedly does not lose ancillary package contents.

---

## P0-2 — Existing `media/` and other package-owned files can be erased on Save

**File:** `Sources/AuroraModel/ProjectPackage.swift:71-78`

The save process deletes the package and recreates:

```text
media/
layouts/
```

as empty directories. `MediaAssetRef` metadata is serialized, but the binary media files are not copied into the newly-created package.

If a future or current show actually contains files in `media/`, pressing Save can destroy them while leaving stale `MediaAssetRef` entries behind.

### Required fix

The transactional save implementation must explicitly preserve/copy package-managed binary content. A strong design is:

```text
Temporary package
├── freshly encoded model JSON
├── cues/
├── media/       ← copied/managed from current project package
└── layouts/     ← copied or freshly serialized
```

Longer term, media import/removal should be owned by `ProjectPackage` or a dedicated project asset manager rather than treated as an incidental folder.

### Required tests

- Add a known binary file under `media/`, save project, verify byte-for-byte preservation.
- Save As copies media into the new package.
- Removed media assets can intentionally remove their corresponding files.

---

## P0-3 — No proper save-point / dirty-state semantics

**Files:**
- `Sources/AuroraCore/DocumentSession.swift:9-10, 50-120`
- `Sources/Aurora/AppModel.swift:119-120` and save methods

`DocumentSession.isDirty` is set to `true` after mutations, undo, and redo, but is never reset after a successful save.

There is no `markSaved()` or save revision identifier.

Consequences:

- Window can continue showing `Edited` after a successful save.
- Aurora cannot tell whether an undo returned the document exactly to its saved state.
- Save/quit logic has no reliable baseline.

### Required fix

Prefer a revision/save-point design rather than a mutable Boolean only.

Example concept:

```swift
var currentRevision: UInt64
var savedRevision: UInt64
var isDirty: Bool { currentRevision != savedRevision }
```

A command/undo/redo changes the logical revision state. Successful Save marks the current state as the saved state.

If revision identity is hard with undo branching, store a save-point token in the undo history or a stable state generation identifier.

### Required tests

- Edit → dirty.
- Save → clean.
- Edit → save → edit → dirty.
- Edit → save → edit → undo back to saved state → clean.
- Redo away from saved state → dirty.

---

## P0-4 — New/Open/Quit can discard unsaved work without confirmation

**Files:**
- `Sources/Aurora/AuroraApp.swift:5-13, 28-47`
- `Sources/Aurora/AppModel.swift` `newShow()` / `openShow()`

`applicationShouldTerminateAfterLastWindowClosed` returns true, while New/Open replace the active `DocumentSession`. There is no save/discard/cancel flow tied to dirty state.

For a lighting-programming application, losing hours of cue work because the operator pressed Cmd+O or closed the window is unacceptable.

### Required fix

Add a shared document-transition guard:

```text
if clean:
    proceed

if dirty:
    Save / Don't Save / Cancel
```

Use it for:

- New Show
- Open Show
- Close window
- Quit Aurora
- Potential future document switching

A true `NSDocument`/`DocumentGroup` architecture could provide some of this behavior eventually, but the current custom document session can implement it directly.

---

## P0-5 — Removed universes can keep transmitting stale DMX forever

**Files:**
- `Sources/AuroraOutput/OutputManager.swift`
- `Sources/AuroraEngine/LightingEngine.swift:54-73, 155-171`

`OutputManager` owns persistent universe buffers:

```swift
private var buffers: [UInt16: DMXBuffer] = [:]
```

`LightingEngine.load(project:)` only calls `ensureUniverse` for universes in the new project. It never removes buffers for universes that disappeared.

`processFrame()` later calls:

```swift
output.flushAll()
```

which flushes every buffer still held by `OutputManager`.

### Real failure scenario

1. Show A outputs nonzero data on Universe 4.
2. User opens Show B, which has only Universe 1.
3. Engine loads Show B.
4. Universe 4's old buffer remains in `OutputManager`.
5. `flushAll()` continues sending the stale Universe 4 frame even though Show B does not contain Universe 4.

This can leave fixtures lit or moving after a project change.

### Required fix

Add explicit universe reconciliation, for example:

```swift
output.reconcileUniverses(to: project.universes)
```

When a universe is removed:

1. Send an intentional blackout/zero frame to that universe if an output driver is active.
2. Optionally send several zero frames for network protocols where useful.
3. Remove the buffer.

Also add:

```swift
OutputManager.removeUniverse(...)
OutputManager.removeAllUniverses(...)
```

and call the appropriate method when opening/newing a project.

### Required tests

- Load project A with Universe 4 and nonzero data.
- Load project B without Universe 4.
- Verify the mock driver observes a zero/termination behavior and no further Universe 4 output.

---

## P0-6 — Cue-only semantics likely reset unstored attributes instead of preserving the previous look

**Files:**
- `Sources/AuroraEngine/CueResolver.swift:6-22`
- `Tests/AuroraEngineTests/CueResolverTests.swift`
- master system design §7.4

Current cue-only implementation:

```swift
if target.tracking == .cueOnly {
    let resolved = PaletteResolver.resolve(...)
    return LookMath.activeLook(from: resolved.levels)
}
```

The corresponding unit test explicitly expects the previous intensity to disappear:

```swift
XCTAssertNil(look.fixtureAttributes[f]?["intensity"])
```

However, the system design says cue-only/non-tracking should contribute its stored values while other values remain according to the existing playback state.

With the current resolver, an unstored attribute disappears from `ActiveLook`; `MergeStub` then supplies the channel's fixture default. In many fixtures that means intensity 0, pan/tilt home, open/default wheel slots, etc.

### Why this matters

A cue intended to change only color can unexpectedly reset intensity, position, beam, or other attributes.

### Required fix

First, explicitly settle Aurora's tracking semantics and document them. If the intended semantics are the system-design semantics, cue-only transition resolution needs both:

- the incoming/current resolved stage look, and
- the target cue's sparse values.

Conceptually:

```text
Cue-only target = previous live/resolved look
                + attributes explicitly stored in this cue
```

A later tracking cue should not necessarily inherit the cue-only contribution into its tracked history.

This suggests separating:

- **historical tracked state**, and
- **transition/live target state**

rather than expecting one stateless `CueResolver.resolveLook(cues:index:)` function to express both concepts.

### Required tests

Add golden sequences, not only individual resolver calls:

```text
Cue 1: intensity 50%                 (track)
Cue 2: color red                     (cue-only)
Cue 3: position center               (track)
```

Verify exactly what the stage should look like after each cue and after Back/Fire.

---

# P1 — Fix Before Rehearsal/Beta Use

## P1-1 — MIDI-to-lighting hot path unnecessarily depends on `MainActor`

**Files:**
- `Sources/AuroraMIDI/MIDIInputManager.swift:111-132`
- `Sources/Aurora/AppModel.swift:295-300, 382-400`

CoreMIDI callback:

```text
CoreMIDI callback
    ↓
MIDIInputManager handler
    ↓
Task { @MainActor ... }
    ↓
AppModel.handleMIDI
    ↓
ShowAction
    ↓
LightingEngine
```

Aurora's architecture explicitly calls for no `MainActor` on the MIDI→output hot path. The current implementation does the opposite.

Under normal conditions this may feel instantaneous. Under UI pressure, however, MIDI-triggered cue firing and drum-triggered lighting can wait behind SwiftUI/AppKit work.

### Required fix

Introduce a non-UI control router/action dispatcher.

Conceptually:

```text
CoreMIDI
   ↓
MIDI parser
   ↓
ControlActionRouter (thread-safe, non-main)
   ↓
LightingEngine / playback

                  ↘ UI notification/logging → MainActor
```

Model-mutating actions such as MIDI Learn may still need to cross to `MainActor`/`DocumentSession`, but live show actions should not.

### Required benchmark

Measure CoreMIDI callback timestamp → action accepted by engine, including under intentional MainActor load.

---

## P1-2 — MIDI source identity is lost, so mappings cannot reliably target a specific device

**Files:**
- `Sources/AuroraMIDI/MIDIInputManager.swift:111-124`
- `Sources/AuroraMIDI/MIDIEvent.swift`
- `Sources/AuroraModel/MIDIMapping.swift`

Every incoming CoreMIDI packet is parsed with:

```swift
sourceID: "coremidi"
```

The read callback is created at the input-port level, and the code does not preserve which endpoint generated each message.

Aurora's original MIDI architecture expects device mapping / multiple devices simultaneously. Two devices sending Note 36 on Channel 1 are currently indistinguishable.

### Required fix

Use CoreMIDI connection `refCon` or a per-source routing context when connecting sources so the parser receives a stable endpoint/device identifier.

Mappings should support an optional source/device ID:

```text
device = specific device | any
channel = 1
message = noteOn
note = 36
```

Stable identity should use CoreMIDI unique ID where available, not the ephemeral endpoint integer converted to `String`.

---

## P1-3 — CoreMIDI setup error path can leak a MIDI client

**File:** `Sources/AuroraMIDI/MIDIInputManager.swift:33-47`

If `MIDIClientCreateWithBlock` succeeds but `MIDIInputPortCreateWithBlock` fails, `start()` throws without disposing the newly-created MIDI client.

### Required fix

Use staged cleanup/defer or call `stop()` before throwing from partial initialization.

Also make `start()` robust against being called twice.

---

## P1-4 — Remote host does not enforce the documented “LAN/private interfaces only” rule

**Files:**
- `Sources/AuroraRemote/RemoteHost.swift:39-71`
- `Sources/AuroraRemote/RemoteWebServer.swift:52-72`
- `docs/design/aurora-system-design.md` security section

Both listeners are created on a port without constraining the local endpoint/interface.

That generally means Aurora listens on available interfaces, not specifically trusted/private venue interfaces.

### Required fix

Add explicit bind policy:

- loopback only
- selected interface
- private/LAN interfaces
- all interfaces only via explicit advanced opt-in

The Settings UI should show the actual addresses Aurora is listening on.

---

## P1-5 — Remote defaults to PIN `0000` and does not rate-limit authentication attempts

**Files:**
- `Sources/AuroraRemote/RemoteSessionManager.swift:25-47`
- `Sources/Aurora/AuroraApp.swift:107-111`

The menu literally enables Remote with PIN `0000`.

Command rate limiting exists **after authorization**, but repeated `/api/hello` attempts are not rate-limited.

### Required fix

- Generate a random per-session PIN when Remote is enabled, or require the operator to set one.
- Do not ship `0000` as the operational default.
- Rate-limit failed authentication by source/client or globally.
- Add temporary backoff after repeated failures.
- Display the PIN and listening address only in the Mac's Remote settings/status UI.

Cleartext LAN operation can remain an explicit v1 limitation if documented, but the default credential must not be trivial.

---

## P1-6 — Remote web tokens and session lifecycle can diverge

**Files:**
- `Sources/AuroraRemote/RemoteWebServer.swift:12, 127-136, 215-221`
- `Sources/AuroraRemote/RemoteSessionManager.swift`

The HTTP server maintains its own:

```swift
[String: UUID] // token → session id
```

`session(from:)` validates only whether the token exists in this dictionary. It does not verify that the corresponding session still exists in `RemoteSessionManager`.

`kickAllRemoteClients()` works around this by restarting the web server, but individual session invalidation is not structurally linked to token invalidation.

### Required fix

Centralize token ownership/session validity in `RemoteSessionManager`, or make `RemoteWebServer.session(from:)` verify the session is still active.

Provide explicit token invalidation on:

- kick
- disconnect
- remote disable
- role/session revocation
- PIN rotation

---

## P1-7 — Remote TCP hello path calls authentication twice on rejection

**File:** `Sources/AuroraRemote/RemoteHost.swift:146-180`

The code effectively does:

```swift
if let response = handleHello(...), response is welcome {
    ...
} else if let response = handleHello(...) {
    ...
}
```

Rejected hellos execute `handleHello` twice.

Today that is mostly harmless, but authentication functions should never be needlessly executed twice, particularly once failure counters/rate limiting are introduced.

### Required fix

Evaluate once and switch on the response.

---

## P1-8 — `AppModel` has become a 737-line God-object candidate

**File:** `Sources/Aurora/AppModel.swift`

`AppModel` now owns or directly coordinates:

- project/document lifecycle
- fixture import
- engine
- output manager
- Art-Net
- sACN
- CoreMIDI
- RTP-MIDI
- OSC
- MIDI Learn
- MIDI actions
- SongDirector
- plugin host
- remote TCP
- remote HTTP
- timers
- status polling
- console logs
- error dialogs
- workspace refreshes

This was acceptable during the rapid roadmap build, but UI mode will add considerably more state.

### Required fix before/during UI redesign

Split coordination into focused controllers/services, for example:

```text
AuroraAppModel / WorkspaceState
├── ProjectController
├── PlaybackControllerFacade / ShowControlRouter
├── MIDIController
├── OutputController
├── RemoteController
├── DiagnosticsStore
└── SettingsStore
```

Do not move engine logic into these controllers; they are app-level orchestration boundaries.

This refactor will make the UI redesign dramatically cleaner.

---

## P1-9 — Presets are modeled but not actually delivered as a usable PR20 feature

**Files:**
- `Sources/AuroraModel/Preset.swift`
- `Sources/AuroraCore/Commands/GroupCommands.swift`
- `Sources/AuroraUI/Panels/PalettesPanel.swift`

The repository has `Preset`, add/remove commands, serialization, and reference counting, but there is no meaningful preset creation/application workflow. Search results show presets are essentially unused outside the model/commands/serialization/reference checks.

PR20's design note says:

> Group/palette/preset CRUD commands + panels

The implementation is therefore only partially complete from a product perspective.

### Required fix

Before calling PR20 fully product-complete, define and implement:

- create preset from programmer/current selection
- rename/update/delete preset
- apply preset to programmer
- palette references inside presets
- deterministic literal-vs-reference resolution
- tests for preset application and palette propagation

The UI can be redesigned later, but the underlying preset behavior should exist now.

---

## P1-10 — Palette-reference validation checks existence but not compatibility

**Files:**
- `Sources/AuroraEngine/PaletteResolver.swift`
- `Sources/AuroraModel/ResolutionIssue.swift`

`paletteRefs` are stored as:

```text
String key → Palette UUID
```

A `color` slot can technically reference an intensity palette, a malformed project can reference multiple palettes that write overlapping attribute keys, and resolution order for conflicting dictionary entries is not a strong semantic contract.

### Required fix

Introduce validation for:

- palette type compatible with reference slot/family
- referenced attributes valid for the intended family
- deterministic conflict rule
- invalid reference produces a `ResolutionIssue`, not silent behavior

Consider replacing raw string family keys with a typed `PaletteReferenceSlot`/`PaletteType` where possible.

---

## P1-11 — Resolution issues are generated but dropped by cue playback

**Files:**
- `Sources/AuroraEngine/PaletteResolver.swift`
- `Sources/AuroraEngine/CueResolver.swift`

`PaletteResolver.resolve` returns both resolved levels and `[ResolutionIssue]`, but `CueResolver` discards the issues.

The UI can call `ShowProject.validateReferences()`, but the live engine does not surface runtime resolution errors.

### Required fix

Expose engine/project validation diagnostics through a diagnostics channel/snapshot. A broken palette reference should become visible in:

- diagnostics panel
- console/log
- cue validation badge
- pre-show validation report

without crashing or blocking output.

---

## P1-12 — Effects are runtime-only and cannot yet be part of a saved show

**Files:**
- `Sources/AuroraEngine/EffectInstance.swift`
- `Sources/AuroraEngine/EffectRunner.swift`
- `docs/design/pr22-effect-engine.md`

This is explicitly documented as a PR22 non-goal, so it is **not an implementation bug**. It is nevertheless an important product gap before Aurora can replace a mature lighting tool.

Current live effects disappear when Aurora closes and cannot be attached to cues/presets.

### Required follow-up

Design persistent effect definitions separately from runtime effect instances:

```text
EffectDefinition (project model)
     ↓
Cue/Preset reference
     ↓
EffectRuntimeInstance (engine)
```

Avoid serializing engine runtime state directly.

This can occur after initial UI work if necessary, but it should remain visible on the roadmap.

---

# P2 — Hardening and Maintainability

## P2-1 — Full workspace is forcibly recreated using `.id(appModel.revision)`

**Files:**
- `Sources/Aurora/ContentView.swift:49`
- `Sources/Aurora/AppModel.swift` `bump()`

`bump()` updates an `@Published revision` and also manually calls `objectWillChange.send()`. `ContentView` then applies:

```swift
.id(appModel.revision)
```

This destroys/recreates the entire workspace view identity for many state changes.

Possible consequences:

- lost transient SwiftUI state
- focus changes
- scroll position resets
- unnecessary redraw cost
- poor scalability as panels become richer

### Required UI-phase fix

Move to fine-grained observable state and targeted bindings. Remove global `.id(revision)` as a general refresh mechanism.

Also remove the redundant manual `objectWillChange.send()` when `@Published` changes already provide invalidation.

---

## P2-2 — Diagnostics module is mostly a namespace stub while logging lives in `AppModel`

**Files:**
- `Sources/AuroraDiagnostics/AuroraDiagnostics.swift`
- `Sources/AuroraDiagnostics/PerformanceBudget.swift`
- `Sources/Aurora/AppModel.swift:481-493`

The intended diagnostics module exists, but structured logging, driver errors, MIDI logs, and UI log ring buffers are largely app-owned arrays of strings.

### Recommended fix

Create a real diagnostics service/store with typed events:

```text
DiagnosticEvent
├── timestamp
├── subsystem
├── severity
├── code
├── message
└── metadata
```

Keep a bounded ring buffer and allow the UI to filter by subsystem/severity.

This also enables the previously-discussed post-show report.

---

## P2-3 — Performance test is far below the stated scale target

**Files:**
- `Tests/AuroraEngineTests/PerformanceScaleTests.swift`
- `docs/design/aurora-system-design.md` performance targets

The design target calls for roughly **2,000 fixtures, 500 cues, continuous MIDI**.

The current scale test exercises **200 one-channel fixtures**, one universe, a static manual look, and 30 synchronous frames.

That is a useful smoke benchmark, not the stated scale test.

### Required expansion

Add macOS benchmark scenarios for:

- 2,000 fixtures across multiple universes
- realistic 8/16/32-channel personalities
- concurrent cue fade
- active effects
- programmer values
- continuous MIDI action input
- Art-Net/sACN enabled to mock or loopback sinks
- snapshot publishing

Measure p50/p95/p99 frame duration and scheduler jitter, not only mean merge time.

---

## P2-4 — `FrameMetricsRecorder.maxFrameMs` is lifetime maximum, not rolling-window maximum

**File:** `Sources/AuroraEngine/EngineFrameMetrics.swift`

The implementation decays the sum/count when the window fills but never decays `maxMs`.

Thus `maxFrameMs` means “maximum since reset,” while `meanFrameMs` approximates a rolling metric. The struct does not make that distinction clear.

### Fix

Either:

- maintain an actual ring buffer and compute rolling max/mean, or
- rename to `lifetimeMaxFrameMs` and document the mixed semantics.

For show diagnostics, p95/p99 and overrun counts are more useful than lifetime max alone.

---

## P2-5 — Engine scheduler silently restarts and suppresses restart errors

**File:** `Sources/AuroraEngine/LightingEngine.swift:44-53`

`updateConfiguration()` does:

```swift
if isRunning {
    stop()
    try? start()
}
```

If restart fails, the caller gets no error and the engine can end up stopped.

### Fix

Make configuration update transactional/error-reporting:

```swift
func updateConfiguration(...) throws
```

or return a status result and propagate it to diagnostics/UI.

---

## P2-6 — Output driver configuration restarts suppress errors

**Files:**
- `Sources/AuroraOutput/ArtNetOutputDriver.swift`
- `Sources/AuroraOutput/SACNOutputDriver.swift`
- `Sources/Aurora/AppModel.swift:441-460`

Several runtime reconfiguration paths use `try? start()`.

A failed network driver restart may therefore leave the UI saying a protocol is enabled while the driver is not actually functioning.

### Fix

Return/propagate restart errors and make `outputStatus` reflect:

```text
Configured / Starting / Running / Failed / Disabled
```

rather than configuration flags alone.

---

## P2-7 — Art-Net/sACN status is configuration-oriented rather than verified-output state

**File:** `Sources/Aurora/AppModel.swift:467-479`

`outputStatus` reports enabled configuration and optional `lastError`, but does not clearly expose driver running state or recent successful transmission.

### Recommended fix

Track per-driver health:

- enabled
- started/running
- frames sent
- last successful send timestamp
- last error
- consecutive send errors

A status light should not be green merely because a checkbox is on.

---

## P2-8 — `OutputManager.startAll()` does not roll back partially-started drivers

**File:** `Sources/AuroraOutput/OutputManager.swift`

If drivers A and B start and driver C throws, A/B remain running while `LightingEngine.start()` throws before setting `startedOutput = true`.

The engine may therefore fail to consider itself responsible for stopping those drivers later.

### Fix

Make `startAll()` transactional:

- track drivers successfully started during this call
- if a later start fails, stop those drivers
- throw the original/aggregate error

---

## P2-9 — Remote HTTP parser needs production input limits and hardening

**File:** `Sources/AuroraRemote/RemoteWebServer.swift:235-284`

The minimal HTTP implementation is reasonable for a scaffold but should not be treated as a general-purpose hardened server.

Items to address:

- explicit maximum header size
- maximum body size
- reject negative/invalid `Content-Length`
- timeout idle/incomplete requests
- normalize header names once
- reject unsupported transfer encodings
- restrict methods/routes
- consider origin policy instead of unconditional `Access-Control-Allow-Origin: *`

For a LAN-only companion, a small bespoke server can still be acceptable if deliberately constrained.

---

## P2-10 — Project loader does not enforce the documented untrusted-file size limits

**Files:**
- `Sources/AuroraModel/ProjectPackage.swift:206-234`
- system design security notes

`Data(contentsOf:)` loads each JSON file without preflight size limits.

### Fix

Before decoding, validate file sizes and collection bounds. Examples:

- maximum JSON file size
- maximum fixture count
- maximum cue count
- maximum media metadata count
- sensible string length limits where appropriate

This is mostly defense-in-depth but aligns with the architecture document.

---

## P2-11 — Command code frequently ignores UI-level errors with `try?`

**Files include:**
- `Sources/AuroraUI/Panels/GroupsPanel.swift`
- `MIDIMappingsPanel.swift`
- `PalettesPanel.swift`
- `SongPanel.swift`

Some destructive or model-mutating UI commands silently discard errors.

### Fix

Route command failures to a shared UI error/diagnostics mechanism. Unexpected command failures during show programming should not vanish.

---

## P2-12 — Group/palette/preset command file is becoming a miscellaneous command bucket

**File:** `Sources/AuroraCore/Commands/GroupCommands.swift`

This file contains commands for groups, palettes, presets, and songs.

### Fix

Split by domain before UI work grows the command surface:

```text
GroupCommands.swift
PaletteCommands.swift
PresetCommands.swift
SongCommands.swift
```

Small change, but it will improve navigation during the UI phase.

---

## P2-13 — Fixture/library `@unchecked Sendable` use should be audited under Swift 6 strict concurrency

**Files:** multiple engine/MIDI/output/remote classes

Much of the code uses `@unchecked Sendable` with explicit `NSLock`, which is a legitimate pragmatic strategy. The issue is not the annotation itself; it is that Swift can no longer verify the safety contract.

### Recommended audit

For every `@unchecked Sendable` type, document the synchronization invariant and ensure every mutable field obeys it.

Particular attention:

- `RemoteHost`
- `RemoteWebServer`
- `RemoteProtocolClient`
- `MIDIInputManager`
- `LightingEngine`
- `PlaybackController`
- output drivers

Where natural, prefer actors or isolated immutable snapshots for control-plane code. Keep actors away from hard real-time-ish frame code if they add unpredictable scheduling overhead.

---

# P3 — Product/Architecture Follow-ups

## P3-1 — Plugin architecture should evolve toward typed data sources and actions

The PR29 skeleton is intentionally minimal and is structurally sound as a placeholder. Before dynamic plugins are implemented, expand the API around typed capabilities rather than handing plugins engine internals.

Recommended long-term concepts:

```text
Plugin
├── Data Sources
├── Events
├── Actions
├── Output Drivers
├── Fixture Importers
├── Effect Generators
└── Settings/Configuration descriptors
```

A weather/humidity plugin should publish:

```text
environment.humidity = 78%
```

and Aurora's automation layer should decide what that means for haze/fog control. Plugins should never directly manipulate the deterministic engine hot path.

---

## P3-2 — Remote snapshot is currently Universe-1-centric

**File:** `Sources/Aurora/AppModel.swift` `makeRemoteSnapshot()`

`activeChannelCount` uses only:

```swift
engineSnap.universeLevels[1]
```

This is fine as an early UI metric but becomes misleading for multi-universe shows.

### Fix

Aggregate across all active universes or expose per-universe summary data.

---

## P3-3 — Song status is not rich enough for final Perform Mode

`SongDirector.statusLine` currently reports only `Song entry N`, and `AppModel` can use that as the remote song title/status.

For final performance UX, provide a structured snapshot:

```text
song id/title
entry index/count
entry label
current cue
next cue
section label
```

This should feed both the Mac Perform Mode and web/iPad remote from one model.

---

## P3-4 — Consider a dedicated show-control action layer shared by MIDI, OSC, remote, keyboard, and future plugins

The same actions now arrive from several paths:

```text
Keyboard
MIDI
OSC
Remote TCP
Remote HTTP
future plugin/automation
```

The repo already has `ShowAction` and `RemoteShowAction`, but application routing still lives mostly in `AppModel`.

Before automation/plugins mature, converge these into one typed control plane with explicit authorization/source metadata.

Example:

```text
ShowControlAction
source: MIDI / OSC / Remote / Keyboard / Plugin
payload: Go / Stop / FireCue / SetAttribute / ...
```

This is also the right location for rate limits, logging, permissions, and latency metrics.

---

# Test Suite Review

The repository has broad unit-test coverage across modules:

- Model serialization
- Patch addressing
- Commands / undo
- Event bus / selection
- Fixture library/import
- Cue resolution
- Playback fades
- Programmer
- Color math
- Effects
- MIDI parsing/action mapping
- OSC parser
- RTP-MIDI config/session wrapper
- Art-Net packet encoding
- sACN packet encoding
- OutputManager
- Remote protocol/web/hardening
- Workspace layout
- Package smoke imports

This is a major positive.

The handoff document reports approximately **157 tests passing on macOS** at the last full run. I could not independently execute the complete suite in this Linux review environment because the package intentionally imports macOS-only frameworks such as CoreMIDI, SwiftUI/AppKit, and Network-framework-specific behavior. That environmental limitation is not counted as an Aurora defect.

### Tests that should be added immediately

1. Atomic package-save failure preservation.
2. Media binary preservation across Save and Save As.
3. Dirty-state/save-point behavior.
4. Unsaved-change transition guard.
5. Removed-universe zero/stop behavior.
6. Cue-only sequence semantics.
7. Multi-device MIDI identity and mapping.
8. MIDI action latency under MainActor load.
9. Remote auth failure rate limiting.
10. Remote token invalidation after kick/revoke.
11. Driver partial-start rollback.
12. 2,000-fixture realistic performance benchmark.

---

# Recommended Fix Order

I recommend doing the repair pass in this order before the major UI redesign:

## Phase 1 — Protect the show file and stage output

1. **Atomic/non-destructive ProjectPackage save**
2. **Media preservation**
3. **Real save-point/dirty model**
4. **Unsaved-change prompts for New/Open/Quit**
5. **Output universe reconciliation / stale-universe blackout**
6. **Cue-only semantics decision + implementation + golden tests**

At the end of this phase, Aurora should no longer have obvious paths to lose a show file or continue outputting stale universes.

## Phase 2 — Make live control trustworthy

7. Move MIDI live actions off `MainActor` hot path.
8. Preserve MIDI source/device identity.
9. Fix partial CoreMIDI initialization cleanup.
10. Make output-driver start/restart errors explicit.
11. Strengthen live diagnostics/driver health.

## Phase 3 — Harden remote/network features

12. Bind remote to explicit trusted interfaces.
13. Replace default `0000` with generated/operator PIN.
14. Rate-limit authentication failures.
15. Centralize/invalidate HTTP session tokens correctly.
16. Fix duplicate hello/auth invocation.
17. Add HTTP request limits/timeouts.

## Phase 4 — Close feature/model gaps

18. Complete real preset behavior/application.
19. Validate palette reference type compatibility.
20. Surface palette resolution issues through diagnostics.
21. Keep persistent effect definitions on roadmap.

## Phase 5 — Prepare for UI mode

22. Break up `AppModel` into focused app controllers.
23. Replace global `revision`/`.id(...)` refresh mechanism with granular observable state.
24. Turn `AuroraDiagnostics` into a real typed diagnostics store.
25. Split miscellaneous command files by domain.

After Phase 5, Aurora will be in an excellent position for the UI/UX redesign because the view layer will be able to bind to cleaner, narrower state objects instead of a single giant coordinator.

---

# What I Would **Not** Rewrite

The following choices are good and should be preserved:

- Module separation between Model/Core/Engine/Output/MIDI/UI/Remote.
- `OutputDriver` abstraction.
- Dedicated engine scheduler and monotonic engine clock abstraction.
- `Programmer` as a layer above playback.
- Effects as a layer between playback and programmer.
- First-class UUID palettes/groups/songs.
- Palette references remaining distinct from literal cue values.
- Song Mode orchestrating existing cue playback rather than becoming another engine.
- Mock/null output drivers for hardware-free tests.
- In-process plugin skeleton rather than premature dynamic loading.
- Remote protocol separated into `AuroraRemote` rather than embedded in views.
- Incremental PR history and subsystem design notes.

The codebase does **not** need a cleanup rewrite. It needs a focused hardening pass.

---

# Overall Assessment

### Architecture: **A-**
The intended boundaries largely survived a very aggressive implementation sprint.

### Core lighting correctness: **B / B+**
The engine is real and testable, but cue-only semantics and stale-universe output need resolution before show trust.

### Data safety: **C until P0 save issues are fixed**
The current package-save behavior is the single largest concern in the repository.

### Live-control latency architecture: **B-**
Core engine threading is sensible, but MIDI currently crosses the main actor before performing actions.

### Network/remote maturity: **C+ as a development feature, not production-secure yet**
Good skeleton and authorization model; needs safer defaults, interface binding, auth hardening, and session lifecycle cleanup.

### Test discipline: **A-**
Excellent breadth for a project this young. The biggest missing tests correspond closely to the high-risk issues identified above.

### UI readiness: **Good after the hardening/refactor pass**
The current UI can now be treated as disposable functional scaffolding. Once P0/P1 items and the AppModel/state cleanup are addressed, Aurora is ready for the full visual/UX design phase without building beauty on top of unstable document/control plumbing.

---

# Suggested Instruction to Grok

> Review `Aurora_Deep_Code_Review_Fixes.md` and implement the remediation work in priority order. Treat P0 issues as release blockers. Preserve the existing module architecture and add regression tests with every fix. Do not begin the major UI redesign while P0 issues remain. For P1/P2 refactors, prefer small independently-testable commits over broad rewrites. Where the review identifies a semantic question, especially cue-only behavior, update the authoritative design documentation and golden tests at the same time as the implementation so code and specification cannot diverge again.

---

## Bottom Line

Aurora did **not** turn into architectural soup during the overnight sprint. That is the most important result of this review.

There are several serious issues, but they are the kind of issues expected when a functional roadmap is implemented at high speed: save transactions, stale runtime state, control-path latency, security defaults, and a coordinator object that has accumulated too many responsibilities.

Fix the P0/P1 items first. Then we can move into UI mode with confidence that the beautiful Aurora interface is sitting on top of software that protects the show, clears stale output, responds predictably, and preserves the clean architecture we started with.
