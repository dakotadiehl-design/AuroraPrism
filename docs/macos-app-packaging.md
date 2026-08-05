# macOS App Packaging

## Primary path: Xcode app

```bash
open Aurora.xcodeproj
# Scheme Aurora → Run
```

Full details (entitlements, schemes, CI): **[`docs/xcode-project.md`](./xcode-project.md)**.

### Bundle layout (built product)

```text
Aurora.app/
  Contents/
    Info.plist
    MacOS/Aurora
    Resources/Assets.car (and asset catalog resources)
    Frameworks/   (if any dynamic deps)
```

### Metadata sources

| File | Role |
|------|------|
| `App/Info.plist` | Bundle ID placeholders, document type, local network usage |
| `App/Aurora.entitlements` | Sandbox + network + USB + user-selected files |
| `App/Assets.xcassets` | AppIcon + AccentColor |
| `project.yml` | XcodeGen source of truth for `Aurora.xcodeproj` |

## CLI path (unchanged)

SPM executable product remains for headless/agent workflows:

```bash
swift build && swift test && swift run Aurora
```

Libraries always build from `Package.swift`. The app target **composes** library products; it does not merge module sources.

## Document type

- Extension: `.aurora` (directory package)
- UTType: `com.aurora.show-package`
- Runtime I/O: `ProjectPackage` + `ProjectController` (not full `NSDocument`)

## Autosave & recovery

- `AutosaveController` (interval when a document URL is set)
- `ProjectPackage.recoverOrphanedPackages(around:)` on open/save

## Sandbox / notarization

Sandbox is **enabled** with network client/server, user-selected files, bookmarks, and USB (see entitlement table in `xcode-project.md`). Notarization requires an Apple Developer identity and is out of band.
