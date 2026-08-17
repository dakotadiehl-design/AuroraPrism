# Prism Cue Blocks — Backend Feature Request and UI Handoff Contract

**Audience:** Grok (backend implementation), followed by Codex (UI/UX implementation)  
**Product:** Prism  
**Scope of this document:** Domain model, persistence, commands, resolution, validation, and tests  
**Out of scope for this pass:** SwiftUI views, visual styling, panel layout, interaction polish, icons, and final user-facing copy

---

## 1. Objective

Implement **Cue Blocks**, a new first-class Prism show-document object inspired by the fixture-scoped preset workflow in LightKey.

A Cue Block is a named, reusable package of attribute values for a concrete set of fixtures. Users will eventually create one by selecting fixtures (directly or through a group), setting values in the Programmer, and saving the relevant values as a Cue Block. Cues can then reference multiple Cue Blocks to construct a complete lighting state.

Example:

```text
Dance Floor
├── Dimmer
│   ├── 25%
│   ├── 50%
│   └── 100%
└── Color
    ├── Amber
    ├── Blue
    └── Fanning: Violet → Blue

Cue: Dance Floor Blue
├── Cue Block: Dance Floor / Dimmer / 75%
└── Cue Block: Dance Floor / Color / Blue
```

The central semantic requirement is that a cue stores **references** to Cue Blocks. It must not merely copy their resolved values. Editing a Cue Block must therefore update the result of every cue that references it.

---

## 2. Terminology and Existing Concepts

Do not rename, remove, or silently reinterpret existing Prism types as part of this backend pass.

| Term | Meaning |
|---|---|
| `Palette` | Existing selection-independent reusable attribute values, referenceable from `CueLevelData` through `paletteRefs`. |
| `Preset` / Look | Existing stored multi-fixture look recalled into the Programmer. Preserve it for compatibility. |
| **Cue Block** | New fixture-scoped, normally attribute-family-scoped reusable data that cues can reference. |
| `Cue` | Timed playback object assembled from Cue Blocks, existing palette references, and literal cue values. |
| Workspace layout/focus preset | Unrelated UI state. Do not touch it. |

The user-facing name for this feature is **Cue Block**. Backend symbols should use `CueBlock`, not another occurrence of `Preset`.

---

## 3. Product Semantics

### 3.1 Fixture scope

A Cue Block records concrete fixture UUIDs in its level data. If it was created from a group, the group's UUID may be retained as provenance, but the group's current membership must not dynamically determine playback.

This is intentional:

- Changing group membership must not silently alter existing cues.
- Deleting a group must not invalidate an otherwise usable Cue Block.
- A future UI may offer an explicit “Update fixtures from group” operation.

The concrete fixture IDs stored in `levels` are authoritative. `sourceGroupID` is optional metadata only.

### 3.2 Attribute scope

Most Cue Blocks represent one semantic family:

- intensity
- color
- position
- beam
- gobo
- general

For example, a Color Cue Block must not accidentally capture intensity simply because intensity is also present in the Programmer.

Use a dedicated `CueBlockType` enum, even if its initial cases mirror `PaletteType`. This avoids coupling two concepts and leaves room for their semantics to diverge.

`general` may contain multiple attribute families and supports broader reusable blocks. It should be valid but not the default escape hatch for incorrect family classification.

### 3.3 Per-fixture values

Cue Blocks must preserve per-fixture values. A fanned color or position block cannot be represented as one global attribute dictionary.

Example:

```text
Fanning: Violet → Blue
Fixture A: colorHue = 0.78
Fixture B: colorHue = 0.72
Fixture C: colorHue = 0.66
Fixture D: colorHue = 0.60
```

### 3.4 References remain live

When Cue A references Cue Block `Blue`, changing `Blue` must change Cue A's subsequently resolved output. Do not materialize Cue Block values into the cue when adding the reference.

### 3.5 Safe partial resolution

Broken or stale data must produce diagnostics, not crashes:

- Missing Cue Block UUID
- Missing fixture UUID
- Missing palette referenced inside a Cue Block
- Incompatible palette family
- Attribute no longer supported by the fixture personality
- Empty Cue Block

Resolution should continue for all valid data.

---

## 4. Required Domain Model

Add these types to `AuroraModel` using public, `Codable`, `Equatable`, `Sendable`, `Identifiable`, and `Hashable` conformance where appropriate.

```swift
public enum CueBlockType: String, Codable, Sendable, Hashable, CaseIterable {
    case intensity
    case color
    case position
    case beam
    case gobo
    case general
}

public struct CueBlock: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var type: CueBlockType
    public var levels: CueLevelData
    public var sourceGroupID: UUID?
    public var notes: String
}

public struct CueBlockReference: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var cueBlockID: UUID
    public var enabled: Bool
}
```

