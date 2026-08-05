# Aurora — Project Handoff / Compressed-Session Memory

**Purpose:** Survive chat-memory compression. **Read this file first** in any new session before changing code.

| Field | Value |
|-------|--------|
| **Last updated** | 2026-08-05 (Stage A P0 post-remediation) |
| **Workspace** | `/Users/dakota/code/Aurora` |
| **Branch** | `main` (local only; no remote assumed) |
| **HEAD (at write)** | see `git log -1` after Stage A commits |
| **Tests** | **190+** passing (`swift test`) |
| **Approx size** | ~10.6k lines production Swift; ~13.3k with tests |

**Authoritative reviews (read in order for backlog):**

1. **`Aurora_Post_Remediation_Deep_Review_UI_Readiness.md`** — current backlog: P0 → UI Gate P1 → AppModel split → then visual UI  
2. `Aurora_Deep_Code_Review_Fixes.md` — first audit (many P0–P2 already fixed in tree)

---

## 1. What Aurora is

**Aurora** is a **macOS-native professional lighting control** app for live performance:

- Patch fixtures, program looks, run cues with timing/tracking  
- MIDI / RTP-MIDI / OSC control, song orchestration  
- Art-Net + sACN DMX output  
- Live effects (pulse/chase/wave/rainbow)  
- Stage **web remote** (iPad Safari) on LAN + PIN  

**Stack:** Swift 5.9+ / 6.x, SwiftUI + AppKit, SPM monorepo, CoreMIDI, Network.framework, **macOS 14+ only**.

**Not Linux for build:** docs OK anywhere; **build/test/run require Mac + full Xcode** (not CLT alone).

**Language decision:** all Swift — no Rust engine planned.

---

## 2. Environment (this machine)

| Item | Value |
|------|--------|
| OS | macOS arm64 |
| Xcode | `/Applications/Xcode.app` **must** be active developer dir |
| `xcode-select -p` | `/Applications/Xcode.app/Contents/Developer` |
| Swift | From Xcode (session saw 6.x) |

**If `#Preview` / `XCTest` missing:**

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

**Build / test / run:**

```bash
cd /Users/dakota/code/Aurora
swift build && swift test
swift run Aurora
# or: open Package.swift in Xcode → scheme Aurora
```

SPM product is a **bare executable**, not `.app`. App sets regular activation policy + activates so a window/Dock icon appear (`AuroraApp.swift`).

---

## 3. Repository layout

```
Aurora/
├── Package.swift
├── README.md
├── Aurora_Deep_Code_Review_Fixes.md   # deep review + required fixes (authoritative for P0–P2)
├── Aurora Lighting Control System.pdf
├── Aurora PR20-PR21 Architectural Guidance.pdf  # palette/song LAW
├── docs/
│   ├── PROJECT_HANDOFF.md             # THIS FILE
│   ├── development-workflow.md
│   └── design/
│       ├── aurora-system-design.md    # master design + PR plan
│       ├── remote-companion.md
│       └── pr*.md
├── Sources/
│   ├── Aurora/                 # @main app, AppModel, ControlActionRouter, SongDirector
│   ├── AuroraModel/            # pure data + ProjectPackage I/O
│   ├── AuroraCore/             # commands, DocumentSession, undo, selection, PluginHost
│   ├── AuroraEngine/           # scheduler, cues, programmer, effects, merge
│   ├── AuroraOutput/           # DMX buffers, Null/Mock/Art-Net/sACN
│   ├── AuroraMIDI/             # CoreMIDI, learn, OSC, RTP-MIDI
│   ├── AuroraFixtureLib/       # seed + FixtureImporter
│   ├── AuroraUI/               # workspace + panels
│   ├── AuroraDiagnostics/      # PerformanceBudget, DiagnosticsStore
│   └── AuroraRemote/           # protocol, TCP host, web server, client scaffold
└── Tests/                      # *Tests per module + AuroraRemoteTests + smoke
```

---

