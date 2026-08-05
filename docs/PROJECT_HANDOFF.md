# Aurora — Project Handoff / Compressed-Session Memory

**Purpose:** Survive chat-memory compression. Read this file first in any new session before changing code.

**Last updated:** 2026-08-05  
**Workspace:** `/Users/dakota/code/Aurora`  
**Branch:** `main` (local only when last written; no remote assumed)  
**HEAD (at write time):** `9f70e8f` — *Document PR24/PR25 in README*

---

## 1. What Aurora is

**Aurora** is a **macOS-native professional lighting control** application for live performance:

- Patch fixtures, program looks, run cues with timing/tracking  
- MIDI control, song orchestration, Art-Net DMX output  
- Goal: modern creative-app UX (Logic/FCP-class docking), not a console clone  
- Future: **stage iPad remote** (web first, then native) — designed, not fully built  

**Stack:** Swift 5.9+ / Swift 6.x toolchain, SwiftUI + AppKit, SPM monorepo, CoreMIDI, Network.framework (Art-Net), macOS 14+ only (`platforms: [.macOS(.v14)]`).

**Not Linux:** Planning docs can be edited anywhere; **build/test/run require macOS + full Xcode** (not Command Line Tools alone).

---

## 2. Environment (this machine)

| Item | Value |
|------|--------|
| OS | macOS (arm64); was ~26.x in session |
| Xcode | `/Applications/Xcode.app` — **must** be active developer dir |
| `xcode-select -p` | Should be `/Applications/Xcode.app/Contents/Developer` |
| Swift | From Xcode (session used 6.1–6.3 range) |
| Host | Development moved from Linux plan machine → Mac for native work |

**If build fails with `#Preview` / `XCTest` missing:** CLT is selected; fix:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
# or GUI: osascript admin prompt was used successfully once
```

**Run app:**

```bash
cd /Users/dakota/code/Aurora
swift build && swift test
swift run Aurora
# or: open .build/arm64-apple-macosx/debug/Aurora
# or: open Package.swift in Xcode → scheme Aurora
```

SPM produces a **bare executable**, not a `.app` bundle. App forces:

- `NSApp.setActivationPolicy(.regular)`  
- `NSApp.activate(ignoringOtherApps: true)`  

in `Sources/Aurora/AuroraApp.swift` so a window/Dock icon appear.

---

## 3. Repository layout

```
Aurora/
├── Package.swift                 # SPM monorepo — single package
├── README.md
├── .gitignore                    # .build/, session tarballs, etc.
├── Aurora Lighting Control System.pdf          # original product overview
├── Aurora PR20-PR21 Architectural Guidance.pdf # critical for palettes/songs
├── aurora-grok-session.tgz       # gitignored session archive (if present)
├── docs/
│   ├── PROJECT_HANDOFF.md        # THIS FILE
│   ├── development-workflow.md   # Mac toolchain / dual-host
│   └── design/
│       ├── aurora-system-design.md   # master design + PR1–34 plan
│       ├── remote-companion.md       # iPad remote design (KD16)
│       └── pr*.md                    # per-PR notes (many)
├── Sources/
│   ├── Aurora/                   # @main executable (design name AuroraApp)
│   ├── AuroraModel/              # pure data + package I/O
│   ├── AuroraCore/               # commands, session, undo, selection, events
│   ├── AuroraEngine/             # scheduler, cues, programmer, merge
│   ├── AuroraOutput/             # DMX buffers, drivers, Art-Net
│   ├── AuroraMIDI/               # CoreMIDI + learn/resolver
│   ├── AuroraFixtureLib/         # seed personalities (Resources/Seed/)
│   ├── AuroraUI/                 # workspace + panels
│   ├── AuroraDiagnostics/        # still thin / stub-ish
│   └── (no AuroraRemote yet)
└── Tests/
    ├── AuroraModelTests/
    ├── AuroraCoreTests/
    ├── AuroraEngineTests/
    ├── AuroraOutputTests/
    ├── AuroraMIDITests/
    ├── AuroraFixtureLibTests/
    ├── AuroraUITests/
    └── AuroraPackageSmokeTests/
