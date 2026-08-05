# Aurora — Project Handoff / Compressed-Session Memory

**Purpose:** Survive chat-memory compression. **Read this file first** in any new session before changing code.

| Field | Value |
|-------|--------|
| **Last updated** | 2026-08-05 (post Xcode app project + full P0–P3 program) |
| **Workspace** | `/Users/dakota/code/Aurora` |
| **Branch** | `main` (local only; no remote assumed) |
| **HEAD** | `36e5015` — *Add production macOS Xcode app project composing SPM modules* |
| **Tests** | **241** passing (`swift test`) |
| **Xcode app** | `Aurora.xcodeproj` — Debug + Release `xcodebuild` verified green |

**Open first after compression:**

1. **`docs/PROJECT_HANDOFF.md`** (this file)  
2. **`docs/STAGE_C_UI_STATE_HANDOFF.md`** — controller ownership for UI work  
3. **`docs/xcode-project.md`** — Xcode app, entitlements, schemes  
4. **`Aurora_Post_Remediation_Deep_Review_UI_Readiness.md`** — historical review (P0–P3 largely **done**)  
5. **`Package.swift`** + **`Sources/Aurora/AppModel.swift`**  

**Do not invent new PR work without an explicit user request.**

---

## 1. What Aurora is

**Aurora** is a **macOS-native professional lighting control** app for live performance:

- Patch fixtures, program looks, run cues with timing/tracking  
- MIDI / RTP-MIDI / OSC control, song orchestration  
- Art-Net + sACN DMX output; ENTTEC USB framing driver (mock transport + protocol)  
- Live effects (pulse/chase/wave/rainbow), persistent in show package  
- Stage **web remote** (iPad Safari) on LAN + random PIN  

**Stack:** Swift 5.9+ / 6.x, SwiftUI + AppKit, SPM monorepo libraries, **Xcode app target** for `Aurora.app`, CoreMIDI, Network.framework, **macOS 14+ only**.

**Language:** all Swift — no Rust engine.

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
├── App/                       # Info.plist, entitlements, Assets, Preview Content
├── Scripts/generate-xcodeproj.sh
├── Sources/
│   ├── Aurora/                # @main shell, AppModel, Controllers/, PanelRegistry
│   ├── AuroraModel/           # pure data, package I/O, validator, migration
│   ├── AuroraCore/            # commands, session, selection, plugins protocols
│   ├── AuroraEngine/          # playback, merge, effects, CompiledShow
│   ├── AuroraOutput/          # DMX, Art-Net, sACN, ENTTEC, health
│   ├── AuroraMIDI/            # CoreMIDI, OSC, resolver, ShowAction
│   ├── AuroraFixtureLib/      # seed + importer
│   ├── AuroraUI/              # panels + workspace (imports MIDI for mappings UI)
│   ├── AuroraRemote/          # TCP/web remote
│   └── AuroraDiagnostics/     # events + store
└── Tests/                     # per-module + smoke
```

**App target** links library products only (not SPM executable product). Shell sources under `Sources/Aurora` are shared with `swift run Aurora`.

---

## 4. Architecture (must not break)

### Control path

```
UI / MIDI / OSC / remote
  → ControlActionRouter / ShowAction (unified dispatcher)
  → DocumentSession (commands) and/or LightingEngine / SongDirector
  → OutputManager (protocol-routed) → drivers → hardware
