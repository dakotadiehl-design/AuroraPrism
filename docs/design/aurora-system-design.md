# Aurora Lighting Control System — System Design

> Historical architecture baseline: the ACP remote sections below describe the retired integration and are superseded by `AURORA_ACP_REMOVAL.md`. Prism now exposes a small rACP adapter through the protocol-neutral show-control boundary; the historical ACP sections remain non-normative.

| Field | Value |
|-------|--------|
| **Status** | Draft (implementation-ready) |
| **Audience** | Developers, contributors, technical reviewers, maintainers |
| **Source overview** | `Aurora Lighting Control System.pdf` (High-Level Feature Overview & Architecture) |
| **Platform** | macOS (native host); stage companion via web (iPad Safari) then optional native iPad |
| **Stack** | Swift 5.9+, SwiftUI + AppKit, CoreMIDI, SPM/Xcode modules; remote web UI over LAN |
| **Scope** | Full system as specified; delivery is incremental via PR plan |

---

## 1. Overview

### 1.1 Product

Aurora is a professional-grade lighting control platform for macOS, designed for live performance environments. The goal is an intuitive, low-latency, highly reliable lighting controller capable of replacing commercial show-control software while remaining modern, extensible, and developer-friendly.

### 1.2 Principles

1. **Performance** — Instant UI; minimal MIDI latency; deterministic cue timing; scale to thousands of fixtures and hundreds of cues under continuous live input.
2. **Reliability** — Mission-critical stability; every editing action predictable and reversible; offline editing; UI never drives hardware directly.
3. **Usability** — Volunteers can operate; professionals get depth; modern creative-app feel (dockable workspace), not a hardware-console clone.

### 1.3 Design goals

- Fast enough for live production  
- Stable enough for mission-critical performances  
- Flexible enough for future protocols  
- Easy enough for volunteers; powerful enough for professional programmers  
- **Deterministic behavior over excessive automation**

### 1.4 Guiding philosophy

Aurora should feel like a modern professional creative application (Logic / Final Cut–class docking and clarity), not a recreation of a physical lighting console alone. Emphasize clarity, responsiveness, and maintainability while providing the depth advanced users expect. Every subsystem should be extensible; every interaction predictable; every architectural choice should favor long-term reliability over short-term convenience.

---

## 2. Key Decisions

| ID | Decision | Choice | Rationale |
|----|----------|--------|-----------|
| KD1 | Platform | macOS first | Matches product brief; native CoreMIDI and system integration |
| KD2 | Language / UI | Swift + SwiftUI primary, AppKit bridges | Low latency, native feel; AppKit for docking and advanced windowing where SwiftUI is weak |
| KD3 | Architecture | Layered modules: UI → Core → Engine → Output | Separation of concerns, offline edit, testability, plugin readiness |
| KD4 | Mutation model | Command pattern + unlimited undo/redo | Predictable history; future macros; no silent side effects |
| KD5 | Eventing | Typed application event bus | Decouple MIDI, engine, UI, diagnostics |
| KD6 | Project storage | Document package (directory bundle), JSON-first schema with version | Portable, VCS-friendly, media-friendly |
| KD7 | Engine isolation | Dedicated scheduler thread + fixed frame rate | Performance is a first-class feature |
| KD8 | Networking priority | CoreMIDI + built-in RTP-MIDI first; Art-Net / sACN / OSC later | Aligns with source “native” vs “future” |
| KD9 | Output abstraction | `OutputDriver` protocol from day one | Mock drivers for tests; USB/network drivers plug in without engine rewrites |
| KD10 | Plugins | Interface reserved; runtime loading later | Avoid premature complexity |
| KD11 | Minimum OS | macOS 14.0 (recommended default) | Modern SwiftUI/concurrency; revisit if volunteer-lab hardware requires lower |
| KD12 | Merge rules (v1) | Intensity HTP; non-intensity LTP; programmer above playback when active | Industry-familiar defaults; documented and testable |
| KD13 | Default engine rate | 40 Hz (25 ms), configurable 20–44 Hz | Balance smoothness vs CPU; measurable |
| KD14 | Fixture definitions | Custom JSON personality format first; import adapters later | Ship seed library quickly; GDTF/OFL as PR-level work |
| KD15 | Dual host workflow | Plan/design on Linux OK; implement & verify on macOS only | Matches team setup; product is macOS-native; see `docs/development-workflow.md` |
| KD16 | Stage remote companion | **ACP-only** remote clients with enrolled identities, explicit capabilities, and Prism-authoritative state | One protocol and security boundary; native and future browser clients use ACP |

