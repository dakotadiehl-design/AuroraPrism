# Prism MUE MIDI Beat Sync and Automatic Song Sections

## Feature Specification

**Product:** Prism  
**Subsystems:** Music Engine (MUE), Advanced MIDI Engine (AME), Song/Setlist, Cue Playback  
**Status:** Future implementation reference  
**Primary input:** MIDI only; audio analysis is explicitly out of scope

---

## 1. Purpose

Prism must be able to follow the musical timing of a live band and use that timing to drive song structure, cues, effects, and other show actions.

The operator programs the song's meter and section structure. MIDI drum events provide continuous tempo and beat evidence. A user-operated MIDI foot pedal provides explicit tempo taps and an authoritative **Beat Sync / Mark 1** input identifying the downbeat. The Music Engine then maintains a live bar-and-beat timeline despite normal human tempo drift.

This enables workflows such as:

> The song is in 4/4. Verse 1 lasts four bars. When four bars have been played, Prism enters Chorus on beat 1 and performs the Chorus entry actions.

The feature must assist live operation without pretending to understand musical intent that has not been programmed or explicitly marked by the user.

---

## 2. Product terminology

### 2.1 Music Engine (MUE)

MUE is the authoritative owner of:

- tempo;
- beat phase;
- meter;
- bar phase and downbeat position;
- transport state;
- absolute musical position;
- timing confidence;
- musical-boundary scheduling;
- section-duration scheduling.

### 2.2 Advanced MIDI Engine (AME)

AME is the authoritative owner of:

- MIDI source binding;
- MIDI message normalization;
- drum-note classification and mapping;
- pedal/button trigger recognition;
- mapping MIDI triggers to semantic Prism actions;
- action scopes, conditions, transforms, and sequences.

AME supplies observations and semantic actions to MUE. AME must not independently maintain a competing musical clock.

### 2.3 Beat Sync / Mark 1

An explicit user action declaring that the event timestamp represents beat 1 of a bar. Mark 1 establishes or corrects bar phase; it does not independently replace the current tempo estimate.

### 2.4 Tap Beat / Tap Tempo

An explicit user action contributing a timing tap to the tempo estimator. Repeated taps establish or correct tempo and beat phase. Ordinary tap-tempo presses do not each declare a downbeat.

---

## 3. Goals

1. Continuously estimate tempo from MIDI drum performance.
2. Follow gradual human tempo drift without visible or structural timing jumps.
3. Allow Tap Tempo from any AME-bound MIDI control, including a foot pedal.
4. Allow a separate Mark 1 action to establish the downbeat and bar phase.
5. Combine estimated tempo, Mark 1, and programmed meter into an authoritative musical timeline.
6. Let users define song sections in bars.
7. Automatically transition sections at their programmed musical boundary.
8. Execute existing section exit/entry actions through the existing serialized control path.
9. Continue safely through short input gaps and refuse unsafe automatic transitions when timing becomes untrustworthy.
10. Keep all automation inspectable and manually overridable during performance.

---

## 4. Non-goals

The initial feature does not include:

- microphone or line-level audio analysis;
- full-band audio beat detection;
- automatic recognition of Verse, Chorus, Bridge, or other semantic sections;
- automatic meter detection;
- automatic inference of song form;
- guaranteed downbeat inference from drum style alone;
- support for unconducted rubato, free-time passages, polymeter, or arbitrary tempo maps without explicit operator assistance;
- replacement of standard MIDI Clock when MIDI Clock is configured as authoritative.

---

## 5. Core user workflow

1. The user creates or selects a song.
2. The user programs its meter, such as 4/4, 3/4, 6/8, or a supported asymmetric grouping.
3. The user creates ordered sections and assigns each a duration and transition rule.
4. The user maps MIDI drum notes to drum roles, or selects an appropriate drum-map preset.
5. The user maps one pedal control to **Tap Beat** and another to **Mark 1**. A single-pedal gesture configuration may be offered but must not be the default.
6. The drummer begins playing or the operator taps the starting tempo.
7. MUE establishes a provisional tempo and beat grid.
8. The operator presses Mark 1 on the count-in or song downbeat.
9. MUE establishes authoritative bar phase and starts or aligns transport according to the configured Mark 1 behavior.
10. MIDI drum events continuously refine tempo and phase as the drummer drifts.
11. MUE counts the programmed number of bars in the active section.
12. At the target bar boundary, MUE requests the programmed section transition.
13. The existing section transition path performs exit actions, changes context, resets/arms associated AME state, and performs entry actions.
14. The operator may mark 1 again, tap tempo, vamp, advance, go back, or disable automatic progression at any time.

