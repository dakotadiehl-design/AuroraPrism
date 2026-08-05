# Aurora UI-02 Shell Hardening — Implementation Plan

**Source of truth:**  
`Aurora_UI_02_Deep_Code_Review_Recommended_Fixes.md`  
**Binding amendments:**  
`Aurora_UI_02_Hardening_Plan_Recommended_Amendments.md`

**Goal:** Fix P0/P1 shell safety and truthfulness so UI-02 can close and UI-03 can begin.  
**Non-goals:** UI redesign, backend rewrite, full Cue/Palette/Programmer restoration (owned by UI-03/04/05).

**Principle:** UI must tell the truth. Mode switch is presentation-only (Build ↔ Perform must preserve live playback).

---

## 0. Scope and constraints

| In scope | Out of scope |
|----------|--------------|
| P0/P1 shell safety & state | Full Show Lock |
| Mode-aware chrome/menus | Docking / WorkspaceLayout revival |
| Truthful presentation contracts | Broad observation architecture rewrite |
| Demo safety defaults | Rebuilding deleted Cue/Palette/Programmer editors |
| Focused tests + handoff docs | FutureReference MIDI sealing |

**Preserve:** `ContentView` → toolbar / Build host / Perform shell / status bar; Option A layout; `InspectorFocus`; Settings scene; panel contract; design system; Stage C controllers.

---

## 1. Current baseline (as of this plan)

Partial hardening already exists and must be **finished and wired**, not redesigned:

| Item | Status | Notes |
|------|--------|-------|
| A1 Cue select vs fire | **Partial** | `CueListPanel` + `AuroraCueRow` support select / double-click fire; verify registry + Build host wiring; no fire-on-single-click |
| A2 Transport text gate | **Partial** | `KeyboardCommandGate` exists; **not wired** into Playback menu `.disabled` |
| A3 Perform chrome | **Partial** | Toolbar hides New/Open in Perform; **menus still always show** structural File actions |
| A4 PerformanceCueSummary | **Partial** | Type + resolve in `PerformanceSnapshot`; Perform shell consumers exist — verify song next targets |
| A5 Inspector CURRENT | **Open** | Still index-only; needs listID and/or cueID |
| B1 Explicit fixture inspect | **Partial** | `noteExplicitFixtureInspect` on workspace; **FixtureBrowserPanel not wired** |
| B2 Document reset | **Partial** | `didReplaceDocument` exists; **not called** from AppModel New/Open/Demo; epoch/selection incomplete |
| B3 CueList self-heal | **Partial** | `documentEpoch` + heal logic in panel; epoch must be bumped on replace |
| B4 View menu | **Open** | Still toggles dead `WorkspaceLayout.visiblePanels` |
| B5 Dirty save await | **Open** | `confirmDiscardIfDirty` still fire-and-check `isDirty`; quit path is the model |
| C1 Demo auto-load | **Open** | DEBUG `onAppear` still auto-loads demo |
| C2 Demo Art-Net | **Open** | `protocolHint: .artNet` in demo |
| C3 Frame-rate slider | **Open** | Commits every tick → engine restart |
| C4 Shared health | **Mostly done** | `AuroraShellHealthSnapshot` used by toolbar/status/Perform |
| C5 Settings scope | **Open** | Output page APPLICATION vs project routing |
| C6 Silent `try?` | **Open** | MIDI delete etc. |
| C7 Fixed cue UUIDs | **Open** | Demo cues still `UUID()` |
| D Tests / docs / verify | **Open** | |

---

## 2. Recommended fix order (approved waves)

Do **not** reorder cosmetic work ahead of show-control safety.

### Wave A — Show-control safety (P0 / critical P1)

#### A1 — Cue: single-click select, double-click fire

**Review §4 + Amendment §1**

| | |
|--|--|
| **Files** | `Sources/AuroraUI/Panels/CueListPanel.swift`, `Sources/AuroraUI/Components/AuroraCueRow.swift`, `Sources/Aurora/Shell/BuildWorkspaceHost.swift`, `Sources/Aurora/PanelRegistry.swift` |
| **Behavior** | Single click → `selectCue` + inspect + SelectionManager cue/list IDs · **no** `onFire`. Double click → fire **exactly once**. Context menu “Fire Cue” + GO remain. First click of double-click must not fire. |
| **Done when** | No path maps ordinary row select to engine fire; selection published for cross-panel use |

#### A2 — Transport shortcuts vs text editing

**Review §5 + Amendment §2**

