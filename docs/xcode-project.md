# Aurora Xcode Application Project

Production macOS app packaging for Aurora. Libraries remain an SPM monorepo; the Xcode **application** target **composes** those products.

## Open & run

```bash
open Aurora.xcodeproj
# Scheme: Aurora → My Mac → Run (⌘R)
```

Or:

```bash
xcodebuild -project Aurora.xcodeproj -scheme Aurora -destination 'platform=macOS' build
```

CLI / tests without Xcode app:

```bash
swift build && swift test && swift run Aurora
```

Regenerate the project after editing `project.yml`:

```bash
./Scripts/generate-xcodeproj.sh   # requires: brew install xcodegen
```

## Architecture

| Layer | Location | Role |
|-------|----------|------|
| Libraries | `Package.swift` + `Sources/Aurora*` (except app shell) | Modules & unit tests |
| App shell | `Sources/Aurora/**` | `@main`, `AppModel`, controllers, panels registry |
| Bundle metadata | `App/Info.plist`, `App/Aurora.entitlements`, `App/Assets.xcassets` | Document type, sandbox, icon |
| Xcode project | `Aurora.xcodeproj` (from `project.yml`) | Builds `Aurora.app` |

**Dependency rule:** the app target links SPM **library** products only:

`AuroraUI`, `AuroraCore`, `AuroraModel`, `AuroraFixtureLib`, `AuroraEngine`, `AuroraOutput`, `AuroraMIDI`, `AuroraRemote`, `AuroraDiagnostics`

It does **not** link the SPM executable product. Module graph and PR1 edges are unchanged.

## Schemes

| Scheme | Purpose |
|--------|---------|
| **Aurora** | Debug run of the app (default) |
| **Aurora-Release** | Release configuration run/archive |

Package unit tests: use `swift test` or open `Package.swift` / the package in Xcode’s package navigator.

## Debug vs Release

| Setting | Debug | Release |
|---------|-------|---------|
| Optimization | `-Onone` | `-O` whole module |
| Assertions | On | Off |
| Hardened Runtime | Off (faster local iteration) | On |
| App Sandbox | On | On |
| Architectures | Active only | Standard (arm64 + x86_64 when applicable) |

## Document support

- UTType: `com.aurora.show-package` (`.aurora` **package directory**)
- Role: Editor / Owner
- Open in place: enabled
- Runtime model: existing `ProjectController` / `DocumentSession` / `ProjectPackage` (not full `NSDocument`) so the live engine is not reset on ordinary edits
- Finder open: `application(_:open:)` on `AuroraAppDelegate`
- Recent documents: `NSDocumentController.noteNewRecentDocumentURL` after successful open/save
- Autosave: `AutosaveController` (when a document URL exists)

## AppKit integration points

| Integration | Type / location |
|-------------|-----------------|
| Application delegate | `AuroraAppDelegate` — activation, quit dirty-check, open URLs |
| SwiftUI app entry | `AuroraApp` `@main` + `@NSApplicationDelegateAdaptor` |
| Menus | `.commands` (File, Edit, View, Playback, MIDI, Remote, Output) |
| Document I/O panels | `ProjectController` / `AppModel` |
| Alerts | `NSAlert` for errors and unsaved changes |

## Entitlements & capabilities

File: `App/Aurora.entitlements`

| Entitlement | Value | Justification |
|-------------|-------|----------------|
| `com.apple.security.app-sandbox` | `true` | Production isolation; path toward notarization |
| `com.apple.security.network.client` | `true` | Outbound Art-Net, sACN, OSC, remote, RTP-MIDI |
| `com.apple.security.network.server` | `true` | Listen: OSC :9000, remote TCP :8742, web :8743; multicast/session needs |
| `com.apple.security.files.user-selected.read-write` | `true` | Open/Save `.aurora` and fixture import via panels |
| `com.apple.security.files.bookmarks.app-scope` | `true` | Security-scoped bookmarks for autosave of user-selected packages |
| `com.apple.security.device.usb` | `true` | ENTTEC USB DMX Pro / local USB serial DMX |

### Explicitly not enabled

| Capability | Reason |
|------------|--------|
| Full disk access | Least privilege; user-selected documents suffice |
| Camera / mic / contacts / photos | Unused |
| Disable library validation | Not required until dynamic plugins |
| Sandbox **off** | Avoid for Release; if a desk QA edge case appears, use a temporary Debug override and document it |

### Info.plist privacy / usage

| Key | Justification |
|-----|----------------|
| `NSLocalNetworkUsageDescription` | Art-Net, sACN, stage remote, OSC, RTP-MIDI on LAN |
| `NSBonjourServices` (`_osc._udp`, `_apple-midi._udp`) | Local discovery patterns used by control stack |

### System frameworks (via SPM modules)

- **Network** — output, remote, RTP helpers  
- **CoreMIDI** — MIDI input / learn  
- **AppKit / SwiftUI** — shell  

## SwiftUI previews

- App target: `ENABLE_PREVIEWS = YES`
- `#Preview` on `ContentView` (DEBUG) hosts the composition root
- Package modules remain preview-friendly when opened via SPM

## CI

`.github/workflows/macos-ci.yml`:

1. `swift build` + `swift test`
2. `xcodebuild` **Debug** and **Release** for scheme `Aurora`

Signing uses ad-hoc (`CODE_SIGN_IDENTITY=-`) on CI.

## Troubleshooting

| Symptom | Check |
|---------|--------|
| No network DMX / remote | Sandbox network client/server entitlements; local network permission prompt |
| Cannot open show after relaunch | Bookmarks entitlement; re-select package once |
| ENTTEC not visible | USB device entitlement; transport wiring |
| Previews fail | Build app scheme once so package products resolve |
| Duplicate `@main` | Do not add SPM executable product to the app target |

## Related docs

- [`macos-app-packaging.md`](./macos-app-packaging.md)
- [`STAGE_C_UI_STATE_HANDOFF.md`](./STAGE_C_UI_STATE_HANDOFF.md)
- [`PROJECT_HANDOFF.md`](./PROJECT_HANDOFF.md)
