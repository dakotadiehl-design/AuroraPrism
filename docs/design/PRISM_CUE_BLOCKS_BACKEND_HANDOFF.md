# Prism Cue Blocks — Backend Handoff

**Audience:** Codex (UI/UX) and future maintainers  
**Product:** Prism (modules remain `Aurora*`)  
**Status:** Backend complete for this pass — **no Cue Blocks SwiftUI UI** was added  
**Spec:** `Prism_Cue_Blocks_Backend_Implementation_Spec.md`

---

## 1. Architecture summary

A **Cue Block** is a durable, fixture-scoped package of attribute values (`CueLevelData`). Cues hold **live references** (`CueBlockReference`) by UUID; editing a block updates every cue that references it on the next resolve.

```text
Programmer snapshot
  → CueBlockRecorder.record (pure; severity-coded issues)
  → AddCueBlockCommand / UpdateCueBlockCommand
  → AddCueBlockReferenceCommand (stable reference IDs)
  → CueResolver (track / cue-only)
       for each enabled ref (array order):
         resolve block palettes → capability-filter block only → merge (later wins)
       then PaletteResolver on cue.levels (palette then literals; unfiltered)
       → ActiveLook + structured issues
```

**Merge precedence:**

```text
earlier Cue Block  <  later Cue Block  <  cue palette refs  <  cue literals
```

Programmer remains ephemeral until recorded. Document mutations go through undoable commands.

---

## 2. Files added and modified

### Added

| Path | Role |
|------|------|
| `Sources/AuroraModel/CueBlock.swift` | Types, family classifier, recorder, project queries |
| `Sources/AuroraCore/Commands/CueBlockCommands.swift` | Add/Update/Remove block + ref commands |
| `Sources/AuroraEngine/FixtureCapabilityMap.swift` | Effective capability map + attribute filter |
| `Sources/AuroraEngine/CueBlockResolver.swift` | Block recall + cue composition |
| `Tests/AuroraModelTests/CueBlockModelTests.swift` | Model/package/recorder/validator |
| `Tests/AuroraCoreTests/CueBlockCommandTests.swift` | Commands + duplicate cue identity |
| `Tests/AuroraEngineTests/CueBlockResolverTests.swift` | Resolution precedence & issues |
| `docs/design/PRISM_CUE_BLOCKS_BACKEND_HANDOFF.md` | This document |

### Modified

| Path | Role |
|------|------|
| `Sources/AuroraModel/Cue.swift` | `cueBlockRefs` + explicit Codable |
| `Sources/AuroraModel/ShowProject.swift` | `cueBlocks` collection |
| `Sources/AuroraModel/ProjectPackage.swift` | Schema **5**, `cue-blocks.json` |
| `Sources/AuroraModel/SchemaMigration.swift` | v4 → v5 |
| `Sources/AuroraModel/ProjectValidator.swift` | Cue Block integrity rules |
| `Sources/AuroraModel/ResolutionIssue.swift` | Palette deps include Cue Blocks |
| `Sources/AuroraEngine/CueResolver.swift` | Composition + issue-aware APIs |
| `Sources/AuroraCore/Commands/ReorderCueCommand.swift` | `DuplicateCueCommand` remaps ref IDs |
| Related package/schema tests | Assert schema 5 / missing `cue-blocks.json` |

### Not modified (deferred)

- `AuroraLibraryPackage` — Cue Blocks are **not** library-portable this pass (fixture UUID remapping required).
- SwiftUI panels / shelves for Cue Blocks.

---

## 3. Public API for UI

### Model

```swift
public enum CueBlockType: String, Codable, … { intensity, color, position, beam, gobo, general }

public struct CueBlock: … {
    var id: UUID
    var name: String
    var type: CueBlockType
    var levels: CueLevelData
    var sourceGroupID: UUID?
    var notes: String
}

public struct CueBlockReference: … {
    var id: UUID           // membership identity (selection/reorder)
    var cueBlockID: UUID   // library identity
    var enabled: Bool
}

// On Cue:
var cueBlockRefs: [CueBlockReference]  // order is merge-significant

// On ShowProject:
var cueBlocks: [CueBlock]
```