| | |
|--|--|
| **Files** | `Sources/Aurora/Shell/KeyboardCommandGate.swift`, `Sources/Aurora/AuroraApp.swift` |
| **Behavior** | Gate already inspects AppKit first responder (NSTextView / field editor / TextField bridges). Wire every Playback menu item: `.disabled(KeyboardCommandGate.isTextEditingActive)`. Optional: wrap `go`/`back`/`stopPlayback` with same guard as belt-and-suspenders. |
| **Manual** | TextField focused: Space/Return/Left/B/Esc do **not** transport; unfocused: Space/Return → GO, etc. |

#### A3 — Perform hides structural Build actions

**Review §6 + Amendment §3**

| | |
|--|--|
| **Files** | `AuroraBuildToolbar.swift` (partial), `AuroraApp.swift` menus |
| **Behavior** | Prefer **hide** over disable in toolbar (already mostly done). In Perform: disable or hide File structural commands — New Show, Open, Import fixture definitions. Save may remain. Mode toggle + identity + health stay. Not full Show Lock. |

#### A4 — Truthful Current/Next (`PerformanceCueSummary`)

**Review §7 + Amendment §4**

| | |
|--|--|
| **Files** | `PerformanceSnapshot.swift`, `ShowControlController` refresh path, `PerformWorkspaceShell.swift` |
| **Behavior** | Views consume resolved `currentCue` / `nextCue` only — **never** `index + 1` as cue number. Song next follows entry target (may be non-adjacent / other list). Section label + cue name must not invent a mismatched pair. |
| **Type** | `PerformanceCueSummary { listID, cueID, number, name, sectionLabel? }` (already present — finish consumers / edge cases) |

#### A5 — Inspector CURRENT uses list + cue identity

**Review §8**

| | |
|--|--|
| **Files** | `InspectorPanel.swift`, host/registry that pass playback props |
| **Behavior** | CURRENT only if inspected cue is the live cue: prefer `cue.id == playbackCueID`, else `list.id == playbackCueListID && index == playbackCueIndex`. Same index on another list must not show CURRENT. |

---

### Wave B — Shell state correctness (P1)

#### B1 — Explicit fixture click → Inspector focus

**Review §9**

| | |
|--|--|
| **Files** | `FixtureBrowserPanel.swift`, `BuildWorkspaceHost.swift`, `WorkspaceController.swift` |
| **Behavior** | Add `onInspectFixtures: ([UUID]) -> Void` (or equivalent). User click → `noteExplicitFixtureInspect`. Programmatic selection → keep sticky cue/group/palette via existing `noteFixtureSelectionChanged`. Group rows: either set `.group(id)` when inspecting group, or make “select only” visually clear. |

#### B2 — Full document-scoped UI reset

**Review §10 + Amendment §5**

| | |
|--|--|
| **Files** | `WorkspaceController.didReplaceDocument`, `AppModel` New/Open/Demo/Finder-open, optional `documentEpoch` on workspace |
| **Behavior** | After every document replacement call `workspace.didReplaceDocument(project:)`. Reset: Inspector focus, document tool-local IDs, bump epoch for CueList (and any similar `@State` IDs). **Do not** reset Build/Perform mode (presentation-only). Panels remain defensive if IDs vanish. |

#### B3 — CueList self-heal (complete with B2)

**Review §10**

| | |
|--|--|
| **Files** | `CueListPanel.swift`, host passing `documentEpoch` |
| **Behavior** | Stale `selectedListID` → first valid list; clear invalid `selectedCueID`; heal on epoch + list-id changes. |

#### B4 — View menu truthfulness

**Review §11**

| | |
|--|--|
| **Files** | `AuroraApp.swift` View menu |
| **Preferred UI-02** | Remove `WorkspacePanelID` visibility toggles. Keep Build Mode / Perform Mode. Optional: Browser / Patch / Groups / Palettes / Cues / Song if they map to real `leftTool` / `lowerTool` setters. Document `WorkspaceLayout` as legacy/future (UI-11), not production chrome. |

#### B5 — Awaitable dirty save for New/Open/Demo

**Review §12 + Amendment §6**

| | |
|--|--|
| **Files** | `AppModel.swift`, `ProjectController.swift` (confirm flow), reuse quit/`ProjectSaveCoordinator` / `saveShowAsync` |
| **Behavior** | Replace sync `confirmDiscardIfDirty` for document replacement with async flow: prompt → Save **await** explicit success → continue; Discard → continue; Cancel → stop. Prefer explicit `SaveResult` / bool from `saveShowAsync`, **not** immediate `!session.isDirty` after fire-and-forget. Same coordinator for New, Open, Finder-open, Demo. |

