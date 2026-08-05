# Aurora UI-04 through UI-07 Integration Code Review

**Review target:** `Aurora_04_07.zip`  
**Scope:** UI-04 Palettes/Presets → UI-05 Cue Workflow → UI-06 Song Mode → UI-07 Perform Mode, plus integration with UI-03 Programmer and output readiness.  
**Overall verdict:** **Conditionally accepted — targeted fixes required before the first hardware smoke test.**

---

# Executive Summary

UI-04 through UI-07 are **architecturally successful overall**.

The implementation preserved the important Aurora ownership rules:

- Programmer remains authoritative for ephemeral programmer values.
- `ShowProject` remains authoritative for document palettes, presets, cues, and songs.
- `DocumentSession.perform(...)` remains the document mutation path.
- Document mutations propagate through the existing project-modified event and UUID-preserving `applyProjectUpdate`.
- Cue selection remains distinct from cue execution.
- `PlaybackController` remains the playback engine.
- `SongDirector` remains orchestration rather than becoming a second playback engine.
- Perform Mode remains a thin presentation/control layer over live snapshots and existing transport.
- GO remains independent from nonfatal output/MIDI/validation health.
- High-frequency Programmer operations continue to use batching.

This is not a redesign situation.

However, several seam-level issues should be fixed before treating UI-03→07 as hardware-smoke-ready.

The most important findings are:

1. **Real ENTTEC output is not implemented yet.**
2. **Palette Apply and Record Ref are not fixture-capability-filtered.**
3. **Palette creation cannot distinguish unsupported fixtures from capable-but-untouched fixtures.**
4. **Multi-cue Record Ref is not atomic and creates multiple undo steps per user gesture.**
5. **Editing/removing entries in a currently loaded Song can leave `SongDirector.entryIndex` stale or semantically shifted.**
6. **Deleting palettes/presets/songs and undoing can restore them at the end rather than the original position.**
7. **Song “+ Cue List” always inserts the first cue list, not the operator-selected list.**
8. **Several integration/edge cases promised by the plan are not directly covered by tests.**

The recommendation is to fix P0/P1 findings, add the focused tests below, run the full suite on macOS, then perform one more integration review before physical fixtures are connected.

---

# Production Code Size

Counting production code only and excluding `Tests/`:

```text
Swift source:
  23,119 physical lines
  208 Swift files

Embedded web UI:
     128 lines (Sources/AuroraRemote/Resources/Web/index.html)

Total hand-written application code:
  23,247 physical lines
```

Test code, excluded from the requested total:

```text
6,263 Swift lines
65 Swift test files
```

The UI-04→07 working-tree delta itself is approximately:

```text
+1,526 production lines
-  246 production lines
-----------------------
+1,280 net production lines
```

---

# Test / Build Verification

`swift test` was attempted in the review environment.

Compilation proceeds into Aurora modules, including the new `PaletteCreate.swift`, but the full suite cannot complete because this environment is not macOS and therefore lacks Apple frameworks used by Aurora:

```text
CoreMIDI
Network
```

Representative failures:

```text
no such module 'CoreMIDI'
no such module 'Network'
```

This is an environment limitation, not evidence that UI-04→07 fail on macOS.

The changed Swift files were also syntax-parsed successfully with `swiftc -frontend -parse`.

**Required before closeout:** run full `swift test` and Xcode Debug on macOS.

The UI handoff files claim 313 passing after UI-04 and 319 after UI-05. Those results were not independently reproducible in this non-macOS review environment.

---

# P0 — Hardware Smoke Blocker

## HW-01 — Real ENTTEC USB DMX Pro discovery/open/selection is not implemented

### Severity

**P0 for the planned physical-light smoke test using ENTTEC.**

This is not specifically a UI-04→07 regression. It is an earlier explicitly deferred backend capability that now becomes important because Aurora is approaching real-rig testing.

### Confirmed current state

Aurora contains:

```text
ENTTECUSBDMXProProtocol
ENTTECUSBDMXProDriver
ENTTECSerialTransport
MockENTTECTransport
LocalDMXDeviceDescriptor
LocalDMXDeviceEnumerator
```

The DMX USB Pro framed packet implementation exists.

However:

```swift
public enum LocalDMXDeviceEnumerator {
    public static func enumerate() -> [LocalDMXDeviceDescriptor] {
        []
    }
}
```

There is no real macOS serial transport implementation.

