# PR18 — Built-in RTP-MIDI

| Field | Value |
|-------|--------|
| **PR** | PR18 |
| **Status** | Implemented |
| **Depends on** | PR16 |

## Approach

Use Apple **CoreMIDI network session** (`MIDINetworkSession`) — the system RTP-MIDI stack — rather than a from-scratch RTP-MIDI implementation.

## Delivered

- `RTPMIDISession` wrapper: enable/disable, connection policy, status
- App menus under **MIDI** (or Output-adjacent): Enable RTP-MIDI
- Existing `MIDIInputManager` continues to receive sources once network endpoints appear
- Unit tests for config defaults / enable state (no live network required)

## Non-goals

- Custom RTP-MIDI packet codec
- Manual peer browser UI beyond system defaults
