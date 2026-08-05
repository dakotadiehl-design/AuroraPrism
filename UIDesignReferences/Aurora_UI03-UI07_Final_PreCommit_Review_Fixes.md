# Aurora UI-03→UI-07 Final Pre-Commit Deep Review

**Review target:** `Aurora_04_07_postreview1.zip`  
**Purpose:** Final commit gate before starting UI-08→UI-11  
**Overall verdict:** **DO NOT COMMIT YET — SMALL, TARGETED FIX PASS REQUIRED**

The UI-04→UI-07 architecture is fundamentally sound and should be preserved. Most findings from the previous integration review were correctly implemented.

This is **not** a redesign request.

The remaining work is concentrated in:

1. ENTTEC / Local DMX end-to-end correctness and operator reachability
2. Preset/Look capability filtering
3. Inspector authoritative-state resynchronization
4. A few closeout/test/documentation corrections

After these items are fixed and macOS tests/build are green, this branch should be suitable for a clean UI-04→07 integration commit before UI-08→11 begins.

---

# 1. Gate Summary

## What passes

The following architectural boundaries remain healthy:

```text
Document commands → DocumentSession → projectModified → applyProjectUpdate
Programmer → ephemeral engine state
Palettes/Presets/Cues/Songs → ShowProject
Cue playback → PlaybackController / LightingEngine
Song progression → SongDirector orchestration
Perform Mode → presentation + existing transport
Output → OutputManager + protocol drivers
```

Confirmed good behavior includes:

- Palette Apply now filters ordinary palettes by fixture capability.
- Record Ref now skips incompatible fixtures.
- Palette creation correctly distinguishes unsupported fixtures from capable-but-untouched fixtures.
- Multi-cue Record Ref uses command grouping.
- Cue Update is immediate and undoable.
- Cue array order remains playback authority; `Cue.number` is display metadata.
- Song cursor now tracks `SongEntry` identity through reorder.
- Palette/Preset/Song delete undo restores original ordering.
- New Songs are empty rather than silently seeded.
- Song cue-list insertion uses an explicit list menu.
- Cue row playback role and selection are separate dimensions.
- `OutputController.presentationSnapshot()` is now a pure read.
- Perform Mode keeps GO independent from nonfatal health state.
- No second playback engine or second Song engine was introduced.
- All 209 production Swift files parse successfully with `swiftc -frontend -parse`.
- `git diff --check` is clean.

## Environment-limited verification

`swift test` was attempted.

Compilation reaches Aurora modules including the newly changed model/output code, then stops because the review environment is not macOS and does not provide:

```text
CoreMIDI
Network
```

This is an environment limitation, not evidence of a project failure.

**Required before final commit:** run full `swift test` and Xcode Debug on macOS.

---

# 2. P0 — ENTTEC / Local DMX Is Not Ready to Bless Yet

The codebase now contains genuine Local DMX work, which is an improvement over the previous review.

Source now includes:

```text
MacLocalDMXDeviceEnumerator
MacENTTECSerialTransport
ENTTECUSBDMXProDriver
OutputController local-DMX registration
Settings → Output → Local DMX
device picker
Rescan
Enable Local DMX
```

However, the feature is **not yet end-to-end safe or operator-complete**.

This also explains the user's observation that they still cannot meaningfully select ENTTEC as an output.

---

## HW-01 — Local DMX is present in Settings, but universe routing is read-only

### Files

```text
Sources/Aurora/Settings/AuroraSettingsRoot.swift
Sources/Aurora/AuroraApp.swift
Sources/AuroraUI/Panels/PatchPanel.swift
Sources/AuroraCore/Commands/*
Sources/AuroraModel/Universe.swift
```

### Current state

Settings includes:

```text
Settings
  → Output
    → Local DMX
      → Rescan
      → Device picker
      → Enable Local DMX
```

That is good.

But the same screen tells the operator:

```text
Route show universes with protocolHint = local
```

while the "Universe routing" section is **read-only**.

The main application Output menu contains only:

```text
Art-Net
sACN
```

There is no Local DMX/ENTTEC item there.

The Patch panel also does not expose `Universe.protocolHint`.

Therefore an operator cannot currently complete the workflow:

```text
Select ENTTEC
→ enable device
→ route U1 to Local DMX
→ send DMX
```

without directly editing project data/code.

The Demo show is intentionally `.none`, so simply enabling the ENTTEC driver does not make Demo output reach it.