`OutputController` currently owns/registers only:

```text
NullOutputDriver
ArtNetOutputDriver
SACNOutputDriver
```

It does **not** create or register an `ENTTECUSBDMXProDriver`.

Settings currently explicitly displays:

```text
ENTTEC serial enumeration is not implemented (USB Pro framing only).
```

The Output menu exposes only Art-Net and sACN.

Therefore the user is correct: **there is nowhere to select an ENTTEC device because real ENTTEC device selection does not currently exist.**

### Important protocol clarification

The existing driver implements:

**ENTTEC DMX USB Pro framed protocol**

It does **not** implement ENTTEC Open DMX.

Do not label it Open DMX.

### Required implementation

Add a real local-DMX device layer before ENTTEC hardware smoke testing.

Recommended shape:

```text
macOS serial device discovery
        ↓
LocalDMXDeviceDescriptor[]
        ↓
selected local device
        ↓
MacENTTECSerialTransport
        ↓
ENTTECUSBDMXProDriver
        ↓
OutputManager.register(...)
        ↓
Universe.protocolHint == .local
```

### Recommended components

#### 1. Replace the hard-coded static placeholder enumerator with an injectable discovery abstraction

Example conceptual API:

```swift
public protocol LocalDMXDeviceDiscovering {
    func enumerate() -> [LocalDMXDeviceDescriptor]
}
```

Provide:

```text
MacLocalDMXDeviceEnumerator
MockLocalDMXDeviceEnumerator
```

This makes device-selection behavior testable.

#### 2. Implement real macOS serial transport

Add a production implementation of:

```swift
ENTTECSerialTransport
```

capable of:

```text
open
close
write
isOpen
```

against a discovered macOS serial device.

Use an appropriate macOS serial implementation, e.g. IOKit discovery plus POSIX/termios/FileHandle transport, while preserving the current transport protocol.

Do not bake serial I/O directly into the driver.

#### 3. Add local-DMX ownership to `OutputController`

`OutputController` should own/publish:

```text
availableLocalDMXDevices
selectedLocalDMXDeviceID
localDMXEnabled
localDMXStatus
```

When a valid device is selected/enabled:

```text
create transport
create ENTTECUSBDMXProDriver
register driver
start if engine running
refresh output health
```

On disable/device removal:

```text
stop
unregister
update health
```

#### 4. Add Settings UI

Under:

```text
Settings → Output → Local DMX
```

provide:

```text
Rescan
Device picker
Enable/Disable
Connection state
Selected universe(s)
Driver health / last error
```

At minimum for first hardware smoke:

```text
Device
Universe 1
Enable
Status
```

#### 5. Persist application-level device selection

Persist a stable device identifier where possible.

Do not rely only on `/dev/cu.*` path because macOS paths may vary between connections.

Use available USB/serial metadata such as:

```text
vendor/product identity
serial number
IORegistry identity
serial path as current connection endpoint
```

#### 6. Route project universes correctly

For an ENTTEC-driven universe:

```swift
Universe.protocolHint = .local
```

The existing `OutputManager.driver(_:accepts:)` routing then correctly sends that universe only to `.local` drivers.

#### 7. Handle disconnect/reconnect truthfully

If the device disappears:

```text
driver health → failed/degraded
transport stops sending
GO remains available
output indicator goes red
```

Do not silently fall back to Art-Net/sACN unless the universe is explicitly `.mirror`.

### Tests required

```text
enumerator returns USB Pro descriptor
selected descriptor creates/registers local driver
.local universe reaches ENTTEC driver
.artNet/.sACN/.none do not reach ENTTEC unless .mirror
device open failure produces failed health
device disconnect produces degraded/failed health
disable unregisters/stops driver
selection persistence resolves a reconnected device
```

### Hardware verification

Before calling ENTTEC ready:

```text
1. Plug in ENTTEC DMX USB Pro.
2. Device appears in Settings.
3. Select it.
4. Route show U1 to Local.
5. Enable local output.
6. Confirm Output health = ready.
7. Send static channel values.
8. Confirm USB Pro traffic / connected fixture response.
9. Disconnect USB live.
10. Verify output health degrades but GO remains usable.
11. Reconnect and verify deliberate recovery behavior.
```

---

# P1 — Fix Before UI-03→07 Integration Closeout

## CR-01 — Palette Apply is not fixture-capability-filtered

### Files