---

## 3. High-Level Architecture

```
┌──────────────────────────────┐     ┌─────────────────────────────┐
│  Aurora UI (SwiftUI+AppKit)  │     │  ACP Remote client          │
│  Workspace | Patch | Cue …   │     │  Native; browser may follow │
└──────────────┬───────────────┘     └──────────────┬──────────────┘
               │ commands / snapshots                 │ remote protocol
               │                                      │ (WebSocket + auth)
               └──────────────────┬───────────────────┘
                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│  Application Core + PrismACP adapter                            │
│  Project Manager | Commands | Undo | Selection | Prefs | Events │
└────────────────────────────┬────────────────────────────────────┘
                             │ model events / engine control
┌────────────────────────────▼────────────────────────────────────┐
│  Lighting Engine                                                │
│  Cue | Effect | Playback | Programmer | Scheduler               │
└────────────────────────────┬────────────────────────────────────┘
                             │ channel frames
┌────────────────────────────▼────────────────────────────────────┐
│  Output Layer                                                   │
│  DMX | MIDI | RTP-MIDI | Future Art-Net | sACN | OSC            │
└─────────────────────────────────────────────────────────────────┘
```

**Control path (never bypassed):**

```
User (Mac UI or remote companion) → Application Core (commands) → Lighting Engine → Output Drivers → Hardware
```

Remote clients **never** talk to Output or the engine scheduler directly. `PrismACP` validates ACP sessions and routes semantic actions through the same `ControlActionRouter` used by local control.

### 3.1 Architectural principles

| Principle | Practice |
|-----------|----------|
| **Modular** | SPM libraries with clear public APIs; subsystems independently testable |
| **Event-driven** | MIDI received, cue started/completed, fixture updated, universe changed, project modified |
| **Command pattern** | Add Fixture, Delete Cue, Patch Fixture, Rename Song, Move Cue, etc. |
| **Data model separation** | UI does not import Output drivers; Engine does not own project serialization |

### 3.2 Module map

| Module | Type | Responsibility |
|--------|------|----------------|
| `AuroraApp` | App target | Entry point, document types, menus, app lifecycle |
| `AuroraUI` | Library | Panels, workspace layout, views, keyboard routing |
| `AuroraCore` | Library | Project manager, commands, undo, selection, preferences, event bus |
| `AuroraModel` | Library | Pure data types: show, fixtures, cues, songs, palettes (no I/O side effects) |
| `AuroraEngine` | Library | Cue/effect/playback/programmer/scheduler; timing-critical |
| `AuroraMIDI` | Library | CoreMIDI, RTP-MIDI, learn, device mapping |
| `AuroraOutput` | Library | DMX buffers, `OutputDriver`, mock/null drivers; future Art-Net/sACN |
| `AuroraFixtureLib` | Library | Manufacturers, personalities, channel layouts, seed data |
| `AuroraDiagnostics` | Library | Logging, metrics, monitor data sources |
| `PrismACP` | Library | ACP lifecycle, enrollment policy, capabilities, revisioned state, command ledger, and semantic action bridge |
| `AuroraACP` | Package dependency | ACP schemas, transport, session, security, and Remote-profile protocol implementation |
| ACP Remote client | Separate application | Enrolled companion using the public ACP Remote profile |

Dependency direction (allowed):

```
App → UI → Core → Model
       UI → Engine (read snapshots only)
       Core → Engine (control / load show state)
       Engine → Output, Model
       MIDI → Core/Engine (events in; no UI)
       FixtureLib → Model
       Diagnostics → Core/Engine/MIDI/Output (observe only)
       PrismACP → Core, Model (semantic commands + revisioned state; no Output/MIDI drivers)
       App → PrismACP         (listener lifecycle, enrollment policy, Bonjour)
```

UI must not depend on Output or MIDI implementations directly. Remote must not depend on Output or MIDI implementations directly.

---

## 4. Feature Inventory (Full System)

### 4.1 Show management

- Fixtures, universes, groups, presets, palettes  
- Cue lists, songs, shows  
- Media assets, user preferences  
- Portable project format suitable for version control and backup  

### 4.2 Patch management

- DMX universes, fixture personalities, address management  
- Duplicate detection, visual patch editor  
- Fixture cloning, batch editing, search and filtering  

### 4.3 Fixture library

- Manufacturers, models, DMX channel layouts  
- Fine channels, color wheels, gobos, pan/tilt, beam parameters  
- Future: import from common industry formats (GDTF / OFL subset)  

### 4.4 Cue engine