### 4.1 Why a reference has its own ID

Do not model cue membership as only `[UUID]`. A stable reference ID allows the later UI to select, reorder, disable, inspect, and remove an individual cue entry without confusing it with the referenced library object. It also leaves room for future per-reference metadata without changing cue identity semantics.

Do not add per-reference intensity, timing, or blend behavior in this pass.

### 4.2 Changes to existing models

Add:

```swift
public var cueBlocks: [CueBlock]
```

to `ShowProject`, with a default of `[]` in its initializer.

Add:

```swift
public var cueBlockRefs: [CueBlockReference]
```

to `Cue`, with a default of `[]` in its initializer.

The order of `cueBlockRefs` is semantically significant and must be preserved through Codable, duplication, commands, and package round trips.

Use backward-compatible decoding for `Cue` so older cue-list files without `cueBlockRefs` decode to an empty array.

---

## 5. Recording Contract

Implement a UI-neutral backend service in `AuroraCore`, tentatively named `CueBlockRecorder`.

The UI will later provide:

- Cue Block name
- Requested `CueBlockType`
- Current Programmer snapshot
- Ordered selected fixture IDs
- Optional source group ID
- Current project fixture definitions/capabilities

The recorder must:

1. Require at least one selected fixture.
2. Read only selected fixtures; do not fall back to every fixture in the Programmer.
3. Keep the selected fixture order in `CueLevelData.fixtures` so fanning and later presentation remain deterministic.
4. Filter values to the requested semantic family.
5. Filter attributes unsupported by each fixture's current personality.
6. Preserve distinct per-fixture values.
7. Omit fixtures with no recordable values after filtering.
8. Reject creation if no values remain.
9. Return structured warnings for partially skipped fixtures or attributes.
10. Produce a `CueBlock`; it must not mutate `ShowProject` directly.

Suggested API shape:

```swift
public enum CueBlockRecorder {
    public struct Request: Sendable { /* inputs above */ }
    public struct Result: Equatable, Sendable {
        public var cueBlock: CueBlock?
        public var issues: [CueBlockRecordingIssue]
    }

    public static func record(_ request: Request) -> Result
}
```

Use structured issue codes/enums rather than localized UI strings as the only result. A later UI must be able to distinguish “no selection,” “Programmer has no matching family values,” and “some selected fixtures unsupported.” Human-readable diagnostic text may accompany each code.

### 5.1 Attribute-family classification

Do not place the canonical classification table in SwiftUI. Provide a backend/model helper that maps semantic attribute tags to `CueBlockType`.

At minimum, classify the attribute names already recognized by Prism, including:

- `intensity` → intensity
- `colorHue`, `colorSat`, `colorVal`, `colorWB`, `colorR`, `colorG`, `colorB`, `colorW`, `colorA`, `colorUV`, `colorWarmWhite`, `colorCoolWhite`, `colorLime`, `colorCyan` → color
- `pan`, `tilt` → position
- known beam attributes → beam
- known gobo attributes → gobo

Search current fixture-definition and Programmer attribute conventions before finalizing the complete mapping. Add focused classification tests. Unknown tags may be recorded only by `general`, unless the repository already has authoritative semantic metadata that can classify them safely.

### 5.2 Updating an existing Cue Block

The recorder/service must also support replacing an existing Cue Block's recorded contents while preserving its UUID. Name, type, source group, and notes should be supplied explicitly by the caller rather than inferred from stale state.

The update itself must be performed through `UpdateCueBlockCommand`.

---

## 6. Cue Composition and Resolution

Implement a resolver in `AuroraEngine`, tentatively named `CueBlockResolver`, or extend `CueResolver` through a clearly isolated helper.

### 6.1 Deterministic precedence

Resolve a cue in this order:

1. Start empty.
2. Resolve enabled Cue Block references in array order.
3. Later Cue Blocks override earlier Cue Blocks for the same fixture and attribute.
4. Resolve the cue's existing `levels.paletteRefs` and merge them over Cue Block results.
5. Apply the cue's literal `levels.attributes` last.

In shorthand:

```text
earlier Cue Block
  < later Cue Block
  < cue palette references
  < cue literal values
```

This extends Prism's existing rule that literal cue values win over reusable references.

Do not depend on dictionary iteration order. Reference-array order and sorted attribute keys must produce deterministic results.

### 6.2 Palettes inside Cue Blocks

