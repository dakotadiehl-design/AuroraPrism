# UI-08→UI-11 Integration Summary

**Baseline:** `64ed03e` UI-04…07  
**Campaign:** UI-08 Settings → UI-09 Patch → UI-10 Remote → UI-11 Layouts  
**Amendments:** A1–A14 applied  
**Stabilization:** First-pass + **second-pass deep review** findings implemented

## Operator surfaces

```text
Settings
  Art-Net / sACN / Local DMX
  RTP-MIDI / OSC
  Remote (config before start; web port real; honest bind labels)
  Operator diagnostics snapshot

Patch
  search + presentation sort
  conflict detail by fixture/address
  bulk offset via BulkRepatchCommand

Remote web / iPad
  requestId required (at-most-once)
  CURRENT / NEXT cues
  large GO; no Fire cue 0/1; no PIN default 0000
  protocolVersion negotiation

Build workspace
  layout fractions drive column ideals
  visibility for left / inspector / lower
  View → Layouts presets (Programming / Patch / Song / Diagnostics)
  flush layout on quit
```

## Stabilization checklist (P0)

| ID | Status |
|----|--------|
| ST-01 MIDI structured health + hotplug | Done |
| ST-02 Null output not green | Done |
| DOC-01 explicit Welcome state | Done |
| UI09-01 Patch search/sort/bulk/conflicts | Done |
| UI09-02 DiagnosticsSnapshot hosted | Done (Settings Advanced; not a full Build panel) |
| UI10-01 requestId required on web | Done |
| UI10-02 atomic requestId reserve | Done |
| UI10-03 CURRENT/NEXT web UI | Done |
| UI10-04 protocolVersion web | Done |
| UI10-05 no PIN 0000 default | Done |
| REM-01 config before start | Done |
| REM-02 remoteWebPort applied | Done |
| REM-03 Apply/Restart Remote | Done |
| REM-04 restore remote on launch | Done |
| REM-05 menu = Settings authority | Done |
| REM-06 transactional start | Done |
| REM-07 honest all-interfaces label | Done |
| UI11-01 fractions used by Build host | Done (ideal widths from fractions) |
| UI11-02 visibility respected | Done |
| UI11-03 named layout menus | Done |
| UI11-04 presets align Option A | Done |
| UI11-05 flush on quit | Done |
| UI08-01 Art-Net/sACN in Settings | Done |
| UI08-02 RTP/OSC in Settings | Done |
| UI08-03 density dead config | Documented as not applied |

## Hard stop

**No UI-12** until independent deep review of this stabilized tree.

## Second-pass highlights

| Area | Change |
|------|--------|
| REM-01 | Listener ready/failed state → `isActuallyRunning` only when both ready |
| REM-02 | Snapshot polling touches session TTL |
| REM-03/06 | Web re-auth on 401/403; retry only transient errors |
| REM-04 | Ordered request-id eviction; clear on kick/disconnect/reclaim |
| REM-05 | Command acks carry snapshotRevision |
| REM-07 | Periodic idle reclaim on remote timer |
| DIAG-01 | Live diagnostics timer |
| DIAG-02/03 | Actual Local DMX + per-universe route health |
| LAYOUT-01 | Drag dividers persist fractions |
| LAYOUT-02 | Build lower **Diagnostics** tool |
| LAYOUT-04 | Document replace keeps layout tools |
| PATCH-01/02 | Row validation + bulk affected-universe preflight |
| SEC-01 | Remote PIN in Keychain |
| SET-01 | Port validation without silent clamp |

## Tests

`swift test` — **356** passing  

## Known limitations

- Local DMX hardware identity often path-backed until richer IOKit metadata  
- Identify deferred (A13)  
- All-interfaces remote bind is not private-LAN filtered (labeled honestly)  
- Injected NWListener factory tests for async fail paths not fully unit-covered (manual port-conflict smoke recommended)