```text
Sources/AuroraUI/Panels/PalettesPanel.swift
Sources/AuroraEngine/Programmer.swift
Programmer capability helpers / presentation resolver as appropriate
```

### Current behavior

`PalettesPanel.apply(_:)` builds:

```swift
for id in ids {
    batch[id] = palette.values
}
programmer.setMany(batch)
```

Every selected fixture receives every attribute key in the palette.

There is no personality/capability filtering.

Example:

```text
Palette:
  pan = 0.25
  tilt = 0.70

Selection:
  Moving Head A
  RGB PAR B
```

Current Programmer state can become:

```text
Moving Head A:
  pan = 0.25
  tilt = 0.70

RGB PAR B:
  pan = 0.25
  tilt = 0.70   <-- invalid semantic Programmer ownership
```

The eventual DMX translation may ignore unsupported attributes, but the invalid values can remain in Programmer state and later be captured into cues/looks.

### Required fix

Before batching palette attributes for a fixture, intersect palette keys with that fixture's supported attribute set.

Conceptually:

```text
palette.values
    ∩
fixture capabilities
    ↓
fixture-specific batch attrs
```

Skip empty fixture batches.

Status should truthfully report partial application when useful.

Example:

```text
Applied Position 3 to 4 capable fixtures
Skipped 6 unsupported fixtures
```

### Acceptance

```text
[ ] Unsupported attributes never enter Programmer state via palette Apply
[ ] Partial selections only mutate capable fixtures/attributes
[ ] Empty-capability selections perform no write
[ ] One setMany batch remains used
```

---

## CR-02 — Record Ref writes palette references to unsupported fixtures

### Files

```text
Sources/AuroraUI/Panels/PalettesPanel.swift
Sources/AuroraModel/ResolutionIssue.swift
```

### Current behavior

`recordRef(_:)` passes the entire selected fixture set into:

```swift
cue.recordPaletteRef(palette: palette, fixtureIDs: selectedFixtures)
```

`recordPaletteRef` then writes:

```text
paletteRefs[palette.type.rawValue] = palette.id
```

for every selected fixture.

No capability filtering occurs.

This can produce references such as:

```text
Position palette reference on a static PAR
Color palette reference on a dimmer-only fixture
```

The resolver may later expand values the fixture cannot use.

### Required fix

Determine which selected fixtures actually support at least one meaningful attribute in the referenced palette family.

Only write refs to compatible fixtures.

Do not infer compatibility solely from `PaletteType`; check actual attribute capability where necessary.

### Acceptance

```text
[ ] Record Ref only writes to compatible fixture slots
[ ] Unsupported selected fixtures are skipped
[ ] Status reports skipped unsupported fixtures
[ ] No fake reference slot is added to incompatible fixtures
```

---

## CR-03 — Palette creation cannot distinguish unsupported from capable-but-untouched fixtures

### Files

```text
Sources/AuroraModel/PaletteCreate.swift
Sources/AuroraModel/PaletteRecord.swift
Sources/AuroraUI/Panels/PalettesPanel.swift
```

### Current behavior

`PaletteCreate.fromProgrammer` receives:

```text
programmerValues
selectedFixtureIDs
```

but not fixture capability information.

`PaletteRecord.fromProgrammer` collects samples only where an attribute value exists:

```swift
if let v = programmerValues[id]?[key] {
    samples.append(v)
}
```

Therefore these two states are indistinguishable:

```text
Fixture B does not support Red
```

and:

```text
Fixture B supports Red but Programmer has not touched Red
```

Example:

```text
Fixture A supports Red and owns Red=1.0
Fixture B supports Red but is untouched
```

Current create logic sees only one sample and can record:

```text
Red = 1.0
```

as if it were a common value.

That is not equivalent to the UI-03 truth model, where support and value ownership are orthogonal.

### Required fix

Palette creation needs capability-aware inputs.

Recommended conceptual algorithm for each attribute:

```text
selected fixtures
      ↓
filter to fixtures capable of attribute
      ↓
inspect Programmer ownership among capable fixtures
```

Then resolve:

```text
no capable fixtures
    → unavailable

capable fixtures all own same value
    → common, record

capable fixtures own different values
    → mixed, skip

some capable fixtures own value and some capable fixtures untouched
    → mixed/indeterminate, skip

unsupported fixtures
    → excluded from value comparison, optionally reported as partial support
```