Because `CueBlock.levels` uses `CueLevelData`, it may contain existing `paletteRefs`. Resolve those using `PaletteResolver` before merging the block. Preserve and report palette resolution issues with enough context to identify the owning Cue Block and, when applicable, the cue being resolved.

### 6.3 Resolution result

Expose a structured result suitable for the engine and later UI diagnostics:

```swift
public struct CueBlockResolutionResult: Equatable, Sendable {
    public var levels: CueLevelData
    public var issues: [CueBlockResolutionIssue]
}
```

Each issue should carry stable identifiers where relevant:

- cue ID
- Cue Block reference ID
- Cue Block ID
- fixture ID
- palette ID
- attribute tag
- stable issue code
- human-readable message

### 6.4 Capability truth

Resolved Cue Block attributes must be filtered against current fixture capabilities before they can enter the final active look. A changed fixture personality must not cause obsolete attributes to leak into Programmer or engine state.

Prefer sharing an existing authoritative capability helper. Do not duplicate a UI-only filtering implementation inside multiple callers. If current capability logic lives in `AuroraUI`, move or reproduce the authoritative semantic portion in a lower-level module without making `AuroraModel` depend on UI.

### 6.5 Tracking and cue playback

Cue Block resolution must feed the same resolved cue path used by tracking and cue-only playback. Do not create a second playback engine or a UI-only resolution path. Existing cues without Cue Block references must resolve exactly as before.

---

## 7. Programmer Recall Contract

The later UI will need to recall a Cue Block into the Programmer for previewing and editing. Grok should provide a reusable resolution operation but should not build or modify SwiftUI panels.

Required backend behavior:

- Resolve the Cue Block's palette references.
- Filter against current fixture capabilities.
- Return fixture-level literal values plus structured issues.
- Do not require a new current fixture selection to determine target fixtures; the Cue Block's stored fixture scope is authoritative.
- Do not mutate the Programmer inside `AuroraModel` or `AuroraEngine` utility code.

The UI/controller layer will decide when to call `programmer.setMany(...)`, how to present warnings, and whether applying a block changes selection.

---

## 8. Commands and Undo/Redo

All document mutations must go through `DocumentSession.perform` and commands. Add commands consistent with existing group/palette/preset commands:

- `AddCueBlockCommand`
- `UpdateCueBlockCommand`
- `RemoveCueBlockCommand`
- `AddCueBlockReferenceCommand`
- `RemoveCueBlockReferenceCommand`
- `MoveCueBlockReferenceCommand`
- `SetCueBlockReferenceEnabledCommand`

Requirements:

- Add undo removes the inserted object/reference.
- Remove undo restores the original array index.
- Update undo restores the complete previous object.
- Move undo restores the original order.
- Commands fail clearly when the target cue, list, reference, or Cue Block is missing.
- Each successful mutation updates `metadata.modifiedAt` and the document dirty state through the existing command path.
- Adding a reference must reject a missing Cue Block ID.
- Adding the same Cue Block more than once to one cue should be rejected unless a concrete product need emerges later. Return a clear command error.

Deleting a Cue Block must **not** silently delete or materialize its cue references. Preserve broken references so validation and the later UI can identify and repair them. The UI will provide a dependency-aware confirmation before invoking the remove command.

Cue duplication must preserve Cue Block references, including their order and enabled state, but each duplicated cue reference should receive a new reference UUID so references remain independently addressable.

---

## 9. Persistence and Migration

### 9.1 Project package

Add a root package file:

```text
cue-blocks.json
```

Update `ProjectPackage` save/load, package manifests/known-file validation, round-trip tests, and any export/import packaging surfaces that carry full show content.

Bump `ProjectPackage.currentSchemaVersion` from its current value to the next schema version.

Migration behavior:

- Packages from earlier schema versions have `cueBlocks = []`.
- For the new schema version and later, `cue-blocks.json` is required. A missing required file is package damage, consistent with current package policy.
- Older cue-list JSON files without `cueBlockRefs` decode with `[]`.
- Do not automatically transform existing `Palette` or `Preset` objects into Cue Blocks. Their semantics are not equivalent, and an automatic migration could alter shows.

### 9.2 Library package

Update `AuroraLibraryPackage` so a library can include Cue Blocks.

Import/upsert requirements:

- Preserve Cue Block UUID identity.
- Include Cue Blocks in library contents and `cue-blocks.json`.
- Validate dependencies on fixtures, source groups, and palettes.
- Do not silently remap UUIDs unless the existing library-import contract already provides a comprehensive reference remapping mechanism.

