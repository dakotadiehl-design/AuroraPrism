# Aurora — Final Pre-Smoke Code Review Required Fixes

**Review date:** 2026-08-16  
**Scope:** Full repository release-gate review before hardware smoke testing  
**Disposition:** **HOLD hardware smoke testing until all P0 items below are fixed and verified.**

---

## Executive summary

Aurora's overall architecture is healthy and the automated software gates are strong:

- Full Swift test suite: **777 tests passed, 0 failures**.
- Clean shipping macOS application build: **succeeded**.
- Xcode static analysis: **succeeded**, with compiler warnings listed below.
- AME timing-policy re-entry and durable non-UID Learn corrections are present and accepted.

The final deep review nevertheless found three live-control blockers that the current tests do not cover:

1. The outer MIDI flood limiter can discard physical release events before AME and MIDI behavior runtimes see them.
2. MIDI source disconnect unwinds AME held/toggle state but does not release sustained `MIDIBehaviorRuntime` instances; stopping MIDI also suppresses disconnect lifecycle delivery entirely.
3. `AuroraActionExecutor` can report invalid cue/sequence targets as successfully executed even when no action occurred.

One MIDI identity hardening issue and warning cleanup are also required before the final checkpoint.

Do not redesign the accepted AME/Musical architecture. These are localized correctness fixes.

---

# P0-1 — Physical release must bypass the outer MIDI safety limiter

## Severity

**P0 / stuck live output and safety behavior**

## Files

- `Sources/Aurora/ControlActionRouter.swift`
- `Sources/AuroraMIDI/MIDISafetyLimiter.swift`
- tests under `Tests/AuroraMIDITests` and `Tests/AuroraEngineTests`

## Current behavior

`ControlActionRouter.handleMIDIEvents(...)` applies the global limiter before any AME or advanced MIDI behavior processing:

```swift
for event in events {
    guard safety.allow(event: event) else { continue }

    // AME processing
    // MIDIBehaviorRuntime noteOn/noteOff
    // legacy processing
}
```

The limiter rejects every event after its rolling-window capacity is reached. It does not distinguish activation from physical release.

With the current router capacity of 250 events per second, a dense stream can fill the window and cause a subsequent Note Off to be discarded.

## Failure sequence

```text
Note On acquires AME hold or starts sustained behavior
Dense notes/CC/clock-adjacent performance traffic fills safety window
Physical Note Off arrives
MIDISafetyLimiter rejects Note Off
AME and MIDIBehaviorRuntime never receive release
Live output remains held
```

This violates the locked invariant that physical release must not be blocked by debounce or burst suppression.

It also affects velocity-zero Note On after parser normalization because that event becomes Note Off and can still be rejected by this outer guard.

## Required correction

Release-class events must reach state-unwind paths regardless of the activation flood limit.

At minimum:

- Note Off must bypass rate/debounce rejection for AME release processing.
- Note On velocity 0, after normalization, must receive the same treatment.
- Release must reach `MIDIBehaviorRuntime.noteOff(...)`.
- Release processing must remain source/channel/note specific.

Safe implementation approaches include:

1. Process release/unwind before consulting the limiter, then apply the limiter only to activation and ordinary performance work.
2. Add an explicit release-aware limiter result that always admits release for safety state changes while optionally suppressing non-safety legacy actions derived from the same event.

Do not allow a release event to retrigger unrelated activation mappings merely because it bypasses the flood limiter. Separate safety unwind from ordinary action admission where necessary.

The limiter should also use monotonic event/host time rather than wall-clock `Date().timeIntervalSince1970` for its rolling window. A wall-clock adjustment can otherwise make stored timestamps appear to be in the future and prolong suppression.

## Required tests

- [ ] Fill the limiter window, then send Note Off; AME hold releases.
- [ ] Fill the limiter window, then send Note On velocity 0; AME hold releases.
- [ ] Fill the limiter window, then send Note Off; sustained MIDI behavior enters release.
- [ ] Release from source A does not release source B's same note/channel state.
- [ ] Debounce configuration never blocks physical release.
- [ ] Release bypass does not execute unrelated Note Off mappings unless those mappings independently pass their intended admission rules.
- [ ] Rolling-window behavior uses monotonic time and remains correct across simulated wall-clock changes.

---

# P0-2 — Source disconnect and MIDI stop must unwind all source-owned live state

## Severity

**P0 / stuck live output after unplug or input shutdown**

## Files

- `Sources/Aurora/ControlActionRouter.swift`
- `Sources/AuroraEngine/MIDIBehaviorRuntime.swift`
- `Sources/AuroraMIDI/MIDIInputManager.swift`
- `Sources/Aurora/Controllers/InputController.swift`
- relevant AME/MIDI behavior integration tests

## Current behavior

The CoreMIDI lifecycle handler calls:

```swift
router.handleMIDISourceDisconnected(sourceID)
```

That method releases AME-held and toggle state through:

