# Aurora — Project Handoff / Compressed-Session Memory

**Purpose:** Survive chat-memory compression. **Read this file first** in any new session before changing code.

| Field | Value |
|-------|--------|
| **Last updated** | 2026-08-05 (**UI-02 GATE CLOSEOUT — READY FOR UI-03**) |
| **Workspace** | `/Users/dakota/code/Aurora` |
| **Branch** | `main` (local only; no remote assumed) |
| **HEAD** | `dbdd891` — tag `ui-02-complete` |
| **Tests** | **281** passing (`swift test`) |
| **Xcode app** | `Aurora.xcodeproj` — Debug build green after closeout |

**Open first after compression:**

1. **`docs/PROJECT_HANDOFF.md`** (this file)
2. **`UIDesignReferences/UIDevPlan.md`** — **active UI-phase roadmap** (amended)
3. **`docs/UI_BACKEND_CONTRACT.md`** — **authoritative UI API / domain contract**
4. **`docs/STAGE_C_UI_STATE_HANDOFF.md`** — controller ownership
5. **`docs/xcode-project.md`** — Xcode app, entitlements, schemes
6. **`Package.swift`** + **`Sources/Aurora/AppModel.swift`**

**Read when architecting** (control plane / MIDI / song / remote / engine — **not** active backlog):

7. **`docs/ARCHITECTURE_FUTURE_GUARDRAILS.md`** — standing “don’t seal wrong abstractions” rules
8. **`FutureReference/Aurora_Future_Features_and_Long_Term_Vision.md`** — long-term product direction only

**Active UI status:**

- **UI-02 GATE CLOSEOUT COMPLETE** — proceed to UI-03 when user asks
- Shell hardened (P0/P1) + final gate: stable playback cue UUID on live edit; presentation never falls back to unrelated first list
- Build: Option A nav · Inspector focus · welcome empty · explicit fixture inspect
- Perform: truthful Current/Next (`PerformanceCueSummary`); structural File actions hidden
- Cue list: single-click select/inspect; double-click fire
- Settings: thin MIDI · frame-rate commit-on-end · Output app/project scope
- Contract: `docs/UI_PANEL_CONTRACT.md`
- Handoff: `UIDesignReferences/UI_02_Shell_Handoff.md`
- Reviews: `UIDesignReferences/UI-02Ref/` (deep review, hardening plan, post-UI-02 final gate)
- Demo: **File → Open Demo Show** (`⇧⌘D`) or `--load-demo-show` — **not** auto on launch; `protocolHint: .none`
- Restoration ownership: UI-03 Programmer · UI-04 Palettes · UI-05 Cues (see UIDevPlan)

**Historical only (not active backlog):**

- Pre-UI gate / remediation reviews — **implemented**; root Markdown removed from tree (recoverable from git history before the UI-02 era if needed)
- `UIDesignReferences/Aurora_UIDevPlan_Recommended_Amendments.md` — incorporated into UIDevPlan
- `FutureReference/*` — vision only; **do not implement unprompted**

**Do not invent new PR work without an explicit user request.**
**Do not implement FutureReference features unless the user asks.**

---

## 1. What Aurora is

**Aurora** is a **macOS-native professional lighting control** app for live performance (patch, cues, MIDI/OSC, Art-Net/sACN, ENTTEC USB Pro framing mock, web remote). Swift SPM monorepo + Xcode app, macOS 14+.

---

## 2. Architecture (must not break)

```
UI / MIDI / OSC / remote
  → ControlActionRouter (multi-observer; live off MainActor)
  → DocumentSession and/or LightingEngine
  → OutputManager → drivers

Save / Save As / autosave
  → ProjectSaveCoordinator (actor, per-destination serial)
  → ProjectPackage.save
```

- **`updateProject`** preserves playback; **`load`** is destructive
- Package writes are **serialized**; stale autosave cannot overwrite a newer manual save on disk
- Output status from live `presentationSnapshot()` / health, not a config-only cache
- Quit: `prepareToTerminate()` → await save → idempotent `shutdown()`

