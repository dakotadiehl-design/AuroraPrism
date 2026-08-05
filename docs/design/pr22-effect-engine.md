# PR22 — Effect Engine

| Field | Value |
|-------|--------|
| **PR** | PR22 |
| **Status** | Implemented (engine only) |
| **Depends on** | PR10 (scheduler/look), PR13 (programmer layering) |
| **Follow-on** | PR23 Effect + Timeline UI |

## Goal

Parameterized, reusable **live effect** generators that modulate the active look between **playback** and **programmer** (system design §7.3).

## Layer order (must preserve)

```
Home / defaults
  → Playback (cues)
  → Effects          ← this PR
  → Programmer (unless blind)
  → Highlight / locate
  → MergeStub → DMX
```

UI must not own effect math. Effects run in `AuroraEngine` on the engine clock.

## Scope (v1)

| In | Out |
|----|-----|
| Runtime `EffectInstance` + `EffectRunner` | Cue-stored effect slots (later) |
| Kinds: **pulse**, **chase**, **wave**, **rainbow** | Pixel mapping / matrix |
| Live start/stop via engine API | Full timeline UI (PR23) |
| Deterministic unit tests | Plugin effect generators (PR29) |

## Types

```swift
enum EffectKind: pulse | chase | wave | rainbow

struct EffectInstance {
  id, name, kind
  rateHz      // cycles per second (default 1)
  size        // amplitude / level 0…1 (default 0.5)
  phase       // 0…1 base phase
  spread      // extra phase per fixture index (0…1)
  attribute   // primary attr for pulse/chase/wave (default "intensity")
  fixtureIDs  // ordered list for chase/wave phase
  enabled
}
```

### Generator semantics

| Kind | Behavior |
|------|----------|
| **pulse** | `clamp(base + size * sin(2π·(rate·t + phase_i)))` on `attribute` |
| **wave** | Same as pulse; default spread spreads phase across fixtures |
| **chase** | One fixture at a time: `attribute = size` on active, `0` on others (absolute for that attr) |
| **rainbow** | Sets `colorR/G/B` from HSV hue = `frac(rate·t + phase + spread·i)·360`, S/V = size (min 0.5) |

`phase_i = phase + spread * i / max(n−1, 1)` for ordered `fixtureIDs`.

Missing base for relative kinds → treat base as **0**.

## API

- `LightingEngine.effects: EffectRunner`
- `EffectRunner.upsert` / `remove` / `clear` / `snapshot` / `apply(on:time:)`
- Frame path uses `clock.now()` so `ManualEngineClock` tests stay deterministic

## Non-goals

- Bypass Output or DocumentSession
- Bake effects into cues (record later)
- Change HTP/LTP merge rules beyond look modulation
