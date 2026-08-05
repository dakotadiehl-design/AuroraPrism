# Aurora — UI Development Plan

**Status:** Active UI-phase roadmap (amended)  
**Created:** 2026-08-05  
**Amended:** 2026-08-05 — incorporated `Aurora_UIDevPlan_Recommended_Amendments.md`  
**Deliverable type:** Execution plan  
**Backend gate:** Closed — pre-UI blockers complete (`b87dcf6` / handoff `3642f1e`)

---

## Document map

| Document | Role |
|----------|------|
| **`UIDesignReferences/UIDevPlan.md`** (this file) | **Active execution order**, code mapping, gates, acceptance |
| `UIDesignReferences/Aurora_UIDevPlan_Recommended_Amendments.md` | Incorporated 2026-08-05 (historical reference) |
| `UIDesignReferences/Aurora_UI_UX_Implementation_Plan.md` | Product principles and detailed surface requirements |
| `UIDesignReferences/Aurora_UI_UX_Design_Reference.pdf` | Visual north star (intent, not pixel-perfect) |
| `docs/UI_BACKEND_CONTRACT.md` | Authoritative API / domain contract for all UI work |
| `docs/STAGE_C_UI_STATE_HANDOFF.md` | Controller ownership |
| `docs/PROJECT_HANDOFF.md` | Session memory; update when phases land |

Do not invent backend features. Do not reopen completed pre-UI blockers. If a view needs a missing contract, **document the gap** before changing domain semantics.

---

# 1. Purpose

Aurora is entering its **visual product-development phase**. The lighting engine, control routing, persistence, output systems, MIDI/network input, song model, effects, diagnostics, remote control, and Stage C state ownership already exist.

The goal of this phase is **not** to redesign the backend.

The goal is to turn the existing system into a polished professional macOS lighting-control application with:

- a coherent visual language
- fast programming workflows
- excellent live-show ergonomics
- a clear separation between **Build** (programming) and **Perform** (stage)

**Approved direction:**

> A modern macOS creative workstation for programming, and a calm stage-control cockpit for performing.

**UI-01 milestone is not** “Aurora has a new skin.”  
**It is:** “Aurora has an approved visual language coherent enough to build the rest of the product from.”

---

# 2. Non-negotiable principles

## 2.1 Complexity available, not constantly visible

Frequently used programming and show controls live in the workspace. Occasional configuration lives in **Settings**.

## 2.2 Build and Perform are different mental states

| Mode | Character |
|------|-----------|
| **Build** | Dense, editable, keyboard-friendly programming |
| **Perform** | Calm, legible at distance, hard to edit by accident — **also an operational safety boundary** |

Web / iPad remote ≈ Perform, not Build.

## 2.3 Color is information

- Shell: restrained dark charcoal surfaces
- Bright color: fixture output, palettes, selection, active state, warnings, deliberate Aurora accents
- No decorative purple gradients covering the app

## 2.4 The UI must tell the truth

Do not create working-looking controls for unimplemented backend behavior. Respect `docs/UI_BACKEND_CONTRACT.md`.

**Deferred (unavailable if exposed):** automatic song progression, Open DMX, real ENTTEC serial enumeration, project-level frame-rate override, native iPad app, full GDTF, TLS remote, dynamic dylib plugins, security-scoped bookmark store, notarization.

## 2.5 Live control stays fast

```text
UI / MIDI / OSC / remote
  → ControlActionRouter (may be non-MainActor)
  → LightingEngine / DocumentSession
  → OutputManager → drivers
```

UI consumes presentation state and dispatches through controllers / router. No high-rate DMX in broad SwiftUI observation.

## 2.6 Composition (UI-FOUNDATION-1 Option A)

```text
AuroraUI (library)     = tokens + components + pure panels/views
Aurora macOS app       = composition, controller bindings, Settings, menus, docking host
```

- Do **not** make `AuroraUI` depend on the executable
- Prefer focused controllers / snapshots over full `AppModel`

