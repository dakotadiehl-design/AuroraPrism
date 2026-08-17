# Aurora AME + Musical Engine Implementation Plan

## Review Amendments / Required Changes Before Implementation

**Reviewed plan:**
`Advanced MIDI Engine + Musical Engine — Implementation Plan`\
**Disposition:** **Approve with changes below.**\
**Purpose:** Preserve the strong architecture in the proposed plan while
correcting several timing/MIDI details and avoiding architectural debt
before Phase A begins.

------------------------------------------------------------------------

# 1. Overall Assessment

The proposed implementation plan is very strong and is substantially
aligned with the intended Aurora architecture.

The following elements should be retained:

-   Advanced MIDI Engine (AME) and Musical Engine remain separate
    first-class subsystems.
-   MIDI performance events flow through AME rather than directly
    manipulating DMX.
-   Musical timing is provider-independent.
-   Future Effects Engine consumes the Musical Engine rather than
    implementing its own clock.
-   First-class `AuroraAction` becomes the common semantic control
    vocabulary.
-   Song sections become first-class IDs rather than string-only
    context.
-   Trigger groups, mapping sets, stateful sequences, inheritance,
    simulation, diagnostics, and the dedicated MIDI Engine window remain
    core requirements.
-   Existing MIDI behavior/envelope infrastructure is migrated rather
    than discarded.
-   The phased STOP/checkpoint implementation strategy is excellent and
    should remain.
-   Headless/runtime implementation before full UI is the correct order.

However, several details should be changed **before Phase A**,
particularly around MIDI Clock semantics, musical position, provider
boundaries, scheduler safety, and sequence-event handling.

------------------------------------------------------------------------

# 2. REQUIRED CHANGE: Create a Dedicated `AuroraMusical` Module Now

The plan currently prefers placing timing protocols/state in
`AuroraModel` for v1 and potentially extracting an `AuroraMusical`
target later.

**Change this decision.**

Create the dedicated lightweight **`AuroraMusical` target in Phase A**.

This is foundational infrastructure that is already known to have
multiple future consumers and providers:

-   Internal tempo
-   MIDI Clock
-   AME
-   Future Effects Engine
-   Future show-control integration
-   Future Ableton Link
-   Future audio beat detection
-   Future OSC timing
-   Potential future timecode adapters
-   UI beat/sync visualization

Avoid deliberately creating a dependency that is expected to be
refactored shortly afterward.

Recommended dependency direction:

``` text
AuroraModel
    ↑
AuroraMusical
    ↑        ↑
AuroraMIDI   AuroraEngine
      \       /
       Aurora App / Core wiring
```

More precisely:

``` text
AuroraModel
    │
    ├──────────────► AuroraMusical
    │                    │
    │                    ├────────► AuroraEngine
    │                    │
    │                    └────────► consumers
    │
    └──────────────► AuroraMIDI
                         │
                         └── MIDI timing adapter feeds AuroraMusical
```

The exact SwiftPM graph may need adjustment based on existing target
relationships, but the architectural rule is:

> **Do not put active timing/provider protocols into AuroraModel merely
> to solve a dependency cycle.**

`AuroraModel` should remain primarily persisted/project-domain data.

`AuroraMusical` should own:

-   `MusicalEngine`
-   `MusicalState`
-   `MusicalTransport`
-   `MusicalSyncState`
-   `MusicalUnit`
-   `MusicalPosition`
-   `TimingProvider` protocol
-   Timing source capabilities
-   Internal timing source
-   Musical scheduler
-   Subdivision/grid math
-   Clock estimator abstractions
-   Test/virtual clock support

`AuroraMIDI` should own the CoreMIDI-specific adapter that translates
MIDI timing messages into canonical Musical Engine timing events.

This boundary will matter greatly when the Effects Engine arrives.

------------------------------------------------------------------------

# 3. REQUIRED CHANGE: Do Not Treat Song Position Pointer as a MIDI Realtime Message

The proposed:

``` swift
enum MIDIIngressEvent {
    case performance(MIDIEvent)
    case realtime(MIDIRealtimeEvent)
}
```

is directionally useful but technically incomplete.

MIDI Clock (`0xF8`), Start (`0xFA`), Continue (`0xFB`), and Stop
(`0xFC`) are **System Real-Time** messages.

**Song Position Pointer (`0xF2`) is a System Common message, not System
Real-Time.**

Therefore use a broader normalized ingress model, for example:

``` swift
enum MIDIIngressEvent: Sendable {
    case channelVoice(MIDIChannelVoiceEvent)
    case systemRealtime(MIDISystemRealtimeEvent)
    case systemCommon(MIDISystemCommonEvent)
}
```

or another equivalent strongly typed representation.

At minimum:

``` text
System Real-Time:
- Timing Clock
- Start
- Continue
- Stop
- Active Sensing
- System Reset

System Common:
- Song Position Pointer
- Song Select if ever needed
- Tune Request if ever needed
```

Do not build an abstraction that incorrectly places SPP inside
`MIDIRealtimeEvent`.

------------------------------------------------------------------------

# 4. REQUIRED CHANGE: MIDI Parser Must Correctly Handle Interleaved Real-Time Bytes

This needs to become an explicit parser acceptance requirement.

MIDI System Real-Time bytes may appear **between bytes of another MIDI
message** without disrupting that message.

Example conceptually:

``` text
Status
Data
Clock
Data
```

The Clock byte must be emitted immediately while the surrounding message
continues parsing correctly.

This is especially important for:

-   MIDI Clock reliability
-   Running status
-   Dense drum/controller traffic
-   RTP-MIDI streams
-   Real-world hardware behavior

Add parser tests covering:

1.  Clock between Note On data bytes.
2.  Clock during running-status streams.
3.  Multiple clocks interspersed with channel voice data.
4.  Start/Stop/Continue interleaving.
5.  SPP parsing alongside real-time interleaving.
6.  Malformed/incomplete system-common messages without poisoning
    subsequent parsing.

This is a **Phase A/C correctness requirement**, not optional hardening.

------------------------------------------------------------------------

# 5. REQUIRED CHANGE: Make SPP Support a V1 Requirement

The current plan says:

> SPP optional for v1 if Start/Continue enough.

Change this.

**Parse and consume Song Position Pointer in v1.**

Aurora is explicitly being architected for future external
show-management control. Musical position therefore matters beyond
merely calculating BPM.

SPP does not need an elaborate UI in v1, but the Musical Engine should
be capable of accepting position information from the MIDI timing
adapter.

MIDI Song Position Pointer represents position in **MIDI beats of six
MIDI clocks each**, equivalent to sixteenth-note units under standard
MIDI Clock.

The Musical Engine should normalize this into its own position
representation rather than leaking MIDI-specific units downstream.

------------------------------------------------------------------------

# 6. REQUIRED CHANGE: Explicitly Separate Clock Pulse, Quarter Note, Metrical Beat, and Bar

This is one of the most important amendments.

The current plan uses terms such as:

-   beat
-   quarter note
-   musical unit
-   beat index
-   6/8 meter

These can become ambiguous.

MIDI Clock is always:

> **24 pulses per quarter note**

It does **not** inherently know that the perceived beat in 6/8 may be a
dotted quarter.

Therefore Aurora must distinguish:

### Clock domain

-   MIDI clock pulse
-   quarter-note position
-   absolute quarter-note phase

### Musical grid domain

-   note subdivisions: 1/32, 1/16, 1/8, 1/4, 1/2, whole
-   dotted values
-   triplet values

### Meter domain

-   numerator
-   denominator
-   bar position
-   beat grouping / beat unit where applicable

For example, in 6/8:

``` text
Meter: 6/8
MIDI clock: still 24 PPQN
Eighth-note grid: derived normally
Common compound-meter pulse: dotted quarter
Bar: six eighth-note denominator units
```

Do not assume:

``` text
1 beat == 1 quarter note
```

throughout the implementation.

Recommended model concepts:

``` text
MusicalDuration
MusicalGridUnit
Meter
BeatGrouping / BeatUnit
QuarterNotePosition
BarBeatPosition
```

This is critical for the future Effects Engine.

A user may want:

-   chase every eighth note
-   pulse every quarter note
-   movement cycle every dotted quarter
-   color fan every bar

Those must remain mathematically unambiguous in 3/4, 4/4, 5/4, 6/8,
12/8, etc.

------------------------------------------------------------------------

# 7. REQUIRED CHANGE: MIDI Clock Does Not Supply Bar/Meter Information

The Musical Engine must never infer meter or bar boundaries solely from
MIDI Clock.

MIDI Clock provides timing pulses. Start/Continue/Stop provide
transport. SPP can provide musical position in MIDI sixteenth-note
units.

Meter must come from another source, such as:

-   Aurora song metadata
-   Aurora project/default configuration
-   Future show-control metadata
-   Future richer synchronization provider

Therefore:

> MIDI Clock supplies rhythmic timing and transport, while Aurora's
> Musical Engine combines that timing with known meter/context to derive
> bars and metrical beat positions.

If meter is unknown, expose it as unknown/default-configured rather than
claiming the external MIDI source supplied it.

Diagnostics should distinguish:

``` text
Timing source: External MIDI Clock
Tempo: 118.4 BPM
Clock: Locked
Transport: Running
Meter source: Song metadata (4/4)
Position source: SPP
```

This source provenance will be extremely useful later.