## 4. Architecture (must not break)

### Control path (never bypass)

```
User (UI / MIDI / OSC / remote)
  → Commands (document) or live intents
  → DocumentSession (mutations + undo)  and/or  LightingEngine (playback/programmer/effects)
  → OutputManager → OutputDriver(s) → hardware
```

- **Live MIDI** goes through **`ControlActionRouter`** (non-MainActor) → engine; UI log on MainActor.  
- **MIDI Learn** stays MainActor + commands.  
- **Remote** is a Core/app client — **no second engine**, no raw DMX from remote.  
- **UI must not** own palette resolve math (`PaletteResolver` / `CueResolver` in Engine).  
- **Literals win** over palette refs; missing refs → `ResolutionIssue`, never crash.

### Layer order (engine frame)

```
Playback look
  → Effects (EffectRunner)
  → Programmer (unless blind) + highlight
  → MergeStub → DMX buffers → drivers
```

### Module deps (SPM)

```
AuroraModel          → (none)
AuroraFixtureLib     → Model
AuroraOutput         → Network
AuroraEngine         → Model, Output
AuroraCore           → Model, Engine
AuroraMIDI           → Model, CoreMIDI, Network
AuroraDiagnostics    → (none)
AuroraUI             → Core, Model, Engine
AuroraRemote         → Core, Model, Network
Aurora (app)         → UI, Core, Model, FixtureLib, Engine, Output, MIDI, Remote, Diagnostics
```

### App ownership (`AppModel` @MainActor)

Still a large coordinator (review P1-8 deferred full split):

- `DocumentSession`, workspace layout  
- `LightingEngine`, `OutputManager`, Null + Art-Net + sACN drivers  
- `MIDIInputManager`, `MIDILearnSession`, `ControlActionRouter`, `RTPMIDISession`, OSC server  
- `SongDirector`, `PluginHost`, `DiagnosticsStore`  
- `RemoteHost` + `RemoteWebServer`  
- Status strings / console + MIDI logs  

---

## 5. Key domain concepts

### Show package `.aurora`

- Directory bundle via `ProjectPackage.save/load`  
- **Atomic save (P0):** write temp package → validate load → swap; original survives failure  
- **Media preserve (P0):** copies `media/` and `layouts/` from existing package on resave  
- Schema v1; prefer additive Codable  
- Load enforces max JSON file size (`ProjectPackage.maxJSONFileBytes`)

### Dirty / save-point (P0)

- `DocumentSession.documentGeneration` / `savedGeneration`  
- `isDirty` ⇔ generations differ  
- `markSaved()` after successful save/open  
- Undo can return to clean if stack matches saved generation  

### Unsaved guards (P0)

- New / Open / Quit call `confirmDiscardIfDirty` (Save / Don’t Save / Cancel)

### Cue tracking (P0-6)

- **Track:** accumulate tracking cues; intermediate **cue-only** skipped for history  
- **Cue-only target:** prior stage look ⊕ sparse cue attrs (does **not** wipe unspecified attrs to home)  
- `PlaybackController` passes `currentLook` as `priorLook` into `CueResolver`

### Palettes / presets

- PDF law: `Aurora PR20-PR21 Architectural Guidance.pdf`  
- `paletteRefs` + `PaletteResolver`; type/slot compatibility checked (P1-10)  
- Presets: create from programmer / apply / delete in Palettes panel (P1-9)  
- Record Ref: session cue selection + fixtures; fallback first cue of first list  

### Output

- **Art-Net:** UDP 6454; show U N → Art-Net N+offset (default −1)  
- **sACN:** E1.31 DATA; default show U N → sACN N; multicast or unicast  
- **`reconcileUniverses`:** removed universes blackout then drop buffer (P0-5)  
- `startAll()` rolls back partially started drivers on failure  

### Effects

- Runtime `EffectRunner` on `engine.effects` (not persisted in show yet — P1-12 follow-up)  
- UI: Effects panel  