## 2.7 Design for docking early; implement advanced docking later

**UI-02** establishes a docking-compatible **panel contract**.  
**UI-11** implements advanced docking, tear-off, multi-display, richer workspace management.

From UI-02 onward, major panels must:

- have a container-independent content root
- avoid assuming a specific parent `HSplitView` / `VSplitView`
- avoid assuming a fixed window or screen size
- avoid owning workspace/window placement
- accept focused dependencies
- remain usable in tab, split, separate window, or future AppKit docking host

> Design for docking in UI-02. Implement sophisticated docking in UI-11.

---

# 3. Starting baseline

## Ready

Stage C controllers, `ControlActionRouter` multi-observer, presentation snapshots, functional stock SwiftUI panels, Build/Perform mode enum, web remote skeleton, 264 tests, backend closed.

## Gaps

No design system; stock appearance; Settings still panel-shaped; Perform is mode flag not cockpit; Option A incomplete (`PanelRegistry` injects full `AppModel`); placeholder AppIcon.

## Existing surface → redesign phase → binding

| Current file | Redesign phase | Prefer binding |
|--------------|----------------|----------------|
| `WorkspaceView.swift` | UI-02, UI-11 | `WorkspaceController` |
| `ContentView.swift` | UI-02, UI-07 | composition root |
| `PanelRegistry.swift` | UI-02 onward | focused deps |
| `FixtureBrowserPanel.swift` | UI-03 | selection / project |
| `ProgrammerPanel.swift` | UI-03 | programmer + project |
| `PalettesPanel.swift` | UI-04 | project + programmer |
| `CueListPanel.swift` | UI-05 | project + performance + transport |
| `SongPanel.swift` | UI-06 | project + `SongDirector` |
| `LivePlaybackPanel.swift` | UI-07 | `PerformanceSnapshot` |
| `MIDIMappingsPanel.swift` | UI-08 (Settings) | `InputController` |
| `PatchPanel.swift` | UI-09 | `ProjectController` |
| `UniverseMonitorPanel.swift` / `ConsolePanel.swift` | UI-09 | diagnostics / dedicated snapshots |
| `index.html` (remote) | UI-10 | same performance semantics |

---

# 4. Foundation carry-ins

| ID | Item | When |
|----|------|------|
| **UI-FOUNDATION-1** | Option A composition | UI-01 structure + progressively |
| **UI-FOUNDATION-2** | App integration tests | After UI-02 |
| **UI-FOUNDATION-3** | Bookmark store | UI-08 or UI-12 if needed |
| **UI-FOUNDATION-4** | Production AppIcon | **UI-02 / UI-03** (not deferred to UI-12) |
| **UI-FOUNDATION-5** | 16-bit home/highlight | **Done** |

UI-12 still runs a final branding consistency audit after early AppIcon install.

---

# 5. Design system (UI-01)

## 5.1 Goal

Establish Aurora’s visual language as code **before** redesigning product surfaces.  
Review must approve components **working together as Aurora**, not only isolation.

## 5.2 Source layout

```text
Sources/AuroraUI/
  DesignSystem/
    AuroraTokens.swift
    AuroraColors.swift
    AuroraTypography.swift
    AuroraSpacing.swift
    AuroraMetrics.swift
    AuroraDensity.swift      # compact / standard / performance
    AuroraAnimation.swift
  Components/
    AuroraPanel.swift
    AuroraPanelHeader.swift
    AuroraToolbar.swift
    AuroraButton.swift
    AuroraIconButton.swift
    AuroraStatusIndicator.swift
    AuroraSectionHeader.swift
    AuroraInspectorSection.swift
    AuroraPaletteTile.swift
    AuroraPresetTile.swift
    AuroraCueRow.swift
    AuroraFader.swift
    AuroraNumericField.swift
    AuroraEmptyState.swift
    AuroraSearchField.swift
    AuroraTransportButton.swift
    AuroraAttributeStateChrome.swift   # visual markers for UI-01 mini-programmer
  Previews/
    AuroraComponentGallery.swift
  Panels/       # product panels — migrate later phases
  Workspace/    # restyle host in UI-02
```

