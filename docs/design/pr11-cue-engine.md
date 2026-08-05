# PR11 — Cue Engine (Timing & Tracking)

| Field | Value |
|-------|--------|
| **PR** | PR11 |
| **Status** | Implemented |
| **Depends on** | PR10 |

## Delivered

- `CueResolver` — track accumulate / cue-only target
- `PlaybackController` — go/back/stop/fire, delay, linear fade, follow afterTime/afterGo
- `LookMath.lerp` for crossfades
- `LightingEngine` uses playback look unless `setLook` override
- Playback fields on `EngineFrameSnapshot`

## Defaults

- One active cue list
- Fade duration = incoming cue `fadeIn`
- Linear attribute lerp