------------------------------------------------------------------------

# 8. REQUIRED CHANGE: Tap Tempo Should Not Be a Peer Continuous Timing Provider

The current plan lists:

-   InternalTempoProvider
-   TapTempoProvider
-   MIDIClockProvider

as equivalent providers.

Change the conceptual model.

**Tap Tempo is an input mechanism for estimating/updating the internal
tempo. It is not normally a continuous timing source.**

Recommended:

``` text
Tap input
   ↓
TapTempoEstimator
   ↓
updates Internal Timing Source BPM
   ↓
Musical Engine
```

This produces cleaner semantics.

Initial timing sources should therefore be:

1.  **Internal Timing Source**
2.  **External MIDI Clock Source**

Tap Tempo modifies the Internal source.

Future sources can include:

-   Ableton Link
-   Audio Beat Detection
-   OSC/show-control timing
-   Timecode-derived position source where appropriate

AME actions may still include:

``` text
tapTempo
```

but that action feeds the tap estimator/internal timing source.

------------------------------------------------------------------------

# 9. REQUIRED CHANGE: Clarify Source Selection vs Source Health/Fallback

Do not allow timing-provider switching to become implicit or surprising
during a live show.

Model these separately:

### User policy

``` text
Internal
External MIDI
External MIDI Preferred + Internal Fallback
```

### Runtime state

``` text
Selected source
Active source
Source health
Sync state
Fallback state
```

Example:

``` text
Policy: External Preferred
Selected External Source: Drum Module
Active Source: Drum Module
Sync: Locked
Fallback: Armed
```

After dropout:

``` text
Policy: External Preferred
Selected External Source: Drum Module
Active Source: Internal Freewheel
Sync: External Lost / Freewheeling
Fallback: Pending
```

Then:

``` text
Active Source: Song Internal Tempo
Sync: Fallback
```

The UI must never merely continue displaying `118 BPM / Locked` after
silently changing masters.

------------------------------------------------------------------------

# 10. REQUIRED CHANGE: Revisit Clock Smoothing / PLL Design

Do not lock the implementation to a simple EMA plus a fixed `±8 BPM/s`
slew cap in the plan.

Those values are acceptable as experimental starting points, but should
not become architectural constants before hardware testing.

The Musical Engine should instead expose a dedicated **clock estimator /
phase-lock component** with testable policy parameters.

It must optimize for two competing goals:

1.  Reject normal MIDI-clock jitter.
2.  Follow legitimate tempo changes and ramps without lagging
    excessively.

The implementation should track both:

-   **tempo estimate**
-   **phase estimate**

Tempo smoothing alone is insufficient. Effects must remain phase-stable.

Add tests for:

-   fixed 120 BPM with random jitter
-   sudden tempo jump
-   gradual accelerando
-   gradual ritardando
-   burst jitter
-   missing single pulses
-   missing several pulses
-   recovery after dropout
-   re-lock with phase offset

The exact smoothing constants should be tuned after synthetic tests and
real MIDI hardware testing.

------------------------------------------------------------------------

# 11. REQUIRED CHANGE: Define Start / Continue / Stop Semantics Precisely

These should not be left as generic transport commands.

Define explicit behavior:

### MIDI Start

-   Set transport to running.
-   Establish/reset musical position to the start origin unless a
    clearly defined pending position rule says otherwise.
-   Reset phase origin deterministically.
-   Notify consumers of a transport discontinuity.

### MIDI Stop

-   Set transport stopped.
-   Preserve the last known position unless project policy explicitly
    resets it.
-   Resolve/cancel/hold quantized scheduled actions according to policy.
-   Do not destroy AME sequence state unless the sequence reset policy
    says to do so.

### MIDI Continue

-   Resume from the current/last established musical position.
-   If an SPP was received before Continue, resume from that position.
-   Do not behave identically to Start.

### SPP

-   Update normalized musical position.
-   Define whether SPP received while running causes immediate
    reposition, queued reposition, or provider-defined behavior.
-   Emit a discontinuity/seek diagnostic when position jumps.

This matters for future show-control integration.

------------------------------------------------------------------------

# 12. REQUIRED CHANGE: Introduce Explicit Musical Discontinuity / Seek Events

Consumers need to know when time did not merely advance normally.

Examples:

-   MIDI Start reset
-   SPP jump
-   external source re-lock with large phase correction
-   future show-control seek
-   future timecode locate

Add a semantic event such as:

``` text
MusicalTimelineEvent
  .started
  .stopped
  .continued
  .positionJumped(old:new:)
  .sourceChanged
  .syncLost
  .syncRecovered
```

The future Effects Engine will need to distinguish:

> "time advanced to here"

from:

> "the show just jumped to here."

