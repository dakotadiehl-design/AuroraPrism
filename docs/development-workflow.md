# Development Workflow

Aurora is a **macOS-native** product. Planning can happen anywhere; compile, test, run, and hardware work require a Mac.

## Hosts

| Role | Environment |
|------|-------------|
| Design docs, PR planning, review of markdown | Any OS (Linux included) |
| `swift build` / `swift test` / `swift run` / Xcode | **macOS 14+** with **Xcode 15+** |
| CoreMIDI, RTP-MIDI, DMX drivers | macOS only |

The package declares `platforms: [.macOS(.v14)]` only. Do not expect SPM tests to pass on Linux.

## Prerequisites (macOS)

1. Install **Xcode** from the App Store or Apple Developer (not only Command Line Tools).
2. Point the active developer directory at Xcode:

   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```

3. Confirm:

   ```bash
   xcode-select -p
   # → /Applications/Xcode.app/Contents/Developer
   xcodebuild -version
   swift --version
   ```

If `xcode-select -p` shows `/Library/Developer/CommandLineTools`, SwiftUI `#Preview` macros and `XCTest` will fail even though `swift` appears on `PATH`.

## Day-to-day commands

```bash
cd /path/to/Aurora
swift build
swift test
swift run Aurora
```

Or open `Package.swift` in Xcode and run the **Aurora** scheme.

## Dual-machine notes (Linux plan → Mac implement)

1. Keep design work in `docs/design/` — portable and reviewable on any OS.
2. Implement and verify on macOS; mark acceptance criteria that need a Mac run as such.
3. Prefer transferring the git repo (push/pull or bundle) over ad-hoc archives.
4. If you must move a local Grok session, use a session archive (e.g. `*.grok-session.tgz`). Those archives are **gitignored** — do not commit them.

## What not to commit

See `.gitignore`. In particular:

- `.build/`, DerivedData, Xcode user state
- `.env` and secrets
- Local session transfer tarballs (`aurora-grok-session.tgz`, `*.grok-session.tgz`)