### Required fix before hardware smoke / recommended before commit

Provide at least one real UI path for changing a project's universe protocol route.

Minimum acceptable pre-UI-09 solution:

```text
Settings → Output → Universe routing

U1 Main Stage   [ None | Local DMX | Art-Net | sACN | Mirror ]
```

The change must be a **document command**, not direct mutation.

Recommended command:

```swift
UpdateUniverseRoutingCommand(
    universeID: UUID,
    protocolHint: UniverseProtocolHint
)
```

Undo must restore the prior route.

Alternative placement in Patch is acceptable, but there must be an operator-accessible route editor.

Do not rely on a caption telling the operator to edit `protocolHint`.

### Acceptance

```text
[ ] Operator can set U1 → Local DMX without editing code/project JSON
[ ] Change uses DocumentSession command path
[ ] Undo restores prior route
[ ] Demo remains safe by default (.none)
[ ] Selecting Local DMX does not silently alter routing
```

---

## HW-02 — ENTTEC enable path double-opens the transport and can report success after driver start failure

### Files

```text
Sources/Aurora/Controllers/OutputController.swift
Sources/AuroraOutput/ENTTECUSBDMXProDriver.swift
```

### Current behavior

`OutputController.enableLocalDMX` does:

```swift
let transport = MacENTTECSerialTransport(path: path)
try transport.open()
...
let driver = ENTTECUSBDMXProDriver(... transport: transport)
...
if engineRunning {
    try? driver.start()
}
localDMXEnabled = true
localDMXStatus = "Local DMX: ..."
```

But `ENTTECUSBDMXProDriver.start()` itself does:

```swift
try transport.open()
```

So the device is opened once by the controller and again by the driver.

Worse, the driver's `start()` error is discarded with:

```swift
try? driver.start()
```

and the controller then unconditionally sets:

```text
localDMXEnabled = true
```

This allows a false state:

```text
Settings says enabled
driver failed to start
no valid DMX output
```

### Required fix

Choose **one owner for opening/closing the transport**.

The cleanest current architecture is:

```text
OutputController
    creates transport
    creates driver
    registers driver
        ↓
driver.start()
    opens transport
        ↓
success → mark enabled
failure → unregister/cleanup + report failed
```

So `OutputController` should **not pre-open** the transport.

Pseudo-flow:

```swift
let transport = MacENTTECSerialTransport(path: path)
let driver = ENTTECUSBDMXProDriver(...)

outputManager.register(driver)

do {
    if engineRunning {
        try driver.start()
    }
    localDMXTransport = transport
    localDMXDriver = driver
    localDMXEnabled = true
    localDMXStatus = ...
} catch {
    outputManager.unregister(id: driver.id)
    driver.stop()
    transport.close()
    localDMXEnabled = false
    localDMXStatus = "Local DMX: open/start failed — \(...)"
}
```

If the engine is not running, explicitly define whether "enabled" means:

```text
registered but waiting for engine
```

and present that truthfully.

### Acceptance

```text
[ ] Transport opens exactly once per driver start
[ ] Failed start cannot produce localDMXEnabled == true
[ ] Failed start unregisters/cleans driver
[ ] Status includes useful failure reason
[ ] Repeated enable/disable does not leak FileHandles
```

---

## HW-03 — Sandboxed serial access is missing the serial-device entitlement

### File

```text
App/Aurora.entitlements
```

### Current entitlements

Aurora has:

```xml
com.apple.security.device.usb = true
```

but not:

```xml
com.apple.security.device.serial = true
```

The new implementation is opening `/dev/cu.*` serial devices.

Apple's App Sandbox entitlement documentation distinguishes serial-device access from USB-device access and identifies:

```text
com.apple.security.device.serial
```

for interaction with serial devices.

### Required fix

Add:

```xml
<key>com.apple.security.device.serial</key>
<true/>
```

Retain USB entitlement if the app also uses/needs USB device access.

### Verify on signed/sandboxed Debug build

Do not verify only through `swift run`, because that does not prove App Sandbox behavior.

Test the actual Xcode app target.

### Acceptance

```text
[ ] App target contains serial entitlement
[ ] Signed sandboxed Debug app can enumerate/open /dev/cu.* device
[ ] No sandbox denial in Console
```

---

## HW-04 — Serial transport must explicitly preserve binary framing

### File

