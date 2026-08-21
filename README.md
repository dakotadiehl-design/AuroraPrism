# Aurora

Professional-grade **lighting control** for macOS — live performance show control with low latency, deterministic cue timing, and a modern dockable workspace.

## Status

**Backend is UI-gate ready.** Stages A–E (P0–P3), Xcode packaging, and the Final Backend UI Gate review are implemented. See [`docs/PROJECT_HANDOFF.md`](./docs/PROJECT_HANDOFF.md) and [`docs/UI_BACKEND_CONTRACT.md`](./docs/UI_BACKEND_CONTRACT.md) before new work.

Remote: ACP WebSocket on port `27421` (Bonjour `_acp._tcp`). The legacy PIN/TCP/HTTP companion is removed.

| Doc | Description |
|-----|-------------|
| [`docs/PROJECT_HANDOFF.md`](./docs/PROJECT_HANDOFF.md) | **Session handoff** — current architecture & status |
| [`docs/UI_BACKEND_CONTRACT.md`](./docs/UI_BACKEND_CONTRACT.md) | **UI redesign contract** — controllers, routes, what not to bypass |
| [`docs/STAGE_C_UI_STATE_HANDOFF.md`](./docs/STAGE_C_UI_STATE_HANDOFF.md) | Controller ownership map |
| [`Aurora Lighting Control System.pdf`](./Aurora%20Lighting%20Control%20System.pdf) | Original high-level overview |
| [`docs/design/aurora-system-design.md`](./docs/design/aurora-system-design.md) | System architecture & full PR plan |
| [`docs/design/pr1-project-scaffold.md`](./docs/design/pr1-project-scaffold.md) | **PR1** module layout, dependencies, acceptance |
| [`docs/design/pr2-domain-model.md`](./docs/design/pr2-domain-model.md) | **PR2** domain model & package format |
| [`docs/design/pr3-command-undo.md`](./docs/design/pr3-command-undo.md) | **PR3** commands & undo |
| [`docs/design/pr4-events-selection.md`](./docs/design/pr4-events-selection.md) | **PR4** event bus & selection |
| [`docs/design/pr5-fixture-library.md`](./docs/design/pr5-fixture-library.md) | **PR5** fixture library seed |
| [`docs/design/pr6-patch-management.md`](./docs/design/pr6-patch-management.md) | **PR6** patch management |
| [`docs/design/pr7-app-shell.md`](./docs/design/pr7-app-shell.md) | **PR7** app shell |
| [`docs/design/pr8-patch-fixture-browser.md`](./docs/design/pr8-patch-fixture-browser.md) | **PR8** patch + fixture browser |
| [`docs/design/pr9-output-layer.md`](./docs/design/pr9-output-layer.md) | **PR9** output / DMX |
| [`docs/design/pr10-playback-engine.md`](./docs/design/pr10-playback-engine.md) | **PR10** engine / scheduler |
| [`docs/design/pr11-cue-engine.md`](./docs/design/pr11-cue-engine.md) | **PR11** cue timing / tracking |
| [`docs/design/pr12-cue-list-ui.md`](./docs/design/pr12-cue-list-ui.md) | **PR12** cue list UI |
| [`docs/design/pr13-programmer-core.md`](./docs/design/pr13-programmer-core.md) | **PR13** programmer core |
| [`docs/design/pr14-programmer-ui.md`](./docs/design/pr14-programmer-ui.md) | **PR14** programmer UI |
| [`docs/design/pr16-coremidi.md`](./docs/design/pr16-coremidi.md) | **PR16** CoreMIDI |
| [`docs/design/pr19-live-playback-ui.md`](./docs/design/pr19-live-playback-ui.md) | **PR19** live ops UI |
| [`docs/design/pr24-diagnostics.md`](./docs/design/pr24-diagnostics.md) | **PR24** diagnostics subset |
| [`docs/design/pr18-rtp-midi.md`](./docs/design/pr18-rtp-midi.md) | **PR18** RTP-MIDI |
| [`docs/design/pr22-effect-engine.md`](./docs/design/pr22-effect-engine.md) | **PR22** live effect engine |
| [`docs/design/pr23-effect-ui.md`](./docs/design/pr23-effect-ui.md) | **PR23** effects UI |
| [`docs/design/pr25-artnet.md`](./docs/design/pr25-artnet.md) | **PR25** Art-Net output |
| [`docs/design/pr26-sacn.md`](./docs/design/pr26-sacn.md) | **PR26** sACN |
| [`docs/design/pr27-osc.md`](./docs/design/pr27-osc.md) | **PR27** OSC |
| [`docs/design/pr28-fixture-import.md`](./docs/design/pr28-fixture-import.md) | **PR28** fixture import |
| [`docs/design/pr29-plugins.md`](./docs/design/pr29-plugins.md) | **PR29** plugins |
| [`docs/design/pr30-performance.md`](./docs/design/pr30-performance.md) | **PR30** performance |
| [`docs/design/pr31-remote-protocol.md`](./docs/design/pr31-remote-protocol.md) | **PR31** remote protocol |
| [`docs/design/pr32-web-companion.md`](./docs/design/pr32-web-companion.md) | **PR32** web companion |
| [`docs/design/pr33-remote-hardening.md`](./docs/design/pr33-remote-hardening.md) | **PR33** remote hardening |
| [`docs/design/pr34-aurora-pad.md`](./docs/design/pr34-aurora-pad.md) | **PR34** Pad scaffold |
| [`docs/design/remote-companion.md`](./docs/design/remote-companion.md) | Stage iPad remote (web first, native later) |
| [`docs/development-workflow.md`](./docs/development-workflow.md) | Mac toolchain & dual-host notes |
| [`docs/xcode-project.md`](./docs/xcode-project.md) | Xcode app target, entitlements, schemes |

