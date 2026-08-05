# PR2 — Domain Model & Project Document Format

| Field | Value |
|-------|--------|
| **PR** | PR2 |
| **Title** | Domain model & project document format |
| **Status** | Implemented |
| **Depends on** | PR1 |
| **Unblocks** | PR3 (commands), PR4 (events), PR5 (fixture lib), PR9 (output) |
| **Parent design** | [`aurora-system-design.md`](./aurora-system-design.md) §5, §17, §18 |

---

## 1. Purpose

1. Define pure **show data types** in `AuroraModel` (`ShowProject` and related entities).
2. Implement **`.aurora` package** load/save with **schema version**.
3. Prove **round-trip** fidelity with golden tests.
4. Keep Engine / MIDI / Output / UI docking **unchanged** beyond a minimal sample-project hook in the app shell.

---

## 2. Non-goals

| Out of scope | Belongs to |
|--------------|------------|
| Command / undo | PR3 |
| Event bus / selection | PR4 |
| Seed fixture library resources | PR5 |
| Document-based `NSDocument` browser | PR7 |
| Engine loop, DMX, MIDI behavior | PR9+ / PR16+ |

---

## 3. Types (summary)

| Type | Role |
|------|------|
| `ShowProject` | Root document |
| `ProjectMetadata` / `ProjectPreferences` | Name, author, defaults |
| `Universe` | Logical DMX universe |
| `FixtureDefinition` / `ChannelDef` / `WheelDef` | Personality |
| `PatchedFixture` | Patched instance |
| `Group`, `Palette`, `Preset` | Selection & looks |
| `Cue`, `CueList`, `CueLevelData` | Cue data (sparse levels) |
| `Song`, `SongEntry`, `Annotation` | Set list |
| `MediaAssetRef`, `MIDIMapping` | Media + control bindings (data only) |
| `ProjectPackage` | Directory-bundle I/O |
| `ProjectPackageError` | Load/save failures |

Schema constant: `ProjectPackage.currentSchemaVersion == 1`.

---

## 4. On-disk layout (schema v1)

```
Show.aurora/
  project.json           # schemaVersion, metadata, preferences, workspaceLayoutId, cueListIds
  universes.json
  fixtures.json
  definitions.json
  groups.json
  palettes.json
  presets.json
  songs.json
  media-assets.json
  midi-mappings.json
  cues/
    <cueListId>.json
  media/                 # reserved for binaries
  layouts/               # reserved
```

JSON is pretty-printed with sorted keys and ISO-8601 dates for VCS-friendly diffs.

---

## 5. Acceptance

- [x] Core entities under `Sources/AuroraModel/`
- [x] Package save/load + schema version guard
- [x] Golden sample + empty project round-trip tests
- [x] Patch overlap helper (invariant support)
- [x] App shell shows sample project name/counts (no file dialog)
- [x] No Engine/MIDI/Output product logic beyond existing stubs

---

## 6. Next: PR3

Command protocol, undo/redo stack, and sample model commands (e.g. add/remove fixture) in `AuroraCore`.