```text
Sources/AuroraOutput/ENTTECUSBDMXProDriver.swift
```

### Current behavior

`MacENTTECSerialTransport.open()` uses:

```swift
FileHandle(forUpdating: url)
```

and performs no termios/raw serial configuration.

ENTTEC's USB Pro protocol is a framed **binary** stream:

```text
0x7E | label | len LSB | len MSB | payload | 0xE7
```

The ENTTEC documentation notes that the VCOM baud setting is effectively a dummy for USB communication speed, so do not invent a "baud controls USB speed" requirement.

However, the tty must still be opened/configured so the operating-system terminal line discipline does not transform binary bytes.

### Required fix

Use a POSIX serial open/configuration path suitable for binary framing.

At minimum:

```text
open() descriptor deliberately
configure raw/binary termios behavior
disable newline/output processing
disable canonical input processing
disable software flow-control unless required
close descriptor exactly once
```

A FileHandle may wrap the configured descriptor after setup if desired.

Do not bake this into `ENTTECUSBDMXProDriver`; keep it in `MacENTTECSerialTransport`.

### Acceptance

```text
[ ] Binary frame bytes leave the process unchanged
[ ] 0x0A / 0x0D and arbitrary DMX bytes are not transformed
[ ] repeated open/close is safe
[ ] write failure updates health
```

---

## HW-05 — Current discovery is a filename heuristic, not reliable ENTTEC identification

### File

```text
Sources/AuroraOutput/ENTTECUSBDMXProDriver.swift
```

### Current enumerator

It scans `/dev` for names containing:

```text
usbserial
usbmodem
SLAB
DMX
FTDI
```

and describes every match as a Local DMX device.

Problems:

1. unrelated USB serial adapters can be presented as ENTTEC;
2. an ENTTEC device whose VCP name does not match these fragments can be missed;
3. `hardwareIdentifier` is not populated;
4. `id` is the `/dev/cu.*` path and is unstable across reconnection.

### Recommended fix

For the real feature, use IOKit/serial metadata to identify serial services and capture stable properties where available.

At minimum:

```text
display name
current callout path
vendor/product information
USB serial number / hardware identity
device type confidence
```

Prefer stable hardware identity for persistence, with path as the current connection endpoint.

For the immediate smoke-test path, it is acceptable to present a broader "Serial device" list if identification is uncertain, but do **not** falsely label unrelated serial adapters as confirmed ENTTEC.

### Acceptance

```text
[ ] ENTTEC USB Pro is discoverable on target Mac
[ ] unrelated serial devices are not falsely presented as confirmed USB Pro
[ ] stable identity is used where available
```

---

## HW-06 — Local output mapping is hardwired to show Universe 1

### File

```text
Sources/AuroraOutput/ENTTECUSBDMXProDriver.swift
```

The driver defaults:

```swift
universeFilter: Set<UInt16> = [1]
```

An ENTTEC USB Pro exposes one physical DMX output universe, but that does not inherently mean it must always be logical **show Universe 1**.

Current behavior means:

```text
Show U1 → Local   works
Show U2 → Local   OutputManager accepts route,
                  ENTTEC driver silently drops it
```

For the first smoke test, U1 is enough.

But UI-09 must introduce explicit logical-universe→local-port mapping.

### Immediate requirement

At minimum, make the current limitation truthful in UI:

```text
Local DMX currently maps Show Universe 1 to ENTTEC output
```

Do not imply arbitrary local universes work.

### UI-09 follow-up

Add explicit mapping:

```text
ENTTEC USB Pro
Physical Output 1 ← Show Universe [picker]
```

---

# 3. P1 — Preset / Look Apply Still Bypasses Fixture Capability Filtering

### File

```text
Sources/AuroraUI/Panels/PalettesPanel.swift
```

### Ordinary palettes are now correct

`apply(_ palette:)` performs:

```text
palette values
∩ fixture capabilities
→ Programmer batch
```

Good.

### Presets are still different

`applyPreset(_:)` resolves levels and then writes:

```swift
batch[fx.fixtureId] = fx.attributes
```

without filtering against the fixture's **current** personality/capability set.

This can matter when:

```text
a fixture personality changes after the Look was stored
a Preset contains stale literal attributes
palette references resolve attributes that no longer apply
old show data contains unsupported keys
```

Those unsupported values then become Programmer-owned and can later be recorded into cues.

### Required fix

Apply the same capability intersection to resolved Preset attributes:

