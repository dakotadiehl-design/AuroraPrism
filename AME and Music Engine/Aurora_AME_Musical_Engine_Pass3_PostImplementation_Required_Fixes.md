# Aurora AME + Musical Engine — Pass 3 Post-Implementation Required Fixes

**Review date:** 2026-08-16  
**Review scope:** Grok's implementation of `Aurora_AME_Musical_Engine_CodeReviewPass3_Final_PreHardware_Fixes.md`  
**Disposition:** **HOLD final software closeout until the two P1 items below are corrected and verified.**

---

## Executive summary

The original Pass 3 P0 timing-policy defect appears corrected in the production host path.

`ShowControlController.applyMusicalEngineFromProject(...)` now re-applies the configured external source whenever the timing policy transitions into an external-capable mode. This prevents an `external → internalOnly → external` round trip from leaving the Musical Engine's selected source set to `internal`.

The AME Learn implementation now enriches learned sources with current MIDI inventory metadata. UID-backed sources retain their CoreMIDI UniqueID, and non-UID sources normally persist a friendly endpoint name instead of an ephemeral `ep:` token.

The shipping Aurora macOS application target also builds successfully. The earlier `AuroraActionExecutor.swift` target-membership failure is no longer present.

Two required closeout issues remain:

1. AME Learn can still commit an unusable non-UID binding when inventory metadata is unavailable.
2. The timing-policy regression tests duplicate the host algorithm instead of exercising the production reconciliation path.

These are targeted corrections. Do not redesign the accepted AME or Musical Engine architecture.

---

# P1-1 — Do not commit an orphaned non-UID Learn binding when metadata is unavailable

## Severity

**P1 / required reliability closeout**

## Files

- `Sources/AuroraModel/MIDISourceIdentity.swift`
- `Sources/Aurora/ControlActionRouter.swift`
- relevant tests under `Tests/AuroraModelTests` and an AME host/runtime test target

## Current behavior

`MIDISourceIdentity.makeDurableBinding(...)` correctly avoids storing a literal `ep:####` value as a display-name or endpoint-name hint.

However, when the runtime source ID is an `ep:` ID and no matching inventory metadata is available, it currently creates a binding resembling:

```text
displayName = "MIDI Source"
lastCoreMIDIUniqueID = nil
manufacturerHint = nil
modelHint = nil
endpointNameHint = nil
```

The learned trigger then references that binding by UUID.

## Why this is still defective

This binding contains no durable device identity and no runtime identity that can resolve it later.

When inventory metadata becomes available on a later update or reconnect, Aurora has no persisted endpoint name, manufacturer, model, or UID with which to associate the binding. A generic display name such as `MIDI Source` cannot recover the original device.

Consequences:

- the learned mapping can be orphaned immediately;
- reconnect cannot resolve it to the new `ep:` ID;
- AME may silently fail to fire a mapping that Learn reported as successfully captured;
- the current source-code comment claiming that later inventory resolution can recover the binding is incorrect.

Avoiding the literal `ep:` string is necessary, but it is not sufficient. Learn must not report durable success when no durable identity was captured.

## Required correction

When a non-UID `ep:` source has no usable inventory metadata, do not commit a source-constrained binding with no identity hints.

Choose a deterministic, explicit behavior such as:

1. Keep Learn armed and wait for inventory metadata, or retry metadata lookup before capture.
2. Produce an unresolved Learn proposal that the host refuses to commit until the user selects a source.
3. Cancel/fail the Learn capture with an explicit diagnostic explaining that source identity metadata was unavailable.

Preferred behavior is to resolve current inventory metadata before the Learn proposal is committed. If the source cannot be identified durably, fail visibly rather than persisting a mapping that cannot match.

Do not:

- store `ep:####` as a durable name hint;
- invent a generic source identity and report Learn success;
- create a source-binding UUID whose binding has no usable resolution fields;
- silently fall back to matching an arbitrary same-named endpoint.

## Required tests

- [ ] UID source Learn persists UID, friendly endpoint name, and available manufacturer metadata.
- [ ] Non-UID source Learn with inventory persists the real endpoint name, never `ep:####`.
- [ ] Non-UID `ep:` source with missing inventory does not commit an unusable binding.
- [ ] Missing-metadata behavior is explicit: deferred, unresolved, or diagnosed as failed.
- [ ] A failed/deferred capture does not leave a committed trigger referencing an orphaned binding.
- [ ] Reconnect from `ep:100` to `ep:900` resolves the learned binding using persisted metadata.
- [ ] The resolved `ep:900` source causes the associated AME trigger and mapping to fire.
- [ ] Two indistinguishable same-name endpoints remain ambiguous and fail closed.

