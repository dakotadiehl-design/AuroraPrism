# Aurora — Project Handoff / Compressed-Session Memory

**Purpose:** Survive chat-memory compression. **Read this file first** in any new session before changing code.

| Field | Value |
|-------|--------|
| **Last updated** | 2026-08-13 (**Patch/Stage UX Waves 1–6 skeleton+features; schema v3**) |
| **Workspace** | `/Users/dakota/code/Aurora` |
| **Branch** | `main` (local only; no remote assumed) |
| **Working tree** | Dirty: full Lightkey Pass-1 gap remediation (uncommitted) |
| **Tests** | **385** passing (`swift test`) |
| **Xcode** | `xcodegen generate` then Debug |

**Open first after compression:**

1. **`docs/PROJECT_HANDOFF.md`** (this file)
2. **`UIDesignReferences/UIDevPlan.md`**
3. **`docs/UI_BACKEND_CONTRACT.md`**
4. **`docs/STAGE_C_UI_STATE_HANDOFF.md`**
5. **`Package.swift`** + **`Sources/Aurora/AppModel.swift`**

**Phase handoffs (UI):**

| Phase | Handoff |
|-------|---------|
| UI-02 | `UIDesignReferences/UI_02_Shell_Handoff.md` |
| UI-03 | `UIDesignReferences/UI_03_Handoff.md` |
| UI-04 | **`UIDesignReferences/UI_04_Handoff.md`** |
| UI-05 | **`UIDesignReferences/UI_05_Handoff.md`** |
| UI-06 | **`UIDesignReferences/UI_06_Handoff.md`** |
| UI-07 | **`UIDesignReferences/UI_07_Handoff.md`** |
| Plan + A1–A6 | `UIDesignReferences/Aurora_UI04-UI07_Plan_Amendments.md` |

---

## Active status

```text
UI-01  Design system          COMPLETE
UI-02  Shell + hardening      COMPLETE  (tag ui-02-complete)
UI-03  Browser + Programmer   COMPLETE  (tag ui-03-complete)
UI-04  Palettes + Presets     COMPLETE
UI-05  Cue Workflow           COMPLETE
UI-06  Song Mode              COMPLETE
UI-07  Perform Mode           COMPLETE
FIXES  Integration CR-01…15 + pre-commit  COMPLETE
UI-08  Full Settings          COMPLETE  (+ Art-Net/sACN/RTP/OSC rehost; density not applied)
UI-09  Patch + diagnostics    COMPLETE  (Build Diagnostics tool; row validation; live snapshot)
UI-10  Web/iPad Remote        COMPLETE  (listener ready truth; session touch; re-auth; Keychain PIN)
UI-11  Build layouts          COMPLETE  (real divider persistence; Diagnostics lower tool)
STAB1  FirstPass findings     COMPLETE
STAB2  SecondPass deep review COMPLETE  (REM/DIAG/LAYOUT/PATCH/SEC/SET)
PARITY Lightkey pre-smoke     NEAR COMPLETE (Pass-1 remaining items landed; Wave 9 ready)
NEXT   Operator hardware smoke + formal Wave 9 checklist
```

**Parity plan:** amended Lightkey-Parity plan (A1–A6). Matrix: `UIDesignReferences/Lightkey_Parity_Matrix.md`  
**Gap report:** `FutureReference/Aurora_LightKey_Parity_Pass1_Audit_Gap_Report.md`  
**Roadmap:** `FutureReference/Aurora_Lightkey_Parity_Pre_Smoke_Test_Roadmap.md`

### Pass-1 full remediation (summary)

- **Engine:** ResolvedShowSnapshot; freeze semantic hold; Master dimmer semantics; multi-cell compile; MIDI behavior layer; expanded effects.
- **MIDI P0-J:** Rules; behaviors (AHDR/ADSR envelopes); drum profiles; safety limiter; CoreMIDI feedback out; expressive events; schema v3.
- **Library P0-E:** `.auroralib` export/import (File menu) + merge command.
- **Effects P0-G:** positionCircle, colorStep, cellChase, beamPulse; phase/spread/direction UI.
- **Patch P0-C:** renumber, bulk create, CSV import, CSV clipboard export.
- **Output P0-L:** Universe Monitor semantic attribution (fixture + parameter).
- **UI:** Profile editor, Stage tools, Programmer beam/strobe/generic, cue authoring, remote Master/BO, Diagnostics health + external log.


**Handoffs:** `UI_08`…`UI_11_Handoff.md`, `UI_08_11_Integration_Summary.md`,
`Aurora_UI08-UI11_FirstPass_Stabilization_Findings.md`,
`Aurora_UI08-UI11_SecondPass_Deep_Review_Findings.md`

---

## 1. What Aurora is

**macOS-native professional lighting control** (patch, cues, MIDI/OSC, Art-Net/sACN, ENTTEC USB Pro framed local DMX — software path ready, physical smoke pending, web remote). Swift SPM monorepo + Xcode app, macOS 14+.

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

- **`updateProject`** preserves playback by **cue UUID** (not array index)
- **Playback order** = `CueList.cues` **array order**; `Cue.number` is display only (UI-05 A4)
- Programmer is **engine-ephemeral** until recorded into cue/preset/palette
- UI composition: **Option A** — AuroraUI pure panels; app binds controllers
- SongDirector **orchestrates** entries onto PlaybackController — not a second engine
- Perform is thin cockpit over `PerformanceSnapshot`; GO not gated by health (A6)

---

## 3. Operator chain (integration review target)

```text
Select fixtures
  → Program attributes (UI-03)
  → Store/apply palettes (UI-04)
  → Record cues (UI-05)
  → Organize song entries (UI-06)
  → Perform Mode GO/BACK/STOP + MIDI (UI-07)
  → Engine / Output
```

---

## 4. Amendment locks still in force

| ID | Rule |
|----|------|
| A1 | UI-04 Record Ref does not expand into cue editor |
| A2 | Mixed palette attrs never silently omitted |
| A3 | Cue Update immediate, undoable, no routine modal |
| A4 | Array order = playback; number = display |
| A5 | GO dominant; song entry nav secondary |
| A6 | Nonfatal health does not disable transport |

---

## 5. Smoke

```bash
swift test
xcodebuild -project Aurora.xcodeproj -scheme Aurora -destination 'platform=macOS' \
  -configuration Debug CODE_SIGN_IDENTITY="-" build
# Optional: xcodegen generate if new sources missing from Xcode
open Aurora.xcodeproj
```

Demo: **File → Open Demo Show** (`⇧⌘D`).

---

## 6. Agent instructions post-compact

```text
1. Read this handoff + UI_BACKEND_CONTRACT first.
2. UI-04…UI-07 are DONE — do not re-implement.
3. STOP before UI-08 unless user explicitly requests.
4. Integration review + hardware smoke readiness next.
5. Preserve control path, save coordinator, Option A, live non-MainActor MIDI.
6. When regenerating Xcode: xcodegen generate.
```

---

## 7. Key new files (UI-04…07)

```text
Sources/AuroraModel/PaletteCreate.swift
Sources/AuroraCore/Commands/RemoveCueListCommand.swift
Sources/AuroraUI/Panels/PalettesPanel.swift   (create/apply/delete/ref)
Sources/AuroraUI/Panels/CueListPanel.swift    (full editor)
Sources/AuroraUI/Panels/SongPanel.swift       (entry editor)
Sources/Aurora/Shell/PerformWorkspaceShell.swift  (cockpit)
UIDesignReferences/UI_04_Handoff.md … UI_07_Handoff.md
```

---

*End of handoff — UI-07 integration gate; safe to compact after commit.*
