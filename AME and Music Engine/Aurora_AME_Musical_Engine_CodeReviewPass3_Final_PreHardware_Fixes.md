# Aurora AME + Musical Engine — Code Review Pass 3 Final Pre-Hardware Fixes

**Review target:** `Aurora_AMEMusicEngine_CodeReviewPass3.zip`  
**Review date:** 2026-08-16  
**Disposition:** **Software architecture is healthy, but HOLD Wave 6 hardware acceptance until the two code fixes and the fresh macOS build gate below are closed.**

---

## Executive summary

Pass 3 is substantially healthier than the prior reviews. The previous closeout items are genuinely present in the implementation:

- Musical Engine project/policy/config setters are idempotent.
- Host-side AME and Musical configuration application is diff-gated.
- Unrelated project edits no longer replace the AME runtime document.
- Immediate and quantized AME actions share the generalized `AuroraActionExecutor` path.
- Song/section host callbacks are installed.
- Song metadata no longer overwrites true project Musical Engine defaults.
- Source-owned held and toggle state unwinds on disconnect.
- Full CoreMIDI ingress reaches the MIDI Clock adapter independently of Learn.
- The scheduler is driven by a dedicated 4 ms non-UI runtime driver.
- Quantized payloads retain control value, latency/provenance, and ordered fixture selection.
- AME editor root identity thrash is removed.
- AME Learn is canceled when the window closes.
- Inventory-resolved source IDs are published to AME runtime matching.
- Unsupported effect/preset/palette/look/behavior paths are now honestly marked unsupported.

I do **not** recommend another architectural redesign.

Two real code defects remain before Wave 6, plus one acceptance/build-artifact discrepancy that must be resolved on the development Mac.

---

# P0 — Required before Wave 6

## P0-1 — Timing policy re-entry can lose the configured external MIDI source

### Severity

**P0 / live-show timing authority**

### Files

- `Sources/Aurora/Controllers/ShowControlController.swift`
- `Sources/AuroraMusical/MusicalEngine.swift`
- tests under `Tests/AuroraMusicalTests` and/or an app integration test

### Current host flow

`ShowControlController.applyMusicalEngineFromProject(...)` correctly computes a diff snapshot:

```swift
let desired = AppliedMusicalProjectConfig(
    tempo: settings.defaultTempoBPM,
    meter: meter,
    freewheelSeconds: settings.freewheelSeconds,
    timingPolicy: policy,
    selectedSourceID: sourceID
)
```

It then applies policy changes separately from source changes:

```swift
if previous?.timingPolicy != desired.timingPolicy {
    musicalEngine.setTimingPolicy(desired.timingPolicy)
}

if previous?.selectedSourceID != desired.selectedSourceID {
    clockAdapter.setPreferredSourceID(desired.selectedSourceID)
    if desired.timingPolicy != .internalOnly {
        musicalEngine.selectExternalTimingSource(desired.selectedSourceID)
    }
}
```

This looks reasonable, but `MusicalEngine.setTimingPolicy(.internalOnly)` intentionally mutates engine state:

```swift
_state.timing.selectedSourceID = Self.internalSourceID
_state.timing.activeSourceID = Self.internalSourceID
```

The host's `lastAppliedMusicalConfig.selectedSourceID`, however, continues to represent the persisted external source choice.

### Failure sequence

Assume the saved external source is `uid:123`.

1. Project is using `.externalMIDI` + `uid:123`.
2. Host state:
   - `lastAppliedMusicalConfig.selectedSourceID == "uid:123"`
   - engine `selectedSourceID == "uid:123"`
3. User changes timing policy to `.internalOnly`.
4. `setTimingPolicy(.internalOnly)` changes engine `selectedSourceID` to `"internal"`.
5. Host config still stores the external configured source as `"uid:123"`.
6. User changes policy back to `.externalMIDI`, without changing the selected-source binding.
7. Host sees:

```text
previous.selectedSourceID == desired.selectedSourceID == "uid:123"
```