### MIDI / OSC / RTP

- CoreMIDI + source unique IDs (`uid:…`) for mappings  
- RTP-MIDI: `MIDINetworkSession` wrapper, MIDI menu  
- OSC: UDP 9000 → `ShowAction`  

### Remote

- TCP protocol port **8742** (newline JSON)  
- Web UI **http://\<mac\>:8743**  
- **Enable Remote** generates **random 6-digit PIN** (not 0000); shown in status/console  
- Auth failure rate limit; tokens owned by `RemoteSessionManager`  
- Cleartext LAN still intentional v1 limitation  

---

## 6. PR / work status

### Feature PRs (1–34) — in tree

Scaffold → model → core → fixtures/patch → UI shell → engine/cues/programmer → MIDI → live → palettes/songs → effects → Art-Net/sACN/OSC/RTP → import → plugins → perf → remote TCP/web/harden → Pad client scaffold.

### Code-review fix commits (most recent arc)

| Commit | Content |
|--------|---------|
| `ef8ce0e` | P0: atomic save, dirty, guards, universe blackout, cue-only |
| `52e4eac` | P1: ControlActionRouter, MIDI source IDs, client cleanup |
| `cd90f80` | P1/P2: remote PIN/auth/tokens, presets, palette checks, diagnostics |
| `2b37f34` | Handoff note for review status |
| `7f8f87c` | Post-remediation UI-readiness review in tree |
| `1718e35` | P0: unique document state IDs (dirty branch collision) |
| `ac1e154` | P0: Save As preserves source media/layouts |
| `eba6370` | P0: preserve playback on non-destructive project updates |
| `2ff023d` | P0: 16-bit coarse/fine DMX compilation |
| `acd97a7` | P0: required schema v1 package files on load |

### Stage A (post-remediation P0) — complete

1. Dirty state-ID / save-point identity  
2. True Save As asset preservation  
3. Playback preserved across ordinary edits  
4. 16-bit coarse/fine output  
5. Required package files fail load  

### Stage B Wave B1 (UI Gate engine truth) — complete

| Item | Status |
|------|--------|
| P1-12 CompiledShow | Done — frame merge uses compiled write plans |
| P1-2 Personality | Done — invert/highlight/home/locate/wheels |
| P1-1 fadeOut/loop | Done — max(fadeOut,fadeIn); Follow re-enters loop |
| P1-4 Persistent effects | Done — EffectDefinition + order stack |
| P1-5 Ordered selection | Done — orderedFixtureIDs |

**Next:** Stage B Wave B2 (MIDI velocity, mapping policy, ShowActionDispatcher), then B3 (routing, validator, groups, palettes, song). Visual UI redesign still blocked.

### Intentionally incomplete

| Item | Notes |
|------|--------|
| Full GDTF | OFL-lite + native JSON only |
| DAW effect timeline | List UI only |
| Persistent effect defs | Runtime-only |
| Native iPad app | `RemoteProtocolClient` only; package macOS-only |
| TLS remote | Cleartext LAN |
| Dynamic plugins | In-process register only |
| AppModel split (P1-8) | Still god-object-ish |
| 2k fixture bench | Smoke ~200 fixtures |
| Hardware Art-Net/sACN validation | Not proven on user’s node in-session |
| True AppKit docking | SwiftUI splits “docking lite” |
| Break palette refs → literals on delete | Confirm only |

---

## 7. Entry points

| Concern | Path |
|---------|------|
| App entry | `Sources/Aurora/AuroraApp.swift` |
| Integration hub | `Sources/Aurora/AppModel.swift` |
| Live MIDI router | `Sources/Aurora/ControlActionRouter.swift` |
| Document session | `Sources/AuroraCore/DocumentSession.swift` |
| Package I/O | `Sources/AuroraModel/ProjectPackage.swift` |
| Engine | `Sources/AuroraEngine/LightingEngine.swift` |
| Cue resolve | `Sources/AuroraEngine/CueResolver.swift` |
| Effects | `Sources/AuroraEngine/EffectRunner.swift` |
| Output reconcile | `Sources/AuroraOutput/OutputManager.swift` |
| Remote | `Sources/AuroraRemote/*` |
| Panels | `Sources/AuroraUI/Panels/*`, `PanelRegistry.swift` |
| Review backlog (current) | `Aurora_Post_Remediation_Deep_Review_UI_Readiness.md` |
| Review backlog (prior) | `Aurora_Deep_Code_Review_Fixes.md` |