Reuse the existing UI-03 presentation/capability semantics where possible rather than creating a second inconsistent resolver.

### Acceptance

```text
[ ] Unsupported ≠ untouched
[ ] Capable+untouched prevents false "common" recording
[ ] Unsupported fixtures do not poison common comparison
[ ] Mixed/untouched omission is communicated
```

---

## CR-04 — Multi-cue Record Ref is not atomic and violates one-gesture/one-undo

### Files

```text
Sources/AuroraUI/Panels/PalettesPanel.swift
Sources/AuroraCore/DocumentSession.swift / CommandGroup facilities
```

### Current behavior

When several selected cues are targets:

```swift
for (listID, var cue) in targets {
    ...
    try context.session.perform(UpdateCueCommand(...))
}
```

Each cue becomes a separate command and separate undo step.

Problems:

1. One user action produces N undo operations.
2. If update 3 of 5 fails, updates 1 and 2 remain committed.
3. The status can represent a partially completed gesture.
4. This conflicts with the plan's "one command per user gesture" principle.

### Required fix

Make Record Ref transactional.

Preferred:

```text
beginGroup("Record Palette Reference")
    perform UpdateCueCommand #1
    perform UpdateCueCommand #2
    ...
endGroup()
```

If any command fails:

```text
cancelGroup()
surface error
```

Alternatively create a purpose-built multi-cue command.

### Acceptance

```text
[ ] Multi-cue Record Ref is one Undo
[ ] Failure leaves all targeted cues unchanged
[ ] Redo reapplies the complete gesture
[ ] Single-cue behavior remains one command
```

---

## CR-05 — Loaded Song cursor becomes stale or semantically wrong after entry edits

### Files

```text
Sources/Aurora/SongDirector.swift
Sources/AuroraUI/Panels/SongPanel.swift
App/project-update integration
```

### Current behavior

`SongDirector` stores:

```text
songID
entryIndex
```

UI-06 can now mutate the loaded song by:

```text
remove entry
reorder entries
delete song
```

No reconciliation occurs.

Example:

```text
Loaded entryIndex = 2

entries:
  [Intro, Verse, Chorus]

Remove Verse (index 1)

new entries:
  [Intro, Chorus]

entryIndex remains 2
```

Now the runtime cursor is out of range.

A different case is worse semantically:

```text
Loaded entryIndex = 1, pointing to Verse
Move Intro below Verse
```

Index 1 may now point to a different entry even though the engine is still running the previously loaded entry.

The original implementation plan explicitly listed:

```text
Director index stale after song edit
→ Clamp index on update; tests
```

That mitigation is not present.

### Required fix

Prefer preserving loaded **SongEntry identity**, not merely clamping an integer.

Recommended evolution:

```text
songID
currentEntryID
entryIndex derived/reconciled from current project song
```

If keeping `entryIndex`, project updates must at minimum:

```text
- clamp index
- deliberately handle reordered/deleted current entry
```

Best semantic behavior:

```text
If current entry still exists after reorder:
    follow it by entry ID

If current entry is deleted:
    choose a documented adjacent/fallback cursor state
    do not silently claim a different entry is current

If loaded song is deleted:
    reset SongDirector song state
    preserve engine look/playback unless explicitly stopped
```

Do not automatically fire/reload a different entry merely because document editing moved the cursor.

### Tests required

```text
loaded entry survives reorder by identity
remove entry before current preserves current identity
remove current entry produces documented fallback
remove last entry clamps/resets truthfully
delete loaded song resets SongDirector snapshot
editing nonloaded song does not affect cursor
```

---

## CR-06 — Undo for palette/preset/song deletion does not restore original order

### Files

```text
Sources/AuroraCore/Commands/GroupCommands.swift
Tests/AuroraCoreTests/CommandUndoTests.swift
```

### Current behavior

Commands such as:

```text
RemovePaletteCommand
RemovePresetCommand
RemoveSongCommand
```

store the removed object but not its index.

Undo appends:

```swift
$0.palettes.append(removed)
$0.presets.append(removed)
$0.songs.append(removed)
```

This changes ordering.

For Songs this is particularly important because song order is operator/set-list-visible.

Example:

```text
[A, B, C]

delete A
[B, C]

undo
[B, C, A]
```

Undo should restore the prior document state:

```text
[A, B, C]
```

`RemoveCueCommand` and the new `RemoveCueListCommand` already preserve original index and are the correct pattern.

