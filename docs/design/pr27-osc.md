# PR27 — OSC Input

| Field | Value |
|-------|--------|
| **PR** | PR27 |
| **Status** | Implemented |
| **Depends on** | PR17 (ShowAction mapping) |

## Delivered

- `OSCParser` for common OSC packet types (string address + float/int/bool args)
- `OSCAddressMap` → `ShowAction` for `/aurora/go|stop|back|fire/{index}|programmer/{attr}`
- `OSCInputServer` UDP listener (Network.framework), fail soft
- App enable + default port 9000; events call `AppModel.perform(action:)`

## Non-goals

- Full OSC 1.1 blob/midi/timetag coverage
- OSC output / bidirectional discovery