- Cue lists; fade and delay timing; crossfades  
- Tracking and non-tracking modes  
- Cue stacks; looping; follow cues; manual cues  
- Deterministic timing and minimal latency  

### 4.5 Live playback

- MIDI notes and CC; keyboard shortcuts  
- On-screen buttons; touch-friendly controls  
- External control surfaces  
- Future: OSC  

### 4.6 Song mode

- Song metadata and cue order  
- Automatic and manual progression  
- Notes, timing information, performer annotations  

### 4.7 Workspace layout

Dockable, saveable panels:

| Panel | Role |
|-------|------|
| Fixture Browser | Library + patched fixtures |
| Patch View | Visual address map |
| Cue List | Edit and fire cues |
| Song View | Set / song order |
| Universe Monitor | Live channel levels |
| Output Monitor | Driver / network status |
| MIDI Monitor | Incoming traffic |
| RTP-MIDI Connections | Network MIDI sessions |
| Inspector | Selection details |
| Timeline | Cue / effect timing (later depth) |
| Color Picker | Live color tools |
| Programmer | Live attribute edit |
| Console Output | Log / diagnostics text |

### 4.8 Programmer

Temporary values; highlight; blind; fan; align; home; locate; selection tools; attribute editing.

### 4.9 Color management

RGB, RGBW, CMY, HSV; color temperature; virtual color wheels; palette generation.

### 4.10 Effect engine

Parameterized, reusable: chase, pulse, wave, rainbow, circle, random, sparkle; position and intensity effects.

### 4.11 Networking

- Built-in RTP-MIDI (priority)  
- Future: Art-Net, sACN/E1.31, OSC, remote control APIs  
- Prefer in-process implementations over heavy external dependencies  

### 4.12 MIDI system

CoreMIDI; built-in RTP-MIDI; notes, CC, program change; MIDI Learn; device mapping; multiple devices simultaneously.

### 4.13 Monitoring & diagnostics

DMX output monitor; universe viewer; packet monitor; MIDI monitor; network diagnostics; logging; performance metrics.

### 4.14 Undo / redo

Unlimited undo/redo; transaction grouping; persistent history for the editing session.

### 4.15 Plugin architecture (later)

Extension points for protocols, import/export, effect generators, fixture libraries, scripting, hardware integrations.

### 4.16 Remote / stage companion

**Goal:** Mac runs Aurora **off stage** (show computer + DMX/MIDI I/O). Operators **monitor and manage live playback from stage** on an iPad.

| Aspect | v1 decision |
|--------|-------------|
| Client | **Web companion** first (iPad Safari / home-screen web app); **native iPad app later** on the same protocol |
| Network | **Venue LAN only** — Bonjour discovery, optional QR; **no cloud** in v1 |
| Auth | Remote **off by default**; **PIN** required when enabled; Mac is master (kick, lock, role) |
| Scope | **Live ops** — GO/Stop/Back/Next, fire cues, song progress, lite programmer, monitors |
| Non-goals v1 | Full patch/cue authoring parity; internet remote; multi-user document co-editing |

Full protocol, roles, and PR breakdown: [`remote-companion.md`](./remote-companion.md).

### 4.17 Future expansion (do not block)

Multi-user collaboration; deep remote programming; timeline-based programming; timecode; audio analysis; AI-assisted cue generation; visualizer; pixel mapping; video sync; plugin marketplace; cloud/VPN remote (beyond LAN).

---

## 5. Data Model

### 5.1 Logical structure

```
ShowProject
├── schemaVersion: Int
├── metadata: ProjectMetadata
├── preferences: ProjectPreferences
├── fixtureDefinitions: [FixtureDefinition]   // embedded and/or refs
├── universes: [Universe]
├── fixtures: [PatchedFixture]
├── groups: [Group]
├── palettes: [Palette]
├── presets: [Preset]
├── cueLists: [CueList]
│   └── cues: [Cue]
├── songs: [Song]
├── mediaAssets: [MediaAssetRef]
├── midiMappings: [MIDIMapping]
└── workspaceLayoutId: UUID?                  // or embedded layout
```

### 5.2 Core types (contract-level)

**Universe**

| Field | Type | Notes |
|-------|------|--------|
| id | UUID | Stable identity |
| number | UInt16 | User-facing universe index |
| name | String | |
| channelCount | UInt16 | Default 512 |
| protocolHint | enum | `.local`, `.artNet`, `.sACN`, `.none` (routing preference) |

**FixtureDefinition (personality)**

