# Aurora — Project Handoff / Compressed-Session Memory

**Purpose:** Survive chat-memory compression. **Read this file first** in any new session before changing code.

| Field | Value |
|-------|--------|
| **Last updated** | 2026-08-05 (Final Backend UI Gate complete) |
| **Workspace** | `/Users/dakota/code/Aurora` |
| **Branch** | `main` (local only; no remote assumed) |
| **HEAD** | *(see `git log -1`)* — Final UI-gate backend fixes |
| **Tests** | **255** passing (`swift test`) |
| **Xcode app** | `Aurora.xcodeproj` — composes SPM libraries |

**Open first after compression:**

1. **`docs/PROJECT_HANDOFF.md`** (this file)  
2. **`docs/UI_BACKEND_CONTRACT.md`** — **authoritative UI API / domain contract**  
3. **`docs/STAGE_C_UI_STATE_HANDOFF.md`** — controller ownership  
4. **`docs/xcode-project.md`** — Xcode app, entitlements, schemes  
5. **`Package.swift`** + **`Sources/Aurora/AppModel.swift`**  

**Historical only (not active backlog):**

- `Aurora_Final_Backend_UI_Gate_Review.md` — **implemented 2026-08-05**  
- `Aurora_Post_Remediation_Deep_Review_UI_Readiness.md`  
- `Aurora_Deep_Code_Review_Fixes.md`  

**Do not invent new PR work without an explicit user request.**  
**Backend gate is closed — next major deliverable is visual UI redesign when the user asks.**

---

## 1. What Aurora is

**Aurora** is a **macOS-native professional lighting control** app for live performance:

- Patch fixtures, program looks, run cues with timing/tracking  
- MIDI / RTP-MIDI / OSC control, song orchestration  
- Art-Net + sACN DMX output; ENTTEC USB Pro framing (mock transport; not Open DMX)  
- Live effects (pulse/chase/wave/rainbow), persistent in show package  
- Stage **web remote** (iPad Safari) on LAN + random PIN  

**Stack:** Swift 5.9+ / 6.x, SwiftUI + AppKit, SPM monorepo libraries, **Xcode app target** for `Aurora.app`, CoreMIDI, Network.framework, **macOS 14+ only**.

---

## 2. Environment

| Item | Value |
|------|--------|
| OS | macOS arm64 |
| Xcode | `/Applications/Xcode.app` (must be active developer dir) |
| Build app | `open Aurora.xcodeproj` → scheme **Aurora** |
| Build CLI | `swift build && swift test && swift run Aurora` |
| CI | `.github/workflows/macos-ci.yml` |

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer   # if needed
cd /Users/dakota/code/Aurora
swift test
xcodebuild -project Aurora.xcodeproj -scheme Aurora -destination 'platform=macOS' \
  -configuration Debug CODE_SIGN_IDENTITY="-" build
```

Regenerate Xcode project: `./Scripts/generate-xcodeproj.sh` (needs `brew install xcodegen`).

---

## 3. Repository layout (high level)

```
Aurora/
├── Package.swift              # library graph + CLI executable product
├── project.yml                # XcodeGen source of truth
├── Aurora.xcodeproj/          # macOS App target (composes SPM libraries)
├── App/                       # Info.plist, entitlements, Assets
├── Sources/
│   ├── Aurora/                # @main shell, AppModel, Controllers/, router
│   ├── AuroraModel/           # pure data, package I/O, validator, migration
│   ├── AuroraCore/            # commands, session, selection
│   ├── AuroraEngine/          # playback, merge, effects, CompiledShow
│   ├── AuroraOutput/          # DMX, Art-Net, sACN, ENTTEC, health
│   ├── AuroraMIDI/            # CoreMIDI, OSC, resolver, ShowAction
│   ├── AuroraFixtureLib/      # seed + importer
│   ├── AuroraUI/              # panels + workspace
│   ├── AuroraRemote/          # TCP/web remote
│   └── AuroraDiagnostics/     # events + store
└── Tests/
```

---

## 4. Architecture (must not break)

### Control path

```
UI / MIDI / OSC / remote
  → ControlActionRouter (multi-observer; live off MainActor)
  → DocumentSession and/or LightingEngine / SongDirector
  → OutputManager (protocol-routed) → drivers → hardware
