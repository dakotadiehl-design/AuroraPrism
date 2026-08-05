# PR25 — Art-Net Output

## Delivered

- `ArtNetPacket.artDmx` encoder (UDP payload)
- `ArtNetOutputDriver` via `Network.framework` UDP
- `ArtNetConfig` (enable, host, port 6454, universe offset default −1)
- Unit tests for packet layout

## Mapping

Show universe **N** → Art-Net universe **N + universeOffset** (default **N − 1** so show 1 → Art-Net 0).

## Manual test

1. Enable Art-Net in app (Output menu).
2. Set destination to node IP (unicast) or leave broadcast.
3. Patch fixture, set intensity / GO.
4. Confirm with node UI, QLC+, or Wireshark filter `udp.port == 6454`.