Otherwise stateful effects can behave unpredictably after seeks.

------------------------------------------------------------------------

# 13. REQUIRED CHANGE: Scheduler Must Use Typed Commands, Not Arbitrary Closures

The conceptual scheduler currently allows:

``` text
schedule(actionID or closure token, ...)
```

For the live-show control path, prefer typed, inspectable scheduled
commands/actions.

For example:

``` text
ScheduledMusicalAction {
    id
    targetBoundary
    action: AuroraAction
    origin
    cancellationPolicy
}
```

or a typed internal token resolving to an action.

Avoid arbitrary closures in the canonical scheduler because they are:

-   difficult to diagnose
-   difficult to serialize/inspect
-   difficult to cancel selectively
-   harder to test
-   potentially capable of capturing unsafe state

The scheduler should provide stable IDs so AME, diagnostics, UI, and
future show control can cancel or inspect pending work.

------------------------------------------------------------------------

# 14. REQUIRED CHANGE: Do Not "Drop Oldest" Scheduled Musical Actions on Queue Overflow

The proposed scheduler says:

> bounded queue (e.g. 256); drop oldest with diagnostic if overrun

Change this policy.

Dropping the **oldest** scheduled event can remove the event closest to
execution and create extremely confusing show behavior.

Preferred policy:

1.  Scheduler has a bounded capacity.
2.  Normal operation should never approach the bound.
3.  If capacity is exceeded, **reject the newly requested scheduled
    action** and emit a high-severity diagnostic.
4.  Safety-critical actions such as panic/blackout/stop must bypass or
    have reserved capacity and must never be rejected behind decorative
    events.
5.  Consider priority classes if required.

The system should fail visibly and deterministically rather than
silently deleting previously accepted work.

------------------------------------------------------------------------

# 15. REQUIRED CHANGE: Define Safety Actions Outside Normal Quantization

Certain actions must never wait for a musical boundary.

At minimum:

-   Panic
-   Blackout where used as emergency/safety control
-   Stop all output / emergency stop semantics
-   Clear dangerous temporary override if applicable

must execute immediately regardless of mapping quantization.

If a user configures a mapping with quantization and then selects a
safety action, Aurora should either:

-   force immediate execution, or
-   reject the incompatible configuration.

Do not permit an emergency action to wait for "next bar."

------------------------------------------------------------------------

# 16. REQUIRED CHANGE: Do Not Default to Coalescing Simultaneous Drum Hits

The sequence-runtime proposal says:

> coalesced same-timestamp group advances once if mapping is group-based

This is too aggressive as a default.

For the intended **Any Drum Hit** use case:

> every qualifying drum strike should normally advance the sequence.

A kick and snare played together may intentionally represent two musical
strikes/events, and timestamp equality/near-equality can also be an
artifact of packet batching.

Recommended default:

> **One normalized qualifying Note On event = one trigger/advance.**

Then provide optional conditioning:

``` text
Burst suppression / coalesce window
```

for users who intentionally want near-simultaneous hits treated as one
event.

This should be explicit and configurable, not inferred from timestamps.

------------------------------------------------------------------------

# 17. REQUIRED CHANGE: Note-On Velocity Zero Must Normalize to Note-Off Semantics

Add this explicitly to MIDI normalization tests.

Many MIDI devices represent Note Off as:

``` text
Note On with velocity 0
```

AME behaviors such as:

-   momentary
-   whileHeld
-   gates

must treat this correctly.

Normalization should ensure downstream AME logic does not need
device-specific handling.

------------------------------------------------------------------------

# 18. REQUIRED CHANGE: Define Held-State Identity Correctly

For momentary/while-held behavior, held-state keys should include enough
identity to prevent collisions.

At minimum consider:

``` text
source binding
channel
note/controller identity
mapping/trigger identity where necessary
```

A Note Off from one source must not release a held action initiated by
an unrelated source merely because both use Note 38.

Also define behavior for:

-   source disconnect while notes are held
-   MIDI Stop
-   project close
-   performance mode disable
-   panic

There must be a deterministic **release-all-held-state** path to prevent
stuck lighting overrides.

------------------------------------------------------------------------

# 19. REQUIRED CHANGE: Add Explicit Event Timestamps at Ingress

Every normalized MIDI ingress event should carry a monotonic timestamp
as close to receipt as possible.

Do not assign timestamps later in AME evaluation.

This timestamp should flow through:

``` text
MIDI ingress
→ normalized event
→ trigger evaluation
→ sequence/action scheduling
→ diagnostics
```

This enables:

-   accurate latency measurement
-   correct ordering
-   jitter analysis
-   deterministic tests
-   future performance profiling

Where CoreMIDI supplies useful packet timestamps, preserve/normalize
them appropriately.

------------------------------------------------------------------------