```text
resolved fixture attrs
    ∩
current fixture capabilities
    ↓
Programmer.setMany
```

Report skipped unsupported fixtures/attributes when useful.

### Tests

```text
Preset stored with pan/tilt
fixture later becomes static RGB
Apply Preset
→ static fixture does not gain pan/tilt Programmer attrs

Preset with mixed compatible/incompatible fixtures
→ only supported attrs are written
```

### Acceptance

```text
[ ] Palette and Preset Apply obey the same capability truth rules
[ ] Unsupported Preset attributes never enter Programmer state
```

---

# 4. P1 — Inspector Draft Resynchronization Is Still Not Actually Fixed

### Files

```text
Sources/AuroraUI/Panels/InspectorPanel.swift
Sources/Aurora/Controllers/WorkspaceController.swift
Sources/Aurora/PanelRegistry.swift
Sources/Aurora/Shell/BuildWorkspaceHost.swift
```

### Closeout document claims

```text
CR-11 | documentEpoch draft resync when not focused
```

But the implemented signal does not represent document mutation.

`WorkspaceController.documentEpoch` increments only in:

```swift
didReplaceDocument(...)
```

which is used for:

```text
New
Open
Demo/document replacement
```

It does **not** increment on ordinary:

```text
command mutation
Undo
Redo
rename/update
```

Inspector editors reload on:

```text
entity.id change
documentEpoch change
```

Therefore same-ID authoritative changes remain capable of leaving stale drafts.

### Example

```text
1. Focus Palette A.
2. Rename Palette A in Inspector.
3. Undo.
4. ShowProject restores old name.
5. Palette A ID is unchanged.
6. documentEpoch is unchanged.
7. Inspector draft can retain the pre-Undo name.
8. Next edit can accidentally write stale state back.
```

The same family of issue can affect:

```text
Palette
Preset
Cue
Song
```

### Required fix

Provide an **authoritative document-mutation revision**, separate from document replacement epoch.

Possible shape:

```swift
@Published private(set) var documentRevision: UInt64
```

Increment on successful project mutation/Undo/Redo, or expose an existing generation/revision from `DocumentSession`.

Best candidate: use `DocumentSession.documentGeneration` as part of the input/projection where practical.

Inspector should reload drafts when:

```text
same entity ID
AND authoritative generation changed
AND editor is not actively editing that field
```

Do not clobber text while the user is typing.

### Tests

Where pure logic can be extracted:

```text
same entity ID + newer generation + not editing → reload
same entity ID + newer generation + editing → preserve draft until commit/cancel
different entity ID → reload
Undo/Redo → inspector eventually matches authority
```

### Documentation

Do not claim CR-11 fixed until the mutation signal actually changes on document mutations.

---

# 5. P2 — ENTTEC Selection/Enable Is Not Persisted

### Files

```text
Sources/Aurora/Controllers/OutputController.swift
Sources/Aurora/Controllers/AppSettingsStore.swift
```

Current:

```text
selectedLocalDMXDeviceID
localDMXEnabled
```

are runtime-only `@Published` fields.

After relaunch the operator must reselect/re-enable.

This is not a blocker for a one-time smoke test, but it is application configuration and belongs in UI-08 Settings persistence.

### Recommendation

Do **not** rush a fragile path-based persistence system into this pre-commit pass.

Instead:

1. finish stable hardware identity first;
2. persist selected hardware identifier + enabled preference in UI-08;
3. reconnect truthfully if the device is absent.

Document this as an explicit UI-08 item.

---

# 6. P2 — Local DMX tests currently miss the exact lifecycle failure found above

### File

```text
Tests/AuroraOutputTests/LocalDMXDiscoveryTests.swift
```

Current test:

```swift
let t = MockENTTECTransport()
try t.open()
...
try driver.start()
```

The mock transport tolerates repeated `open()` and therefore masks the double-open lifecycle problem.

### Add a strict mock

Create a transport that can assert:

```text
openCount
closeCount
failOnSecondOpen
```

Tests:

```text
driver.start → exactly one open
driver.stop → exactly one close
repeated driver start behavior is deliberate
OutputController enable → no pre-open + driver-open duplication
driver start failure → enabled false
```

If `OutputController` is awkward to instantiate in the package test target because it lives in the app target, extract Local DMX lifecycle coordination into a testable type rather than skipping the behavior.

---