```swift
ameRuntime.releaseHeld(forSourceID: sourceID)
```

However, `MIDIBehaviorRuntime` also owns live sustained instances keyed by:

```text
deviceID:channel:note
```

There is no disconnect/unwind API for behavior instances. A behavior with nonzero sustain can therefore remain live indefinitely after its device disappears because no Note Off will arrive.

In addition, `MIDIInputManager.stop()` disconnects all endpoints and clears its source tables without emitting `.disconnected` lifecycle events. Any caller that stops/restarts MIDI while the app remains live bypasses even the AME unwind path.

## Failure sequences

### Device unplug

```text
Note On starts sustained MIDI behavior
Device is unplugged
AME state releases
MIDIBehaviorRuntime instance remains unreleased
Lighting output remains stuck at sustain
```

### MIDI subsystem stop/restart

```text
Source owns AME hold/toggle or sustained behavior
MIDIInputManager.stop() disconnects endpoints
No source lifecycle notifications are emitted
Runtime source-owned state survives stop
```

## Required correction

Add a source-specific behavior unwind API, for example:

```swift
MIDIBehaviorRuntime.releaseAll(forDeviceID:at:)
```

It should mark matching instances released at the supplied monotonic engine time so configured release envelopes complete naturally. If immediate removal is the accepted safety policy, make that explicit and test it.

`ControlActionRouter.handleMIDISourceDisconnected(...)` must unwind both:

- AME-held/toggle state owned by the disconnected source;
- live MIDI behavior instances owned by the disconnected source.

`MIDIInputManager.stop()` must snapshot connected source IDs and deliver one disconnect lifecycle event for each source after safely disconnecting/clearing internal CoreMIDI state. Do not call external handlers while holding the manager lock.

Ensure shutdown remains idempotent and does not double-release when CoreMIDI also emits a removal notification.

## Required tests

- [ ] Unplug source A releases source A's sustained MIDI behaviors.
- [ ] Source A disconnect does not release source B's behaviors.
- [ ] AME hold, AME toggle, and MIDI behavior state all unwind in one source-disconnect path.
- [ ] `MIDIInputManager.stop()` emits disconnect lifecycle once per connected source.
- [ ] Repeated stop is idempotent and emits no duplicate disconnects.
- [ ] Stop/restart does not preserve stale parser, held, toggle, or behavior state.
- [ ] Release envelope completes and live behavior count returns to zero.

---

# P0-3 — Invalid action targets must not report successful execution

## Severity

**P0 / silent live no-op reported as success**

## Files

- `Sources/Aurora/AuroraActionExecutor.swift`
- `Sources/AuroraEngine/LightingEngine.swift`
- `Sources/AuroraEngine/PlaybackController.swift`
- `Sources/AuroraEngine/AME/AMERuntime.swift`
- action-executor integration tests

## Current behavior

`AuroraActionExecutor.execute(...)` returns `.executed` after its lighting-action switch even when a target lookup fails.

Examples:

### Invalid cue UUID

```swift
case .fireCue(let id):
    eng.fire(cueID: id) // void; silently returns when cue is absent
```

### Invalid cue index

```swift
case .fireCueIndex(let index):
    if ... indices.contains(index) {
        eng.fire(...)
    }
    // falls through to `.executed` even if no index was valid
```

### Missing sequence reset target

```swift
case .resetSequence(let id):
    ame.resetSequence(id: id) // void; silently returns when sequence is absent
    return .executed
```

This causes immediate and quantized AME paths to report success, notify observers, and suppress claimed legacy fallback even though nothing happened.

## Required correction

Make target-dependent execution APIs return a truthful result.

Recommended changes:

- `PlaybackController.fire(...)` or `LightingEngine.fire(...)` returns `Bool`/outcome indicating whether the cue was found and transition began.
- `.fireCueIndex` explicitly returns `.unsupported` or another non-success outcome for a negative/out-of-range index or absent active list.
- `AMERuntime.resetSequence(...)` returns `Bool`, matching `advanceSequence(...)`.
- `AuroraActionExecutor` propagates these results.
- Observer summaries must report unsupported/invalid rather than executed.
- An invalid AME action must not count as `ameFired` and must not suppress a valid unclaimed legacy path.

Decide and document whether `.go`, `.back`, and `.stop` are accepted commands when already at a terminal/idle state. Target-specific actions with objectively invalid IDs or indices must never be reported as executed.

## Required tests

- [ ] Missing cue UUID returns `.unsupported`/invalid, not `.executed`.
- [ ] Negative cue index returns non-success.
- [ ] Out-of-range cue index returns non-success.
- [ ] No active/available cue list returns non-success for indexed fire.
- [ ] Missing sequence reset target returns non-success.
- [ ] Valid cue UUID/index and valid sequence reset still return `.executed`.
- [ ] Invalid immediate and quantized AME actions produce honest diagnostics.
- [ ] Invalid AME no-op does not suppress an otherwise eligible legacy mapping.
- [ ] Compound action returns `.partial` when valid and invalid target-dependent children are mixed.

