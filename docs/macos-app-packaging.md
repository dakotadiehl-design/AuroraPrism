# macOS App Packaging (P3-3)

Aurora’s SPM product remains a runnable executable (`swift run Aurora`). For a polished desk app:

## Bundle skeleton

```text
Aurora.app/
  Contents/
    Info.plist          ← from App/Info.plist
    MacOS/Aurora        ← built executable
    Resources/          ← optional assets
```

## Build notes

1. Prefer an Xcode macOS App target that links local SPM package libraries and compiles `Sources/Aurora`.
2. Document type: `.aurora` package (`com.aurora.show-package`) — see `App/Info.plist`.
3. Autosave: `AutosaveController` in the app target (interval default 120s when a document URL exists).
4. Open recovery: `ProjectPackage.recoverOrphanedPackages(around:)` on open/save.

## Sandbox / notarization

Not enabled by default — Art-Net, sACN, MIDI, and remote LAN need network + MIDI entitlements if sandboxing later.