---

### Wave C — Operational polish (P1 / easy P2)

| ID | Fix | Files | Behavior |
|----|-----|-------|----------|
| **C1** | No surprise DEBUG demo | `AuroraApp.swift` | Remove auto-load on empty. Keep File / Welcome “Open Demo Show”. Optional `--load-demo-show` / env gate only if needed for screenshots. |
| **C2** | Demo routing safe | `ShowProject+DemoSummerNight.swift` | Default universe `protocolHint: .none` (not `.artNet`). |
| **C3** | Frame-rate commit on end | `AuroraSettingsRoot.swift`, maybe `AppModel` | Local `@State` while dragging; call `setPreferredFrameRateHz` only on editing end (or discrete control). Label that change affects running engine. |
| **C4** | Shared health (finish) | `AuroraShellHealth.swift` + consumers | One mapping for toolbar / status / Perform. MIDI error → warning **everywhere**. Omit Network unless truthful aggregate exists. |
| **C5** | Settings Output scope | `AuroraSettingsRoot.swift` | Split APPLICATION (drivers/defaults) vs PROJECT (universe protocol hints / routing). |
| **C6** | Surface silent failures | Settings MIDI delete (+ easy panel sites) | `do/catch` or shared helper; status message / log; no pretend success. |
| **C7** | Deterministic demo cue IDs | `ShowProject+DemoSummerNight.swift` | Fixed UUIDs for cues (like fixtures); keep song entry refs consistent. |

---

### Wave D — Tests, ownership, cheap cleanup, verification

#### D1 — Automated tests (extracted logic; no UI pixel tests)

| Area | Assertions |
|------|------------|
| Cue actions | select ≠ fire; fire explicit; double-fire not duplicated |
| PerformanceCueSummary | number = `Cue.number` not index+1; song non-adjacent / other-list next |
| Inspector CURRENT | same index wrong list → not current |
| WorkspaceController | explicit fixture inspect; document reset; tools; mode does not wipe playback (playback not on workspace) |
| Dirty coordinator | save success → continue once; cancel → stop |
| Health pure map | MIDI error → warning; no fabricated network-disabled if omitted |
| Demo model | protocolHint none; fixed cue IDs if unit-testable |

#### D2 — Roadmap ownership (docs only)

Update `UIDevPlan.md` and/or handoff so restoration is explicit:

| Phase | Owns |
|-------|------|
| **UI-03** | Programmer: Clear All, Fan, Align, technical RGB/W — restore / replace / retire decisions |
| **UI-04** | Palettes/presets: create from Programmer, delete, rename, record ref to cue |
| **UI-05** | Cue workflow: add/delete list/cue, edit name/fade/delay, record/update, explicit Fire UI |

Double-click fire from hardening remains compatible with UI-05.

#### D3 — Cheap observation cleanup (optional if quick)

- Remove redundant `objectWillChange.send()` after pure `@Published` assigns in `WorkspaceController` (and similar obvious sites).  
- Do **not** redesign AppModel observation for this pass (P2 — early UI-03).

#### D4 — macOS verification

```text
swift test          # on macOS product environment
xcodebuild …        # Debug (and ideally Release)
```

Plus manual checklist from review §32 and amendments §11 (see §5 below).

#### D5 — Mode-transition acceptance (Amendment §8)

```text
Build → Perform → Build
```

Must **not** change: current cue, list position, Song position, engine/output/MIDI running state, fixture selection (where appropriate). Presentation only.

---

## 3. Explicit non-work (do not rebuild in this pass)

| Regression | Owner |
|------------|-------|
| Full Cue List editor (add/delete/edit/record) | UI-05 |
| Palette create/delete/record-ref | UI-04 |
| Programmer Fan/Align/Clear All/RGB tech | UI-03 |
| Full Show Lock | later |
| Docking / revive WorkspaceLayout production menus | UI-11 |
| Broad PanelRegistry / AppModel observation split | progressive per panel phase |

---

## 4. Implementation sequence (concrete PR-style steps)

Work in order; each step should leave the app buildable.