```

~110 Swift sources under `Sources/`, ~23 under `Tests/`. **~108 tests** passing at last full run.

---

## 4. Architecture (must not break)

### Control path (never bypass)

```
User (UI / MIDI / future remote)
  → Commands / intents
  → DocumentSession (model mutations + undo)
  → LightingEngine (playback + programmer merge)
  → OutputManager → OutputDriver(s) → hardware
```

- **UI must not import Output/MIDI drivers** for hot path (panels get engine/session via AppModel).  
- **UI must not own palette semantics** — resolution is Model/Engine (`PaletteResolver` → `CueResolver`).  
- **Remote (future)** is a Core client, not a second engine (`docs/design/remote-companion.md`).

### Module dependency graph (SPM)

```
AuroraModel          → (none)
AuroraFixtureLib     → AuroraModel (+ Resources seed JSON)
AuroraOutput         → Network.framework
AuroraEngine         → AuroraModel, AuroraOutput
AuroraCore           → AuroraModel, AuroraEngine
AuroraMIDI           → AuroraModel, CoreMIDI
AuroraUI             → AuroraCore, AuroraModel, AuroraEngine
Aurora (app)         → UI, Core, Model, FixtureLib, Engine, Output, MIDI
```

### App ownership (`AppModel`)

Single `@MainActor` `AppModel` owns:

- `DocumentSession` (show + undo + selection + events)  
- `LightingEngine` + `OutputManager`  
- `NullOutputDriver` always; `ArtNetOutputDriver` when enabled  
- `MIDIInputManager` + `MIDILearnSession`  
- `SongDirector`  
- Fixture library box for UI  
- Workspace layout (UserDefaults)  
- Status: engine / MIDI / Art-Net / console + MIDI logs  

---

## 5. Key domain concepts

### Show document

- Type: directory package **`.aurora`**  
- API: `ProjectPackage.save/load`  
- Schema: `ProjectPackage.currentSchemaVersion` (v1; additive fields preferred)  
- Root: `ShowProject` (universes, fixtures, definitions, cues, songs, palettes, groups, midiMappings, …)

### Attributes

- Normalized **0.0…1.0** in looks/programmer/cues  
- Merge to DMX 0…255 via `MergeStub` / channel `defaultValue` when missing  

### Palettes / presets / groups (PDF is law)

**Read:** `Aurora PR20-PR21 Architectural Guidance.pdf`

- **First-class UUID entities**, not UI-only copy buttons  
- Cues store **literals** and/or **`paletteRefs`** on `FixtureCueLevels`  
- Change palette once → all **referencing** cues update on resolve  
- Literals on same attr **win** after ref expand  
- Missing palette: `ResolutionIssue`, skip attrs, **never crash**  
- **Palette** = attribute family (color/position/…); **Preset** = larger multi-fixture look  
- **Song** orchestrates cue lists/cues by UUID — **not** a second cue engine  

### Playback

- One active cue list (v1)  
- `PlaybackController`: delay → linear fade → active; follow afterTime/afterGo  
- Tracking via `CueResolver` (with project for palette expand)  
- Programmer layered on top (`Programmer.apply`); blind suppresses programmer contribution  

### Art-Net (PR25)

- UDP **6454**, ArtDmx encode in `ArtNetPacket`  
- Show universe **N** → Art-Net **N + universeOffset** (default offset **−1** → show 1 = Art-Net 0)  
- Config: `ArtNetConfig` UserDefaults `aurora.output.artnet.v1`  
- Menu: **Output → Enable Art-Net / Destination…**  
- Keep Null driver when Art-Net off  

---

## 6. PR implementation status

### Done (in tree)

| PR | Topic |
|----|--------|
| 1 | SPM scaffold, modules, smoke tests |
| 2 | Domain model + `.aurora` package I/O |
| 3 | Command + DocumentSession + undo/groups/coalesce |
| 4 | EventBus + SelectionManager |
| 5 | FixtureLibrary seed JSON (dimmer, RGB, RGBW, mover) |
| 6 | Patch addressing + patch/universe/clone/batch commands |
| 7 | Workspace multi-pane shell, open/save, menus |
| 8 | Fixture browser + patch table + inspector |
| 9 | DMX buffers, Null/Mock drivers, OutputManager |
| 10 | Engine scheduler ~40 Hz, merge stub, snapshots |
| 11 | Cue resolve, fade/delay/follow playback |
| 12 | Cue list UI + cue commands |
| 13 | Programmer core (blind/highlight/locate/home) |
| 14 | Programmer panel + fan/align |
| 15 | ColorMath + HSV in programmer |
| 16 | CoreMIDI input + parser |
| 17 | MIDI learn + mapping → actions |
| 19 | Live transport panel + keyboard GO/STOP/BACK |
| 20 | Groups/palettes (refs + resolver) — core model/UI present |
| 21 | SongDirector + Song panel |
| 24 | Universe monitor + console/MIDI log (subset) |
| 25 | Art-Net output driver |

### Designed, not fully built

| PR | Topic | Design doc |
|----|--------|------------|
| 18 | Built-in RTP-MIDI | system design |
| 22–23 | Effects engine + UI | system design |
| 26 | sACN | system design |
| 27 | OSC | system design |
| 28 | Fixture import (GDTF/OFL) | system design |
| 29 | Plugins | system design |
| 30 | Performance hardening | system design |
| 31–34 | Remote web/iPad companion | `remote-companion.md`, KD16 |

### Known gaps / incomplete polish

- **Record palette ref UI** exists (“Record Ref to Cue” on first cue of first list) — not full multi-cue workflow  
- Palette delete confirm when referenced is soft (validation exists; stronger UX optional)  
- Universe monitor shows first 128 channels of first universe  
- Art-Net not fully validated on user’s physical node yet  
- No true AppKit docking framework — SwiftUI `HSplitView`/`VSplitView` “docking lite”  
- No committed `.xcodeproj` — open `Package.swift`  
- Some PR docs are thin notes; **system design + PDFs** are authoritative  

---

## 7. Important types & entry points

| Concern | Where |
|---------|--------|
| App entry | `Sources/Aurora/AuroraApp.swift` |
| Session / document | `Sources/Aurora/AppModel.swift`, `Sources/AuroraCore/DocumentSession.swift` |
| Commands | `Sources/AuroraCore/Commands/*`, `GroupCommands.swift` |
| Package I/O | `Sources/AuroraModel/ProjectPackage.swift` |
| Engine | `Sources/AuroraEngine/LightingEngine.swift` |
| Playback | `Sources/AuroraEngine/PlaybackController.swift` |
| Palette resolve | `Sources/AuroraEngine/PaletteResolver.swift` |
| Cue resolve | `Sources/AuroraEngine/CueResolver.swift` |
| Programmer | `Sources/AuroraEngine/Programmer.swift` |
| Merge → DMX | `Sources/AuroraEngine/MergeStub.swift` |
| Output | `Sources/AuroraOutput/OutputManager.swift` |
| Art-Net | `Sources/AuroraOutput/ArtNet*.swift` |
| MIDI | `Sources/AuroraMIDI/*` |
| Panels | `Sources/AuroraUI/Panels/*` |
| Workspace | `Sources/AuroraUI/Workspace/*` |
| Panel wiring | `Sources/Aurora/PanelRegistry.swift` |

---

## 8. Conventions established in this project

1. **Mutations through commands** when show document changes; programmer values are engine-ephemeral  
2. **`@MainActor`** for session/UI; engine/output/MIDI use locks / background queues  
3. **Version strings** on modules like `0.x.0-prN` (not always perfectly synced)  
4. **Design docs** under `docs/design/prN-*.md` for major PRs  
5. **Prefer additive Codable** over hard schema bumps when possible  
6. **Do not** put exploit/network abuse helpers; Art-Net is show LAN only  
7. **Git:** commits on `main`; identity may be auto `Dakota Diehl <dakota@…>`  
8. **Session tarballs** gitignored (`aurora-grok-session.tgz`)  

---

## 9. How a human uses the app today (smoke path)

1. `swift run Aurora`  
2. Patch: Add Universe → Fixture Browser → Patch Selected  
3. Select fixture → Programmer (intensity/HSV)  
4. Cue List: Add List → + Cue → set timing → Live panel **GO**  
5. Optional: MIDI panel Learn Go; send note  
6. Optional: Palettes “New Color from Prog” / “Record Ref to Cue”  
7. Optional: Output → Art-Net destination + Enable  
8. Universe Monitor / Console for diagnostics  
9. File → Save `.aurora` package  

---

## 10. Roadmap choices already made

| Decision | Choice |
|----------|--------|
| Language | **All Swift** (no Rust engine planned) |
| Remote | **Web first**, native iPad later; LAN + PIN; live-ops v1 (`remote-companion.md`) |
| Next product lane (user chose) | **Lane A — real light**: Art-Net (done) → validate on node → sACN/effects/remote as needed |
| Dual host | Plan on any OS; implement on Mac only (KD15) |

### Sensible next work (post-Lane A)

1. **Hardware validate** Art-Net on real node (universe offset, unicast IP)  
2. **PR26 sACN** if needed  
3. **PR22 effects** if desk depth  
4. **PR31–32 remote** if off-stage Mac + iPad demo  
5. Harden palette delete UX / multi-cue ref recording  

---

## 11. Git history (high level)

Chronological feature arc on `main`:

1. PR1 scaffold → PR2 model → PR3–4 core → PR5–6 fixture/patch  
2. PR7–8 UI shell/patch → PR9–11 engine/cues → PR12–14 programmer  
3. PR16–17 MIDI → PR19 live → PR15/20/21 color/groups/songs (often batched commits)  
4. PR24–25 diagnostics + Art-Net (Lane A)  

Some commits batch multiple PR numbers (e.g. `79ba7c9` PR17–21, `f44f8c2` Lane A).

---

## 12. Files to open first after compression

1. **`docs/PROJECT_HANDOFF.md`** (this file)  
2. **`docs/design/aurora-system-design.md`** — full PR plan + KD table  
3. **`Aurora PR20-PR21 Architectural Guidance.pdf`** — palette/song law  
4. **`docs/design/remote-companion.md`** — if remote work  
5. **`Package.swift`** + **`Sources/Aurora/AppModel.swift`** — living integration hub  
6. **`README.md`** — status one-liner + build commands  

---

## 13. Agent instructions for future sessions

- Prefer **existing modules and dependency rules** over new top-level packages  
- Extend **commands + tests** for show mutations  
- Engine changes: keep **deterministic `stepForTesting` / ManualEngineClock** coverage  
- Art-Net: fail soft; never block engine loop on network  
- Do not reintroduce Linux-only build expectations  
- When unsure about palettes/songs, **prefer reference + resolve** over bake-only  
- Update this handoff when major PR status or architecture changes  

---

## 14. Checklist: “I am oriented”

- [ ] Can build/test/run on this Mac with Xcode selected  
- [ ] Know control path UI → session → engine → output  
- [ ] Know palette refs resolve in engine, not UI  
- [ ] Know Art-Net enable path and universe offset  
- [ ] Know next lane options (hardware validate / sACN / effects / remote)  
- [ ] Read PDF guidance before changing PR20/21 semantics  

---

*End of handoff. Compress chat freely after this file is committed if desired.*