# 7. P2 — Closeout Documentation Overstates the Current State

### Files

```text
UIDesignReferences/UI_04_07_Integration_Closeout.md
docs/PROJECT_HANDOFF.md
```

Examples:

```text
CR-11 ... fixed
HW-01 foundation complete
NEXT optional ENTTEC hardware smoke
```

CR-11 is not fully fixed.

ENTTEC currently has UI/discovery/transport scaffolding, but the lifecycle, sandbox serial entitlement, raw serial path, and operator routing gap prevent calling it hardware-smoke-ready.

Also `PROJECT_HANDOFF.md` still describes:

```text
ENTTEC USB Pro framing mock
```

while other sections imply real hardware foundation.

### Required update after fixes

Make the handoff precise:

```text
ENTTEC USB Pro:
- framed protocol implemented
- real macOS serial transport implemented/tested
- device discovery implemented
- Settings device selection implemented
- U1→Local route UI implemented
- physical hardware verification: pending/complete
```

Distinguish software support from physical-device validation.

---

# 8. P2 — Remove Redundant Manual `objectWillChange` Calls in OutputController

### File

```text
Sources/Aurora/Controllers/OutputController.swift
```

Methods modifying `@Published` configuration still manually call:

```swift
objectWillChange.send()
```

after writes.

This is not currently a correctness blocker, but it produces unnecessary invalidation and conflicts with the cleanup direction already used elsewhere.

Review:

```text
setArtNetEnabled
setArtNetDestination
setSACNEnabled
setSACNUnicastHost
```

Remove manual sends where `@Published` mutation already publishes correctly.

Do not remove a send if a nested struct mutation genuinely does not publish under the chosen implementation; if uncertain, assign a new copy to the `@Published` property explicitly.

---

# 9. Review of Previous Findings

## CR-01 Palette Apply capability filtering

**PASS**

Ordinary palette Apply filters each fixture's values by capability.

## CR-02 Record Ref capability filtering

**PASS**

Only compatible fixture IDs receive refs.

## CR-03 Capability-aware palette creation

**PASS**

Capable+untouched blocks false common values.

Unsupported fixtures do not poison common comparison.

## CR-04 Multi-cue atomic Record Ref

**PASS WITH NOTE**

Command grouping is used and `cancelGroup()` reverses buffered commands.

This produces one Undo after successful completion.

Intermediate `projectModified` events still occur for commands inside the group; acceptable for now, but document transactions are not completely invisible to observers while open.

## CR-05 Song cursor reconciliation

**PASS**

`currentEntryID` identity is preserved through reorder.

Deleted current entry uses documented fallback.

Deleted Song resets runtime Song cursor without explicitly blacking out playback.

## CR-06 Ordered Undo

**PASS**

Palette/Preset/Song removal commands now store index and restore at original position.

## CR-07 Song cue-list selection

**PASS**

The UI presents a menu of available lists rather than silently using the first.

## CR-08 New Song empty

**PASS**

New Song is created empty.

## CR-09 Cue selected × playback role

**PASS**

`AuroraCueRow` now models:

```text
playbackRole
isSelected
```

separately and accessibility announces both.

## CR-10 Inspector error handling

**PASS**

Meaningful mutation paths use explicit `do/catch`.

## CR-11 Inspector resync

**FAIL / INCOMPLETE**

See Section 4.

## CR-12 Output snapshot purity

**PASS**

`presentationSnapshot()` no longer mutates published state.

## CR-13 Git phase boundaries

**NOT RECONSTRUCTED**

Current Git HEAD is still the UI-03-era checkpoint and all UI-04→07 work is a dirty working tree.

Do not fabricate historical phase commits now.

After this final repair pass, make one explicit clean integration checkpoint such as:

```text
UI-04 through UI-07 complete + integration hardening
```

Then start UI-08→11 from that clean commit.

## CR-14 Perform copy cleanup

**PASS**

Developer-facing explanatory copy was reduced.

## CR-15 no-op transport modifiers

**PASS**

Removed.

---

# 10. ENTTEC Operator UX Clarification

The user reported:

> "I still do not see anything about the ENTTEC device in this build, or selecting it as an output."

The source tree now **does** contain:

```text
Settings → Output → Local DMX
```

with device Rescan/Picker/Enable.

So if the built application truly shows no Local DMX section at all, verify that the app being run is built from this exact working tree.

However, even when that section is visible, the user is still correct that the workflow is incomplete because:

