# Aurora

Professional-grade **lighting control** for macOS — live performance show control with low latency, deterministic cue timing, and a modern dockable workspace.

## Status

**PR6 patch management** is in tree: seed fixture library, addressing helpers, and undoable patch/universe/clone/batch commands. Engine and UI docking are still ahead.

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

See the [PR plan](./docs/design/aurora-system-design.md#17-pr-plan). **PR7** adds the app shell and dockable workspace.