If full dependency-safe library import cannot be implemented cleanly in this pass, fail explicitly or document the limitation in the handoff; do not import blocks with silently corrupted references.

---

## 10. Validation and Dependency Queries

Extend `ProjectValidator` with stable issues for:

- Duplicate Cue Block IDs
- Cue Block referencing a missing fixture
- Cue Block referencing a missing palette
- Cue Block with `sourceGroupID` pointing to a missing group (warning only; levels remain usable)
- Cue referencing a missing Cue Block
- Duplicate Cue Block references within the same cue
- Cue Block containing attributes incompatible with its declared type
- Empty Cue Block

Add model/core query helpers for the UI:

```swift
project.cueBlockReferenceCount(_ cueBlockID: UUID) -> Int
project.cueBlockReferenceSites(_ cueBlockID: UUID) -> [CueBlockReferenceSite]
project.cueBlocks(sourceGroupID: UUID?, type: CueBlockType?) -> [CueBlock]
```

`CueBlockReferenceSite` should expose cue-list ID/name, cue ID/number/name, and reference ID. Do not return preformatted UI-only strings as the sole API.

Also update deletion/dependency reporting for palettes: a palette referenced inside a Cue Block must count as a palette dependency.

---

## 11. UI Handoff API Requirements

Codex will implement UI/UX after the backend is complete. The backend must make the following interactions possible without direct `ShowProject` mutation or UI-owned business logic:

| Future UI action | Required backend surface |
|---|---|
| Save selected Programmer values as a Cue Block | `CueBlockRecorder` structured request/result + `AddCueBlockCommand` |
| Update an existing Cue Block from Programmer | Recorder/update service + `UpdateCueBlockCommand` |
| Browse by originating group and type | `sourceGroupID`, `CueBlockType`, query helpers |
| Show fixture count and affected attributes | Derivable structured data/helpers, not parsed display strings |
| Apply a Cue Block to Programmer | Capability-safe resolver returning literal fixture levels and issues |
| Add a Cue Block to selected cue | `AddCueBlockReferenceCommand` |
| Reorder blocks inside a cue | `MoveCueBlockReferenceCommand` |
| Temporarily disable a block | `SetCueBlockReferenceEnabledCommand` |
| Remove a block from a cue | `RemoveCueBlockReferenceCommand` |
| Warn before deleting a used block | Reference count/site queries |
| Display broken references | Stable validator/resolver issues with entity IDs |
| Show live-linked update behavior | Cue resolution by UUID at playback time |

Public APIs used by the UI must not depend on SwiftUI view types or localized strings. Prefer small value types, stable issue codes, UUIDs, and deterministic arrays.

The backend implementation should compile without requiring the new UI to exist. Existing UI should continue to work unchanged, even though it will not expose Cue Blocks yet.

---

## 12. Non-Goals for Grok's Backend Pass

Do not implement:

- A Cue Blocks SwiftUI panel or shelf
- The screenshot's exact tree, folder, icon, or color styling
- Drag and drop
- Context menus or inspectors
- Keyboard shortcuts
- User-facing naming dialogs
- Automatic group-membership synchronization
- Per-reference scaling, timing, fades, or blend modes
- MIDI/OSC/AME `fireCueBlock` actions
- Replacement or removal of existing Palette/Preset functionality
- Workspace layout changes
- A second lighting/playback engine

Avoid placeholder UI. Backend completeness and a clean UI contract are more valuable than an inert visual surface.

---

## 13. Required Tests

Add focused tests in the appropriate model, core, engine, and package test targets.

### 13.1 Model and Codable

- Cue Block round-trip preserves ID, type, source group, notes, fixture order, literals, and palette references.
- Old cue JSON without `cueBlockRefs` decodes to an empty array.
- Reference order and enabled state survive round-trip.

### 13.2 Recording

- No selection returns a structured failure and creates no block.
- Only selected fixtures are captured.
- Color recording excludes intensity and position.
- Intensity recording excludes color.
- Per-fixture fanned values remain distinct and ordered.
- Unsupported attributes are skipped and reported.
- Fixtures with no matching values are omitted and reported.
- An all-empty result is rejected.
- Updating contents preserves Cue Block UUID.

### 13.3 Commands

- Add/update/remove undo and redo correctly.
- Remove undo restores original project order.
- Add/remove/move/enable reference commands undo and redo correctly.
- Duplicate reference insertion is rejected.
- Cue duplication creates new reference IDs while preserving referenced Cue Block IDs and order.

### 13.4 Resolution

