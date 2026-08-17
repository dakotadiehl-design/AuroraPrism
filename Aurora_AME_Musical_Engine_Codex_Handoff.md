# Aurora AME + Musical Engine — Codex Handoff

**Project:** Aurora  
**Subsystems:** Advanced MIDI Engine (AME) + Musical Engine  
**Handoff purpose:** Transfer ongoing code-review and closeout work from archive-based ChatGPT reviews to Codex running directly on the development machine/repository.  
**Current status:** Software architecture is largely accepted. Two pre-hardware fixes remain before Wave 6 hardware/reliability validation.

---

# 1. Mission

Codex is being handed the Aurora repository to continue deep code review, correction, and closeout work on the **Advanced MIDI Engine (AME)** and **Musical Engine**.

The goal is **not** to redesign these systems.

The goal is to:

1. Preserve the architecture that has already survived several deep reviews.
2. Fix the small number of remaining pre-hardware issues.
3. Verify the shipping macOS app builds cleanly.
4. Run the full test suite.
5. Perform fresh end-to-end review directly against the repository.
6. Prepare the project for **Wave 6 hardware validation**.
7. Avoid claiming the AME + Musical Engine track is complete until the hardware/reliability gate has actually been executed.

---

# 2. High-level architecture

Aurora intentionally separates musical intelligence, MIDI transport/parsing, AME rule evaluation, and application execution.

Conceptually:

```text
CoreMIDI / RTP-MIDI
        |
        v
AuroraMIDI
  - MIDIInputManager
  - MIDIMessageParser
  - MIDIIngressEvent
  - MIDISourceIdentity
        |
        +------------------------------+
        |                              |
        v                              v
Performance MIDI                 MIDI Clock / RT / SPP
        |                              |
        v                              v
AME Runtime                 MIDIClockTimingAdapter
        |                              |
        |                              v
        |                       MusicalEngine
        |                      - timing source
        |                      - transport
        |                      - meter/tempo
        |                      - scheduler
        |                      - quantization
        |
        v
AME emissions
        |
        +-------------------+
                            |
                 immediate / quantized
                            |
                            v
                 AuroraActionExecutor
                            |
       +--------------------+--------------------+
       |                    |                    |
       v                    v                    v
 Lighting/Programmer    Song/Section        Musical/Show
      actions             actions             actions
```

The separation between **AME** and the **Musical Engine** is deliberate and must remain.

AME answers questions such as:

> “What should this MIDI event mean?”

The Musical Engine answers questions such as:

> “When should this action occur musically?”

---

# 3. Architectural decisions that are already locked

Do **not** casually redesign the following.

## 3.1 AuroraMusical remains independent

`AuroraMusical` must remain free of:

- CoreMIDI
- AME model types
- UI frameworks
- app-specific lighting execution logic

It owns musical timing concepts and scheduling contracts.

---

## 3.2 Timing state and show context are separate

Musical timing state and show/song/section context are intentionally separate concerns.

Do not collapse them into one mega-state object.

---

## 3.3 Monotonic time is authoritative

Live MIDI timing must use monotonic host time.

Do not reintroduce:

```swift
Date().timeIntervalSince1970
```

as the timing authority for MIDI ingress, scheduling, phase estimation, or latency measurement.

Wall-clock time is acceptable only for human-readable logging.

---

## 3.4 MIDI Real-Time parsing rules are settled

The parser must continue to support:

- F8 MIDI Clock
- FA Start
- FB Continue
- FC Stop
- FE Active Sensing
- FF System Reset
- realtime bytes interleaved inside channel/system-common messages
- SPP as **System Common**, not System Real-Time
- Note On velocity 0 normalization to Note Off

Realtime bytes must not disrupt running status or pending ordinary messages.

---

## 3.5 External clock authority begins only after lock

A single stray F8 must **not** steal timing authority.

External MIDI Clock becomes authoritative only after sufficient estimator confidence/lock.

Loss/reacquisition behavior must reset estimator state correctly.

---

## 3.6 AME dry-run and live state are separate domains

Dry-run/test activity must not contaminate armed/live runtime state.

Examples:

- held controls
- toggles
- sequence state
- random state

must not leak from dry-run into armed mode.

---

## 3.7 Held-control release semantics are safety-critical

Physical release must not be blocked by:

- debounce
- burst suppression
- scope changes
- timing availability
- section transitions
- quantization

A hold acquired from Note On must be safely releasable from Note Off.