so it **does not call** `selectExternalTimingSource("uid:123")`.
8. `setTimingPolicy(.externalMIDI)` preserves the engine's existing selected ID, which is still `"internal"`.
9. `acceptsTimingEventLocked(from:)` requires incoming source ID to equal the selected ID.
10. Real clock from `uid:123` is rejected.

The same class of failure exists for `.internalOnly → .externalPreferredFallback`.

### Why this matters

A user can configure an external clock correctly, temporarily switch Aurora to internal timing, then switch back and silently stop accepting the previously selected clock source.

That is exactly the kind of stateful transition that a hardware test may expose only after several minutes of seemingly unrelated operation.

### Required correction

Treat **configured external source intent** and **current active timing policy** as separate concepts.

Recommended host behavior:

- Keep `desired.selectedSourceID` as the configured external source.
- When either:
  - the selected external source changes, **or**
  - the policy changes into an external-capable policy (`externalMIDI` / `externalPreferredFallback`),
  explicitly synchronize both the adapter and Musical Engine selected source.

Conceptually:

```swift
let policyChanged = previous?.timingPolicy != desired.timingPolicy
let sourceChanged = previous?.selectedSourceID != desired.selectedSourceID

if policyChanged {
    musicalEngine.setTimingPolicy(desired.timingPolicy)
}

if sourceChanged || (policyChanged && desired.timingPolicy != .internalOnly) {
    clockAdapter.setPreferredSourceID(desired.selectedSourceID)
    musicalEngine.selectExternalTimingSource(desired.selectedSourceID)
}
```

An even cleaner semantic is to let `selectedSourceID` always mean the **configured external preference**, even while `internalOnly` owns active authority. If taking that route, ensure the state model clearly distinguishes:

- configured/selected external source,
- active source,
- timing policy.

Do not conflate those again.

### Important estimator behavior

Re-entering external timing after an internal-only interval should reset/reacquire external estimator state rather than inheriting stale lock history. Calling `selectExternalTimingSource(...)` on the re-entry transition naturally provides that reset because the engine's selected ID changed to `internal` during internal-only mode.

### Mandatory tests

Add all of these:

- [ ] `externalMIDI(uid:A) → internalOnly → externalMIDI(uid:A)` restores `selectedSourceID == uid:A`.
- [ ] Clock pulses from `uid:A` are accepted after the transition and can reacquire lock.
- [ ] `externalPreferredFallback(uid:A) → internalOnly → externalPreferredFallback(uid:A)` reacquires `uid:A`.
- [ ] Change source while internal-only (`uid:A → uid:B`), then enter external mode → engine selects `uid:B`.
- [ ] Re-entering external mode resets stale estimator state and requires the normal acquisition criteria.
- [ ] Scheduler failure-policy behavior is not triggered merely by a host diff bug.

---

# P1 — Required reliability correction before RTP-MIDI / reconnect testing

## P1-1 — AME Learn stores ephemeral `ep:` endpoint IDs as name hints when a source has no CoreMIDI UniqueID

### Severity

**P1 / binding durability, especially RTP/network MIDI and devices without stable CoreMIDI UniqueID**

### Files

- `Sources/Aurora/ControlActionRouter.swift`
- `Sources/Aurora/Controllers/InputController.swift`
- `Sources/AuroraModel/MIDISourceIdentity.swift`
- possibly `MIDISourceBinding` model helpers
- tests under `AuroraEngineTests` / `AuroraMIDITests`

### Current Learn behavior

`ControlActionRouter.makeLearnProposal(...)` only receives the normalized event's runtime `sourceID`.

For UID-backed endpoints:

```swift
if let uid = MIDISourceIdentity.parseCoreMIDIUniqueID(event.sourceID) {
    binding = MIDISourceBinding(
        displayName: event.sourceID,
        lastCoreMIDIUniqueID: uid,
        endpointNameHint: event.sourceID
    )
}
```

The UID is durable enough for matching, although using a friendly inventory name for display would still be nicer.

For endpoints without a CoreMIDI UniqueID:

```swift
binding = MIDISourceBinding(
    displayName: event.sourceID,
    endpointNameHint: event.sourceID
)
```

If the runtime source is `ep:4242`, Aurora persists:

```text
displayName       = "ep:4242"
endpointNameHint  = "ep:4242"
```

### Why this is fragile

`ep:<MIDIEndpointRef>` is a runtime endpoint identity, not a durable human/device identity suitable for persistence.

The inventory resolver later tries to resolve name-based bindings against:

```swift
InventorySource(id: "ep:NEW", name: "actual endpoint name", manufacturer: "...")
```

and `hintMatches(...)` compares `endpointNameHint` / `displayName` to the **actual source name**.

A learned hint of `"ep:4242"` cannot match a future inventory source named, for example, `"Network Session 1"` or `"Nord Drum 3P"`.

This works in the original session only because the runtime fallback can compare the event's current source ID directly to the persisted `ep:4242` string. After reconnect/relaunch, the endpoint ref may change and the mapping becomes orphaned.

### Required correction

AME Learn needs access to source inventory metadata at capture time.

Recommended design:

1. When Learn captures a normalized event, resolve `event.sourceID` against current `MIDIDeviceInfo` / inventory.
2. Persist:
   - stable CoreMIDI UniqueID when available;
   - actual endpoint/device name as `endpointNameHint`;
   - manufacturer when available;
   - model/name hint if available;
   - friendly display name for UI.
3. Treat `ep:` as **runtime-only canonical identity**, not the persisted name hint.
4. On subsequent launch/reconnect, resolve the binding's hints back to the new canonical live `uid:`/`ep:` ID using `MIDISourceIdentity.resolve(...)`.

Possible API shapes:

```swift
makeLearnProposal(
    from event: AMENormalizedEvent,
    sourceMetadata: MIDISourceIdentity.InventorySource?
)
```

or have `InputController`/host enrich the Learn capture before committing it.

For UID-backed sources, still store the real display/name/manufacturer metadata instead of `uid:123` as the friendly label when inventory data is available.

### Mandatory tests

- [ ] Learn source with UID persists UID + friendly endpoint metadata.
- [ ] Learn source without UID persists actual endpoint name, **not** `ep:...` as the name hint.
- [ ] Session 1: learned `ep:100`, name `Network Session 1`.
- [ ] Session 2/reconnect: inventory reports same name as `ep:900`.
- [ ] Binding resolves to `ep:900` and AME trigger fires.
- [ ] Two same-name endpoints without stronger hints resolve as ambiguous/fail-closed.
- [ ] RTP-MIDI source reconnect does not silently orphan an AME learned mapping.

---

# P1 — Build/acceptance gate discrepancy

## P1-2 — Archive contains a failed Xcode application build; require a fresh successful app build after project regeneration

### Evidence in this archive

The included file:

```text
Build Aurora_2026-08-16T15-56-32.txt
```

contains an Xcode application-target failure:

```text
ControlActionRouter.swift: cannot find 'AuroraActionHostCallbacks' in scope
ControlActionRouter.swift: cannot find type 'AuroraActionExecutionOutcome' in scope
ControlActionRouter.swift: cannot find type 'AuroraActionExecutor' in scope
ShowControlController.swift: cannot find type 'AuroraActionExecutionOutcome' in scope
```

The apparent cause in that recorded build is that the app target did not yet see `AuroraActionExecutor.swift`.

### Current tree status

The **current** archived `Aurora.xcodeproj/project.pbxproj` now contains:

```text
AuroraActionExecutor.swift in Sources
```

and `project.yml` includes the whole `Sources/Aurora` directory.

The file timestamps also suggest the Xcode project was modified **after** the failed build log was produced.

Therefore this may already have been corrected after the recorded build, but this archive does not contain a newer successful Xcode app-build artifact proving it.

I also independently built the isolated `AuroraMusical` SwiftPM target successfully in the review environment.

### Required action on the development Mac

Before Wave 6:

1. Regenerate the Xcode project from the canonical project definition if that remains the normal workflow.
2. Clean/build the **shipping Aurora app target** in Xcode or `xcodebuild`.
3. Run the full macOS test suite.
4. Record the successful build/test result in the checkpoint.

Do not accept a SwiftPM library-only build as sufficient. The failure here occurred specifically at the app integration target.

### Acceptance

- [ ] `AuroraActionExecutor.swift` is in the app target after a clean generation.
- [ ] Shipping Aurora app target compiles from a clean build directory.
- [ ] Full macOS suite is green.
- [ ] Checkpoint records the fresh successful build/test, not only the earlier `754 / 0` statement.

---

# P2 — Cleanup before final stamp

These are not hardware blockers but should be cleaned while touching the area.

## P2-1 — Stale compiler warnings in recorded macOS build

The archived Xcode log contains warnings including:

- `MusicalEngine.swift`: `fireNow` / `canceled` never mutated.
- `AMEConfigurationValidator.swift`: unused pattern bindings.
- `AMESequenceRuntime.swift`: unreachable `default`.
- unrelated `RemoteWebServer.swift`: `bodyStart` never mutated.

Some may already have been fixed after that build log. Confirm with the fresh build and clean any remaining warnings in the AME/Musical path.

## P2-2 — Add the missing policy-reentry case to the permanent regression suite

The existing idempotency test checks re-applying `.externalMIDI` while already external, but does not cover a round trip through `.internalOnly`.

The critical distinction is:

```text
same policy reapply  !=  policy leave-and-return
```

Keep a regression test for the second case permanently.

---

# What NOT to redesign

The following should remain intact:

- `AuroraMusical` remains CoreMIDI-independent.
- `MIDIClockTimingAdapter` remains the CoreMIDI-to-Musical bridge.
- Dedicated non-UI Musical Engine runtime driver.
- Monotonic `HostTime` throughout ingress and scheduling.
- Typed scheduled action token/payload model.
- Ingress-time selection/control-value snapshot semantics.
- Unified generalized `AuroraActionExecutor` for immediate + quantized actions.
- AME early release path and snapshotted release actions.
- Source-owned held/toggle disconnect unwinding.
- Host diff-gating of project musical settings / AME document updates.
- Song metadata layered through `ShowMusicalContext`, not project-default mutation.
- Additive section mapping membership semantics.
- Honest unsupported action classification.

This is a small closeout, not a new phase.

---

# Required implementation order

```text
1. Fix policy re-entry / external-source synchronization (P0-1)
2. Add policy-transition regression tests
3. Fix durable metadata capture for AME Learn (P1-1)
4. Add reconnect/relaunch identity tests
5. Regenerate Xcode project
6. Clean-build shipping Aurora app target
7. Run full macOS suite
8. Update checkpoint
9. Proceed to Wave 6 hardware / RTP-MIDI / soak matrix
```

---

# Final software re-acceptance gate

Before starting the real-device Wave 6 matrix:

- [ ] External source survives `external → internal → external` policy round trips.
- [ ] Source change while internal is respected when returning to external mode.
- [ ] External estimator reacquires cleanly after policy re-entry.
- [ ] Learned non-UID/RTP endpoint survives reconnect with a changed `ep:` runtime ID.
- [ ] Ambiguous name-only sources fail closed.
- [ ] Shipping Aurora Xcode app target builds cleanly from a fresh project generation.
- [ ] Full macOS test suite green.
- [ ] No new AME/Musical warnings in the clean build.

Once these are green, I consider the software implementation ready to enter **Wave 6 hardware acceptance**.

---

## Reviewer disposition

**Core AME architecture:** GREEN  
**Musical Engine timing/scheduler core:** GREEN  
**Quantization path:** GREEN  
**Song/section integration:** GREEN  
**Held/toggle safety:** GREEN  
**Editor/Learn:** GREEN with P1-1 durability correction required  
**Timing-policy integration:** YELLOW until P0-1 fixed  
**Wave 6 hardware acceptance:** HOLD until this document's gate is green

