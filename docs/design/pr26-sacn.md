# PR26 — sACN / E1.31 Output

| Field | Value |
|-------|--------|
| **PR** | PR26 |
| **Status** | Implemented |
| **Depends on** | PR9 |

## Delivered

- `SACNPacket.dataPacket` E1.31 DATA framing (Root + Framing + DMP)
- `SACNOutputDriver` via `Network.framework` UDP
- `SACNConfig` (enable, unicast host or multicast, priority, universe offset)
- Unit tests for packet layout / universe mapping

## Mapping

Show universe **N** → sACN universe **N + universeOffset** (default **0**, show 1 → sACN 1).

Multicast default group: `239.255.(u>>8).(u&0xFF)` per E1.31.

## Architecture

Same as Art-Net: `OutputDriver` registration on `OutputManager`; fail soft; engine loop never blocks.
