# UI-11 Handoff — Build Layouts

**Status:** Stabilized (post FirstPass review)

## Implemented

| Area | Notes |
|------|--------|
| Schema v2 | `schemaVersion`, namedPreset |
| Named Build presets | Programming, Patch, Song, Diagnostics — Option A left/lower tools |
| Build host | Fractions → column ideal widths; visibility for left/inspector/lower |
| View menu | Layouts submenu + Show/Hide Inspector/Lower |
| Perform | Remains fixed `PerformWorkspaceShell` |
| Clamp | Safe fraction geometry |
| Debounced save | `saveDebounced` / `flushPending` on quit |
| Corrupt restore | Falls back to default |

## API

```swift
workspace.applyNamedBuildLayout("Patch")
workspace.resetLayout()
workspace.updateSplitFractions(..., immediate: false)
workspace.flushLayoutPersistence()
```

## Known limitation

Native `HSplitView` does not push live divider drag positions back into the model; saved fractions restore ideal widths on next layout apply / launch.

## Checkpoint

Part of UI-08→11 + stabilization tree.
