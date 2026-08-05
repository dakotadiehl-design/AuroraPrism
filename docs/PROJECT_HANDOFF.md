# Aurora — Project Handoff / Compressed-Session Memory

**Purpose:** Survive chat-memory compression. **Read this file first** in any new session before changing code.

| Field | Value |
|-------|--------|
| **Last updated** | 2026-08-05 (**ready for compaction — UI-03 closed**) |
| **Workspace** | `/Users/dakota/code/Aurora` |
| **Branch** | `main` (local only; no remote assumed) |
| **HEAD** | `49ffb41` (handoff pin); product commit **`dd131db`** |
| **Tags** | `ui-02-complete` → `dbdd891` · **`ui-03-complete` → `dd131db`** |
| **Working tree** | **Clean** |
| **Tests** | **304** passing (`swift test`) |
| **Xcode** | Debug build green after UI-03 Pass 2 |

**Open first after compression:**

1. **`docs/PROJECT_HANDOFF.md`** (this file)
2. **`UIDesignReferences/UIDevPlan.md`** — active UI-phase roadmap
3. **`docs/UI_BACKEND_CONTRACT.md`** — authoritative UI API / domain contract
4. **`docs/STAGE_C_UI_STATE_HANDOFF.md`** — controller ownership
5. **`docs/xcode-project.md`** — Xcode app, entitlements, schemes
6. **`Package.swift`** + **`Sources/Aurora/AppModel.swift`**

**Phase handoffs (UI):**

| Phase | Handoff / plan |
|-------|----------------|
| UI-02 shell | `UIDesignReferences/UI_02_Shell_Handoff.md` |
| UI-02 reviews | `UIDesignReferences/UI-02Ref/` |
| UI-03 Programmer | **`UIDesignReferences/UI_03_Handoff.md`** |
| UI-03 plans/reviews | `UIDesignReferences/UI-03Ref/` |

**Architecture (not backlog):**

7. **`docs/ARCHITECTURE_FUTURE_GUARDRAILS.md`**
8. **`FutureReference/*`** — vision only; **do not implement unprompted**

---

## Active status

```text
UI-01  Design system          COMPLETE
UI-02  Shell + hardening      COMPLETE  (tag ui-02-complete)
UI-03  Browser + Programmer   COMPLETE  (tag ui-03-complete, Pass 2)
NEXT   UI-04 Palettes         when user asks only
```

**Do not invent PR work. Do not start UI-04 (or any phase) unprompted.**

---

## 1. What Aurora is

**macOS-native professional lighting control** (patch, cues, MIDI/OSC, Art-Net/sACN, ENTTEC USB Pro framing mock, web remote). Swift SPM monorepo + Xcode app, macOS 14+.

---

## 2. Architecture (must not break)

```text
UI / MIDI / OSC / remote
  → ControlActionRouter (multi-observer; live off MainActor)
  → DocumentSession and/or LightingEngine
  → OutputManager → drivers

Save / Save As / autosave
  → ProjectSaveCoordinator (actor, per-destination serial)
  → ProjectPackage.save
```

- **`updateProject`** preserves playback by **cue UUID** (not array index); **`load`** is destructive
- Package writes serialized; quit awaits save then `shutdown()`
- Output status from live health / `presentationSnapshot()`
- Programmer is **engine-ephemeral** until recorded into cue/preset
- UI composition: **Option A** — AuroraUI pure panels; app binds controllers
- Build Option A: left Browser|Patch|Groups · center **Programmer always** · lower Palettes|Cues|Song · right Inspector
- Perform is presentation-only mode (does not stop playback)

### Future MIDI — do not seal note → cue only

See **`docs/ARCHITECTURE_FUTURE_GUARDRAILS.md`**. Keep rich MIDI path open; live off MainActor.

---

## 3. UI-03 summary (just closed)

