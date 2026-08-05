# Stage C — UI State Ownership Handoff

**Purpose:** Contracts for the visual UI redesign. Written after Stage C (AppModel split).  
**Date:** 2026-08-05  
**Do not start visual redesign until Go/No-Go checklist is green** (see post-remediation review §13).

---

## Composition root

`AppModel` is a **thin composition root** + menu/panel facade. Real ownership lives in controllers under `Sources/Aurora/Controllers/`.

| Controller | File | Owns |
|------------|------|------|
| `ProjectController` | `ProjectController.swift` | `DocumentSession`, document URL, dirty, save/open/new/undo, fixture library, panel context |
| `ShowControlController` | `ShowControlController.swift` | `LightingEngine`, `ControlActionRouter`, `SongDirector`, transport, `PerformanceSnapshot` |
| `InputController` | `InputController.swift` | CoreMIDI, learn, RTP-MIDI, OSC, MIDI log/status |
| `OutputController` | `OutputController.swift` | `OutputManager`, Art-Net/sACN drivers & config, output status line |
| `RemoteController` | `RemoteController.swift` | TCP/web remote host, PIN enable, lock, kick, remote snapshots |
| `DiagnosticsController` | `DiagnosticsController.swift` | `DiagnosticsStore`, console log, validation issue count |
| `WorkspaceController` | `WorkspaceController.swift` | Panel layout, Build/Perform mode |
| `AppSettingsStore` | `AppSettingsStore.swift` | App-global prefs (frame rate, console timestamps) |

Observation: children are `ObservableObject`; AppModel cascades `objectWillChange`. Prefer **`notifyUI()`** over the old dual revision/`bump` pattern (`bump()` remains as an alias).

---

## Shared presentation types

### `PerformanceSnapshot`

Built ~4 Hz (status timer) and after transport — **not** every engine frame.

Fields: show name, dirty, engine running, frame index/rate, cue index/name/list, playback phase, `SongPerformanceSnapshot`, validation issue count, output status line, active channel count.

**Consumers:** Mac Perform chrome, status bar, remote `RemoteSnapshot` construction.

### `SongPerformanceSnapshot`

From `SongDirector.snapshot(project:)`: song title, entry index/count, current/next labels, cue list/cue IDs, annotations, progression mode, missing-target flag.

### `ShowActionCatalog` (`AuroraMIDI`)

Stable bindable actions for Settings (MIDI/OSC) and Perform. Scalar actions: `programmerAttr`.

---

## What the UI may bind to

| UI surface | Bind to |
|------------|---------|
| Document title / dirty | `appModel.document` / `windowTitle` / `session.isDirty` |
| Panel layout | `appModel.workspace.layout` |
| Build vs Perform | `appModel.workspace.mode` |
| Live cue / GO | `appModel.performance` + `showControl` transport |
| Programmer | `engine.programmer` (still engine-owned runtime) |
| Selection order | `session.selection.snapshot.orderedFixtureIDs` |
| Output health line | `output.outputStatus` / `performance.outputStatusLine` |
| Project issues | `ProjectValidator` after mutation; count on `performance.validationIssueCount` |
| MIDI learn | `input.isMIDILearning`, `armMIDILearn` / `cancelMIDILearn` |
| Remote PIN status | `remote.remoteStatus` |

**Do not** put engine frame buffers into general SwiftUI `@State` every tick. Use throttled `PerformanceSnapshot` + dedicated monitor panels.

---

## Control path (unchanged)

```
UI / MIDI / OSC / remote → ControlActionRouter / perform(ShowAction)
  → LightingEngine / SongDirector
  → OutputManager (protocol-routed) → drivers
```

Document mutations still go through **commands** + `DocumentSession`.

---

## Go/No-Go for visual redesign

All Stage A P0 + Stage B UI Gate domain items + Stage C ownership are in tree. Remaining optional during UI work: P2/P3 (TLS, ENTTEC, GDTF, native Pad, etc.).

**Next product step:** write UI specification against this ownership map; implement dark professional workspace (Build/Perform, browser / programmer / inspector) consuming these APIs only.