## 5.3 Density system

```text
compact       Build dense tables/lists/inspectors/diagnostics
standard      Programmer, palettes, Settings, normal editors
performance   Perform Mode, remote, large transport, distance-readable chrome
```

Components use `@Environment(\.auroraDensity)` — not arbitrary per-view padding.

## 5.4 Semantic color / type / spacing

Colors: `surfaceBase`, `surfacePanel`, `surfaceRaised`, `surfaceSelected`, `separator`, `textPrimary` / `Secondary` / `Tertiary`, `accent`, `accentSubtle`, `success`, `warning`, `critical`, `disabled`.

Typography: window title, workspace title, panel title, section heading, body, secondary, numeric readout, cue number, status, compact label.

Spacing: small consistent scale. Metrics: radii, control heights, hit targets (density-aware).

## 5.5 Interaction states

normal · hover · pressed · selected · focused · disabled · warning · critical  

Keyboard focus must remain visible.

## 5.6 Gallery compositions (required)

### Mini Programmer

Panel surface/header · attribute-family nav · fader · numeric · programmer-owned state · palette tiles · section headings · compact labels

### Mini Cue List

Normal · current · next · selected · warning/broken · timing · cue number typography

### Mini Perform Transport

Current · next · large GO · BACK · STOP · healthy status · warning/failed status

## 5.7 Acceptance — UI-01

```text
[x] Semantic colors, type, spacing, metrics, animation tokens
[x] Semantic density system: compact / standard / performance
[x] Panel surface + header components
[x] Primary/secondary/icon buttons
[x] Status indicator
[x] Section headers / inspector section
[x] Palette tile + preset tile + cue row + fader + numeric + search + empty state
[x] Transport button
[x] Mini Programmer composition in gallery
[x] Mini Cue List composition in gallery
[x] Mini Perform Transport composition in gallery
[x] States demonstrated: normal, hover, pressed, selected, focused, disabled, warning, critical
[ ] Components look coherent when combined, not merely in isolation  ← human review
[x] No product panels wholesale-redesigned yet
[ ] STOP for human visual review  ← YOU ARE HERE
```

## 5.8 Hard gate

**STOP after UI-01 for human visual review of the gallery and mini-compositions.**  
Do not begin UI-02 until approved.

---

# 6. Phased roadmap

Each phase is independently buildable and reviewable.

---

## UI-01 — Design system foundation

| | |
|--|--|
| **Goal** | Tokens + density + components + realistic mini-compositions |
| **Code** | `Sources/AuroraUI/DesignSystem/`, `Components/`, `Previews/` |
| **Bindings** | None (pure views, mock data) |
| **Gate** | **HARD VISUAL REVIEW** |

---

## UI-02 — Application shell

| | |
|--|--|
| **Goal** | Professional app chrome hosting existing functional panels |
| **Surfaces** | Toolbar, title/dirty, Build/Perform chrome, health strip, workspace host, **contextual Inspector architecture**, **Settings shell + IA**, docking-compatible panel contract |
| **Code** | `ContentView`, `AuroraApp`, `WorkspaceView`, shell views, Settings scene skeleton |
| **Bindings** | Focused controllers / snapshots — not full `AppModel` for new screens |
| **Depends on** | UI-01 approved |
| **Out of scope** | Full Programmer (UI-03), full Perform cockpit (UI-07), full Settings content (UI-08), advanced docking (UI-11) |
| **Also** | Install production AppIcon (or start in UI-03); begin Option A for new wiring |

### Contextual Inspector (required in UI-02)

Answers: *What is selected, and what can I change about that thing?*

```text
Fixture → Fixture Inspector
Group → Group Inspector
Cue → Cue Inspector
Palette → Palette Inspector
Preset → Preset Inspector
Song → Song Inspector
No selection → project/workspace context or calm empty state
```

