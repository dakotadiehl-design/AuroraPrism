# Aurora — Panel Hosting / Docking Contract (UI-02D)

**Status:** Active shell contract  
**Purpose:** Keep panel **content** reusable when hosts change (Build layout today → dock host in UI-11).

---

## Rules

1. **Host-agnostic content roots**  
   Panel bodies (browser, programmer, palettes, cues, inspector, …) must not own window placement or assume a specific `HSplitView` / `VSplitView` parent.

2. **Composition lives in the host**  
   `BuildWorkspaceHost` (and future `DockHost`) only **compose** content roots + chrome (headers, tabs, split sizes).

3. **No duplicate panel implementations**  
   Do not create a “Build-only” copy of a panel solely for layout. Rehost the same content type.

4. **Focused dependencies**  
   Prefer `WorkspacePanelContext`, programmer, snapshots, and callbacks over injecting full `AppModel` into pure content when avoidable.

5. **Inspector focus is shell UI state**  
   `WorkspaceController.inspectorFocus` selects what the Inspector presents. It does not replace Programmer fixture selection.

6. **Navigation levels stay distinct**  
   - Mode: BUILD | PERFORM (toolbar)  
   - Workspace tools: left Browser|Patch|Groups; lower Palettes|Cues|Song  
   - Panel-local: inspector sections only  

---

## Conceptual mapping

```text
Today:     BuildWorkspaceHost  → hosts content roots
Later:     DockHost            → hosts THE SAME content roots
```

Content must not create host-specific state or chrome.

---

## Related

- Shell plan: UI-02 amended plan  
- Build host: `Sources/Aurora/Shell/BuildWorkspaceHost.swift`  
- Future vision guardrails: `docs/ARCHITECTURE_FUTURE_GUARDRAILS.md`  