### Required fix

Store `removedIndex` and reinsert at:

```swift
min(removedIndex, collection.count)
```

for:

```text
RemovePaletteCommand
RemovePresetCommand
RemoveSongCommand
```

Consider the same correction for other ordered user-facing collections opportunistically, but do not expand into unrelated cleanup if risky.

### Tests

For each:

```text
[A, B, C]
delete B
undo
assert [A, B, C]
```

---

# P2 — Strongly Recommended Before Hardware Smoke

## CR-07 — Song “+ Cue List” always inserts the first cue list

### File

```text
Sources/AuroraUI/Panels/SongPanel.swift
```

### Current behavior

The button is labeled:

```text
+ Cue List
```

but calls:

```swift
addEntryFromFirstList(song)
```

which always does:

```swift
guard let list = context.project.cueLists.first
```

The operator cannot choose which list is added.

This does not satisfy the intended "add existing cue/list reference" workflow once multiple cue lists exist.

### Required fix

Use, in order:

```text
selected cue-list ID from session selection, if valid
otherwise an explicit picker/menu
```

Do not silently use the first list unless the UI explicitly says:

```text
+ First Cue List
```

which is not the desired product behavior.

### Acceptance

```text
[ ] Operator can choose any existing cue list
[ ] Added entry references the chosen list UUID
[ ] Missing/no selection presents a picker or truthful prompt
```

---

## CR-08 — New Song silently seeds the first cue list

### File

```text
Sources/AuroraUI/Panels/SongPanel.swift
```

### Current behavior

`addSong()` automatically inserts the first cue list if any exists.

That creates document content the operator did not explicitly request.

### Recommendation

Prefer creating an empty Song:

```text
New Song
  → zero entries
```

Then let the operator explicitly add cue/list entries.

If auto-seeding is a deliberate product decision, document it and make it visible.

---

## CR-09 — Cue row role is single-axis, so selection can hide CURRENT/NEXT semantics

### Files

```text
Sources/AuroraUI/Panels/CueListPanel.swift
Sources/AuroraUI/Components/AuroraCueRow.swift
```

### Current behavior

Role resolution starts with:

```swift
if selectedCueID == cue.id { return .selected }
```

before current/next.

Therefore:

```text
selected + CURRENT → selected
selected + NEXT    → selected
```

`AuroraCueRowRole` cannot represent simultaneous semantic states.

CURRENT and selected currently share much of the visual styling, but accessibility and NEXT truth can be lost.

### Recommendation

Separate row state dimensions:

```text
playbackRole: normal/current/next/warning
isSelected: Bool
```

or introduce composite semantics.

Selection should be an overlay/focus state, not replace playback truth.

### Acceptance

```text
[ ] CURRENT remains identifiable while selected
[ ] NEXT remains identifiable while selected
[ ] accessibility announces both when appropriate
```

---

## CR-10 — Inspector command failures are silently swallowed

### File

```text
Sources/AuroraUI/Panels/InspectorPanel.swift
```

### Current pattern

Several inspector commit paths use:

```swift
try? context.session.perform(...)
onProjectChanged()
```

If a stale target or command validation error occurs, the failure disappears.

The UI then still refreshes as if the operation succeeded.

### Required fix

Use `do/catch`.

Surface errors through the app/document error/status path.

Do not call success refresh/status logic as if the mutation succeeded.

---

## CR-11 — Inspector drafts do not resynchronize when the same entity changes externally

### File

```text
Sources/AuroraUI/Panels/InspectorPanel.swift
```

### Current behavior

Draft fields reload on:

```text
onAppear
entity.id change
```

but not on same-ID document mutation.

Example:

```text
1. Rename Palette A in inspector.
2. Undo while Palette A remains focused.
3. Project object reverts.
4. Inspector draft can still contain the pre-undo name.
5. Next commit can reapply stale draft state.
```

Similar risk exists for:

```text
Cue
Palette
Preset
Song
```

### Recommendation

Provide a document/entity revision input, or observe relevant entity values and reload drafts when authoritative state changes and the user is not actively editing.

Avoid clobbering in-progress typing.

A simple robust approach may be:

```text
documentEpoch + editing/focus guard
```

---

## CR-12 — `OutputController.presentationSnapshot()` mutates observable state while called from SwiftUI rendering

### Files