```

- Live MIDI off MainActor via `ControlActionRouter`  
- Remote is a client — **no second engine**  
- Palette resolve in Engine; **literals win** over refs  
- Layer: playback → effects → programmer → merge → DMX  
- **`updateProject`** preserves playback; **`load`** is destructive (New/Open)  

### Module deps (SPM)

```
AuroraModel          → (none)
AuroraFixtureLib     → Model
AuroraOutput         → Model, Network
AuroraEngine         → Model, Output
AuroraCore           → Model, Engine
AuroraMIDI           → Model, CoreMIDI, Network
AuroraDiagnostics    → (none)
AuroraUI             → Core, Model, Engine, MIDI   # MIDIMappingsPanel needs ShowAction
AuroraRemote         → Core, Model, Network
Aurora (app / CLI)   → UI, Core, Model, FixtureLib, Engine, Output, MIDI, Remote, Diagnostics
```

### Stage C ownership (`AppModel` = composition root)

| Controller | Owns |
|------------|------|
| `ProjectController` | session, URL, dirty, save/open |
| `ShowControlController` | engine, router, song, `PerformanceSnapshot` |
| `InputController` | MIDI/OSC/RTP/learn |
| `OutputController` | drivers, Art-Net/sACN config, health line |
| `RemoteController` | remote host/web |
| `DiagnosticsController` | console + DiagnosticsStore |
| `WorkspaceController` | layout, Build/Perform mode |
| `AppSettingsStore` | app-global prefs |
| `AutosaveController` | timed save when URL set |

Full map: **`docs/STAGE_C_UI_STATE_HANDOFF.md`**.

---

## 5. Key domain rules (post-review)

| Topic | Behavior |
|-------|----------|
| Dirty state | Unique monotonic state IDs; no coalesce across save-point; branch after undo stays dirty |
| Save As | `preservingAssetsFrom:` copies media/layouts from **open** package |
| Playback edits | `.projectModified` → `updateProject` (keep look); New/Open → `load` |
| 16-bit DMX | Coarse/fine pairs → single UInt16 MSB/LSB |
| Package load | Required v1 JSON files fail if missing; `effects.json` optional for old packages |
| Cue fade/loop | Crossfade = max(out fadeOut, in fadeIn); Follow re-enters loop; GO/Back break loop |
| Effects | `EffectDefinition` on project; explicit `order`; selection order for phase |
| Selection | `orderedFixtureIDs` + membership set |
| MIDI | Velocity/CC → scalar; `matchAll`; data2 exact filter; fireCueIndex = **active** list |
| Output | `protocolHint` routes to matching drivers; health snapshots |
| Validation | `ProjectValidator` on load/update; cached off 40 Hz path |
| Groups | `Group.fixtureIds` authoritative; sync to `fixture.groupIds` |
| Palettes | Record common values only; report mixed |
| Song | `SongPerformanceSnapshot`; reset on New/Open |

---

## 6. Work completed (this long arc)

### Stage A — P0 (data/stage safety)
Dirty state IDs · Save As assets · playback preserve · 16-bit · required package files  

### Stage B — UI Gate domain (P1-1…14)
CompiledShow · personality · fadeOut/loop · persistent effects · ordered selection · MIDI/dispatcher · routing · validator · groups · palette record · Song snapshot  

### Stage C — UI state architecture (P1-15)
Controller split · `PerformanceSnapshot` · `notifyUI()` · Build/Perform mode · handoff doc  

### Stage E — P2/P3 hardening
MIDI hotplug + running status · per-universe Art-Net/sACN seq · output health · buffer tails · package recovery · schema migration · patch Int math · remote bind/TTL/limits · frame p95/p99 · ENTTEC driver · soak tests · Info.plist/autosave · plugin protocols  

### Xcode production packaging
`Aurora.xcodeproj` + sandbox entitlements + AppIcon + document UTType + CI + `docs/xcode-project.md`  

### Recent commits (newest first)

| Commit | Summary |
|--------|---------|
| `36e5015` | Xcode app project composing SPM modules |
| `17c8d37` | P2/P3 hardening (MIDI/output/remote/package/ENTTEC) |
| `6c83ba3` | Stage C AppModel split + PerformanceSnapshot |
| `08c9255`…`1718e35` | Stage B then Stage A review fixes |

---

## 7. Intentionally incomplete / next (user-driven only)

| Item | Notes |
|------|--------|
| **Visual UI redesign** | Ready to start against Stage C contracts; not started |
| Real Art-Net/sACN hardware soak | Mock soak tests exist; desk node not proven in-session |
| Physical ENTTEC USB | Protocol + mock transport; real serial transport TBD |
| Notarization / Developer Team signing | Ad-hoc local/CI signing only |
| Dynamic dylib plugins | Protocols only; in-process register remains |
| Full GDTF / TLS remote / native iPad app | Roadmap |
| Full `NSDocument` | Intentionally **not** used — custom session preserves live engine |

**Sensible next user goals:**

1. Visual UI redesign (consume `STAGE_C_UI_STATE_HANDOFF.md`)  
2. Hardware validate Art-Net/sACN/ENTTEC on real devices  
3. Notarization / Team signing when ready to distribute  

---

## 8. Entry points

| Concern | Path |
|---------|------|
| App entry | `Sources/Aurora/AuroraApp.swift` |
| Composition root | `Sources/Aurora/AppModel.swift` |
| Controllers | `Sources/Aurora/Controllers/*` |
| Live MIDI router | `Sources/Aurora/ControlActionRouter.swift` |
| Document session | `Sources/AuroraCore/DocumentSession.swift` |
| Package I/O | `Sources/AuroraModel/ProjectPackage.swift` |
| Engine | `Sources/AuroraEngine/LightingEngine.swift` |
| Compiled show | `Sources/AuroraEngine/CompiledShow.swift` |
| Output / health | `Sources/AuroraOutput/*` |
| Xcode | `Aurora.xcodeproj`, `project.yml`, `App/*` |
| UI state handoff | `docs/STAGE_C_UI_STATE_HANDOFF.md` |
| Xcode/entitlements | `docs/xcode-project.md` |

---

## 9. Conventions

1. Document mutations via **commands** + undo; programmer is engine-ephemeral  
2. `@MainActor` session/UI; engine/output/MIDI/remote use locks / queues  
3. Live GO/fire must not wait on MainActor when avoidable  
4. Additive Codable preferred  
5. Network: fail soft; never block 40 Hz tick  
6. Commits on `main`; update this handoff after major work  
7. Quality over finishing everything; no unprompted feature invention  
8. Do not re-open palette/song law without PR20–21 PDF  

---

## 10. Smoke path (human)

1. `open Aurora.xcodeproj` → Run **Aurora** (or `swift run Aurora`)  
2. Patch universe + fixture  
3. Programmer → Cue List → Live **GO**  
4. Optional: Effects, Art-Net/sACN, Enable Remote + PIN → browser `:8743`  
5. File → Save (atomic; dirty clears); dirty New/Open/Quit prompts  

---

## 11. Agent instructions post-compact

```
Read docs/PROJECT_HANDOFF.md first.
Do not invent new PR work without an explicit user request.
Preserve control path and module dependency direction.
Prefer existing modules over new packages.
UI redesign only when user asks; use docs/STAGE_C_UI_STATE_HANDOFF.md.
Update this handoff after major architecture/status changes.
```

---

## 12. Orientation checklist

- [ ] Xcode selected; `swift test` → 241 green  
- [ ] Optional: `xcodebuild -scheme Aurora … build` green  
- [ ] Control path + Stage C controllers understood  
- [ ] P0–P3 review backlog largely implemented (see §6)  
- [ ] Next work chosen by **user** (UI redesign / hardware / shipping)  

---

*End of handoff. Compact chat freely after this file is committed.*