| Field | Type | Notes |
|-------|------|--------|
| id | UUID | |
| manufacturer | String | |
| model | String | |
| modeName | String | e.g. "16-channel" |
| channelCount | UInt16 | |
| channels | [ChannelDef] | name, attribute, coarse/fine, default, highlight |
| colorModel | enum? | rgb, rgbw, cmy, … |
| hasPanTilt | Bool | + ranges / invert flags |
| wheels | [WheelDef] | color/gobo slots |

**PatchedFixture**

| Field | Type | Notes |
|-------|------|--------|
| id | UUID | |
| name | String | |
| definitionId | UUID | |
| universeId | UUID | |
| address | UInt16 | 1-based DMX start |
| groupIds | [UUID] | |
| notes | String | |

**Cue**

| Field | Type | Notes |
|-------|------|--------|
| id | UUID | |
| number | Decimal | User cue number (e.g. 1.5) |
| name | String | |
| fadeIn | TimeInterval | |
| fadeOut | TimeInterval | |
| delay | TimeInterval | |
| follow | FollowMode | none / manual / after-time / after-go |
| followTime | TimeInterval? | |
| tracking | TrackingMode | track / cue-only (non-tracking) |
| levels | CueLevelData | sparse attribute or channel targets |
| loop | LoopSpec? | for stacks |

**Song**

| Field | Type | Notes |
|-------|------|--------|
| id | UUID | |
| title / artist / notes | String | metadata |
| entries | [SongEntry] | ordered cue-list refs or cue refs |
| annotations | [Annotation] | performer notes, timing |

### 5.3 Invariants

1. **Address uniqueness** — Within a universe, patched ranges must not overlap unless the user explicitly allows a conflict (warned, not silent).  
2. **Stable IDs** — All entities use UUIDs; renames do not break references.  
3. **Schema version** — Every project file carries `schemaVersion`; loaders migrate or fail clearly.  
4. **Sparse cues** — Cues store only changed (or tracked) attributes; resolution is an engine concern.  
5. **Offline integrity** — Project must load and edit with no output drivers attached.

### 5.4 On-disk format

- **Document type:** macOS package (directory bundle), e.g. `Show.aurora`  
- **Recommended layout:**

```
Show.aurora/
  project.json          # metadata, schemaVersion, graph of IDs
  universes.json
  fixtures.json
  cues/
    <cueListId>.json
  songs.json
  definitions/          # embedded personalities
  media/
  midi-mappings.json
  layouts/
```

- Prefer **JSON + Codable** for VCS diffs; large media as separate files.  
- Optional single-file export: zip of the package for sharing.  
- Autosave and versions follow `NSDocument` / `ReferenceFileDocument` conventions.

---

## 6. Application Core

### 6.1 Command system

```swift
protocol Command {
    var name: String { get }
    func perform(context: CommandContext) throws
    func undo(context: CommandContext) throws
}
```

- All user mutations go through commands.  
- **UndoManager** (app-owned, not only `UndoManager` AppKit glue) supports unlimited stack depth for the session, transaction grouping (`beginGroup` / `endGroup`), and coalescing where appropriate (e.g. continuous fader drag).  
- Playback-affecting commands notify the engine after successful perform/undo.

### 6.2 Event bus

Typed events (examples):

- `midiEventReceived`  
- `cueStarted` / `cueCompleted`  
- `fixtureUpdated`  
- `universeChanged`  
- `projectModified`  
- `selectionChanged`  
- `engineFramePublished` (throttled for UI)  
- ACP session/readiness and revisioned domain-state events

Subscribers: UI panels, diagnostics, **PrismACP adapter**, optional future plugins. Delivery on appropriate queues (UI on main; engine never waits on UI or network sockets).

### 6.2.1 ACP Remote as a command source

`PrismACP` translates authorized, preconditioned ACP controls into the **same** semantic `ControlActionRouter` entry points used by the Mac UI. ACP never mutates cue, programmer, output, or DMX internals directly. Structural edits that are unsafe for stage are not remotely exposed.

### 6.3 Selection manager

Single source of truth for selected fixtures, cues, songs, and channels. Programmer and Inspector observe selection; multi-select is first-class.

### 6.4 Project manager

Load/save package; dirty tracking; migration; coordinates model ↔ engine load (push committed show state into engine on open / after structural edits).

### 6.5 Preferences

- **App-level:** MIDI devices, default frame rate, UI theme, global shortcuts.  
- **Project-level:** default fade times, tracking default, universe routing.

---

## 7. Lighting Engine

### 7.1 Responsibilities