- One Cue Block resolves into a cue.
- Multiple non-conflicting blocks combine.
- Later block wins on an attribute conflict.
- Cue palette reference wins over a block value.
- Cue literal wins over all references.
- Disabled reference contributes nothing.
- Editing a Cue Block changes every referencing cue's next resolution.
- Missing block produces an issue while valid blocks continue resolving.
- Missing palette inside a block produces contextual issues without crashing.
- Changed fixture capability filters stale attributes.
- Existing cue resolution is unchanged when `cueBlockRefs` is empty.
- Tracking and cue-only paths consume the same composed result.

### 13.5 Persistence and validation

- New package save/load round-trip includes `cue-blocks.json` and cue references.
- Older supported package loads with no Cue Blocks.
- New-schema package missing `cue-blocks.json` fails as damaged.
- Validator finds missing block, fixture, group provenance, and palette dependencies.
- Palette dependency count includes references inside Cue Blocks.
- Library package round-trip/upsert preserves Cue Blocks and their references.

---

## 14. End-to-End Backend Acceptance Scenarios

### Scenario A — Dance Floor Blue

Given four selected Dance Floor fixtures with blue values in the Programmer, recording a Color Cue Block named `Blue` creates one block containing those four fixture IDs and only color attributes. Adding its reference to a cue causes that cue to resolve blue on those fixtures.

### Scenario B — Compose color and dimmer

Given `Dance Floor / Color / Blue` and `Dance Floor / Dimmer / 75%`, a cue referencing both resolves both blue color and 75% intensity for the stored fixture scope.

### Scenario C — Fanned values

Given four fixtures with different hue values, recording a Color Cue Block preserves all four values. Recalling or resolving the block recreates the fan rather than collapsing it to one common color.

### Scenario D — Live reference update

Given seven cues referencing `Blue`, updating the block's hue while preserving its UUID changes the next resolved result of all seven cues without rewriting those cues.

### Scenario E — Cue override

Given a cue that references `Dimmer 75%` but contains a literal intensity of 65% for one fixture, that fixture resolves to 65% while the remaining block fixtures resolve to 75%.

### Scenario F — Group changes

Given a block created from the `Dance Floor` group, later adding a fixture to the group does not add it to the existing block. The block retains its original concrete fixture scope.

### Scenario G — Broken dependency

Given a deleted Cue Block that remains referenced by a cue, the project validator and resolver report the missing UUID. Other Cue Blocks in the cue still resolve, and the application does not crash.

---

## 15. Implementation Constraints

Follow established Prism architecture:

- `ShowProject` remains authoritative for durable show data.
- Programmer state remains engine-ephemeral until recorded.
- Document mutations go through undoable commands.
- Ordinary edits use the existing project update path; do not call destructive engine load APIs.
- Resolve through the existing cue/playback authority; do not create parallel output state.
- Preserve deterministic ordering.
- Keep model and engine code independent of SwiftUI.
- Preserve all existing Palette and Preset behavior unless a change is strictly required to integrate Cue Block resolution.
- Do not expose behavior that is represented in the model but not actually wired into resolution.

Before modifying files, inspect current uncommitted work and preserve unrelated user/Codex changes. In particular, coordinate carefully around any existing modifications to cue recording, `AppModel`, `CueListPanel`, `ProgrammerPanel`, and `ProgrammerCueBridge`.

---

## 16. Grok Deliverables and Handoff

Grok's completion response must include:

1. A concise architecture summary.
2. Exact files added and modified.
3. Final public API signatures intended for UI use.
4. Package schema version and migration behavior.
5. Merge precedence as actually implemented.
6. Validation and resolution issue codes.
7. Tests added and exact test commands run.
8. Test results, including any pre-existing failures.
9. Known limitations or deferred items.
10. Confirmation that no SwiftUI feature UI was added.

Also create a short backend handoff document under `docs/design/` containing the above information and at least one minimal code example for:

- Recording a Cue Block from a Programmer snapshot
- Adding it to the project through a command
- Adding a reference to a cue through a command
- Resolving the cue and inspecting issues

The backend is ready for Codex's UI/UX pass only when:

- All required public data and command APIs compile.
- Persistence and backward compatibility are tested.
- Existing cues resolve unchanged.
- Cue Block composition is active in the real engine cue path.
- Capability filtering and broken-reference diagnostics are available outside SwiftUI.
- No required UI behavior depends on direct model mutation or parsing status strings.

---

## 17. Final Product Principle

A Cue Block is not a button that pastes values and forgets where they came from. It is a durable, fixture-scoped lighting building block whose identity remains visible to every cue that uses it.

That principle should govern the model, persistence format, commands, resolver, validation, and eventual UI.