### Future MIDI — do not seal note → cue only

Long-term Aurora treats MIDI as a **rich real-time performance input**, not a thin “Note 38 → fire cue” layer.
Today’s mapping → `ShowAction` path is intentionally simple, but must stay open:

| Keep open | Avoid |
|-----------|--------|
| Rich `MIDIEvent` (source, channel, note, velocity, CC) | Collapsing to note-number-only at the boundary |
| Open `MIDIMapping.action` key space + optional scalar | Sealing actions to fireCue only |
| `programmerAttribute` and non-cue `ShowAction`s | MIDI learn that can only arm cue fire |
| Live path off MainActor via `ControlActionRouter` | Moving live MIDI into SwiftUI / MainActor-only AppModel |

Full rules: **`docs/ARCHITECTURE_FUTURE_GUARDRAILS.md`**.
Vision (not backlog): **`FutureReference/Aurora_Future_Features_and_Long_Term_Vision.md`**.
If a design would significantly block Advanced MIDI, semantic control, or UI-independent execution — **document the tradeoff before committing**.

---

## 3. Pre-UI blockers completed (this pass)

| ID | Fix |
|----|-----|
| **BLOCKER-1** | `ProjectSaveCoordinator` + async ProjectController save/autosave; quit awaits save |
| **PRE-UI-1** | `OutputPresentationSnapshot` from live health; presentation poll refreshes |
| **PRE-UI-2** | Lock-protected `isRunning` on all output drivers |
| **PRE-UI-3** | `applicationShouldTerminate` / `applicationWillTerminate` → shutdown |
| **UI-FOUNDATION-5** | 16-bit home/highlight uses coarse\|fine / 65535 |
| Doc | Bookmarks entitlement documented as reserved/not implemented |

**Carry into first UI PR (not done here):** UI-FOUNDATION-1 Option A composition, app integration tests, bookmark store, AppIcon artwork.

---

## 4. Key domain rules (summary)

| Topic | Behavior |
|-------|----------|
| Dirty | Unique state IDs; group dirty on first mutation |
| Save | Coordinator serializes; mark clean only for written state ID if still current |
| Route `none` | No physical output; `mirror` = all protocols |
| Active channels | Sum across all universes |
| Song | Manual only |
| Frame rate | App setting drives engine 20–44 Hz |
| ENTTEC | USB Pro framing only — not Open DMX |
| Home/Highlight | Full 16-bit when coarse+fine present |

---

## 5. Intentionally next (user-driven)

1. **UI-03** — Fixture Browser + Programmer attribute-state semantics + scale (when asked)
2. Hardware soak Art-Net/sACN/ENTTEC (optional parallel)
3. Do **not** reopen UI-02A visual identity or re-shell UI-02

**Stop backend feature work** until user requests otherwise.

---

## 6. Smoke

```bash
swift test
xcodebuild -project Aurora.xcodeproj -scheme Aurora -destination 'platform=macOS' \
  -configuration Debug CODE_SIGN_IDENTITY="-" build
open Aurora.xcodeproj   # Run Aurora
```

---

## 7. Agent instructions post-compact

```
Read docs/PROJECT_HANDOFF.md and docs/UI_BACKEND_CONTRACT.md first.
When changing MIDI / control plane / song / remote / engine APIs:
  also read docs/ARCHITECTURE_FUTURE_GUARDRAILS.md
  (and FutureReference vision if the change has long-term impact).
Do not invent PR work without explicit user request.
Do not implement FutureReference features unprompted.
Do not seal MIDI as cue-only triggers.
Backend pre-UI blockers are DONE — do not re-implement from review MDs.
UI redesign only when user asks (Option A composition).
Preserve control path, save coordinator, module deps, live non-MainActor MIDI.
```

---

*End of handoff.*