| Subsystem | Role |
|-----------|------|
| **Scheduler** | Fixed-rate loop; monotonic clock; produces frames |
| **Playback** | Active cue stacks, crossfades, follows |
| **Cue engine** | Resolve tracking, apply timing curves |
| **Programmer** | Live temporary layer; blind/highlight |
| **Effect engine** | Time-based modifiers on attributes |
| **Merger** | Combine sources into final DMX (HTP/LTP rules) |

### 7.2 Timing

- Use **continuous monotonic time** (`DispatchTime` / `mach_absolute_time` / `ContinuousClock`) for fades and follows.  
- Default **40 Hz** frame tick; configurable.  
- Follow and delay schedules are computed in engine time, not “next UI refresh.”

### 7.3 Layer priority (v1)

From lowest to highest influence on a given attribute:

1. Home / default  
2. Playback (cues), with HTP for intensity and LTP for others across concurrent playback sources as defined  
3. Effects (modulate current)  
4. Programmer (when values set), unless blind (programmer does not hit output)  
5. Highlight / locate overrides as specified  

Exact tables live in engine unit tests (golden vectors).

### 7.4 Tracking

- **Track mode:** unresolved attributes inherit from previous cues in the list when resolving “look.”  
- **Cue-only (non-tracking):** cue contributes only its stored levels; others remain as prior resolved state per playback rules.  

Implementation: sparse storage + resolve pass when building the active look or when recording.

### 7.5 Programmer features

| Feature | Behavior |
|---------|----------|
| Temporary values | Held until clear, store, or update cue |
| Highlight | Force high-visibility look on selection |
| Blind | Edit programmer without changing live output |
| Fan / Align | Distribute values across selection |
| Home | Release attributes to default/home |
| Locate | Open beam / center for focusing |

### 7.6 Effects

Effects are parameterized generators (rate, size, phase, spread, waveform) producing per-fixture attribute offsets or absolute values. Stored as reusable definitions; can be parked on cues or run live from programmer (phased delivery).

### 7.7 Threading

- Engine loop on a high-QoS dedicated thread or timer source.  
- Incoming MIDI enqueued via lock-free or brief-spinlock queue; **no MainActor** on the MIDI→output hot path.  
- UI consumes immutable snapshots (copy-on-write buffers) at a throttled rate (e.g. 15–30 Hz for monitors).

### 7.8 Performance budgets (targets)

| Metric | Target |
|--------|--------|
| UI edit feedback | < 16 ms perceived |
| MIDI note → engine queue | < 2 ms typical |
| Engine frame jitter | Low; measure p99 under load |
| Scale smoke test | 2 000 fixtures, 500 cues, continuous MIDI |

---

## 8. Output Layer

### 8.1 Driver protocol

```swift
protocol OutputDriver: AnyObject {
    var id: UUID { get }
    var name: String { get }
    func start() throws
    func stop()
    /// universeIndex is logical project universe mapping
    func send(universe: UInt16, dmx: UnsafeBufferPointer<UInt8>)
}
```

Implementations:

| Driver | Phase |
|--------|--------|
| `NullOutputDriver` | Always (offline / tests) |
| `MockOutputDriver` | Captures frames for tests |
| USB-DMX (vendor-specific) | When hardware chosen |
| `ArtNetOutputDriver` | Future PR |
| `SACNOutputDriver` | Future PR |

### 8.2 Universe buffers

- One 512-byte (or configured) buffer per active universe.  
- Engine writes merged values; output manager fans out to drivers per routing table.  
- Disconnects fail soft: log + diagnostics; engine continues.

---

## 9. MIDI & RTP-MIDI

### 9.1 CoreMIDI

- Enumerate sources/destinations; multi-device.  
- Handle note on/off, CC, program change.  
- Virtual endpoints optional for testing.

### 9.2 MIDI Learn & mapping

- Map (device, channel, message) → action (Go, Stop, fire cue N, set attribute, etc.).  
- Mappings stored in project (and optionally app defaults).  
- Learn mode: next message binds to selected action.

### 9.3 RTP-MIDI

- Built-in session participant (announce / connect) so users are not required to run Apple MIDI Network Setup for basic use.  
- Share parsing/dispatch with CoreMIDI path after packet decode.  
- Prefer pure Swift/C implementation in-process.

### 9.4 Future OSC

- OSC messages enter the **same mapping/action layer** as MIDI (one control plane).

---

## 10. Fixture Library

### 10.1 Seed format

JSON personality files under `AuroraFixtureLib` resources:

- Channel list with attribute tags (`intensity`, `pan`, `tilt`, `colorR`, …)  
- Fine channel pairing  
- Wheel slots  
- Defaults and highlight values  