Release actions are snapshotted when the hold is acquired.

---

## 3.8 Safety actions bypass quantization

Safety-critical actions must execute immediately.

Examples include the established panic/blackout-style safety path.

Do not allow a public API path that can place a safety action behind a future musical boundary.

---

## 3.9 Scheduler access is mediated by MusicalEngine

The scheduler is an implementation detail.

Callers should schedule through:

```text
MusicalEngine.schedule(...)
```

rather than reaching directly into a publicly exposed scheduler.

---

## 3.10 AuroraAction is the canonical action vocabulary

AME uses typed `AuroraAction` values.

Do not return to parallel string fields such as:

```text
actionKey
actionParameter
```

as the primary runtime/persistence representation.

`AuroraAction` structured recursive Codable must remain lossless, including nested compound actions.

---

## 3.11 AME persistence remains separate

AME configuration is persisted in its own project package data, including `ame.json`.

Do not merge it back into unrelated legacy MIDI structures.

---

## 3.12 Sequence semantics are deliberate

Important sequence behavior already established:

- `fireThenAdvance` and `advanceThenFire` must remain behaviorally distinct.
- sequence RNG is deterministic per sequence/state scope rather than globally coupled.
- reset policy is the sequence's single source of truth.
- state scope is explicit, not a vague shared boolean.

---

# 4. Work completed and reviewed

The AME + Musical Engine effort progressed through phases A–I and later a six-wave integration remediation.

The important result is that the core architecture is now considered healthy.

## Phase A

Established:

- musical model contracts
- metrical structure
- typed actions
- recursive action persistence
- monotonic MIDI ingress timestamping
- AME graph models
- validators
- sequence state contracts
- persistence migration

## Phase B

Established:

- Musical Engine runtime
- internal timing
- transport
- musical position
- scheduler
- quantization contracts
- timing-source policy behavior

## Phase C

Established:

- MIDI Clock timing adapter
- estimator/lock behavior
- Start/Stop/Continue
- SPP
- dropout/freewheel
- external-to-internal fallback
- source admission

Phase C clock behavior has already undergone multiple closeout reviews.

## Phase D

Established:

- AME mapping evaluator
- held/momentary/toggle behavior
- release semantics
- transforms
- action emissions
- timing/quantization bridge

## Phase E

Established:

- triggered sequences
- sequence state
- trigger policies
- deterministic random/weighted behavior
- reset/state-scope semantics

## Phases F–I / Integration Waves

Later work added:

- AME editor
- AME Learn
- production MIDI Clock wiring
- project timing configuration
- high-resolution Musical Engine runtime driver
- generalized AuroraAction execution
- quantized payload snapshotting
- song/section integration
- mapping-set activation
- source disconnect unwinding
- diagnostics and reliability scaffolding

---

# 5. Previously discovered full-stack bugs that should remain fixed

When reviewing current code, verify these do not regress.

## 5.1 Live MIDI Clock must reach MusicalEngine

Production `InputController` / show-control composition must keep a full ingress handler alive for:

- F8
- Start
- Stop
- Continue
- SPP

This timing path must remain independent of channel-voice Learn/performance handlers.

AME Learn must not starve MIDI Clock.

---

## 5.2 Musical scheduling must not run from UI timers

MusicalEngine scheduling must use its dedicated high-resolution runtime driver.

Do not reintroduce:

```text
250 ms
4 Hz
UI/status timer
```

as the execution cadence for quantized musical work.

Opening or closing the AME window must not affect timing accuracy.

---

## 5.3 `holdUntilTimingAvailable` must actually hold

AME should forward the scheduling intent downstream.

MusicalEngine owns the temporal hold.

When timing becomes unavailable:

```text
holdUntilTimingAvailable
```

must not silently drop the event.

---

## 5.4 Quantized payloads must preserve trigger-time meaning

Scheduled payloads must retain, as appropriate:

- `AuroraAction`
- control value / velocity / CC value
- ingress HostTime
- mapping/provenance identity
- fixture selection snapshot for selection-relative actions

Changing fixture selection before the musical boundary must not redirect the already-scheduled action.

---

## 5.5 Immediate and quantized execution use the same action executor

Immediate AME actions must not fall back through an old `ShowAction`-only path.

The same `AuroraAction` must have consistent semantics whether:

- immediate
- quantized
- section lifecycle driven

---

## 5.6 Song metadata must not overwrite project defaults

The Musical Engine already has layered provenance.

Project defaults must remain the actual project defaults.