```text
Universe routing is read-only
main Output menu has no Local DMX entry
Demo U1 defaults to .none
```

Therefore "select device" currently does not equal "select ENTTEC as the project's output."

The pre-commit pass should make that path obvious.

Suggested minimum UX:

```text
Settings → Output

LOCAL DMX
Device: [ ENTTEC DMX USB Pro ... ]
[Rescan]
Enabled: [x]

PROJECT UNIVERSES
U1 Main Stage:
Route: [ Local DMX ▼ ]
```

Status:

```text
ENTTEC DMX USB Pro · connected · U1
```

Do not call it Open DMX.

---

# 11. Required Tests Before Commit

## Local DMX / ENTTEC

```text
[ ] strict transport opens once
[ ] start failure does not mark enabled
[ ] disable closes/unregisters
[ ] serial entitlement present
[ ] binary/raw serial transport test where feasible
[ ] mocked discoverer populates picker state
[ ] missing selected device reports unavailable
[ ] U1 local route reaches local driver
[ ] .none does not reach local driver
[ ] Art-Net/sACN routes do not reach local driver
[ ] route command undo/redo
```

## Preset Apply

```text
[ ] stale unsupported Preset attrs filtered
[ ] compatible attrs still apply
[ ] one Programmer batch
```

## Inspector

```text
[ ] Undo same focused Palette resyncs draft
[ ] Redo resyncs
[ ] same for Cue/Preset/Song representative editors
[ ] active typing not clobbered
```

## Existing regression suite

```text
[ ] PaletteCreate tests green
[ ] SongCursorReconcile tests green
[ ] command-order undo tests green
[ ] playback ordering authority tests green
[ ] UI-03 Programmer tests green
[ ] full swift test green on macOS
```

---

# 12. Manual macOS Commit-Gate Checklist

Run the actual signed Xcode Debug app.

```text
[ ] Settings window contains Output tab
[ ] Output tab contains Local DMX section
[ ] Plug in ENTTEC DMX USB Pro
[ ] Rescan
[ ] Device appears
[ ] Select device
[ ] Set U1 route = Local DMX through UI
[ ] Enable Local DMX
[ ] Status becomes Ready only after successful driver start
[ ] Console shows no sandbox serial denial
[ ] Send fixture intensity/color
[ ] ENTTEC emits DMX / real fixture responds
[ ] Unplug device live
[ ] Output health degrades
[ ] GO remains usable
[ ] Disable Local DMX cleans driver
[ ] Re-enable does not leak/fail due duplicate open
```

Then application workflow:

```text
[ ] mixed-capability palette Apply
[ ] Preset Apply with changed fixture personality
[ ] Record Ref multi-cue → one Undo
[ ] Undo Palette rename while Inspector remains focused
[ ] Inspector shows authoritative restored name
[ ] Song entry reorder preserves loaded identity
[ ] Build ↔ Perform preserves playback
[ ] MIDI GO updates CURRENT
```

---

# 13. Recommended Fix Order

```text
1. HW-02 Local DMX lifecycle: remove double-open / false enabled state
2. HW-03 serial sandbox entitlement
3. HW-04 raw/binary macOS serial transport
4. HW-01 editable Universe → Local routing
5. HW-05 discovery identity reliability
6. P1 Preset/Look capability filtering
7. P1 Inspector real mutation revision/resync
8. Local DMX + Inspector tests
9. Documentation corrections
10. Full swift test on macOS
11. Xcode Debug build
12. Physical ENTTEC smoke
13. Commit UI-04→07 integration checkpoint
14. Start UI-08→11
```

---

# 14. Final Commit Gate

## Current tree

**DO NOT COMMIT AS THE UI-04→07 FINAL CHECKPOINT YET.**

Reason:

```text
ENTTEC output path can claim enabled after a failed/double-open start
ENTTEC universe routing is not operator-editable
sandboxed serial entitlement is incomplete
serial transport needs explicit binary/raw handling
Preset Apply can still introduce unsupported Programmer attrs
Inspector same-ID mutation resync is still incomplete
```

## After these targeted fixes

If:

```text
full macOS tests are green
Xcode Debug is green
ENTTEC software path works
Inspector regression is closed
Preset Apply is capability-safe
```

then the correct gate should become:

**APPROVED TO COMMIT UI-04→07 AND BEGIN UI-08→11.**

No architecture rewrite is requested.
