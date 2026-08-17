# UI-08 Handoff — Full Settings Content

**Status:** COMPLETE (amended plan A1, A5, A12)  
**Tests:** included in 344 green suite  

## Implemented

| Area | Notes |
|------|--------|
| AppSettingsStore | Frame rate, console TS, density key, Local DMX prefs, remote access prefs |
| Local DMX (A1) | Persist hardware identity + endpoint; never silent substitute; requested vs actual enabled |
| Remote (A5) | Default off; This Mac / LAN bind; PIN not in status logs; Settings enable/regenerate PIN |
| MIDI (A12) | Mappings remain PROJECT in Settings; document commands/undo |
| Universe routing | Existing command path in Settings (PROJECT) |

## Not implemented (deliberate)

- Full Appearance theme editor  
- RTP-MIDI/OSC full Settings (still placeholders)  
- Local DMX IOKit vendor enrichment beyond path/hardwareIdentifier field  

## Files

`AppSettingsStore.swift`, `OutputController.swift`, `AuroraSettingsRoot.swift`, `RemoteController.swift`, `RemoteSessionManager` bind default loopback  

## Checkpoint

Part of UI-08→11 campaign commit.  
