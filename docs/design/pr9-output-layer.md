# PR9 — Output Layer & DMX Buffers

| Field | Value |
|-------|--------|
| **PR** | PR9 |
| **Status** | Implemented |
| **Depends on** | PR1 |
| **Unlocks** | PR10 engine |

## Delivered

- `OutputDriver` protocol
- `DMXBuffer` (512 ch)
- `NullOutputDriver`, `MockOutputDriver`
- `OutputManager` with register/start/setLevels/flush (locked)

No Art-Net/sACN or UI monitor in this PR.