# 20. REQUIRED CHANGE: Add End-to-End Latency Instrumentation

Because this is a live-performance feature, diagnostics should
eventually be able to report:

``` text
MIDI received
→ mapping matched
→ action dispatched
→ lighting engine accepted
```

Add timestamps/IDs sufficient to calculate event-to-action latency.

The UI does not need to display a giant latency dashboard in v1, but
diagnostic infrastructure should support it.

A drum-triggered lighting accent that is logically correct but
perceptibly late is still a failed feature.

------------------------------------------------------------------------

# 21. REQUIRED CHANGE: Clarify `Global` vs `Project`

The plan currently resolves Show == Project but still lists:

``` text
global | project | song | section
```

Define the distinction explicitly.

Recommended:

### Global

Application/user-library mappings available across projects, if Aurora
actually intends to support such a concept.

### Project

Mappings stored in the current Aurora show/project.

If cross-project global mappings are **not** being implemented in v1,
remove `global` from the persisted scope enum for now rather than
creating a fake distinction.

A simpler v1 hierarchy may be:

``` text
Project → Song → Section
```

with reusable Mapping Sets stored in the project/library as appropriate.

Do not introduce two scopes that behave identically.

------------------------------------------------------------------------

# 22. REQUIRED CHANGE: Avoid Automatic Song-Section Migration That Changes Show Semantics

The plan proposes:

> synthesize sections from unique non-empty `SongEntry.label`s in order

This may be useful, but should not happen blindly if `SongEntry.label`
historically means something other than a true structural song section.

Migration must preserve existing show behavior.

Recommended:

-   Existing projects load with a default `Main` section unless labels
    can be proven to represent section structure safely.
-   Optionally offer a migration helper that proposes sections from
    labels.
-   Do not silently reinterpret arbitrary cue-entry labels as
    authoritative song structure.

Phase A should audit actual existing `SongEntry.label` usage before
choosing the migration.

------------------------------------------------------------------------

# 23. REQUIRED CHANGE: Keep Structural Show Context Distinct from Timing Source Data

`activeSongID` and `activeSectionID` may appear in `MusicalState` for
consumer convenience, but they are not timing-provider properties.

Do not allow a MIDI Clock provider to own or mutate them.

Recommended conceptual separation:

``` text
MusicalTimingState
  tempo
  phase
  position
  meter
  transport
  sync

ShowMusicalContext
  activeSongID
  activeSectionID
  song tempo metadata
  meter metadata
```

The public Musical Engine snapshot may combine them:

``` text
MusicalState {
    timing
    context
}
```

but their ownership remains distinct.

This will make future show-management integration much cleaner.

------------------------------------------------------------------------

# 24. REQUIRED CHANGE: Define Section Transition Ordering

The plan says sequence reset should run before `onEnter` lighting
actions, which is good.

Make the entire transition atomic and deterministic.

Recommended ordering:

``` text
1. Begin section transition
2. Execute old section onExit actions
3. Update active section context
4. Resolve new mapping inheritance
5. Apply sequence reset/arming policies
6. Execute new section onEnter actions
7. Publish final section-change snapshot/event
```

Clarify whether actions generated during `onExit`/`onEnter` are
immediate or may themselves request quantization.

AME must never briefly evaluate an incoming MIDI event against a
half-transitioned section state.

Use serialized control-plane execution.

------------------------------------------------------------------------

# 25. REQUIRED CHANGE: Define Mapping Claim / Legacy Double-Fire Behavior Before Phase D

The plan correctly identifies the risk:

> legacy + AME dual evaluation double-fire

Do not leave this merely configurable at runtime without deterministic
migration rules.

Phase A should establish an explicit compatibility policy, for example:

1.  Existing legacy mappings continue to execute through the legacy
    path.
2.  Newly created AME mappings execute only through AME.
3.  Migrated legacy mapping receives a stable migration ID.
4.  Once migrated/claimed by AME, the legacy representation is
    suppressed.
5.  Diagnostics indicate which engine claimed the event.

Avoid heuristic "AME matched something, therefore suppress all legacy
mappings for that MIDI event," because one physical MIDI event may
legitimately drive independent legacy and AME actions during migration.

Suppression should be based on mapping identity/migration ownership, not
merely event identity.

------------------------------------------------------------------------

# 26. REQUIRED CHANGE: Sequence Random Modes Need Deterministic Testability

For:

-   random
-   weighted random
-   shuffle bag

inject the random-number generator / seed.

Tests must be deterministic.

Runtime may use a production RNG, but the sequence engine should accept
an RNG abstraction or seedable generator in tests.

This also makes future show reproduction/debugging possible.

------------------------------------------------------------------------

# 27. REQUIRED CHANGE: First-Trigger Policy Enum Needs Cleanup