---

## 6. Timing model

### 6.1 Continuous musical position

MUE must represent position in musical units, not elapsed wall-clock seconds. Section duration remains a fixed number of bars even when tempo changes.

When tempo is updated, MUE must re-anchor the clock at the current host time and current musical position. It must apply the new tempo forward from that anchor. It must not recalculate the entire position from song start using the new BPM.

Example:

```text
Current position: bar 6, beat 2.35
Current tempo:    120.0 BPM
New estimate:     121.1 BPM

Re-anchor bar 6, beat 2.35 at the current monotonic host time,
then advance from that point at 121.1 BPM.
```

### 6.2 Tempo is continuously adjustable

Tempo estimation is not a one-time acquisition step. MUE must follow gradual acceleration and deceleration throughout the song.

The estimator must:

- apply small corrections for normal human drift;
- resist isolated early or late strikes;
- require repeated evidence for large changes;
- preserve phase continuity;
- prevent half-time and double-time oscillation;
- freewheel through short gaps;
- expose both the estimated BPM and confidence.

### 6.3 Meter is programmed metadata

MIDI Clock and drum events do not provide meter. Meter comes from the song configuration, with project defaults used only as fallback.

MUE must support the existing full metrical model, including beat grouping for asymmetric meters. Bar length and metrical beats must always derive from the programmed meter.

---

## 7. MIDI drum tempo estimator

### 7.1 Input contract

AME converts accepted MIDI note events into normalized drum observations:

```swift
struct DrumOnsetObservation: Sendable {
    var hostTime: HostTime
    var sourceID: String
    var role: DrumRole
    var velocity: Double
}
```

All observations must use the same monotonic host-time domain as MUE and MIDI Clock. Wall-clock time must never be used for timing math.

### 7.2 Drum mapping

The user must be able to:

- select a General MIDI drum-map preset;
- select device-specific presets where available;
- learn a drum note through AME;
- manually assign kick, snare, hi-hat, ride, crash, tom, or other/unknown roles;
- enable or disable individual roles as timing evidence;
- inspect the last received note, role, velocity, and source.

Unknown or unmapped notes must not receive strong timing weight by default.

### 7.3 Weighted evidence

Different events supply different types of evidence:

- regular hi-hat or ride patterns provide strong subdivision evidence;
- kick and snare commonly provide beat evidence;
- low-velocity ghost notes receive reduced weight;
- tom fills and rapid clusters receive reduced tempo weight;
- crash plus kick can reinforce a user-marked or predicted downbeat but must not independently establish one;
- repeated events from the same role may reveal a stable periodicity.

Weights must be configurable internally and testable. Initial values may be product defaults rather than user-facing advanced controls.

### 7.4 Multiple tempo hypotheses

The estimator must maintain competing tempo interpretations rather than relying on the last two onsets. At minimum it must protect against half-time and double-time ambiguity.

Each hypothesis should include:

```swift
struct BeatHypothesis: Sendable {
    var tempoBPM: Double
    var phaseHostTime: HostTime
    var score: Double
    var stability: Double
    var lastSupportingObservation: HostTime
}
```

Hypothesis scoring must consider:

- agreement with predicted beat and subdivision locations;
- role and velocity weight;
- continuity with the previously selected tempo;
- repeated support across multiple events;
- a penalty for implausibly large instantaneous changes;
- decay when supporting evidence stops.

### 7.5 Outlier and fill rejection

The estimator must not sharply alter tempo due to one event. Rapid clusters consistent with a fill must temporarily contribute less to the main tempo hypothesis. A large tempo change must require multiple observations that agree with the new grid.

### 7.6 Bounded correction

Tempo and phase corrections must be bounded per update. Default tuning should follow gradual drift promptly while requiring stronger evidence for abrupt changes.

Exact constants require rehearsal testing, but configuration must support:

- tempo smoothing strength;
- maximum ordinary tempo slew;
- phase correction strength;
- outlier window;
- large-change confirmation count;
- half/double switch hysteresis;
- freewheel duration;
- confidence decay.

---

## 8. Foot-pedal actions

### 8.1 Tap Beat

`tapTempo` remains a semantic Prism action and must be directly assignable through AME.

Tap calculation must:

- require at least two taps for an estimate;
- use a robust statistic over recent intervals, such as a median or weighted robust mean;
- reject intervals outside the supported BPM range;
- reject clear interval outliers;
- reset the tap series after a configurable timeout;
- report provisional confidence after two taps;
- report stronger confidence after three or more consistent taps;
- re-anchor tempo without discontinuously moving musical position.

Tap Beat may reinforce beat phase, but it must not designate every tap as beat 1.

### 8.2 Mark 1 / Beat Sync

A new semantic action must be added:

```swift
case syncDownbeat
```

The user-facing name is **Mark 1** or **Beat Sync**.

On first acquisition, Mark 1 must:

- preserve the current valid tempo estimate;
- declare the event host time to be beat 1;
- align musical position to a bar boundary;
- establish authoritative downbeat confidence;
- start transport if the configured behavior is `startIfStopped`;
- recalculate active-section timing from the corrected musical grid.

When already locked, Mark 1 must:

- find the closest plausible predicted beat within a capture window;
- designate that beat as beat 1;
- apply a bounded phase correction;
- avoid changing BPM solely due to pedal timing error;
- log and display the correction magnitude;
- require an explicit restart action if the intended operation is to return to song bar 1.

### 8.3 Separate restart action

Prism should support a distinct **Restart at 1** action. Mark 1 corrects the running grid; Restart at 1 resets musical position and begins a new song timeline.

### 8.4 Single-pedal gestures

Optional gestures may allow a single switch to perform more than one action, such as normal press for Tap Beat and long press for Mark 1. This must be opt-in because double-press and long-press recognition can add latency and ambiguity during live performance.

---

## 9. Timing-source arbitration

MUE must fuse timing observations through an explicit timing-source arbiter. Sources must not directly overwrite one another.

Default authority order:

1. configured authoritative MIDI Clock;
2. explicit user Tap Beat observations;
3. MIDI drum tempo estimator;
4. last stable tempo during freewheel;
5. programmed song tempo;
6. project default tempo.

This order is policy-driven. For example, in drum-follow mode, a pedal tap establishes a strong starting estimate and the drum estimator subsequently follows gradual drift. A new sequence of consistent pedal taps may apply a stronger correction.

Observations should use a shared contract:

```swift
struct TempoObservation: Sendable {
    var bpm: Double
    var hostTime: HostTime
    var confidence: Double
    var source: TempoObservationSource
}
```

The active timing snapshot must expose source, confidence, sync condition, and whether downbeat was explicitly marked.

---

## 10. Lock and confidence states

MUE must distinguish the following states:

```swift
enum MusicalLockQuality: String, Codable, Sendable {
    case searching
    case tempoOnly
    case beatLocked
    case downbeatMarked
    case freewheeling
    case lost
}
```

At minimum, the runtime snapshot must expose:

- tempo confidence;
- beat-phase confidence;
- whether downbeat is explicitly marked;
- active observation source;
- time since the last valid observation;
- current freewheel state;
- half/normal/double-time ambiguity status.

Automatic structural transitions must require an explicitly marked downbeat and sufficient timing confidence unless the user selects a more permissive policy.

---

## 11. Song and section model

### 11.1 Song timing

Each song may define:

- default tempo;
- meter and beat grouping;
- timing input policy;
- preferred drum source and drum map;
- Mark 1 behavior;
- loss-of-lock policy;
- initial section.

### 11.2 Section timing

`SongSection` must gain explicit musical timing configuration:

```swift
struct SongSectionTiming: Codable, Equatable, Sendable, Hashable {
    var lengthInBars: Int?
    var transition: SongSectionTransition
}

enum SongSectionTransition: Codable, Equatable, Sendable, Hashable {
    case automaticNext
    case jumpTo(UUID)
    case loop
    case vampUntilTriggered
    case manual
}
```

Rules:

- `lengthInBars` must be positive when present;
- `nil` length represents indefinite duration and requires a manual/vamp-compatible transition;
- automatic transitions must identify a valid destination;
- the final section may be manual, looped, or explicitly jump elsewhere;
- invalid cycles and missing destinations must be reported by project validation;
- project persistence and migrations must preserve existing songs by defaulting legacy sections to manual/indefinite behavior.

### 11.3 Active section timing

Runtime state should include:

```swift
struct ActiveSectionTiming: Sendable {
    var sectionID: UUID
    var startPosition: QuarterNotePosition
    var targetPosition: QuarterNotePosition?
    var completedBars: Int
}
```