---

# P1-1 — Treat CoreMIDI UniqueID zero as non-durable

## Severity

**P1 / source identity durability and ambiguity**

## Files

- `Sources/AuroraMIDI/MIDIInputManager.swift`
- `Sources/AuroraModel/MIDISourceIdentity.swift`
- MIDI identity tests

## Current behavior

`MIDIInputManager.stableSourceID(for:)` treats any successful `kMIDIPropertyUniqueID` property read as durable:

```swift
var unique: Int32 = 0
let status = MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &unique)
if status == noErr {
    return MIDISourceIdentity.coreMIDIUniqueID(unique)
}
```

A successful property read with `unique == 0` yields `uid:0`. Zero is not a useful durable identity and can collapse multiple endpoints onto the same canonical ID.

That can also overwrite `sourceIDStorage["uid:0"]`, while CoreMIDI connection refCons still refer to the prior stored object, creating an unsafe lifetime/collision scenario.

## Required correction

Use UID identity only when the returned value is useful:

```text
status == noErr && unique != 0
```

Otherwise use the runtime endpoint-ref identity and Learn's durable metadata fallback.

Also make runtime source-ID storage safe if two endpoints ever produce the same claimed UID. Storage/refCon lifetime should be owned per endpoint/connection, not solely by a possibly colliding source-ID string.

## Required tests

- [ ] Nonzero UID produces `uid:<value>`.
- [ ] UID property failure produces `ep:<endpoint>`.
- [ ] UID zero produces `ep:<endpoint>`, never `uid:0`.
- [ ] Two endpoints with unusable/duplicate IDs cannot overwrite each other's refCon storage.
- [ ] Learn for a zero-UID source follows the non-UID metadata durability path.

---

# P2 — Clean the shipping-build warnings relevant to the release gate

The clean build and Xcode analysis succeed but report warnings.

## AME / live-control warnings

- `Sources/AuroraEngine/AME/AMESequenceRuntime.swift`: unreachable `default` branch.
- `Sources/Aurora/ControlActionRouter.swift`: ignored return value from `actionTokens.consume(...)` at the schedule cancel and rejection cleanup sites.

Use explicit discard where intentional:

```swift
_ = actionTokens.consume(token)
```

Remove the unreachable exhaustive-switch default.

## Other warnings observed

- `Sources/AuroraRemote/RemoteSessionManager.swift`: unused result of `reclaimInactiveLocked(now:)`.
- `Sources/AuroraRemote/RemoteWebServer.swift`: `bodyStart` never mutated.
- `Sources/Aurora/PanelRegistry.swift`: unreachable `default`.
- `Sources/Aurora/Tools/CheckpointC1ScreenshotExporter.swift`: unused `id` binding.

These are not hardware blockers by themselves, but a warning-clean baseline makes new hardware-path warnings visible.

---

# Verification performed

## Repository inventory

Reviewed implementation, test, app, script, and configuration inventory across:

- `Aurora`
- `AuroraCore`
- `AuroraDiagnostics`
- `AuroraEngine`
- `AuroraFixtureLib`
- `AuroraMIDI`
- `AuroraModel`
- `AuroraMusical`
- `AuroraOutput`
- `AuroraRemote`
- `AuroraUI`

Inventory contained 679 review files and approximately 71,577 implementation/test/configuration lines.

## Full Swift test suite

```text
Executed 777 tests
0 failures
Result: PASS
```

## Clean shipping application build

```text
xcodebuild -project Aurora.xcodeproj \
  -scheme Aurora \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/AuroraPreSmokeDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  clean build

Result: PASS
```

## Xcode static analysis

```text
xcodebuild -project Aurora.xcodeproj \
  -scheme Aurora \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/AuroraPreSmokeAnalyzeDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  analyze

Result: PASS with warnings listed above
```

---

# Final pre-smoke acceptance gate

Before beginning hardware smoke testing:

- [ ] Release events bypass flood/debounce suppression for safety unwind.
- [ ] Dense input cannot leave AME holds/toggles or MIDI behaviors stuck.
- [ ] Device unplug releases all state owned by that source only.
- [ ] MIDI subsystem stop emits equivalent source-disconnect cleanup.
- [ ] Invalid cue and sequence targets report non-success truthfully.
- [ ] Invalid AME no-ops do not suppress valid legacy handling.
- [ ] UID zero follows the non-UID durable metadata path.
- [ ] New adversarial regression tests pass.
- [ ] Full Swift test suite passes.
- [ ] Clean shipping Aurora app build passes.
- [ ] AME/live-control compiler warnings are removed.
- [ ] Pre-hardware checkpoint records the final evidence.

After these software gates pass, proceed to Wave 6 with real local MIDI, RTP-MIDI, dense performance input, unplug/reconnect, clock dropout, source switching, and show-length soak testing. Hardware acceptance remains incomplete until that real-device matrix is executed.