Do not turn Inspector into a permanent grab-bag of unrelated controls. Feature phases add sections; **routing architecture** lands in UI-02.

### Settings shell (UI-02)

Native Settings scene + navigation + design-system treatment + app-global vs project scope convention + placeholders marked unavailable. Populate pages in later phases; **UI-08 consolidates**.

### Docking-compatible panel contract (UI-02)

Container-independent content roots; no fixed host assumptions; focused dependencies.

### Acceptance — UI-02

```text
[ ] Major panel content roots are container-independent
[ ] Panels do not assume one specific split/window host
[ ] Contextual Inspector selection-routing architecture exists
[ ] Native macOS Settings shell exists
[ ] App-global vs project/show settings have a defined presentation convention
[ ] New screens do not depend on full AppModel when focused deps suffice
[ ] Existing functional panels still run inside the new shell
[ ] Build and Perform chrome are visibly distinct (full cockpit is UI-07)
[ ] SHELL REVIEW before UI-03
```

---

## UI-03 — Fixture browser + Programmer

| | |
|--|--|
| **Goal** | First complete high-value creative workflow |
| **Surfaces** | Fixture/group browser, Programmer attribute families |
| **Depends on** | UI-02 |
| **Out of scope** | Stage-map spatial selection; raw DMX as primary UX |

### Attribute-state semantics (required)

```text
untouched
programmer-owned          # distinguishable without color alone
inherited / tracked
palette-referenced
mixed selection           # never show an arbitrary single value
unavailable               # not supported by selection
```

Mixed personalities: supported by all / some / none — do not fabricate unsupported controls.

### Scale acceptance

Select ~80 fixtures across multiple personalities and groups: browser + Programmer remain responsive; mixed capability correct; no high-rate broad invalidation.

### Post-UI-02 gate carry-in (required in UI-03)

From `Aurora_Post_UI02_Final_Gate_Review.md` — implement during UI-03, not as shell rework:

```text
- Live/derived Programmer presentation (not first-fixture @State only)
- Mixed selection state: common / mixed / unset / unsupported / partial
- Normalize fixture/group selection on orderedFixtureIDs (Fan/Align)
- Incremental focused observation (avoid broad AppModel 4 Hz where it hurts)
- Explicit decisions: Clear All / Fan / Align / technical RGB-W
```

### Functional restoration (from UI-02 deep review)

UI-02 simplified Programmer. UI-03 must **decide for each prior function**: restore, replace with better interaction, move to Inspector/context menu, or intentionally retire with reason:

```text
Clear All
Fan
Align
technical RGB/W control
other deeper Programmer workflows
```

Do not silently drop fan/align.

### Acceptance — UI-03

```text
[ ] Select → set intensity/color/position → apply palette → observe programmer state
[ ] Programmer distinguishes untouched vs programmer-owned
[ ] Mixed values represented truthfully
[ ] Mixed fixture capabilities represented truthfully
[ ] Unsupported attributes do not appear functional
[ ] Palette/reference state communicable where relevant
[ ] Large selection (~80 fixtures) remains responsive
[ ] No high-rate broad SwiftUI invalidation introduced
[ ] Explicit decision for Clear All / Fan / Align / technical RGB-W
```

---

## UI-04 — Palettes / presets

Visual shelves; preserve reference semantics. Click applies to selection. No invented modifier-key gestures without spec.

### Functional restoration (from UI-02 deep review)

```text
Create palette from Programmer
Create preset/look from Programmer
Delete
Rename/edit
Record palette reference to cue
Reference semantics
```

---

## UI-05 — Cue workflow

Readable cue list; current/next unmistakable; record/update; no inert fields; no automatic song progression.

### Functional restoration (from UI-02 deep review)

UI-02 hardening already provides: single-click select/inspect, double-click fire, GO/transport. UI-05 owns the full editor:

```text
Add Cue List / Delete Cue List
Add Cue / Delete Cue
edit cue name, fade, delay
record / update
explicit Fire UI (compatible with double-click fire)
cue / list selection publishing for cross-panel workflows
```

---

## UI-06 — Song Mode

Musician hierarchy; **manual only**; Automatic progression disabled/unavailable until backend exists.

---

## UI-07 — Perform Mode (safety + cockpit)

| | |
|--|--|
| **Goal** | Stage cockpit + operational safety boundary |
| **Bindings** | `PerformanceSnapshot` only for main content |
| **Depends on** | UI-02; benefits from UI-05/UI-06 |

While in Perform Mode:

- show-structure editing normally unavailable
- destructive programming unavailable or requires intentional Build transition
- incidental dialogs must not obscure transport
- GO/BACK/STOP immediately available
- warnings escalate without taking control away

> Perform Mode is an operational safety boundary as well as a visual mode.

### Future Show Lock (compatibility only — not required now)

Avoid architecture that prevents a future explicit lock (structure/patch/palette lock while allowing transport and approved live overrides). No implementation required in this roadmap unless it falls out naturally.

### Acceptance — UI-07

```text
[ ] Distance-readable show/song, current, next, GO/BACK/STOP, health
[ ] Perform Mode prevents accidental structural editing
[ ] Essential transport remains available during warnings/errors
[ ] No incidental modal unnecessarily covers GO
[ ] Build-only commands hidden/disabled or require intentional mode transition
[ ] Architecture remains compatible with a future Show Lock
```

---

## UI-08 — Full Settings content / consolidation

Complete Settings pages; migrate MIDI mappings out of permanent workspace; app vs project scope explicit.

---

## UI-09 — Patch / Output / Diagnostics

Professional technical workspaces; human-readable validation; quiet healthy status.

---

## UI-10 — Web / iPad remote

Perform semantics on touch; no second engine; large targets; no Build clone.

### Post-UI-02 gate carry-in

Remote still uses legacy cue-index presentation. Consume the same `PerformanceCueSummary` / CURRENT-NEXT contract as Mac Perform — do not invent a second definition of current/next.

---

## UI-11 — Advanced docking / layouts / multi-display

Named layouts (Programming, Patch, Song, Perform, Diagnostics); resize/hide/tab/tear-off; multi-display. Panel contents already container-independent from UI-02 contract.

**Default Programming layout (Build):**

```text
┌─────────────────────────────────────────────────────────────────────┐
│ Toolbar / Project / Workspace                         Health Status │
├───────────────┬─────────────────────────────────────┬───────────────┤
│ Browser       │ Programmer / Primary Editor         │ Inspector     │
├───────────────┴─────────────────────────────────────┴───────────────┤
│ Palette / Preset Shelf                                              │
├─────────────────────────────────────────────────────────────────────┤
│ Cue / Song / Effects / Monitor (lower)                              │
└─────────────────────────────────────────────────────────────────────┘
```

---

## UI-12 — Final product polish

Accessibility, keyboard audit, first-run, empty states, performance profiling, **final branding consistency** (AppIcon installed earlier in UI-02/03). Optional bookmarks if Recent Shows needs them.

---

# 7. Status & health chrome

```text
● ENGINE   ● OUTPUT   ● MIDI   ● NETWORK
```

Quiet when healthy. Use `OutputPresentationSnapshot`. Warnings escalate without covering GO in Perform.

---

# 8. Menus, keyboard, accessibility

Native menus/shortcuts; focus visible; VoiceOver labels; contrast; large Perform targets; animation for state only.

---

# 9. North-star acceptance checklist

1. What show is open?  
2. What fixtures am I controlling?  
3. What are they currently doing?  
4. What cue is active?  
5. What happens next?  
6. Is engine / output / MIDI / network healthy?  
7. Where do I program?  
8. Where do I perform?  
9. Where do I configure occasional systems?  
10. Can I recover from a mistake without hunting?