The proposed values:

``` text
fireCurrentThenAdvance
advanceThenFire
fireStep0
```

contain overlapping semantics.

Prefer a clearer definition such as:

``` text
enum SequenceTriggerPolicy {
    case fireThenAdvance
    case advanceThenFire
}
```

with explicit initial index/state.

For the default:

``` text
initialIndex = 0
policy = fireThenAdvance
```

First hit fires Step 0, then prepares Step 1.

Keep runtime state semantics simple enough that diagnostics can always
answer:

``` text
trigger received
fired step 0
next step 1
```

------------------------------------------------------------------------

# 28. REQUIRED CHANGE: Define Sequence Action Failure Semantics

A sequence step may eventually reference:

-   cue
-   preset
-   palette
-   effect
-   compound action

What happens if that object no longer exists?

Do not crash and do not silently advance without diagnostics.

Recommended:

``` text
Missing reference:
- mark sequence/mapping degraded in UI
- emit diagnostic
- do not execute missing action
- define whether sequence advances (recommended: yes for ordinary missing decorative step, configurable later)
```

Project validation should detect broken references before performance.

Add a **Validate AME Configuration** pass before entering performance
mode or as part of project diagnostics.

------------------------------------------------------------------------

# 29. REQUIRED CHANGE: Add Configuration Validation

Before live use, Aurora should be able to identify:

-   unresolved MIDI source bindings
-   missing cue/preset/palette references
-   empty trigger groups
-   mappings referencing deleted sections
-   sequence with zero steps
-   invalid weights
-   impossible transform ranges
-   duplicate/ambiguous overrides
-   unavailable timing source
-   mappings requiring external sync while no source is configured

This may initially be a model/runtime validation API rather than a full
UI.

The AME window can later show warnings/badges.

------------------------------------------------------------------------

# 30. REQUIRED CHANGE: Separate "Sync Required" from Ordinary Mapping Conditions

A mapping condition may say:

``` text
transport running
section == Intro
```

But requiring a locked external clock is operationally different.

Model timing requirements explicitly where useful:

``` text
TimingRequirement
  none
  musicalTimeAvailable
  transportRunning
  externalSyncLocked
```

This makes diagnostics clearer:

> Mapping skipped: external sync required, Musical Engine currently
> freewheeling.

rather than a generic condition failure.

------------------------------------------------------------------------

# 31. REQUIRED CHANGE: Define Behavior When Musical Time Is Unavailable

The current plan contains ambiguity:

> run immediate + warning OR cancel

Resolve this per mapping/action, not globally.

Recommended quantization fallback policy:

``` text
QuantizationFailurePolicy
  cancel
  executeImmediately
  holdUntilTimingAvailable
```

Default:

-   **Creative beat-quantized lighting:** cancel and diagnose.
-   **Noncritical user-triggered actions:** optionally execute
    immediately.
-   **Safety actions:** always immediate and bypass quantization.

Do not hide this behavior in a global engine default.

------------------------------------------------------------------------

# 32. REQUIRED CHANGE: Future Effects Contract Should Be Explicit in Phase B

Although the Effects Engine is out of scope, Phase B should include
tests proving that a generic consumer can:

-   read current tempo
-   read continuous phase
-   determine next subdivision boundary
-   subscribe to transport changes
-   identify source/sync state
-   detect timeline discontinuities
-   schedule work on musical boundaries
-   work identically under Internal and MIDI Clock sources

This is the architectural seam the Effects Engine will depend upon.

Do not wait until Effects implementation to discover that the Musical
Engine only supports AME's needs.

------------------------------------------------------------------------

# 33. REQUIRED CHANGE: Add Provider Capability and Provenance to Individual State Fields Where Needed

A single `sourceCapabilities` flag may be insufficient because different
pieces of state can originate from different places.

Example:

``` text
Tempo/phase: MIDI Clock
Meter: Song metadata
Song/section: Aurora Song Mode
Position: SPP
```

The Musical Engine should preserve enough provenance for diagnostics and
correct reasoning.

This does not require bloating every UI surface. Internally, however, it
should be possible to answer:

> Where did this value come from?

This will become important with future show-control and Link providers.

------------------------------------------------------------------------

# 34. REQUIRED CHANGE: Explicitly Defer MIDI Time Code, Do Not Conflate It with MIDI Clock

Add to the non-goals:

> **MIDI Time Code (MTC) is deferred and is architecturally distinct
> from MIDI Clock.**

MIDI Clock represents musical tempo/beat synchronization.

MTC represents timecode position.

A future Pink Floyd-scale show may eventually use both concepts, but
Aurora must not treat them as interchangeable.

The future timing architecture should allow a time-position provider
without forcing timecode into the beat-clock abstraction.