---

# P1-2 — Test the real host timing-policy reconciliation path

## Severity

**P1 / required regression coverage**

## Files

- `Tests/AuroraMusicalTests/MusicalEnginePolicyReentryTests.swift`
- `Sources/Aurora/Controllers/ShowControlController.swift`
- possibly a small shared/testable configuration reconciler or an Aurora host integration test target

## Current behavior

The production correction in `ShowControlController.applyMusicalEngineFromProject(...)` is consistent with the requested fix:

```swift
let policyChanged = previous?.timingPolicy != desired.timingPolicy
let sourceChanged = previous?.selectedSourceID != desired.selectedSourceID

if policyChanged {
    musicalEngine.setTimingPolicy(desired.timingPolicy)
}

let needsExternalSourceSync =
    sourceChanged || (policyChanged && desired.timingPolicy != .internalOnly)

if needsExternalSourceSync {
    clockAdapter.setPreferredSourceID(desired.selectedSourceID)
    if desired.timingPolicy != .internalOnly {
        musicalEngine.selectExternalTimingSource(desired.selectedSourceID)
    }
}
```

The added tests, however, call a private test helper that reimplements these rules. They do not invoke `ShowControlController.applyMusicalEngineFromProject(...)` or another production reconciliation component.

## Why this is insufficient

The original defect was in host-side configuration diff application.

A test containing its own correct copy of the intended algorithm can remain green if:

- the production host condition is removed;
- the order of production policy/source calls regresses;
- the adapter is no longer synchronized;
- project source-binding resolution feeds the wrong desired source;
- `lastAppliedMusicalConfig` behavior changes incorrectly.

The current tests prove the Musical Engine behaves correctly when manually called in the desired order. They do not permanently guard the host bug that actually occurred.

## Required correction

Add regression coverage that exercises the production reconciliation behavior.

Acceptable approaches include:

1. Add an Aurora host integration test that constructs `ShowControlController`, applies real `ShowProject` musical settings/source bindings, and inspects the Musical Engine and clock adapter state.
2. Extract the policy/source reconciliation decision into a small production component used by `ShowControlController`, then unit-test that component directly while retaining engine behavior tests.

Do not leave the test-only `applyPolicyAndSource(...)` helper as the sole regression protection for this defect.

## Required transition matrix

Test the real production path for:

- [ ] `external(A) → internalOnly → external(A)`
- [ ] `external(A) → preferredFallback(A) → external(A)`
- [ ] `internalOnly → external(A)`
- [ ] `external(A) → internalOnly → preferredFallback(A)`
- [ ] `external(A) → external(B)`
- [ ] source selection changes from `A` to `B` while internal-only, then external mode selects `B`

After every transition, verify:

- [ ] persisted/configured policy;
- [ ] Musical Engine timing policy;
- [ ] Musical Engine selected source identity;
- [ ] MIDI Clock adapter preferred source identity;
- [ ] live admission rejects the wrong source and accepts the configured source;
- [ ] re-entry resets stale estimator state and requires normal reacquisition;
- [ ] host diff application does not spuriously invoke scheduler timing-loss behavior.

---

# Verification already completed

## Focused Swift regression tests

Command:

```text
swift test --filter 'MusicalEnginePolicyReentryTests|MIDISourceIdentityLearnTests'
```

Result:

```text
11 tests executed
0 failures
```

This confirms the currently implemented unit tests pass, but it does not close the integration-test gap described in P1-2.

## Shipping Aurora application build

Command:

```text
xcodebuild \
  -project Aurora.xcodeproj \
  -scheme Aurora \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/AuroraPass3ReviewDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Result:

```text
** BUILD SUCCEEDED **
```

This closes the previously recorded `AuroraActionExecutor.swift` application-target visibility discrepancy for the reviewed working tree.

The complete macOS test suite was not run during this review and remains part of final software closeout.

---

# Final re-acceptance gate

Before declaring the software ready for Wave 6 hardware validation:

- [ ] P1-1 no longer permits a successful Learn commit without durable non-UID metadata.
- [ ] Reconnect resolution is verified through actual AME trigger/mapping execution.
- [ ] Ambiguous fallback remains fail-closed and observable.
- [ ] P1-2 exercises the production host reconciliation path.
- [ ] The complete required timing transition matrix is covered.
- [ ] Focused AME/Musical regression tests pass.
- [ ] Full macOS test suite passes.
- [ ] Shipping Aurora app target clean-builds again after the final corrections.
- [ ] The pre-hardware checkpoint records the final build and test evidence.

Wave 6 hardware acceptance remains a separate real-device phase and must not be marked complete based on software tests alone.