## Development environments

| Role | Machine |
|------|---------|
| **Planning / design docs** | Linux (or any OS) is fine |
| **Build, test, run, hardware** | **macOS 14+** only |

Details (including how to move a Grok session to another machine): [`docs/development-workflow.md`](./docs/development-workflow.md).

## Prerequisites

- **macOS 14.0+** (for compile and run)
- **Xcode 15+** / Swift 5.9+

The package declares `platforms: [.macOS(.v14)]` only. Do not expect `swift test` to work on Linux.

## Build / test / run

### Xcode app (recommended for UI / desk)

```bash
open Aurora.xcodeproj
# Scheme: Aurora → My Mac → Run
```

Details: entitlements, schemes, document type — [`docs/xcode-project.md`](./docs/xcode-project.md).

### SPM CLI

```bash
swift build
swift test
swift run Aurora
```

Run the CLI product from **Terminal.app** (or iTerm) on a local desktop session — not over SSH. The Xcode target produces a real `Aurora.app` (Dock, Finder `.aurora` documents, sandbox). SPM still builds library modules and a bare executable for agent/headless workflows.

Libraries are always composed from `Package.swift`; the app target does **not** merge module sources.

## Modules

| Module | Role |
|--------|------|
| `AuroraModel` | Pure show data types |
| `AuroraCore` | Commands, undo, project manager, events |
| `AuroraEngine` | Cue / playback / programmer / scheduler |
| `AuroraMIDI` | CoreMIDI, RTP-MIDI, learn |
| `AuroraOutput` | DMX buffers & drivers |
| `AuroraFixtureLib` | Fixture personalities |
| `AuroraDiagnostics` | Logging, monitors, metrics |
| `AuroraUI` | Panels & workspace views |
| `Aurora` (executable) | App entry (design name: **AuroraApp**) |

Dependency rules are documented in [PR1 scaffold](./docs/design/pr1-project-scaffold.md#6-dependency-graph). `AuroraUI` may import `AuroraMIDI` (mappings panel); it must not import `AuroraOutput`.

## Next

**Visual UI redesign** when requested — bind to Stage C controllers and follow [`docs/UI_BACKEND_CONTRACT.md`](./docs/UI_BACKEND_CONTRACT.md). Do not re-open completed review MDs as active backlog. Parallel hardware soak (Art-Net/sACN/ENTTEC) does not block UI design.
