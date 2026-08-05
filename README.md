# Aurora

Professional-grade **lighting control** for macOS — live performance show control with low latency, deterministic cue timing, and a modern dockable workspace.

## Status

**PR15–21 show craft** is in tree: MIDI learn, color math, first-class palette refs, groups, and song orchestration. Effects (PR22) still ahead.

| Doc | Description |
|-----|-------------|
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
| [`docs/design/remote-companion.md`](./docs/design/remote-companion.md) | Stage iPad remote (web first, native later) |
| [`docs/development-workflow.md`](./docs/development-workflow.md) | Mac toolchain & dual-host notes |

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

```bash
swift build
swift test
swift run Aurora
```

Run that from **Terminal.app** (or iTerm) on the Mac’s local desktop session — not over SSH and not from a headless agent. The SPM product is a bare executable (not an `.app` bundle yet); the app forces a regular activation policy so a window and Dock icon appear.

Or open `Package.swift` in Xcode and run the **Aurora** scheme (most reliable for UI work). You should see a window listing the sample project and linked modules.

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

Dependency rules are documented in [PR1 scaffold](./docs/design/pr1-project-scaffold.md#6-dependency-graph). UI must not depend on Output or MIDI.

## Next

See the [PR plan](./docs/design/aurora-system-design.md#17-pr-plan). **PR17** maps MIDI to actions; **PR15** deepens color tools.
