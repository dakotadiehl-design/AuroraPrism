# PR23 — Effect + Timeline UI

| Field | Value |
|-------|--------|
| **PR** | PR23 |
| **Status** | Implemented |
| **Depends on** | PR22 |

## Delivered

- `EffectsPanel` workspace panel
- Start pulse / chase / wave / rainbow on **current fixture selection**
- Rate / size controls for new effects
- Running list: enable toggle, remove
- Wires only to `LightingEngine.effects` (no UI math)

## Out of scope (honest)

- Full DAW-style timeline / keyframe editor
- Persisting effects on cues (show-document effect slots)

v1 “timeline” = ordered list of live running instances (not a multi-track timeline).
