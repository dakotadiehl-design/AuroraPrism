# Aurora — UI / Backend Contract

**Purpose:** Authoritative API and domain contract for the **visual UI redesign**.  
**Read with:** `docs/PROJECT_HANDOFF.md`, `docs/STAGE_C_UI_STATE_HANDOFF.md`.  
**Last updated:** 2026-08-05 (post Pre-UI blockers: save coordinator + output health)

Do **not** invent controls for unimplemented behavior. Do **not** bypass commands / `ControlActionRouter` / controllers.

---

## 1. Composition root

`AppModel` is the composition root and menu facade. Prefer binding views to focused controllers:

| UI surface | Controller / store |
|------------|-------------------|
| Patch, fixtures, groups, cues, save/open | `ProjectController` (`document`) |
| Transport, programmer, song, performance chrome | `ShowControlController` (`showControl`) |
| MIDI / OSC / RTP / learn / MIDI log | `InputController` (`input`) |
| Art-Net / sACN / output health | `OutputController` (`output`) |
| Remote PIN / clients | `RemoteController` (`remote`) |
| Console / typed events | `DiagnosticsController` (`diagnostics`) |
| Build vs Perform, panel layout | `WorkspaceController` (`workspace`) |
| App frame rate, console prefs | `AppSettingsStore` (`settings`) |

`notifyUI()` / `objectWillChange` cascade from children is already wired. Do **not** reintroduce a global `revision` rebuild of the whole workspace.

---

## 2. Live control path

```
UI / MIDI / OSC / remote
  → ControlActionRouter.dispatch / handleMIDIEvents   [may be non-MainActor]
  → LightingEngine / DocumentSession
  → OutputManager → drivers
```

### Rules

1. **Live transport** (`go` / `back` / `stop` / `fireCue*` / programmer attributes) must call `ControlActionRouter` **without waiting on MainActor** from network/MIDI callbacks.
2. **UI status / logs** may hop to MainActor **after** live dispatch.
3. **Song next/previous** may use MainActor (`SongDirector` is `@MainActor`).
4. Document mutations always go through `DocumentSession.perform` + commands (undoable).
5. Programmer values are engine-ephemeral until recorded into a cue/preset.

### Multi-observer control events (UI-GATE-1)

`ControlActionRouter` supports **multiple** UI observers via `addUIObserver` / `removeUIObserver`.

- MIDI log status: installed by `InputController.startMIDI`
- Show-control presentation: installed by `AppModel` via `showControl.addUIObserver`

Never use a single replaceable callback for two consumers.

---

## 3. State ownership

| Kind | Owner | Notes |
|------|--------|------|
| Show document | `ProjectController` / `DocumentSession` | Dirty = unique state IDs; groups mark dirty on first mutation |
| Package I/O | `ProjectSaveCoordinator` (via `ProjectController`) | **All** Save / Save As / autosave for a destination are serialized; stale autosave never overwrites a newer manual save on disk |
| Engine / playback | `ShowControlController` / `LightingEngine` | `updateProject` preserves look; `load` is destructive |
| Selection | `DocumentSession.selection` | `orderedFixtureIDs` is phase order |
| Workspace layout / mode | `WorkspaceController` | `WorkspaceMode.build` \| `.perform` |
| App prefs | `AppSettingsStore` | Frame rate **is** applied to engine |
| Project prefs | `ShowProject.preferences` | Cue defaults; `preferredFrameRateHz` is **deprecated / unused by engine** |
| Output status chrome | `OutputController.presentationSnapshot()` | Built from live `healthSnapshots()` each poll — not a stale config-time string |

---

## 4. Domain semantics the UI must respect

### Output routing (`Universe.protocolHint`)

| Value | Meaning |
|-------|---------|
| `none` | **No physical output** (safe default) |
| `local` | Local DMX only (e.g. ENTTEC USB Pro framing) |
| `artNet` | Art-Net only |
| `sACN` | sACN only |
| `mirror` | Explicit fan-out to all physical protocols |

