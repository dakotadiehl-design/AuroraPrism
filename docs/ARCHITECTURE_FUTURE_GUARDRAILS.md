# Aurora — Architecture Future Guardrails

**Status:** Standing guidance (not an active backlog)  
**Purpose:** Build today’s Aurora cleanly while avoiding architectural assumptions that conflict with tomorrow’s Aurora.  
**Full vision (reference only):** `FutureReference/Aurora_Future_Features_and_Long_Term_Vision.md`

**Do not** implement future features from the vision document unprompted.  
**Do** consult that document when changing the control plane, MIDI, song model, remote protocol, or engine APIs.

---

## Intent

| Do | Do not |
|----|--------|
| Keep extensibility seams open | Seal “MIDI = fire cue only” into contracts |
| Document tradeoffs when a design blocks future capability | Add speculative subsystems “because someday” |
| Prefer open action keys and rich event payloads | Collapse MIDI to note-number-only at boundaries |
| Preserve UI-independent live control path | Move live dispatch into SwiftUI views |

---

## What already helps

### Control path (seed of a UI-independent Show Engine)

```text
MIDI / OSC / UI / remote
  → ControlActionRouter (live path may be non-MainActor)
  → LightingEngine / DocumentSession
  → OutputManager → drivers
```

Preserve multi-observer UI notify **after** live dispatch. Do not make AppModel/SwiftUI the only way to fire show actions.

### MIDI today (simple, not sealed)

| Layer | Role | Future-friendly rule |
|-------|------|----------------------|
| `MIDIEvent` | note/CC/PC + sourceID + velocity/value | Keep rich payloads; extend carefully |
| `MIDIControlValue` | normalized 0…1 + isTrigger | Path for velocity/CC modulation |
| `MIDIMapping` | device, channel, type, data1/2, **action string**, parameter | Action key space must stay open |
| `MIDIActionResolver` | matchAll / filters | Can grow conditions later |
| `ShowAction` | go/stop/back/fireCue*/**programmerAttribute** | Not cue-only today — keep it that way |
| `ControlActionRouter` | live apply + observers | Dispatch hub; future behaviors plug in here or beside |

**Today:** mapping → discrete `ShowAction` (intentionally simple).  
**Must not become:** a sealed product contract that only allows cue fire.

### Other seeds

- **Semantic control:** attribute tags, programmer, palettes/presets  
- **Song:** songs + labeled entries (manual progression only for now)  
- **Remote:** protocol/actions distinct from Mac views; multi-client path exists  

---

## MIDI guardrails (highest priority)

1. **Never document or code MIDI as only “event → fire cue.”**  
   Prefer **event → ShowAction / behavior ID**, with optional scalar (velocity/CC).

2. **Preserve rich `MIDIEvent` payloads** (source, channel, note, velocity, CC).  
   Do not collapse to note number only at the control boundary.

3. **Keep `MIDIMapping.action` as an open key space**  
   (or a typed enum with forward-compatible unknown cases).  
   Do not reduce it to fireCue-only without extension room.

4. **Keep live MIDI off MainActor** (`ControlActionRouter.handleMIDIEvents`).  
   Future envelopes/energy need a real-time-capable path.

5. **Keep conceptual layers separate** (even if packages stay merged for now):
   - parse → match/rules → behaviors/envelopes (future) → engine application  
   Do not merge match + fade + output into untestable UI code.

6. **Song/section-aware mappings are future.**  
   When evolving mapping schema, prefer optional context fields + package version story over baking “global flat table forever.”

7. **Safety hooks** (rate limit, panic, runaway protection) belong on router/engine later — not inside SwiftUI panels.

### Anti-patterns

- MIDI learn that can only arm cue fire  
- Envelope timers inside panel views  
- `AuroraUI` depending on CoreMIDI / device frameworks  
- Replacing live `ControlActionRouter` with MainActor-only AppModel methods  
- Storing performance energy only in `@Published` UI state  

---

## Broader future capabilities

| Future capability | Guardrail now |
|-------------------|---------------|
| Semantic fixture control | Attribute tags + programmer/palette semantics; raw DMX is not the only model |
| Music-aware Song Mode | Keep song/entry structure; don’t force song ≡ cue list in APIs |
| Reusable lighting behaviors | Named actions/behaviors over one-off view closures |
| Spatial metadata | Model-owned when introduced; not only opaque UI state |
| Busking / layers | Don’t assume full-cue replace is the only look stack |
| Multi-remote | Keep remote action protocol distinct from Mac views |
| Rehearsal record/playback | Prefer event logs over “UI revision” history |
| Rig adaptation | Intent (palette/attr) > hard-coded channel values in show content |
| Show Engine UI-independence | Never move live dispatch into SwiftUI |
| Degraded operation | Structured output health; no fake-healthy UI |

---

## When a conflict appears

If a current design would **significantly** block Advanced MIDI, semantic control, or UI-independent execution:

1. **Document the tradeoff** before committing (PR note / handoff).  
2. Prefer the option that keeps the control plane and event model open.  
3. Do **not** implement the full future feature just to “solve” the conflict.

---

## Related docs

- Vision (future only): `FutureReference/Aurora_Future_Features_and_Long_Term_Vision.md`  
- Active contracts: `docs/UI_BACKEND_CONTRACT.md`, `docs/STAGE_C_UI_STATE_HANDOFF.md`  
- Session memory: `docs/PROJECT_HANDOFF.md`  
- Active UI roadmap: `UIDesignReferences/UIDevPlan.md`  