---

## 8. Conventions

1. Document mutations via **commands** + undo; programmer is engine-ephemeral  
2. `@MainActor` session/UI; engine/output/MIDI/remote use locks / background queues  
3. Live show actions (GO/fire) must not wait on MainActor when avoidable  
4. Additive Codable preferred  
5. Network: fail soft; never block 40 Hz engine tick  
6. Tests: `stepForTesting` / `ManualEngineClock` for engine; packet goldens for Art-Net/sACN  
7. Commits on `main`; update this handoff after major work  
8. One PR / fix cluster at a time preferred for quality (user rule)

---

## 9. Smoke path (human)

1. `swift run Aurora`  
2. Patch universe + fixture  
3. Programmer → Cue List → Live **GO**  
4. Optional: Effects on selection  
5. Optional: Output Art-Net / sACN  
6. Optional: **Remote → Enable** → note PIN → browser `http://<mac-ip>:8743`  
7. File → Save (atomic; dirty clears)  
8. Dirty New/Open/Quit prompts  

---

## 10. Sensible next work

**Active program:** post-remediation hardening for UI readiness (not visual redesign yet).

1. **Stage A — P0** (block show use / UI): dirty state-ID collision, Save As assets, playback preserve on edit, 16-bit DMX, required package files  
2. **Stage B — UI Gate P1** domain semantics (cues, fixtures, song, effects, selection, MIDI, dispatcher, routing, validator, groups, palettes)  
3. **Stage C — AppModel split** + `PerformanceSnapshot` → then **stop for UI spec**  
4. Later: hardware Art-Net/sACN, visual redesign, P2/P3  

Do **not** re-open palette/song semantics without the PR20–21 PDF.  
Do **not** start visual UI redesign until Stage C Go/No-Go checklist is green.

---

## 11. Git arc (high level)

1. PR1–21 core desk + MIDI + palettes/songs  
2. Lane A Art-Net + diagnostics  
3. Phase 1 polish (palette ref UI, universe monitor)  
4. Roadmap PR18/22–34 (effects, protocols, remote)  
5. Deep code review P0–P2 fixes (`ef8ce0e` … `cd90f80`)  

---

## 12. Open first after compression

1. **`docs/PROJECT_HANDOFF.md`** (this file)  
2. **`Aurora_Deep_Code_Review_Fixes.md`** if continuing review backlog  
3. **`docs/design/aurora-system-design.md`**  
4. **`Aurora PR20-PR21 Architectural Guidance.pdf`** if palettes/songs  
5. **`Package.swift`** + **`Sources/Aurora/AppModel.swift`**  
6. **`README.md`**  

---

## 13. Agent instructions

- Read this handoff before edits  
- Preserve control path and module dependency direction  
- Prefer existing modules over new packages  
- Engine: keep deterministic tests  
- Update handoff when architecture or PR status changes  
- User prefers: implement + test + commit per PR/cluster; **correctness over finishing everything**  

---

## 14. Orientation checklist

- [ ] Xcode selected; `swift test` green (~173)  
- [ ] Control path + MIDI router + remote-as-client understood  
- [ ] Atomic save / dirty / cue-only / universe reconcile known  
- [ ] Palette refs resolve in engine; type slots matter  
- [ ] Remote PIN is random on enable  
- [ ] Next work chosen by user (hardware / UI / remaining P2)  

---

*End of handoff. Compact chat freely after this file is committed.*