**Programming should feel powerful. Performance should feel calm.**

---

# 10. Quality bar (every phase)

| Rule | Detail |
|------|--------|
| Tests | `swift test` green; Xcode Debug builds |
| Previews | `#Preview` for pure components |
| Observation | No high-rate DMX in broad app state |
| Tokens | Semantic design tokens + density |
| PRs | One phase per reviewable change set |
| Backend | No convenience domain rewrites |
| Deferred | Never fake-working |

---

# 11. Rules for agents

1. No backend semantics change for view convenience.  
2. Document missing contracts before changing them.  
3. Independently buildable phases.  
4. Previews for pure views.  
5. No high-frequency frame buffers in broad observation.  
6. Focused controllers / snapshots.  
7. No global workspace invalidation.  
8. Semantic tokens + density.  
9. No invented deferred features.  
10. No giant multi-screen redesign PRs.  
11. Keyboard usability.  
12. Live-control path stays low-latency.  
13. Native macOS where beneficial.  
14. PDF is intent, not pixel-perfect.  
15. Backend truth over decorative design conflicts.  
16. **Stop after UI-01 for visual review.**  
17. Design for docking from UI-02; implement advanced docking in UI-11.  

---

# 12. Immediate next step

**Implement UI-01 only** (density + components + mini-compositions).  
**STOP for human visual review.**  
Do not begin UI-02 until the gallery is approved.

---

# 13. Execution sequence

```text
[x] UI-01 Design system foundation
[x] UI-01B Visual identity refinement
[x] UI-01C Render-target visual identity
[x] UI-02A Real Build workspace + brand + icon closeout — **COMPLETE**
[x] UI-02 Application shell (post-02A) — **COMPLETE — SHELL REVIEW**
[x] UI-02 Shell hardening (deep review P0/P1) — **COMPLETE**
[x] UI-02 Final gate closeout — **COMPLETE**
[x] UI-03 Fixture Browser + Programmer — **PASS 2 COMPLETE**
        • Dual-axis support × value; mixed display-state enum
        • Fan center+spread; Align no fabricated zero
        • Pan/tilt-only pad visual truth; hasRGBColor vs technical
        • Batched multi-attr Programmer writes
        ↓
    Next when user asks: UI-04

[ ] UI-04 Palettes + Presets
        • create/delete/rename + record ref to cue
[ ] UI-05 Cue Workflow
        • full list/cue edit + record/update
[ ] UI-06 Song Mode
[ ] UI-07 Perform Mode (cockpit + safety boundary)
[ ] UI-08 Full Settings content / consolidation
[ ] UI-09 Patch / Output / Diagnostics
[ ] UI-10 Web / iPad Remote
[ ] UI-11 Advanced Docking / Saved Layouts / Multi-display
[ ] UI-12 Final Product Polish
[ ] Update docs/PROJECT_HANDOFF.md after major phase landings
```

---

# 14. Items that remain unchanged

- Backend gate closed; `UI_BACKEND_CONTRACT.md` authoritative  
- `AuroraUI` pure; no executable dependency  
- Focused bindings over full `AppModel`  
- No MainActor latency in live control  
- Structured presentation snapshots  
- High-rate DMX limited to monitor paths  
- Visual references are intent  
- Deferred features never falsely functional  
- Accessibility and keyboard required  
- Reviewable phases  
- **UI-01 remains a hard stop before the design language spreads**

---

# 15. Doc maintenance

| Action | When |
|--------|------|
| Keep this file as active UI roadmap | Ongoing |
| Check off §13 | As phases merge |
| Update `PROJECT_HANDOFF.md` | After significant landings |
| Do not reopen historical backend review MDs | Ever |

---

*End of UIDevPlan (amended).*  
*Visual: `Aurora_UI_UX_Design_Reference.pdf` · Detail: `Aurora_UI_UX_Implementation_Plan.md` · Contracts: `docs/UI_BACKEND_CONTRACT.md`*
