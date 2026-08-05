# Stage Remote Companion (iPad)

| Field | Value |
|-------|--------|
| **Status** | Design accepted (not implemented) |
| **Parent** | [`aurora-system-design.md`](./aurora-system-design.md) KD16, §3, §4.16, §14, Phase H |
| **Host** | macOS Aurora process (show computer, off stage) |
| **Clients v1** | Web UI in iPad Safari (LAN) |
| **Clients later** | Native iPad app (`AuroraPad`) on the **same protocol** |

---

## 1. Product intent

Run the **show computer off stage** (quiet, cabled DMX/MIDI/network). On stage, operators use an **iPad** to:

- See current cue / song / connection health  
- **GO / Stop / Back / Next** and fire cues  
- Light programmer and compact monitors  

v1 is **live ops**, not a full second programming console.

---

## 2. Key decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Client strategy | **Shared protocol**; ship **web first**; native iPad later | Zero install for volunteers; keep path to better stage UX |
| Network | **Venue LAN only** | No cloud; predictable show network |
| Auth | **Off by default**, **PIN** when on | Accidental open ports are dangerous mid-show |
| Control path | Remote → **Core commands/events** only | Same as desktop UI; no second engine; no remote DMX injection |
| OSC | Separate (PR27) for hardware/surfaces | Not a substitute for rich iPad UI state |

---

## 3. Architecture

```
┌─────────────┐  HTTP static UI   ┌──────────────────┐
│ iPad Safari │  WebSocket ops    │ Aurora (macOS)   │
│ (or Pad app)│ ◄───────────────► │ Remote host      │
└─────────────┘   PIN session     │  AuroraRemote    │
                                  └────────┬─────────┘
                                           │ commands / snapshots
                                  ┌────────▼─────────┐
                                  │ AuroraCore       │
                                  │ (+ Engine …)     │
                                  └──────────────────┘
```

### 3.1 Modules

| Piece | Role |
|-------|------|
| `AuroraRemote` | Sessions, roles, protocol encode/decode, rate limits, bridge to Core |
| Host HTTP + WS | Serves web assets; accepts companion sockets |
| Remote web assets | Touch-first live-ops UI |
| Mac “Remote” panel | Enable/disable, PIN, QR, connected clients, lock |
| `AuroraPad` (later) | Native client; **no parallel business logic** |

### 3.2 Dependency rules

- `AuroraRemote` → `AuroraCore`, `AuroraModel`  
- **Forbidden:** Remote → `AuroraOutput`, raw MIDI drivers, engine hot thread waits  

---

## 4. Discovery (LAN)

- **Bonjour/mDNS** service type (illustrative): `_aurora-remote._tcp`  
- TXT: show name, `remoteProtocolVersion`, PIN required flag, feature bits  
- Mac UI: **QR code** encoding `http://<host>:<port>/` (and optional short-lived join token)  
- Operators may also type the URL shown on the Mac  

v1 may use **HTTP on private interfaces**. Document the threat model; TLS/pairing can land in hardening if required.

---

## 5. Protocol (web + native)

| Layer | Choice (v1) |
|-------|-------------|
| Transport | **WebSocket** (primary); optional HTTP GET for health |
| Payload | **JSON** text messages (debuggable on bad venue Wi‑Fi) |
| Versioning | `remoteProtocolVersion` on handshake; reject incompatible clients clearly |

### 5.1 Message classes

1. **Auth** — PIN / token → session + role  
2. **Commands** — live actions mapped to Core (see allow-list)  
3. **Snapshots / events** — active cue, song position, transport state, throttled monitor data  
4. **Presence** — client id, role, display name (for Mac operator list)  
5. **Control** — Mac→client force viewer, kick, session lock  

### 5.2 Command allow-list (v1 Operator)

| Allowed | Not allowed (v1) |
|---------|------------------|
| Go, Stop, Back, Next | Delete fixtures / universes |
| Fire cue / select cue list row | Re-patch addresses |
| Song next/prev (and auto/manual if exposed) | Import definitions, MIDI learn |
| Lite programmer sets on current selection | Arbitrary project file mutation APIs |
| Request select-by-group (if enabled) | Raw universe byte poke |

Viewer role: snapshots only.

### 5.3 Snapshot rates

- Transport / cue / song state: on change + low-rate heartbeat  
- Universe monitors: **~10–15 Hz** max (same idea as desktop throttling)  
- Engine must not block on slow sockets; drop or coalesce snapshots  

---

## 6. Roles & safety

| Role | Capabilities |
|------|----------------|
| **Viewer** | Monitors + read-only show state |
| **Operator** | Viewer + live-ops allow-list |
| **Master (Mac)** | Full app; enable remote; set PIN; kick; lock to viewer-only; disable remote |

Defaults:

- Remote **disabled** until enabled for the session  
- **PIN** required  
- Mac **kill switch** (“Remote locked” / disable)  
- Optional: confirm first Operator connection on Mac  

**Selection (OQ9 default):** Mac selection is source of truth in v1; remote programmer edits apply to that selection; remote may send select-by-group requests.

**Multi-operator (OQ8 default):** last-writer for live attribute ops; Mac can force all remotes to Viewer.

---

## 7. Web live-ops surface (v1)

Touch-first, large targets, readable in dark stage conditions:

1. **Transport** — GO, Stop, Back, Next  
2. **Cue list** — current list, fire, follow indicators  
3. **Song** — title, position, next entry  
4. **Programmer (lite)** — intensity / color / position for selection  
5. **Status** — connection, role, engine OK, compact universe summary  

Non-goals: patch editor, full docking, effect graph, deep MIDI learn UI.

---

## 8. Why not only native or only OSC

| Approach | Role in Aurora |
|----------|----------------|
| **Web first** | Best volunteer path; ships with Mac app updates |
| **Native iPad later** | Better long-show UX; same protocol |
| **OSC/MIDI** | Hardware controllers & show integration (PR27); not rich iPad state |
| **Cloud** | Out of scope for v1 |

---

## 9. PR plan (Phase H)

| PR | Title | Depends | Deliverable |
|----|-------|---------|-------------|
| **PR31** | Remote protocol & session core | PR3–4, PR10–11 | `AuroraRemote`, PIN/session, WS skeleton, command bridge, snapshot fan-out, unit tests |
| **PR32** | Web companion (live ops) | PR31, PR12, PR19 | Static UI, Bonjour, QR panel, Operator surfaces |
| **PR33** | Remote hardening | PR32 | Roles, lock, limits, reconnect, security tests |
| **PR34** | Native iPad companion | PR31–33 | `AuroraPad`, distribution TBD |

Earliest useful implementation: after commands/events and cue playback/fire exist. **Does not block PR1–PR24.**

---

## 10. Testing

| Layer | Approach |
|-------|----------|
| Protocol codec | Golden JSON fixtures; version reject |
| Auth / roles | PIN fail; viewer cannot fire; operator allow-list |
| Bridge | Mock Core action handler; command mapping tests |
| Load | Multiple WS clients; snapshot coalesce under slow consumer |
| Manual | iPad Safari on real LAN; Mac off “stage” machine |

No physical iPad required for CI (protocol + headless WS client).

---

## 11. Acceptance (design)

- [x] Documented as Core client, not second engine  
- [x] Web + native share one protocol  
- [x] v1 = live ops, LAN + PIN  
- [x] Mac master controls enable/roles/lock  
- [x] Phase H PR31–PR34 in system design  

---

## 12. Document history

| Version | Date | Notes |
|---------|------|--------|
| 1.0 | 2026-08-04 | Initial remote companion design from product decisions |