The transition target is computed from the section's start position, programmed bar count, and meter bar length. It must never be implemented by counting UI timer callbacks.

---

## 12. Section transition behavior

When the target musical position becomes due, MUE requests a semantic section transition. The existing host transition path remains authoritative and must preserve this order:

1. execute the old section's exit actions;
2. update active song and section context;
3. resolve section mapping inheritance;
4. reset or arm associated sequences according to their policies;
5. execute the new section's entry actions;
6. publish the new performance snapshot.

MUE must not directly fire raw cues or write DMX.

### 12.1 Re-sync near a transition

A Mark 1 correction close to a pending automatic transition must not cause an accidental immediate section jump. After a material phase correction, the scheduler must recompute the target and apply a configurable guard interval. The default should require the corrected target to remain at least one metrical beat ahead or wait for the next valid boundary.

### 12.2 Tempo drift

Changing tempo changes the wall-clock time at which the section ends but not its musical length. A four-bar section remains four bars.

---

## 13. Failure and safety policies

Each song or show must define a loss-of-lock policy:

```swift
enum MusicalTimingLossPolicy: String, Codable, Sendable {
    case freewheelThenVamp
    case requireLock
    case continueInternal
    case advanceAnyway
    case manual
}
```

Recommended default: **freewheel briefly, then vamp**.

Required behavior:

- short observation gaps freewheel from the last stable tempo;
- confidence visibly declines during freewheel;
- prolonged loss suspends automatic structural transitions under the default policy;
- safety-critical actions remain immediate and never wait for musical timing;
- manual Next Section, Go, Stop, Back, Blackout, and Panic remain available;
- reacquisition must use hysteresis and must not jump section state;
- Mark 1 must provide a fast, deterministic recovery path;
- timing loss and recovered lock must be recorded in diagnostics.

---

## 14. User interface

MUE requires a clearly named, first-class interface. It must not remain discoverable only as timing fields inside the MIDI Engine window.

### 14.1 Song programming UI

The song editor must provide:

- song tempo and meter;
- beat grouping where applicable;
- ordered section list;
- section duration in bars;
- destination/transition rule;
- entry and exit actions;
- loss-of-lock policy;
- validation of unreachable, cyclic, or invalid section structures.

Example:

```text
Intro          4 bars   -> Verse 1
Verse 1        8 bars   -> Chorus 1
Chorus 1       8 bars   -> Verse 2
Verse 2        8 bars   -> Chorus 2
Bridge         Vamp     -> Foot pedal / manual
Final Chorus  16 bars   -> Outro
Outro          Manual
```

### 14.2 Live MUE status

The performance interface must prominently show:

```text
124.2 BPM    4/4    BAR 3 · BEAT 2
TEMPO: MIDI DRUMS — LOCKED
DOWNBEAT: PEDAL MARKED
VERSE 1: BAR 2 OF 4
NEXT: CHORUS
```

It must also expose:

- transport state;
- active timing source;
- tempo and beat confidence;
- freewheel/lost indication;
- last Mark 1 status;
- current and next sections;
- completed and remaining bars;
- Hold/Vamp;
- Resume Auto;
- Next/Previous Section;
- Mark 1;
- Tap Beat;
- Half Tempo and Double Tempo corrections;
- automatic-transition enable/disable.

### 14.3 AME configuration UI

AME must expose learnable actions for:

- Tap Beat;
- Mark 1;
- Restart at 1;
- Half Tempo;
- Double Tempo;
- Hold/Vamp;
- Resume Automatic Progression;
- Next Section;
- Previous Section.

The MIDI monitor should show whether an event was interpreted as a drum onset, tempo tap, or downbeat marker.

---

## 15. Diagnostics and observability

Diagnostics must permit rehearsal and support analysis without logging unbounded MIDI traffic.

Record rate-limited events for:

- estimator acquisition;
- tempo-source change;
- material tempo correction;
- rejected outlier clusters;
- half/double hypothesis change;
- Mark 1 received and correction size;
- entry into and exit from freewheel;
- timing loss and reacquisition;
- automatic transition scheduled, fired, canceled, or suspended;
- manual override of automatic progression.

A diagnostic snapshot should include the active and alternate tempo hypotheses, confidence, phase error, observation age, section target position, and transition policy.

---

## 16. Persistence and migration

All new song, section, timing-policy, pedal-action, and drum-map configuration must persist in the Prism project package.

Migration requirements:

- existing projects must open without user intervention;
- existing song sections default to indefinite/manual transition;
- existing project and song tempo/meter defaults retain their current meaning;
- existing `tapTempo` mappings continue to work;
- unknown future enum values must fail safely rather than enabling automatic progression;
- package validation must reject nonpositive bar counts and invalid section destinations.

---

## 17. Performance and concurrency

- MIDI ingestion must remain nonblocking.
- Estimator work must not run on the lighting frame loop.
- Observation queues must be bounded.
- Runtime processing must avoid per-event unbounded allocation.
- UI polling must never be responsible for musical scheduling.
- Scheduled transitions must be harvested by the existing high-resolution MUE runtime driver.
- State shared across MIDI, MUE, AME, and UI boundaries must have explicit serialization or synchronization.
- All event ordering must use monotonic host timestamps.

---

## 18. Testing requirements

### 18.1 Deterministic estimator tests

Use a virtual host clock and recorded MIDI-event fixtures to verify:

- steady 4/4 at common tempos;
- gradual acceleration and deceleration;
- natural timing jitter;
- missing kick or snare events;
- sixteenth-note hi-hats;
- ghost notes;
- drum fills;
- short rests and long dropouts;
- half-time and double-time ambiguity;
- outlier rejection;
- tap-tempo acquisition and timeout;
- Mark 1 phase correction;
- reacquisition after freewheel.

### 18.2 Section tests

Verify:

- four bars cause exactly one transition at the correct boundary;
- tempo drift does not change the musical bar count;
- no cumulative drift occurs across many sections;
- Mark 1 recalculates a pending target safely;
- a correction near a boundary obeys the transition guard;
- vamp and manual sections never advance automatically;
- timing loss suspends transitions under the default policy;
- manual override remains available while timing is lost;
- exit and entry actions retain deterministic ordering.

### 18.3 Rehearsal fixtures

Create captured MIDI fixtures representing real drummers and styles. Acceptance must include repeated rehearsal playback, not only synthetic periodic input.

---

## 19. Acceptance criteria

The initial feature is complete when all of the following are true:

1. A user can program song meter and ordered sections with bar durations.
2. A user can map MIDI drum notes to timing roles.
3. MIDI drum input can acquire and continuously adjust a stable tempo estimate.
4. Gradual drummer drift is followed without discontinuous musical-position jumps.
5. A MIDI foot pedal can perform Tap Beat.
6. A separately mapped pedal action can perform Mark 1.
7. Mark 1 establishes authoritative bar phase without replacing a valid tempo estimate.
8. MUE exposes live BPM, bar, beat, source, confidence, and lock state.
9. A four-bar section transitions exactly once at the intended next-section downbeat.
10. Section duration remains correct while tempo changes.
11. Short input loss freewheels; prolonged loss follows the configured safety policy.
12. The operator can vamp, resume, resync, and advance manually at all times.
13. Existing section enter/exit actions and AME scope transitions remain deterministic.
14. Existing projects migrate safely with automatic section transitions disabled by default.
15. No estimator or UI work blocks the lighting engine frame loop.

---

## 20. Recommended implementation phases

### Phase A — Product model and UI

- Add section bar duration and transition rules.
- Add song timing/loss policy.
- Add MUE Song Structure and live-status UI.
- Add persistence, validation, migration, and command-backed editing.

### Phase B — Pedal timing authority

- Expose robust Tap Beat through AME.
- Add Mark 1 and Restart at 1 semantic actions.
- Add bar-phase alignment and resynchronization safeguards.
- Implement section scheduling from an internally controlled tempo.

### Phase C — MIDI drum estimator

- Add drum-map configuration and normalized onset observations.
- Implement multiple tempo hypotheses, smoothing, outlier rejection, and confidence.
- Feed observations through the MUE timing-source arbiter.
- Add synthetic and captured-MIDI test suites.

### Phase D — Live safety and closeout

- Implement freewheel, vamp, reacquisition, and transition guards.
- Add diagnostics and rehearsal tooling.
- Tune defaults using real MIDI drum performances.
- Complete scale, concurrency, migration, and regression testing.

---

## 21. Product principle

Prism must distinguish machine inference from human musical intent.

MIDI drums provide continuously updated evidence about tempo and beat. The operator's Mark 1 supplies authoritative downbeat intent. The programmed meter and section structure supply song form. MUE combines these inputs into a stable musical timeline, while AME and the existing control system perform the resulting actions safely and predictably.

The system should feel as though Prism is following the band, while always leaving the operator in control.