Do not implement song changes by doing something like:

```text
setProjectDefaults(songTempo, songMeter)
```

Song tempo/meter belong in song/show context.

Example expected behavior:

```text
Project default: 96 BPM
Song A override: 110 BPM
Song B override: none

Song A => 110 BPM
Song B => 96 BPM
```

Not 120 BPM and not the previous song's tempo.

---

## 5.7 Source disconnect must unwind live state

Disconnecting a MIDI source must unwind the held/toggle state owned by that source only.

Do not release unrelated devices' state.

Do not leave a toggle ON because its originating controller vanished.

---

## 5.8 Project edits must not reset the timing engine

A major bug found in the previous pass was non-idempotent Musical Engine configuration application.

Unrelated project commands such as:

- rename cue
- edit AME label
- move unrelated document data

must **not** unnecessarily reapply timing-source policy, reset external authority, or trigger scheduler timing-loss policies.

Configuration application should be:

- diff-based, or
- rigorously idempotent

for unchanged timing configuration.

---

# 6. Current pre-hardware issues that still require correction

These are the two remaining code issues identified in the latest Pass 3 review.

---

## P0-1 — Timing policy re-entry can lose the selected external source

### Failure sequence

A configuration like:

```text
policy = external MIDI
selected source = uid:12345
```

works.

Then:

```text
external MIDI
    ↓
internal only
    ↓
external MIDI
```

can leave the Musical Engine's internal selected-source state as:

```text
"internal"
```

while the host-side persisted/configured external binding still points to:

```text
uid:12345
```

If the host's configuration diff decides that the external source value itself has not changed, it may skip calling the source-selection API again.

Result:

- UI/configuration says external source is `uid:12345`
- MusicalEngine still thinks selected source is `"internal"`
- real MIDI clock events from the configured device are not admitted as expected

### Required invariant

After applying configuration:

```text
engine timing policy
engine selected external source
host persisted musical settings
```

must describe the same state.

### Required fix

When timing policy transitions into a mode requiring or permitting an external source:

```text
.externalMIDI
.externalPreferredFallback
```

the configured external source must be re-applied even if the stored binding ID/source ID itself did not change.

Alternatively, make the configuration application function derive the complete desired state and reconcile the engine atomically.

Do not rely on a comparison of only the external-source field.

### Mandatory tests

Add tests for:

```text
external(A) → internalOnly → external(A)
external(A) → preferredFallback → external(A)
internalOnly → external(A)
external(A) → internalOnly → preferredFallback(A)
external(A) → external(B)
```

Verify both:

- policy
- selected source identity

after each transition.

Also verify live source admission after each transition.

---

## P1-1 — AME Learn must persist a durable identity for non-UID MIDI sources

CoreMIDI UniqueID is the preferred durable identity where available.

The problem is endpoints that do not provide a useful UniqueID.

Current Learn behavior can fall back to storing something resembling:

```text
ep:4242
```

inside a name-hint field.

That is not a durable human/device identity.

Endpoint references are runtime topology identifiers and can change after:

- reconnect
- CoreMIDI graph rebuild
- application restart
- RTP-MIDI session recreation

Example:

```text
Learn:
  sourceID = ep:4242

Reconnect:
  same device = ep:900

Persisted binding no longer resolves.
```

### Required behavior

For a source with CoreMIDI UniqueID:

```text
persist UID
persist display name as hint
```

For a source without a durable UID:

```text
persist stable descriptive source metadata
```

At minimum this should include the CoreMIDI display/source name rather than an `ep:` token pretending to be a name.

If practical, persist a small identity descriptor such as:

```swift
struct MIDISourceBinding {
    var lastCoreMIDIUniqueID: Int32?
    var displayNameHint: String?
    var manufacturerHint: String?
    var modelHint: String?
}
```

Do not overbuild device fingerprinting if CoreMIDI does not expose reliable fields.

### Resolution precedence

Recommended:

```text
1. CoreMIDI UniqueID exact match
2. durable metadata/name fallback
3. unresolved + explicit diagnostic
```

Do not silently bind a same-named device if multiple candidates are ambiguous.

### Mandatory tests

- UID source survives endpoint-reference change
- non-UID source resolves by persisted display metadata after endpoint-reference change
- duplicate-name fallback is diagnosed as ambiguous
- Learn never stores literal `ep:####` as a display-name hint
- RTP-MIDI-like reconnect scenario resolves correctly when available metadata permits it

---

# 7. Clean shipping-app build is mandatory