### 10.2 API

- Lookup by manufacturer/model/mode  
- Validate channel count vs patch span  
- Clone definition into project embed on first use (project self-contained)

### 10.3 Import (later)

Adapters convert external formats into the internal personality schema; never require engine changes for new importers.

---

## 11. UI Architecture

### 11.1 Document app

- Document-based macOS app: each show is a document.  
- Multi-document supported.

### 11.2 Docking

- **Hybrid:** AppKit docking host (split views / tabbed panel containers) embedding SwiftUI panel contents.  
- Persist layout: panel IDs, sizes, visibility → user defaults and/or project.  
- Default layout: Patch | Programmer | Cue List | Universe Monitor.

### 11.3 Interaction

- Keyboard-first for programming; large hit targets for live GO.  
- Consistent Inspector for selection.  
- Destructive actions require confirmation only when not easily undoable (prefer undo).

### 11.4 Color tools

Shared color model conversions in Model/Engine; UI binds to programmer attributes.

---

## 12. Diagnostics

- Structured logger with levels (trace/debug/info/warn/error).  
- Live monitors subscribe to event bus / engine snapshots.  
- Metrics: frame time, MIDI queue depth, dropped frames, driver errors.  
- Console panel streams filtered logs.

---

## 13. Testing Strategy

| Layer | Approach |
|-------|----------|
| Model | Round-trip encode/decode; address conflict detection |
| Commands | Perform/undo pairs restore state |
| Engine | Deterministic golden tests for fades, follows, tracking, merge |
| MIDI | Virtual sources; mapping table tests |
| Output | Mock driver frame capture |
| UI | Critical view smoke tests; manual live checklist |
| Performance | Benchmark target fixture/cue counts in CI periodically |

No hardware required for CI.

---

## 14. Security & Reliability Notes

- Network protocols (Art-Net/sACN/RTP-MIDI): bind intentionally; document port usage.  
- **Remote companion:** bind to **private/LAN interfaces only** by default; disabled until operator enables; **PIN** (and session tokens) required; role separation (Viewer / Operator); Mac kill switch; rate-limit commands; never expose raw DMX injection APIs to remotes.  
- Prefer documenting HTTP-on-LAN risk for v1; revisit TLS / pairing certs if venues require it.  
- No force-unwrap on engine/output paths.  
- Crash recovery: autosaved package + clear restore UX.  
- Show file from untrusted source: parse safely (size limits, schema validation).

---

## 15. Open Questions

Recommended defaults are marked; change before implementation if product owners disagree.

| # | Question | Recommended default |
|---|----------|---------------------|
| OQ1 | First physical DMX path? | Mock + Art-Net before proprietary USB; add USB when a target device is chosen |
| OQ2 | HTP/LTP details for multi-cue intensity? | HTP intensity across playbacks; LTP latest for color/position |
| OQ3 | Full tracking console semantics day one? | Yes for design; implement core track + cue-only in cue engine PR; advanced “mark cues” later if needed |
| OQ4 | GDTF first-class? | Internal JSON first; GDTF import as dedicated PR |
| OQ5 | Single vs multi-window? | Single main document window + optional undocked panels/windows |
| OQ6 | License? | TBD by owner (affects plugin distribution) |
| OQ7 | Min macOS? | 14.0 |
| OQ8 | Multi-operator remote conflict? | Last-writer for live ops attributes; Mac can lock remote to Viewer; presence list on Mac |
| OQ9 | Remote selection model? | Mac selection is source of truth in v1; remote may request select-by-group |
| OQ10 | Web UI tech (SPA framework)? | Decide at PR32; keep host static-file + WebSocket simple |

---

## 16. PDF Feature Traceability

| Source topic | Design section |
|--------------|----------------|
| Introduction / principles | §1 |
| Design goals | §1.3 |
| Show / patch / library / cues / songs | §4, §5 |
| Workspace / programmer / color / effects | §4, §7, §11 |
| Networking / MIDI / RTP-MIDI | §8, §9 |
| Monitoring / undo / plugins | §6, §12, §4.15 |
| Layered architecture diagram | §3 |
| Modular / event / command / separation | §3.1, §6 |
| Performance goals | §7.8 |
| Future expansion | §4.17 |
| Stage / tablet companion | §4.16, [`remote-companion.md`](./remote-companion.md) |
| Guiding philosophy | §1.4 |

---

## 17. PR Plan

Incremental, independently reviewable pull requests. Later PRs assume earlier ones are merged.

### Phase A — Foundation