------------------------------------------------------------------------

# 35. RECOMMENDED CHANGE: Rename "Musical Engine" Types Consistently

The product/subsystem name should remain:

# Musical Engine

Avoid drifting between:

-   Music Engine
-   Beat Engine
-   MIDI timing engine
-   Musical Engine

Use **Musical Engine** consistently in code/docs/UI unless a specific
lower-level component has a narrower name.

------------------------------------------------------------------------

# 36. RECOMMENDED CHANGE: MIDI Engine Window Should Show Musical Source Provenance

The AME toolbar's compact sync chip should eventually be able to
communicate:

``` text
118.4 BPM  •  MIDI LOCKED
```

with detail popover:

``` text
Timing: Drum Module
Transport: Running
Clock: Locked
Meter: 4/4 (Song)
Position: Bar 12 Beat 3 (SPP + Song Meter)
Jitter: 0.7 ms
```

This is especially valuable during live troubleshooting.

------------------------------------------------------------------------

# 37. RECOMMENDED CHANGE: Add a Dedicated "Performance Armed" State

Consider separating:

``` text
MIDI connected
AME enabled
AME performance armed
```

A user may want to edit/test mappings without allowing live hardware
input to alter the running show.

Possible states:

-   **Edit / Monitor:** receive and display MIDI, do not dispatch show
    actions.
-   **Test:** simulation may dispatch to a controlled preview/test path.
-   **Performance Armed:** hardware MIDI mappings may execute live
    Aurora Actions.

This should integrate with existing MIDI safety/performance controls
rather than duplicate them.

Exact UX can be deferred to Phase F, but the runtime concept should be
considered in Phase D.

------------------------------------------------------------------------

# 38. RECOMMENDED CHANGE: Add "Dry Run" Diagnostics Mode

A useful AME diagnostic mode would process:

``` text
incoming MIDI
→ trigger matching
→ conditions
→ transforms
→ sequence decision
```

but stop before dispatching Aurora Actions.

The monitor could show:

> Snare → MFN Intro Drum Sequence → would fire Step 3 "Blue Backlight"

This is extremely useful for safely testing a drum kit while
fixtures/output are not intended to react.

This can share the Performance Armed state described above.

------------------------------------------------------------------------

# 39. RECOMMENDED CHANGE: Preserve Raw MIDI Data in Diagnostics, Not Core Rules

Friendly semantics are excellent:

``` text
Snare
Any Drum Hit
```

But diagnostic records should preserve:

``` text
source
channel
status/message type
data bytes
normalized semantic event
timestamp
```

This gives Aurora both approachable programming and serious
troubleshooting capability.

------------------------------------------------------------------------

# 40. RECOMMENDED CHANGE: Expand Phase I Hardware Test Matrix

Phase I should include real-device tests for at least:

### MIDI Clock

-   stable hardware clock
-   RTP-MIDI clock
-   clock with simultaneous dense note traffic
-   cable/network dropout
-   reconnect
-   Start/Stop/Continue
-   SPP + Continue
-   tempo changes

### Drum performance

-   fast snare rolls
-   kick/snare simultaneous patterns
-   tom fills
-   cymbal choke/note-off behavior if exposed by device
-   velocity extremes
-   repeated Note On without expected Note Off
-   Note On velocity 0
-   multi-device same note/channel collision

### Long run

-   clock + performance MIDI continuously for at least a representative
    rehearsal/show duration
-   diagnostic buffer remains bounded
-   no increasing latency
-   no sequence drift
-   no stuck held states
-   no queue growth

------------------------------------------------------------------------

# 41. UPDATED PHASE PLAN

Keep Grok's A→I structure, but amend it as follows.

## Phase A --- Contracts / Modules / MIDI Semantics

Add:

-   Create `AuroraMusical` target now.
-   Establish typed System Real-Time vs System Common MIDI events.
-   Implement parser correctness for interleaved real-time bytes.
-   Make SPP parsing/model support mandatory.
-   Audit `SongEntry.label` before any automatic section migration.
-   Define legacy-to-AME mapping ownership/claim semantics.
-   Define `MusicalTimingState` vs `ShowMusicalContext`.
-   Define ingress monotonic timestamps.
-   Define validation framework skeleton.

## Phase B --- Musical Engine Core

Add:

-   Explicit quarter-note vs metrical-beat model.
-   Compound-meter tests.
-   Tap tempo as estimator feeding Internal timing source, not peer
    continuous provider.
-   Timeline discontinuity events.
-   Generic future Effects consumer tests.
-   Typed scheduler commands with cancellation IDs.
-   Safe queue-overflow behavior.
-   Field/source provenance where appropriate.

## Phase C --- External MIDI Timing

Add:

-   SPP mandatory.
-   Precise Start/Stop/Continue semantics.
-   Phase-lock/clock estimator abstraction rather than fixed EMA
    architecture.
-   Interleaved clock + dense performance traffic integration tests.
-   Source selection vs active/fallback state.
-   Re-lock/seek/discontinuity tests.

## Phase D --- AME Core

Add:

-   Held-state identity and release-all semantics.
-   Performance armed / dry-run runtime mode.
-   Mapping migration ownership rather than event-wide suppression.
-   Explicit timing requirements.
-   Quantization failure policy.
-   End-to-end latency IDs/timestamps.

## Phase E --- Groups / Sequences

Change:

-   Default: one qualifying MIDI event equals one sequence trigger.
-   No timestamp-based coalescing by default.
-   Optional burst suppression/coalesce policy.
-   Inject deterministic RNG for random modes.
-   Simplify first-trigger policy.
-   Add broken-reference handling and validation.

## Phase F --- AME UX

Add:

-   Performance Armed / Monitor-only status.
-   Dry-run diagnostics option.
-   Timing provenance/details popover.
-   Validation warnings for unresolved sources/broken references.

## Phase G --- Quantization

Add:

-   Safety-action quantization bypass.
-   Per-mapping quantization failure policy.
-   Timeline seek/source-change behavior.
-   Compound-meter subdivision tests.

## Phase H --- Song / Section Integration

Add:

-   Atomic deterministic section-transition ordering.
-   Confirm section migration behavior with real legacy projects.
-   Explicit meter/tempo metadata provenance.

## Phase I --- Reliability

Expand hardware matrix per §40 above.

------------------------------------------------------------------------

# 42. Revised Non-Negotiable Architectural Rules

Grok should treat the following as hard constraints:

1.  **Musical Engine and AME remain separate systems.**
2.  **Create `AuroraMusical` as a dedicated foundational module now
    rather than planning an expected later extraction.**
3.  **MIDI Clock is only one Musical Engine timing source.**
4.  **Tap Tempo updates the internal timing source; it is not itself the
    continuous clock.**
5.  **MIDI System Real-Time and System Common messages are modeled
    correctly.**
6.  **SPP support is included in v1.**
7.  **MIDI real-time bytes must be parsed correctly when interleaved
    with other messages.**
8.  **24 PPQN quarter-note timing must not be conflated with metrical
    beat semantics.**
9.  **MIDI Clock does not magically provide meter/bar structure.**
10. **Musical timing values retain enough provenance to know where
    tempo, meter, position, and show context originated.**
11. **The Musical Engine exposes discontinuities/seeks, not only
    continuously advancing phase.**
12. **AME never implements its own beat/subdivision clock.**
13. **Future Effects Engine consumes the same Musical Engine API as
    AME.**
14. **Aurora Actions remain semantic and never directly write DMX
    buffers.**
15. **Safety actions cannot be delayed by beat quantization.**
16. **Scheduler overflow must not discard previously accepted oldest
    actions.**
17. **One drum event means one trigger by default; coalescing is
    opt-in.**
18. **Held MIDI state must have deterministic release behavior on
    disconnect/panic/disable.**
19. **Every MIDI event receives a monotonic ingress timestamp.**
20. **Legacy migration must prevent double-fire by mapping ownership,
    not broad event suppression.**
21. **Random sequence behavior must be deterministic under test.**
22. **Broken references and unresolved sources must be detectable before
    live performance.**
23. **MTC/timecode remains distinct from MIDI Clock and is deferred.**
24. **Audio beat detection and Ableton Link remain deferred providers,
    but the architecture must support them without redesign.**
25. **External show-management software must eventually be able to
    provide structural commands independently from continuous musical
    timing.**

------------------------------------------------------------------------

# 43. Final Recommendation

Proceed with Grok's plan **after incorporating these amendments**.

The original plan is fundamentally sound. These changes are primarily
about ensuring that Aurora's Musical Engine becomes a genuinely reusable
musical-time foundation rather than a MIDI-clock implementation that
later needs to be generalized.

This matters because the next major consumer after AME is expected to be
Aurora's **Effects Engine**, including:

-   beat-driven effects
-   color fans
-   intensity waves
-   chases
-   movement effects
-   multi-beat transitions
-   subdivision-driven animation

And farther ahead, Aurora is expected to participate in larger
synchronized productions where external show-management software may
control:

-   song/section state
-   lighting sequences
-   musical timing
-   keyboard patch changes
-   guitar effects
-   audio effects
-   video/show events

The architecture established in this implementation therefore needs to
survive well beyond the immediate AME feature.

With the amendments above, the proposed phased plan is suitable to begin
**Phase A only**, followed by the existing mandatory STOP/review
checkpoint.