```text
Sources/Aurora/Controllers/OutputController.swift
Sources/Aurora/Shell/PerformWorkspaceShell.swift
Sources/Aurora/Settings/AuroraSettingsRoot.swift
```

### Current behavior

SwiftUI view code calls:

```swift
appModel.output.presentationSnapshot()
```

`presentationSnapshot()` can then do:

```swift
outputStatus = snap.statusLine
objectWillChange.send()
```

This means a read performed during view rendering may publish observable changes.

That can cause:

```text
extra invalidation
"Publishing changes from within view updates" style warnings
render/update loops in unlucky conditions
```

There are also redundant manual `objectWillChange.send()` calls around `@Published` properties.

### Recommendation

Make:

```swift
presentationSnapshot()
```

a pure read.

Let:

```swift
refreshOutputStatus()
```

perform published mutation on the controller's scheduled refresh path.

Views should consume already-published semantic state where possible.

### Acceptance

```text
[ ] SwiftUI body reads do not mutate OutputController
[ ] Output health remains current
[ ] No redundant objectWillChange sends after @Published writes
```

---

## CR-13 — Phase checkpoint promise was not preserved in Git history

### Current archive

Git HEAD remains at the UI-03-era handoff history.

UI-04→07 are present as working-tree modifications/untracked files.

The autonomous plan explicitly required independently reviewable checkpoints.

### Why it matters

Clean phase commits/tags provide:

```text
bisectability
rollback
review isolation
regression localization
```

The handoff docs exist, but the code boundaries do not.

### Recommendation

After fixes:

```text
commit/tag coherent UI-04 boundary if reconstructable
commit/tag UI-05
commit/tag UI-06
commit/tag UI-07
```

If reconstructing historical commits would be risky, do not manufacture fake history. At minimum create a clean integration-fix commit and preserve clean boundaries going forward.

---

# P3 — Cleanup / UX Polish

## CR-14 — Remove developer-facing explanatory copy from final Perform chrome where unnecessary

Examples currently include:

```text
Health does not disable GO
SONG / SECTION (not GO)
Entry changes song section · GO advances cues in list
```

These were useful implementation guardrails, but the final production UI should communicate hierarchy through design, labels, and layout rather than repeatedly explaining architecture to the operator.

Keep useful concise operator guidance if testing proves it helps.

Do not remove clarity merely for aesthetics.

---

## CR-15 — `.disabled(false)` / `.opacity(1)` on Perform transport are redundant

The lines are harmless but communicate a false sense of protection.

The important rule is architectural:

```text
do not derive transport enabled-state from health
```

Remove no-op modifiers unless they are intentionally retained as temporary assertions/comments.

---

# Test Coverage Gaps to Add

The new tests for Palette creation, UpdatePreset undo, cue ordering, RemoveCueList undo, Song command undo, and cue update preservation are useful.

Add the following integration coverage.

## UI-04 / Palette

```text
palette apply filters attributes by fixture capability
position palette selected with mover + static PAR
color palette selected with RGB + dimmer
unsupported fixtures remain absent from Programmer attrs

palette create:
capable-owned + capable-untouched → mixed/skip
capable-owned + unsupported → common/partial
all capable untouched → refuse/no value

Record Ref:
unsupported fixtures get no ref
multi-cue Record Ref = one undo
mid-operation failure rolls back entire group
```

## UI-05 / Cue

```text
selected CURRENT row preserves both semantic states
selected NEXT row preserves both semantic states

record/update → applyProjectUpdate preserves playback identity
undo Update restores prior levels
```

## UI-06 / Song

```text
add chosen cue list, not first list
new Song starts with documented entry behavior

loaded entry reorder preserves current entry identity
remove entry before current
remove current entry
remove last entry
delete loaded Song
undo Song delete restores original order
```

## UI-07 / Perform

```text
Build → Perform → Build preserves playback cue/list identity
GO remains dispatchable with:
  output failed
  MIDI disconnected
  validation issues present

Song entry nav does not call GO
GO does not advance SongDirector entry
```

## Output / ENTTEC

See HW-01 test list.

---

# Manual macOS Verification Checklist

After fixes and green tests:

```text
[ ] Open Demo Summer Night
[ ] Select mixed-capability fixtures
[ ] Apply Color palette; verify only capable fixtures own color attrs
[ ] Apply Position palette; verify static fixtures do not gain pan/tilt attrs
[ ] Create palette with capable+untouched fixture; verify no false common
[ ] Record Ref to multiple selected cues; one Undo reverts all
[ ] Record cue from Programmer
[ ] Update selected cue; one Undo restores prior levels
[ ] Delete/Undo palette and Song; order restored exactly
[ ] Create Song with multiple cue lists
[ ] Add specifically chosen cue list
[ ] Load Song
[ ] Reorder/remove entries around current entry; current identity remains truthful
[ ] Delete loaded Song; Perform snapshot clears Song state without unexpected blackout
[ ] Enter Perform
[ ] GO/BACK/STOP operate with output warning present
[ ] MIDI GO updates CURRENT
[ ] Switch Build ↔ Perform during playback; playback remains continuous
[ ] Inspect Console for SwiftUI publish-during-render warnings
[ ] Approx. 80-fixture Programmer/color interaction remains responsive
```

Then, if HW-01 is implemented:

```text
[ ] ENTTEC appears in Local DMX device picker
[ ] Route U1 → Local
[ ] Enable ENTTEC
[ ] Real fixture receives DMX
[ ] Disconnect/reconnect behavior is truthful
```

---

# What Is Working Well

Do not lose these improvements while fixing the findings.

## Architecture

- Document command mutation → project event → UUID-preserving engine update is correct.
- Removing redundant explicit `reloadEngineFromSession()` from cue mutations is correct.
- Programmer remains ephemeral.
- Palettes apply into Programmer rather than becoming a second live layer.
- Cue Record and Update are clearly separate.
- Cue playback order is explicitly documented/tested as list-array order.
- Update is immediate and undoable rather than modal.
- Song navigation uses `SongDirector`.
- Song navigation remains separate from cue GO.
- Perform Mode does not create local playback authority.
- Perform structural safety is enforced in menu/toolbar surfaces.
- GO is not tied to health state.
- Performance UI remains snapshot-based rather than observing raw DMX frames.

## UI-04

- Mixed palette omissions are communicated instead of fabricated.
- Empty palette creation is refused.
- `UpdatePresetCommand` exists.
- Look application resolves palette references before Programmer write.
- Palette deletion warns on references.

## UI-05

- Select ≠ fire is preserved.
- Double-click/Fire are explicit execution.
- Cue number is treated as display metadata.
- Record/Update use Programmer capture.
- Timing metadata is kept separate from Update-level replacement.

## UI-06

- Songs reference global cue/list UUIDs.
- Removing an entry does not delete a cue.
- Automatic progression is not falsely exposed.
- Missing targets are surfaced.

## UI-07

- CURRENT/NEXT are sourced from performance truth.
- GO/BACK/STOP use existing app transport.
- Song navigation is secondary.
- Output/MIDI health are informational.
- Structural Build operations are absent/disabled in Perform.

---

# Recommended Fix Order

```text
1. HW-01 ENTTEC implementation decision
   - Implement before hardware smoke, OR
   - explicitly choose Art-Net/sACN for first smoke test

2. CR-01 Palette Apply capability filtering

3. CR-02 Record Ref capability filtering

4. CR-03 Capability-aware palette creation

5. CR-04 Atomic multi-cue Record Ref

6. CR-05 SongDirector loaded-entry reconciliation

7. CR-06 Ordered undo restore

8. CR-07 Chosen cue-list insertion in Song editor

9. CR-09 Cue row composite state

10. CR-10 / CR-11 Inspector error + draft synchronization

11. CR-12 Output snapshot purity / observation cleanup

12. Tests + full macOS build

13. UI-03→07 integration review

14. Physical-light smoke test
```

---

# Final Gate

## UI-04→07 implementation verdict

**CONDITIONALLY ACCEPTED.**

The architecture is strong enough to keep.

Do **not** roll back the four phases.

Fix the P1 seam issues and add the integration tests.

## Hardware readiness

**NOT YET READY FOR AN ENTTEC USB DMX Pro smoke test** because Aurora currently has framing/mock support but no real macOS ENTTEC discovery/open/selection/registration path.

A hardware smoke test can still proceed through **Art-Net or sACN** once the UI-03→07 integration fixes are closed, if a compatible network node is available.

## Closeout target

After the fixes:

```text
UI-03 Programmer
  → UI-04 Palettes
  → UI-05 Cues
  → UI-06 Songs
  → UI-07 Perform
  → Output
```

should be reviewed one final time as a complete operator pipeline.

Then connect real lights.