| PR | Title | Components | Depends | Description |
|----|-------|------------|---------|-------------|
| **PR1** | Project scaffold & module layout | App, all library targets, CI smoke | — | macOS app shell; empty modules; build + unit test target |
| **PR2** | Domain model & project document format | `AuroraModel`, document I/O | PR1 | Entities, Codable schema version, package load/save, round-trip tests |
| **PR3** | Command system & undo | `AuroraCore` | PR1–2 | Command protocol, undo/redo, transactions, sample model commands |
| **PR4** | Event bus & selection | `AuroraCore` | PR1–2 | Typed events, selection manager |

### Phase B — Patch, library, UI shell

| PR | Title | Components | Depends | Description |
|----|-------|------------|---------|-------------|
| **PR5** | Fixture library seed format | `AuroraFixtureLib` | PR2 | Personality schema, seed fixtures, lookup API |
| **PR6** | Patch management logic | Core / Model | PR2–5 | Addressing, duplicate detection, clone/batch as commands |
| **PR7** | App shell & dockable workspace | App, UI | PR1 | Windowing, AppKit docking host, layout save/load, panel placeholders |
| **PR8** | Patch View + Fixture Browser | UI | PR6–7 | Visual patch, search/filter, inspector hooks |

### Phase C — Engine & output

| PR | Title | Components | Depends | Description |
|----|-------|------------|---------|-------------|
| **PR9** | Output layer & DMX buffers | `AuroraOutput` | PR1–2 | Buffers, `OutputDriver`, null/mock drivers |
| **PR10** | Playback engine & scheduler | `AuroraEngine` | PR9 | Fixed-rate loop, merge stubs, clock, UI snapshots |
| **PR11** | Cue engine (timing & tracking) | Engine | PR2, PR10 | Fades, delays, crossfades, follow, tracking, golden tests |
| **PR12** | Cue List UI | UI | PR7, PR11 | Edit/fire cues, timing fields |

### Phase D — Programmer & color

| PR | Title | Components | Depends | Description |
|----|-------|------------|---------|-------------|
| **PR13** | Programmer core | Engine / Core | PR10 | Temp values, highlight, blind, home/locate |
| **PR14** | Programmer + selection UI | UI | PR8, PR13 | Attribute editors, fan/align |
| **PR15** | Color management | Model / Engine / UI | PR13–14 | RGB/RGBW/CMY/HSV, CCT, virtual wheels, palettes |

### Phase E — MIDI & live control

| PR | Title | Components | Depends | Description |
|----|-------|------------|---------|-------------|
| **PR16** | CoreMIDI integration | `AuroraMIDI` | PR1 | Devices, note/CC/PC, multi-device |
| **PR17** | MIDI Learn & mappings | MIDI / Core | PR3, PR16 | Learn mode, project mappings → actions |
| **PR18** | Built-in RTP-MIDI | MIDI | PR16 | Sessions without requiring external setup apps |
| **PR19** | Keyboard & on-screen playback | UI | PR11–12 | Live ops controls, shortcuts |

### Phase F — Songs, groups, effects

| PR | Title | Components | Depends | Description |
|----|-------|------------|---------|-------------|
| **PR20** | Groups, presets, palettes | Model / UI | PR2, PR8 | CRUD + apply |
| **PR21** | Song mode | Model / Engine / UI | PR11–12 | Order, auto/manual progression, annotations |
| **PR22** | Effect engine | Engine | PR10, PR13 | Parameterized effects library |
| **PR23** | Effect + Timeline UI | UI | PR22 | Editors and basic timeline |

### Phase G — Diagnostics, future protocols, polish

| PR | Title | Components | Depends | Description |
|----|-------|------------|---------|-------------|
| **PR24** | Diagnostics suite | Diagnostics / UI | PR9, PR16 | DMX/MIDI monitors, logging, metrics |
| **PR25** | Art-Net driver | Output | PR9 | Art-Net behind `OutputDriver` |
| **PR26** | sACN/E1.31 driver | Output | PR9 | sACN output |
| **PR27** | OSC input | Control path | PR17 | OSC → shared mapping layer |
| **PR28** | Fixture import formats | FixtureLib | PR5 | Industry format subset → internal schema |
| **PR29** | Plugin architecture skeleton | Core interfaces | Mature APIs | Extension points for protocols/effects/libs |
| **PR30** | Performance hardening | Engine / CI | PR10–11 | Benchmarks, latency budgets, scale tests |

### Phase H — ACP stage remote companion