Do not label `none` as “all drivers”. Mock drivers with protocol `.none` are test sinks only.

### PerformanceSnapshot (Perform + remote)

- `activeChannelCount` = sum of channels > 0 across **all** universes
- `activeUniverseCount` = universes with at least one active channel
- Mac Perform and remote must use the same totals
- High-rate DMX arrays stay in Universe Monitor snapshots — not the SwiftUI observation tree

### Song progression

- Only **manual** progression is implemented
- Do **not** expose a working Automatic mode control until completion semantics exist
- `setProgressionMode(.automatic)` is rejected (stays manual)

### Frame rate

- App setting `AppSettingsStore.preferredFrameRateHz` → `LightingEngine.updateConfiguration`
- Clamped 20…44 Hz
- Project-level `preferredFrameRateHz` is package-compat only

### Local DMX hardware

- Contract type: `LocalDMXDeviceDescriptor` (`AuroraOutput`)
- ENTTEC driver is **USB DMX Pro** framed protocol — **not** Open DMX
- Real serial enumeration not implemented; UI may show unavailable/empty list

### MIDI

- Status UI binds to `InputController` (`midiStatus`, `lastMIDIEvent`, `midiLog`)
- Parser preserves running status **and** incomplete messages across packets
- Realtime (`0xF8+`) may interleave without destroying pending channel messages

### Package save / autosave

- All writes go through `ProjectSaveCoordinator` (per-destination serial actor)
- Manual Save and autosave never run concurrent I/O to the same package path
- Stale autosave after a newer manual write is **skipped** (does not call `ProjectPackage.save`)
- Document marked clean only if the written state ID still matches current `documentGeneration`
- Concurrent edits during a save leave the document dirty
- Quit uses `prepareToTerminate()` → await save → idempotent `shutdown()`

### Output health presentation

- Prefer `OutputPresentationSnapshot` aggregates: `healthy` / `warning` / `failed` / `disabled`
- Refresh from driver health on the presentation timer; do not trust a string set only at config change

---

## 5. What the UI must not bypass

1. Direct mutation of `ShowProject` without commands
2. Calling `engine.load` for ordinary edits (use project update path)
3. Inferring MIDI activity only from engine state
4. Building Settings controls for unimplemented behavior (automatic song, Open DMX, project frame-rate override)
5. Stuffing 40 Hz DMX into `@Published` app-wide state
6. Second lighting engine for remote/iPad

---

## 6. Build vs Perform UX

| Mode | Intent |
|------|--------|
| **Build** | Dense dockable editors (patch, programmer, cues, effects, inspector) |
| **Perform** | Calm transport + health; hard to edit accidentally |

Web/iPad remote ≈ Perform, not Build.

---

## 7. Intentionally deferred (show as unavailable if exposed)

- Real ENTTEC serial transport / device enumeration
- Hardware Art-Net/sACN soak proof
- Automatic song entry progression
- Security-scoped bookmark store (entitlement reserved only)
- App integration XCTest target for controller wiring
- Full GDTF, TLS remote, native iPad app
- Dynamic dylib plugins (protocols exist)
- Notarization / Team signing
- Production AppIcon artwork (placeholder catalog)

### UI composition (UI-FOUNDATION-1 Option A)

`AuroraUI` = design-system + pure views. Controller-aware screens live in the **app target**. Do not make `AuroraUI` depend on the executable or re-bind every view to full `AppModel`.

---

## 8. Historical documents

These reviews are **completed backlog**, not active task lists:

- `Aurora_Final_Backend_UI_Gate_Review.md` — fixed 2026-08-05
- `Aurora_Post_Remediation_Deep_Review_UI_Readiness.md` — largely done
- `Aurora_Deep_Code_Review_Fixes.md` — historical

Active memory: **this file** + `PROJECT_HANDOFF.md` + `STAGE_C_UI_STATE_HANDOFF.md`.