```

- Live MIDI/OSC/remote transport **does not wait on MainActor** before engine dispatch  
- Remote/song navigation may hop MainActor for `SongDirector` only  
- **`updateProject`** preserves playback; **`load`** is destructive (New/Open)  
- UI observers: `addUIObserver` — MIDI log + show-control both subscribe  

### Module deps (SPM)

```
AuroraModel          → (none)
AuroraFixtureLib     → Model
AuroraOutput         → Model, Network
AuroraEngine         → Model, Output
AuroraCore           → Model, Engine
AuroraMIDI           → Model, CoreMIDI, Network
AuroraDiagnostics    → (none)
AuroraUI             → Core, Model, Engine, MIDI
AuroraRemote         → Core, Model, Network
Aurora (app / CLI)   → all libraries
```

### Stage C controllers

| Controller | Owns |
|------------|------|
| `ProjectController` | session, URL, dirty, save/open |
| `ShowControlController` | engine, router, song, `PerformanceSnapshot` |
| `InputController` | MIDI/OSC/RTP/learn |
| `OutputController` | drivers, Art-Net/sACN, health |
| `RemoteController` | remote host/web |
| `DiagnosticsController` | console + typed `DiagnosticsStore` |
| `WorkspaceController` | layout, Build/Perform mode |
| `AppSettingsStore` | app-global prefs (incl. real frame rate) |
| `AutosaveController` | background package I/O + state-ID check |

Full UI contract: **`docs/UI_BACKEND_CONTRACT.md`**.

---

## 5. Key domain rules (post UI-gate)

| Topic | Behavior |
|-------|----------|
| Dirty state | Unique monotonic state IDs; open command groups dirty on first mutation |
| Save As | `preservingAssetsFrom:` copies media/layouts from **open** package |
| Autosave | Snapshot on MainActor → I/O off MainActor → mark clean only if state ID matches |
| Playback edits | `.projectModified` → `updateProject`; New/Open → `load` |
| 16-bit DMX | Coarse/fine pairs → single UInt16 MSB/LSB |
| Package load | Required v1 JSON files fail if missing |
| Cue fade/loop | Crossfade = max(out fadeOut, in fadeIn); Follow re-enters loop |
| Effects | Persistent; explicit `order` (duplicates flagged by validator) |
| Selection | `orderedFixtureIDs` + membership set |
| MIDI | Multi-map; velocity/CC scalar; incomplete messages preserved across packets |
| Output route | **`none` = no physical output**; `mirror` = all protocols; typed routes match |
| Active channels | Sum across **all** universes (Mac + remote agree) |
| Validation | Cached off 40 Hz; unique universe **numbers**; full ID categories |
| Groups | `Group.fixtureIds` authoritative |
| Song | Manual progression only; automatic not implemented — do not expose as working |
| Frame rate | **App** setting drives engine scheduler (20–44 Hz); project field unused |
| ENTTEC | USB Pro framing only — not Open DMX; `LocalDMXDeviceDescriptor` for UI |

---

## 6. Work completed

### Stages A–E + Xcode (prior)
P0 data safety · UI Gate domain · Stage C controllers · P2/P3 hardening · Xcode packaging  

### Final Backend UI Gate (this pass)

| ID | Fix |
|----|-----|
| UI-GATE-1 | Multi-observer `ControlActionRouter` (MIDI log + show-control) |
| UI-GATE-2 | OSC + remote live dispatch before MainActor UI |
| UI-GATE-3 | Route `none` = no output; explicit `mirror` |
| UI-GATE-4 | Multi-universe active channel totals |
| UI-GATE-5 | MIDI incomplete-message state machine |
| UI-GATE-6 | Song automatic hidden/rejected until designed |
| UI-GATE-7 | Background autosave + state-ID check |
| PRE-UI-1 | Validator expansion + `AddUniverseCommand` number uniqueness |
| PRE-UI-2 | App frame rate drives engine + `settings.save()` |
| PRE-UI-3 | ENTTEC not Open DMX; `LocalDMXDeviceDescriptor` |
| PRE-UI-4 | Typed diagnostics subsystems on key log paths |
| PRE-UI-5 | Command-group provisional dirty |
| PRE-UI-6 | `nextFreeAddress` Int math |
| PRE-UI-7 | Orphan backup by mtime |
| PRE-UI-8 | `UI_BACKEND_CONTRACT.md` + handoff/README |

---

## 7. Intentionally incomplete / next (user-driven only)

| Item | Notes |
|------|--------|
| **Visual UI redesign** | Ready — consume `UI_BACKEND_CONTRACT.md` + Stage C handoff |
| Real Art-Net/sACN/ENTTEC hardware | Mock soak exists; desk not proven in-session |
| Physical ENTTEC serial transport | Descriptor contract ready; IOKit TBD |
| Automatic song progression | Deferred by product decision |
| Notarization / Team signing | Ad-hoc local/CI only |
| Dynamic dylib plugins | Protocols only |
| Full GDTF / TLS remote / native iPad | Roadmap |
| Full `NSDocument` | Intentionally not used |

**Sensible next user goals:**

1. Visual UI redesign  
2. Hardware validate Art-Net/sACN/ENTTEC  
3. Notarization when distributing  

---

## 8. Entry points

| Concern | Path |
|---------|------|
| App entry | `Sources/Aurora/AuroraApp.swift` |
| Composition root | `Sources/Aurora/AppModel.swift` |
| Controllers | `Sources/Aurora/Controllers/*` |
| Live router | `Sources/Aurora/ControlActionRouter.swift` |
| Document session | `Sources/AuroraCore/DocumentSession.swift` |
| Package I/O | `Sources/AuroraModel/ProjectPackage.swift` |
| Engine | `Sources/AuroraEngine/LightingEngine.swift` |
| Output routing | `Sources/AuroraOutput/OutputManager.swift` |
| UI contract | `docs/UI_BACKEND_CONTRACT.md` |

---

## 9. Conventions

1. Document mutations via **commands** + undo; programmer is engine-ephemeral  
2. Live GO/fire must not wait on MainActor when avoidable  
3. Additive Codable preferred  
4. Network: fail soft; never block 40 Hz tick  
5. Commits on `main`; update this handoff after major work  
6. Quality over finishing everything; no unprompted feature invention  
7. Do not re-open palette/song law without PR20–21 PDF  

---

## 10. Smoke path (human)

1. `open Aurora.xcodeproj` → Run **Aurora** (or `swift run Aurora`)  
2. Patch universe + fixture  
3. Programmer → Cue List → Live **GO**  
4. Optional: Effects, Art-Net/sACN, Enable Remote + PIN → browser `:8743`  
5. File → Save (atomic; dirty clears)  

---

## 11. Agent instructions post-compact

```
Read docs/PROJECT_HANDOFF.md and docs/UI_BACKEND_CONTRACT.md first.
Do not invent new PR work without an explicit user request.
Preserve control path and module dependency direction.
UI redesign only when user asks.
Backend UI-gate items are DONE — do not re-implement from old review MDs.
Update this handoff after major architecture/status changes.
```

---

## 12. Orientation checklist

- [ ] `swift test` → 255 green  
- [ ] Control path + multi-observer + non-MainActor remote/OSC understood  
- [ ] Output route semantics (`none` ≠ mirror) understood  
- [ ] UI redesign consumes `UI_BACKEND_CONTRACT.md`  
- [ ] Next work chosen by **user**  

---

*End of handoff. Compact chat freely after this file is committed.*