Does **not** block live-capable core (PR1–PR24). The former private remote protocol and bundled browser client have been deleted; ACP is the only remote boundary.

| PR | Title | Components | Depends | Description |
|----|-------|------------|---------|-------------|
| **PR31** | ACP service integration | `PrismACP`, `AuroraACP` | PR3–4, PR10–11 | Enrollment, WebSocket transport, capability negotiation, revisioned state, semantic command bridge |
| **PR32** | ACP Remote client | Separate client app | PR31, PR12, PR19 | Bonjour discovery, authenticated session, cue/output controls, transferred resources |
| **PR33** | ACP hardening | PrismACP / App | PR32 | Authorization, command recovery, reconnect, leases, security and safety tests |
| **PR34** | Additional ACP clients (optional) | Native or browser client | PR31–33 | Same ACP protocol and security model; no Prism-hosted legacy web UI |

### Dependency sketch

```
PR1 → PR2 → PR3 / PR4
         → PR5 → PR6 → PR8
PR1 → PR7 → PR8, PR12, …
PR2 → PR9 → PR10 → PR11 → PR12 / PR13 / PR21 / PR22
PR1 → PR16 → PR17 / PR18
PR3/4 + PR10/11 (+ PR12/19) → PR31 → PR32 → PR33 → PR34
```

**Live-capable core** is approximately **PR1–PR24** (through diagnostics). PR25–PR30 are full-system / protocol / polish work. **PR31–PR34** add off-stage Mac + on-stage iPad remote without a second engine.

---

## 18. Implementation Notes for PR1–PR4

### PR1 (done — see dedicated doc)

Scaffold is specified and implemented as a single Swift package:

- **Spec:** [`pr1-project-scaffold.md`](./pr1-project-scaffold.md)  
- **Layout:** root `Package.swift`, libraries under `Sources/`, app target `Aurora` (design name `AuroraApp`)  
- **No** domain model or engine logic in PR1  

### PR2 (done — see dedicated doc)

Domain model and `.aurora` package I/O:

- **Spec:** [`pr2-domain-model.md`](./pr2-domain-model.md)  
- **Types:** `ShowProject` and related entities; `ProjectPackage` load/save; schema v1  
- **Tests:** golden sample + empty round-trip; unsupported schema; patch overlap  

### PR3 (done — see dedicated doc)

Command system and undo:

- **Spec:** [`pr3-command-undo.md`](./pr3-command-undo.md)  
- **`DocumentSession`**, `Command`, sample add/remove fixture + rename  
- Groups, coalescing renames, atomic failed perform  

### PR4 (done — see dedicated doc)

Event bus and selection:

- **Spec:** [`pr4-events-selection.md`](./pr4-events-selection.md)  
- **`EventBus`**, `SelectionManager`, session publishes `projectModified` / `selectionChanged`  
- Selection pruned when entities disappear; **not** restored on undo  

### PR5 (done — see dedicated doc)

Fixture library seed:

- **Spec:** [`pr5-fixture-library.md`](./pr5-fixture-library.md)  
- Bundled Generic personalities; `FixtureLibrary` load/lookup/search  

### PR6 (done — see dedicated doc)

Patch management:

- **Spec:** [`pr6-patch-management.md`](./pr6-patch-management.md)  
- Addressing helpers; universe/embed/patch/repatch/clone/batch commands  

### After PR4–PR6

Wire document UI when the app shell lands (PR7); Patch View (PR8). Engine and MIDI remain stubs until their PRs.

---

## 19. Document History

| Version | Date | Notes |
|---------|------|--------|
| 0.1 | 2026-08-04 | Initial system design from overview PDF; Swift stack; full PR plan |
| 0.2 | 2026-08-04 | PR1 scaffold landed; link to `pr1-project-scaffold.md`; §18 updated |
| 0.3 | 2026-08-04 | KD15 dual host workflow (Linux plan / macOS dev); `docs/development-workflow.md` |
| 0.4 | 2026-08-04 | PR2 domain model & package format; link to `pr2-domain-model.md` |
| 0.5 | 2026-08-04 | KD16 stage remote companion (web first, native later); §4.16; Phase H PR31–34; `remote-companion.md` |
| 0.6 | 2026-08-04 | PR3 command system & undo; link to `pr3-command-undo.md` |
| 0.7 | 2026-08-04 | PR4 event bus & selection; link to `pr4-events-selection.md` |
| 0.8 | 2026-08-04 | PR5 fixture library seed; link to `pr5-fixture-library.md` |
| 0.9 | 2026-08-04 | PR6 patch management; link to `pr6-patch-management.md` |
