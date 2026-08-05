# PR16 — CoreMIDI Integration

| Field | Value |
|-------|--------|
| **PR** | PR16 |
| **Status** | Implemented |

## Delivered

- `MIDIEvent`, `MIDIMessageParser` (note/CC/PC + running status)
- `MIDIInputManager` — enumerate sources, connect all, event handler
- App status: connected source count / last event
- No Learn / no engine mapping (PR17)
