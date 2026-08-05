# PR7 — App Shell & Dockable Workspace

| Field | Value |
|-------|--------|
| **PR** | PR7 |
| **Status** | Implemented |
| **Depends on** | PR1–PR4 |

## Delivered

- `AppModel` owns `DocumentSession`, layout, open/save path
- `WorkspaceView` multi-pane host (SwiftUI splits)
- Panel IDs + `WorkspaceLayout` persistence (UserDefaults)
- Menus: New/Open/Save, Undo/Redo, View → panels
- Placeholder + structural panels for browser/patch/inspector (content refined in PR8)

## Layout

Leading (browser/patch) | Center (patch/cues/programmer) | Inspector  
Bottom: universe monitor / console / cues