| Concept | Implementation |
|---------|----------------|
| Support × value | `AttributeSupportState` × `ProgrammerValueState` in `ProgrammerAttributePresentation` |
| Projection store | `ProgrammerPresentationStore` (not second truth; discardable) |
| Mixed UI | `AuroraControlDisplayValue` (.value / .mixed / .unavailable) |
| Fan | center + spread on **ordered** capable fixtures; pan/tilt independent |
| Align | **Align to First** first capable **owned** value; no fabricated 0 |
| Color | HSV only if `hasRGBColor`; technical channels only if supported |
| Batch write | `Programmer.setMany([UUID:[String:Double]])` for multi-attr (HSV) |
| Selection | Groups/browser use `selectFixturesOrdered` |

Key files:

```text
Sources/AuroraEngine/ProgrammerAttributePresentation.swift
Sources/AuroraEngine/ProgrammerGeometry.swift
Sources/AuroraEngine/Programmer.swift
Sources/Aurora/Controllers/ProgrammerPresentationStore.swift
Sources/AuroraUI/Panels/ProgrammerPanel.swift
Sources/AuroraUI/Panels/FixtureBrowserPanel.swift
Sources/AuroraUI/Components/AuroraControlDisplayValue.swift
Sources/AuroraUI/Components/AuroraFader.swift
Sources/AuroraUI/Components/AuroraPositionPad.swift
```

---

## 4. UI-02 shell guarantees (still true)

| Behavior | Rule |
|----------|------|
| Cue click | Single = select/inspect; double = fire once |
| Transport shortcuts | Gated while text editing (`KeyboardCommandGate`) |
| Perform chrome | Hides New/Open/Import |
| Current/Next | `PerformanceCueSummary` (real cue numbers, Song targets) |
| Document replace | `didReplaceDocument` + `documentEpoch` |
| Dirty New/Open | Await explicit save result |
| Demo | Explicit only; `protocolHint: .none`; fixed cue IDs |
| Health | Shared `AuroraShellHealthSnapshot` |

---

## 5. Domain rules (short)

| Topic | Behavior |
|-------|----------|
| Dirty / save | Coordinator; mark clean only for written state if still current |
| Route `none` | No physical output; `mirror` = all protocols |
| Song | Manual only |
| Frame rate | App setting 20–44 Hz; commit on slider **end** |
| ENTTEC | USB Pro framing only — not Open DMX |
| Home | Full 16-bit when coarse+fine present |

---

## 6. Intentionally next (user-driven only)

1. **UI-04** — Palettes / presets: create from Programmer, delete, rename, record-ref to cue  
2. **UI-05** — Full cue list edit / record / update  
3. Optional: hardware soak Art-Net/sACN/ENTTEC  

**Deferred from reviews (not blockers):** remote CURRENT/NEXT (UI-10); progressive AppModel observation; inherited/palette-ref chrome when data real.

---

## 7. Smoke

```bash
swift test
xcodebuild -project Aurora.xcodeproj -scheme Aurora -destination 'platform=macOS' \
  -configuration Debug CODE_SIGN_IDENTITY="-" build
# Optional: xcodegen generate if new sources missing from Xcode
open Aurora.xcodeproj
```

Demo: **File → Open Demo Show** (`⇧⌘D`) or `--load-demo-show`. Debug does **not** auto-load demo.

---

## 8. Agent instructions post-compact

```text
1. Read docs/PROJECT_HANDOFF.md and docs/UI_BACKEND_CONTRACT.md first.
2. UI roadmap: UIDesignReferences/UIDevPlan.md — next is UI-04 only if user asks.
3. UI-03 details: UIDesignReferences/UI_03_Handoff.md
4. Do not invent PR work without explicit user request.
5. Do not implement FutureReference features unprompted.
6. Do not seal MIDI as cue-only triggers.
7. Do not redesign UI-02 shell or reopen UI-02A visual identity.
8. Preserve control path, save coordinator, Option A composition, live non-MainActor MIDI.
9. Backend pre-UI blockers and UI-02/UI-03 are DONE — do not re-implement from old review MDs.
10. When regenerating Xcode project: xcodegen generate (project.yml is source of truth).
```

---

## 9. Git checkpoints (local)

```text
b87dcf6  Pre-UI blockers
dbdd891  ui-02-complete — hardened application shell
dd131db  ui-03-complete — Fixture Browser + Programmer (incl. Pass 2)
49ffb41  Handoff pin for dd131db
```

---

*End of handoff — safe to compact.*