### Queries

```swift
project.cueBlockReferenceCount(_ cueBlockID: UUID) -> Int
project.cueBlockReferenceSites(_ cueBlockID: UUID) -> [CueBlockReferenceSite]
project.cueBlocks(sourceGroupID: UUID?, type: CueBlockType?) -> [CueBlock]
project.cueBlock(id: UUID) -> CueBlock?
// Palette delete UI also sees Cue Block sites via:
project.paletteReferenceCount / paletteReferenceCueSummaries
```

### Recording

```swift
let caps = FixtureCapabilityMap.build(from: project) // or subset for selection
let result = CueBlockRecorder.record(.init(
    name: "Blue",
    type: .color,
    programmerValues: programmerSnapshot, // [UUID: [String: Double]]
    selectedFixtureIDs: orderedSelection,
    sourceGroupID: groupID,
    notes: "",
    existingID: nil, // set when updating to preserve UUID
    capabilityMap: caps
))
// result.cueBlock, result.issues (each has code + severity)
```

### Commands (`DocumentSession.perform`)

```swift
AddCueBlockCommand(cueBlock:)
UpdateCueBlockCommand(cueBlock:)
RemoveCueBlockCommand(cueBlockID:)  // does NOT strip cue refs
AddCueBlockReferenceCommand(listID:cueID:reference:) // or cueBlockID convenience
RemoveCueBlockReferenceCommand(listID:cueID:referenceID:)
MoveCueBlockReferenceCommand(listID:cueID:referenceID:toIndex:) // clamped like ReorderCue
SetCueBlockReferenceEnabledCommand(listID:cueID:referenceID:enabled:)
```

Reference IDs and duplicate-cue IDs are fixed at command construction / first perform so undo/redo is stable.

### Resolution

```swift
// Playback (wrappers):
CueResolver.resolveLook(cues:index:project:) -> ActiveLook

// Diagnostics / future UI:
CueResolver.resolveLookDetailed(cues:index:project:) -> CueResolutionResult
// CueResolutionResult { look: ActiveLook, issues: [CueBlockResolutionIssue] }

// Programmer recall (UI applies via programmer.setMany):
CueBlockResolver.resolveBlockForRecall(cueBlock:project:) -> CueBlockResolver.Result
```

**Diagnostics route:** Prefer `resolveLookDetailed` / `trackedLookDetailed` from controllers or a playback diagnostics snapshot. Compatibility wrappers discard issues for existing callers.

---

## 4. Package schema and migration

| Item | Value |
|------|--------|
| `ProjectPackage.currentSchemaVersion` | **5** |
| New file | `cue-blocks.json` (always written; required on load when schema ≥ 5) |
| Older packages (schema ≤ 4) | Missing `cue-blocks.json` → `cueBlocks = []` after migration |
| Cues without `cueBlockRefs` | Decode as `[]` |
| Palettes / presets | **Not** auto-converted to Cue Blocks |

Workspace layout schema is independent and was not bumped.

---

## 5. Merge precedence (as implemented)

1. Start empty.  
2. Enabled `cueBlockRefs` in array order; later block overwrites same fixture+attribute.  
3. Disabled refs contribute nothing (missing block still issues).  
4. Cue `levels` via `PaletteResolver` (palette refs then literals).  
5. Cue path merges **over** block accumulator.

**Capability filtering** applies only to Cue Block contributions, always from `FixtureCapabilityMap.build(from: project)`. Legacy palette/literal cue path is unchanged when `cueBlockRefs` is empty.

---

## 6. Issue codes

### Recording (`CueBlockRecordingIssue`)

| Code | Severity | Meaning |
|------|----------|---------|
| `no-selection` | error | No selected fixtures |
| `no-matching-values` | error | Nothing left after filtering |
| `fixture-no-matching-data` | warning | Fixture omitted |
| `attribute-family-skipped` | warning | Wrong family for typed block |
| `unsupported-attribute-skipped` | warning | Capability filter |