1. **A1 finish** — Confirm CueList single/double-click + SelectionManager + Build host/registry props; no single-click fire.  
2. **A2** — Wire `KeyboardCommandGate` into Playback commands (and optional action guards).  
3. **A3** — Mode-gate File structural menus in Perform.  
4. **A4 verify** — Perform shell + snapshot resolve; kill any remaining index+1 presentation.  
5. **A5** — Pass playback listID/cueID into Inspector; CURRENT by identity.  
6. **B1** — `onInspectFixtures` from FixtureBrowser → `noteExplicitFixtureInspect`.  
7. **B2+B3** — Call `didReplaceDocument` + bump `documentEpoch` from all replace paths; CueList heals.  
8. **B4** — Strip dead View panel toggles; keep real shell actions.  
9. **B5** — Async dirty decision for New/Open/Demo/Finder using awaitable save result.  
10. **C1–C3** — Demo auto-load off; protocolHint none; frame-rate onEditingChanged end.  
11. **C4–C7** — Health consistency check; Settings scope; try?; fixed demo cue UUIDs.  
12. **D** — Tests + roadmap docs + mode-transition verify + macOS build/test.  
13. **Close** — Update `UI_02_Shell_Handoff.md` / `PROJECT_HANDOFF.md`: UI-02 hardening complete; UI-03 unblocked.

---

## 5. Acceptance checklist (UI-02 hardening complete)

```text
[ ] Single-click cue selects/inspects; does not fire
[ ] Double-click cue fires exactly once
[ ] GO remains explicit transport path
[ ] Text/value editing: Space/Return/Left/B/Esc do not accidental-transport
[ ] Perform hides structural New/Open/Import (toolbar + menus)
[ ] Current/Next use resolved cue identity; Cue.number not index+1
[ ] Song Next matches actual Song entry target
[ ] Inspector CURRENT uses list+cue identity
[ ] Explicit fixture click → fixture Inspector focus
[ ] Document replace resets/validates document-scoped UI state
[ ] Cue List self-heals stale list selection
[ ] View menu only commands that affect production UI
[ ] Save-before-New/Open awaits explicit save success then continues once
[ ] DEBUG does not surprise-load demo
[ ] Demo default routing is not live Art-Net
[ ] Frame-rate edit does not restart engine every tick
[ ] Shared health mapping; MIDI error consistent; no fake Network disabled
[ ] Settings app/project scope truthful on Output page
[ ] Easy silent mutation failures surfaced
[ ] Demo cue IDs deterministic
[ ] Build → Perform → Build preserves live show/playback state
[ ] UI-03/04/05 restoration ownership documented
[ ] macOS tests pass; Xcode Debug build passes
[ ] Backend domain semantics unchanged
```

---

## 6. Risk notes

| Risk | Mitigation |
|------|------------|
| Double-click fires twice (select gesture + fire) | Separate actions; only `onDoubleClickFire` calls engine |
| Gate misses SwiftUI field editors | Class-name + NSTextView checks; manual macOS pass |
| Async dirty race | Single await path; do not continue on cancel/failure |
| Demo `.none` surprises devs expecting Art-Net | Explicit Output menu still enables Art-Net; docs note default |
| Epoch not bumped | Centralize bump inside `didReplaceDocument` or AppModel replace helper |

---

## 7. Success definition

UI-02 hardens to:

```text
safe · truthful · state-correct · operationally predictable
```

Then: macOS verification → close UI-02 → proceed to **UI-03 (Fixture Browser + Programmer)** without shell rewrites.

---

## 8. Primary file map

| Area | Paths |
|------|-------|
| Cue UX | `AuroraUI/Panels/CueListPanel.swift`, `AuroraUI/Components/AuroraCueRow.swift` |
| Keyboard | `Aurora/Shell/KeyboardCommandGate.swift`, `Aurora/AuroraApp.swift` |
| Toolbar / health | `AuroraBuildToolbar.swift`, `AuroraAppStatusBar.swift`, `AuroraShellHealth.swift` |
| Perform | `PerformWorkspaceShell.swift`, `PerformanceSnapshot.swift` |
| Workspace | `WorkspaceController.swift`, `BuildWorkspaceHost.swift` |
| Document | `AppModel.swift`, `ProjectController.swift` |
| Fixture | `FixtureBrowserPanel.swift` |
| Inspector | `InspectorPanel.swift` |
| Settings | `AuroraSettingsRoot.swift` |
| Demo | `ShowProject+DemoSummerNight.swift` |
| Tests | `Tests/` (new shell/presentation unit tests) |
| Docs | `UIDevPlan.md`, `UI_02_Shell_Handoff.md`, `PROJECT_HANDOFF.md` |
