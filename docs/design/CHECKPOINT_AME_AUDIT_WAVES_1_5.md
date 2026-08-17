# Checkpoint — Pre-Smoke Software Gate (Wave 6 ready)

**Date:** 2026-08-16  
**Status:** **SOFTWARE COMPLETE — pre-smoke gate green**  
**Suite:** **787 tests, 0 failures** (`swift test`)  
**App build:** **BUILD SUCCEEDED** (`xcodebuild … Aurora … build`)  

Hardware smoke / Wave 6 matrix may proceed.

---

## Pre-smoke fixes (`presmoke_fixes.md`)

| Item | Status |
|------|--------|
| P0-1 Physical release bypasses MIDI flood/debounce limiter (monotonic time) | Done |
| P0-2 Disconnect releases AME + MIDI behaviors; `MIDIInputManager.stop()` emits disconnects | Done |
| P0-3 Invalid cue/sequence targets return non-success (`fire`/`resetSequence` → Bool) | Done |
| P1-1 UID `0` treated as non-durable → `ep:` path; per-endpoint refCon retainers | Done |
| P2 AME/live-control + related shipping warnings cleaned | Done |

---

## Smoke test readiness

Automated software gates for stuck-hold, disconnect, and truthful execution are green.  
**Wave 6 remains a real-device exercise** (local MIDI, RTP, dense input, unplug, clock dropout, soak).