### Resolution (`CueBlockResolutionIssue`)

| Code | Severity | Meaning |
|------|----------|---------|
| `missing-cue-block` | error | Ref points at missing block |
| `empty-cue-block` | warning | Block has no fixtures |
| `missing-fixture` | warning | Fixture not in patch |
| `fixture-no-supported-attributes` | warning | Empty capability set |
| `capability-filtered-attribute` | warning | Dropped unsupported attr |
| `missing-palette-in-block` | warning | Palette inside block |
| `palette-resolution` | warning | Cue palette path issue |

### Validator (stable message codes)

`duplicate-cue-block`, `empty-cue-block`, `missing-cue-block-fixture`, `missing-cue-block-palette`, `missing-cue-block-source-group` (warning-style message), `missing-cue-block-ref`, `duplicate-cue-block-ref`, `duplicate-cue-block-ref-id`, `cue-block-type-attribute-mismatch`.

---

## 7. Tests run

```bash
swift test --filter CueBlock
# 37 tests, 0 failures

swift test --filter 'ProjectPackage|ProjectValidator|PaletteResolver|CueResolver|AMEPhaseAModel|PackageRecovery|AuroraModelTests'
# 140 tests, 0 failures (includes Cue Block model/package suites via AuroraModelTests filter)
```

No pre-existing failures observed in these filtered runs.

---

## 8. Known limitations / deferred

1. **Library package** does not export/import Cue Blocks (fixture UUID remapping not designed).  
2. Capability filtering of **legacy** palette/literal cue levels is intentionally unchanged.  
3. Engine frame path still uses `ActiveLook` wrappers; detailed issues are available via new APIs (UI not wired).  
4. No MIDI/OSC `fireCueBlock`, no per-reference blend/timing, no auto group re-sync.  
5. Soft HSV authoring capability requires RGB emitters (existing Engine rule).

---

## 9. No SwiftUI feature UI

Confirmed: this pass adds no Cue Blocks panel, shelf, inspector chrome, or gallery surface. Existing UI continues unchanged.

---

## 10. Minimal code examples

### Record from Programmer snapshot

```swift
let capabilityMap = FixtureCapabilityMap.build(from: session.project)
let record = CueBlockRecorder.record(.init(
    name: "Blue",
    type: .color,
    programmerValues: programmer.captureAttributeMap(), // UI supplies
    selectedFixtureIDs: selection.orderedIDs,
    sourceGroupID: selectedGroupID,
    capabilityMap: capabilityMap
))
guard let block = record.cueBlock else {
    // present record.issues (error severity)
    return
}
// optional: surface warnings from record.issues
try session.perform(AddCueBlockCommand(cueBlock: block))
```

### Add reference to a cue

```swift
let ref = CueBlockReference(cueBlockID: block.id, enabled: true)
try session.perform(AddCueBlockReferenceCommand(
    listID: listID,
    cueID: cueID,
    reference: ref
))
```

### Resolve and inspect issues

```swift
let detailed = CueResolver.resolveLookDetailed(
    cues: list.cues,
    index: selectedIndex,
    project: session.project
)
// apply detailed.look via existing playback path
for issue in detailed.issues {
    // diagnostics: issue.code, severity, entity UUIDs
}
```

### Recall into Programmer (UI layer)

```swift
let resolved = CueBlockResolver.resolveBlockForRecall(
    cueBlock: block,
    project: session.project
)
// map resolved.levels.fixtures → programmer.setMany(...)
// show resolved.issues as warnings
```

---

## Ready for UI pass when

- [x] Public model, command, recorder, resolver APIs compile without UI  
- [x] Schema 5 persistence + backward load tested  
- [x] Empty-ref cues resolve via same composition path (palette/literal semantics preserved)  
- [x] Live UUID references active in real `CueResolver` track/cue-only paths  
- [x] Capability filtering + broken-ref diagnostics outside SwiftUI  
- [x] No required UI behavior depends on direct `ShowProject` mutation  

**Backend is ready for Codex’s Cue Blocks UI/UX pass.**