The last reviewed archive contained a recorded Xcode build failure where:

```text
AuroraActionExecutor.swift
```

was not visible to the Aurora app target.

The current project file appeared to include the missing source afterward, suggesting the log may predate a project regeneration/fix.

Do not assume this is solved.

Before Wave 6:

1. Clean derived data if appropriate.
2. Regenerate the project if Aurora's workflow requires it.
3. Build the actual Aurora macOS app target.
4. Run the complete macOS test suite.
5. Record results in the checkpoint.

The acceptance criterion is not merely:

```text
AuroraMusical builds
```

It is:

```text
The shipping Aurora application builds successfully.
```

---

# 8. Fresh code-review instructions for Codex

After fixing the two known issues, perform a fresh end-to-end review rather than only checking the requested patches.

Focus especially on the following.

## 8.1 Timing authority

Check:

- internal-only policy
- strict external MIDI policy
- preferred external with fallback
- selected-source changes
- source disconnect/reconnect
- single stray F8
- estimator lock
- freewheel
- fallback to project/song internal tempo
- reacquisition
- Start/Stop/Continue
- SPP + Continue

No stale estimator/source state should survive a source replacement.

---

## 8.2 Quantized scheduling

Check:

- immediate
- next beat
- metrical beat
- bar
- subdivisions
- compound/asymmetric meter
- failure policy `.cancel`
- `.executeImmediately`
- `.holdUntilTimingAvailable`
- transport stop
- timing loss
- tempo change while queued
- source switch while queued

Ensure timing behavior is independent of the AME/UI window lifecycle.

---

## 8.3 AME held/toggle lifecycle

Test adversarially:

```text
Note On
section changes
timing disappears
device disconnects
document changes
mode changes
Note Off
```

The control must unwind safely.

Also test:

- repeated Note On before Note Off
- velocity-zero Note On
- dry-run → armed
- armed → dry-run/edit
- source A and source B simultaneously holding controls

---

## 8.4 Sequence behavior

Verify:

- fireThenAdvance
- advanceThenFire
- random
- weighted random
- reset-on-song
- reset-on-section
- manual reset
- per-song/per-section/global state scopes
- deterministic per-sequence RNG
- no cross-sequence random coupling
- invalid/out-of-range requested step does not silently fire another step

---

## 8.5 Generalized action execution

For every `AuroraAction` case:

- execute correctly, or
- explicitly report unsupported

Never report “supported/executed” while optional chaining or placeholder behavior causes a no-op.

Immediate and quantized paths must agree.

Compound actions must preserve order.

---

## 8.6 Song/section context

Normal product navigation must update AME context.

Test:

- load song
- next song
- previous song
- enter section
- next section
- previous section
- section transition lifecycle
- song with tempo override
- song without tempo override
- project default restoration

AME context must not require test-only APIs.

---

## 8.7 Mapping-set activation

Locked semantic contract:

> Normal scope establishes the ordinary active mapping population. `localMappingIDs` and `mappingSetIDs` add mappings to that population. They do not silently replace ordinary scoped mappings.

Then inheritance/override/disable resolution runs over the effective candidate set.

Verify this remains true.

---

## 8.8 Editor and Learn

The shipping AME editor should allow the user to configure the practical feature set without editing JSON.

Review support for:

- create
- delete
- duplicate
- undo/redo
- triggers
- mappings
- scope
- behavior
- actions
- release actions
- control/value transform
- quantization
- timing failure policy
- sequence configuration
- sequence steps
- source bindings
- debounce/burst
- inheritance/override/disable
- validation navigation
- MIDI Learn
- live match highlighting

Do not require a giant node-graph UI if the command-backed inspector workflow is functional.

---

# 9. Wave 6 is a hardware acceptance phase

After software closeout, do not simply mark the track complete.

Wave 6 must be run with real hardware / real macOS MIDI topology.

Recommended hardware matrix:

## MIDI Clock

- local hardware clock
- RTP-MIDI clock
- stable clock
- tempo changes
- dense notes + clock
- dropout
- reconnect
- Start
- Stop
- Continue
- SPP + Continue
- source switch
- source disappears while selected

## Drum/performance MIDI

- rapid snare rolls
- kick/snare simultaneously
- dense fills
- velocity extremes
- repeated Note On without Note Off
- Note On velocity 0
- choke/note-off behavior
- multiple devices using same notes/channels
- unplug while held
- unplug while toggle is active

## Long run

Run a representative show-length soak.

Observe:

- scheduler pending count
- held scheduler count
- action token registry count
- AME held count
- AME toggle count
- diagnostics/ring buffer size
- timing latency
- sequence state

Confirm:

- no unbounded growth
- no accumulating timing latency
- no stuck held controls
- no sequence drift
- no source-state contamination
- no memory/CPU escalation attributable to AME/Musical Engine

---

# 10. Final acceptance scenario

The AME + Musical Engine track is complete only when a real user can perform a scenario roughly equivalent to this through the shipping UI:

1. Open Aurora.
2. Load a project.
3. Open AME editor.
4. Start Learn.
5. Hit a real snare pad.
6. Aurora learns the source/note.
7. Create or associate an AME mapping.
8. Attach a multi-step sequence.
9. Scope it to a song/section.
10. Set musical quantization, e.g. next eighth.
11. Select an external MIDI Clock source.
12. Start real external clock.
13. Enter the song/section normally through the product UI.
14. Hit the snare repeatedly.
15. Sequence advances with musically quantized execution.
16. Change tempo externally.
17. Quantized actions continue correctly.
18. Test clock dropout and the configured failure policy.
19. Hold a live momentary control.
20. Physically unplug its MIDI source.
21. The held state unwinds safely.
22. Leave the section and verify lifecycle/reset behavior.
23. Run long enough to verify bounded runtime state.

If any essential step requires:

- hand-editing JSON
- test-only APIs
- direct internal object mutation
- opening a debug-only window

the product integration is not yet complete.

---

# 11. Expected Codex deliverables

For each review/fix cycle, Codex should produce:

1. **Code changes**
2. **Tests**
3. **Build/test results**
4. **A concise review summary**
5. **Any remaining blockers**
6. **Updated checkpoint documentation**

When something is intentionally deferred, state explicitly:

```text
SUPPORTED
UNSUPPORTED
DEFERRED
```

Do not allow “partial” support to masquerade as successful execution.

---

# 12. Review severity model

Use:

## P0 — Blocker

Could cause:

- stuck live output
- incorrect safety behavior
- timing authority failure
- major quantization failure
- silent live no-op reported as success
- corrupted persistence
- app build failure

Must fix before Wave 6.

## P1 — Required closeout

Material product defect or incomplete accepted scope.

Fix before calling the AME/Musical Engine track complete.

## P2 — Hardening / polish

Does not block hardware validation unless it affects observability or testability.

---

# 13. Do not broaden scope unnecessarily

Out of scope for this closeout unless required by a discovered bug:

- Ableton Link
- audio beat detection
- MTC
- replacing legacy MIDI mappings entirely
- generalized AI show generation
- large Effects Engine redesign
- giant visual node graph
- unrelated Aurora UX redesign

The task is to finish and validate the system already designed.

---

# 14. Immediate work order for Codex

Perform these in order:

```text
1. Inspect current repo state and relevant checkpoints.
2. Verify shipping Aurora app target builds.
3. Fix timing-policy/source re-entry.
4. Add transition regression tests.
5. Fix durable AME Learn identity for non-UID endpoints.
6. Add reconnect/ambiguity tests.
7. Run full macOS test suite.
8. Perform fresh cross-system review using Section 8.
9. Fix any new P0/P1 findings.
10. Re-run clean app build + tests.
11. Produce pre-hardware acceptance checkpoint.
12. STOP before claiming Wave 6 complete.
```

---

# 15. Current disposition

At handoff time:

```text
Core AME architecture             ACCEPTED
Musical Engine architecture       ACCEPTED
MIDI Clock architecture           ACCEPTED
Quantization core                 ACCEPTED
Held/toggle lifecycle             ACCEPTED
Sequence engine                   ACCEPTED
Song/section integration          ACCEPTED with final verification
AME editor                        IMPLEMENTED, verify completeness
AME Learn                         IMPLEMENTED, one durability fix remains
Timing policy integration         one known re-entry bug remains
Shipping app build                must be freshly verified
Wave 6 hardware acceptance        NOT YET COMPLETE
```

The project is very close to hardware validation.

The remaining work should be treated as a **final software closeout**, not a new design phase.

---

# 16. Guiding principle

Aurora is intended for live performance.

When choosing between:

```text
technically clever
```

and:

```text
deterministic, observable, recoverable, and safe on stage
```

choose the second one every time.

A live-show control system must fail predictably, release safely, preserve musical intent, and tell the operator what happened.
