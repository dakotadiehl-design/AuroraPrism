# Aurora Advanced MIDI Engine

## Product / UX Architecture Specification for Future Implementation

**Status:** Future implementation after the current Aurora UX/UI work is
complete\
**Purpose:** Preserve the agreed product direction and provide Grok Plan
Mode with a concrete basis for architecture and implementation planning.

------------------------------------------------------------------------

## 1. Executive Summary

Aurora's Advanced MIDI Engine should not be designed as a conventional
"MIDI Learn -\> bind note/CC -\> control one parameter" feature.

It should be a **real-time, context-aware, stateful event-routing and
performance automation engine** that translates MIDI performance into
first-class Aurora actions.

The core conceptual pipeline is:

**MIDI Input -\> Trigger / Trigger Group -\> Conditions / Context -\>
Transform / Behavior -\> Aurora Action**

Example:

> Drum module sends snare Note 38 -\> Aurora identifies the snare -\>
> confirms that *Money for Nothing / Intro* is the active song section
> -\> advances the section's drum-triggered lighting sequence -\> fires
> the next preset/cue/look.

The MIDI Engine is intended to become one of Aurora's signature
capabilities and should substantially exceed simple MIDI mapping
systems.

------------------------------------------------------------------------

## 2. UX Principle: A Dedicated MIDI Engine Window

The Advanced MIDI Engine should **not** live inside Aurora's primary
Programmer/Stage workspace and should not be treated as a Settings
panel.

It should be a **separate macOS window**, accessible from the
application menu:

**Window -\> MIDI Engine...**

The main Aurora window and MIDI Engine window may remain open
simultaneously.

### Why

The two windows represent different jobs:

-   **Main Aurora Window:** design, program, visualize, and run
    lighting.
-   **MIDI Engine:** design the logic that makes Aurora respond to
    musicians and MIDI controllers.

Separating these tasks keeps the primary show-programming workspace
clean while allowing the MIDI system to become sophisticated without
overwhelming the main UI.

Basic device configuration may still exist under:

**Aurora -\> Settings -\> MIDI**

Settings should contain configuration such as device enablement,
network/RTP-MIDI behavior, reconnect policy, and other application-level
preferences.

Creative MIDI programming belongs in the dedicated MIDI Engine window.

------------------------------------------------------------------------

## 3. Proposed Window Layout

The MIDI Engine should retain Aurora's established professional dark
macOS creative-workstation design language: restrained charcoal
surfaces, Aurora purple accents, strong visual hierarchy, and native
macOS interaction patterns.

A proposed structure is:

``` text
+----------------------------------------------------------------------------+
| MIDI ENGINE                         MIDI ACTIVE             Learn MIDI       |
+------------------+--------------------------------------+------------------+
|                  |                                      |                  |
| SOURCES /        |           MAPPING WORKSPACE          |    INSPECTOR     |
| CONTEXT          |                                      |                  |
|                  |                                      |                  |
| Sources          |  INPUT                               | Trigger          |
|  Drum Module     |  Any Drum Hit                        | Any Drum         |
|  FCB1010         |      |                               |                  |
|                  |  CONTEXT                             | Mode             |
| Global           |  Money for Nothing / Intro           | Advance          |
|                  |      |                               |                  |
| Songs            |  SEQUENCE                            | Reset On         |
|  Money for       |  [A] -> [B] -> [C] -> [D] -> loop   | Section Entry    |
|   Nothing        |      |                               |                  |
|    Intro         |  ACTION                              | Velocity         |
|    Verse 1       |  Fire selected preset                | Ignore           |
|    Chorus        |                                      |                  |
|                  |                                      |                  |
+------------------+--------------------------------------+------------------+
| MIDI MONITOR  Ch 10  Note 38  Vel 117  SNARE -> Intro Drums -> Step 3      |
+----------------------------------------------------------------------------+
```

The three primary regions are:

1.  **Navigation / Sources / Context**
2.  **Visual Mapping Workspace**
3.  **Inspector**

A collapsible **Live MIDI Monitor** spans the bottom.

------------------------------------------------------------------------

## 4. The Core UX Language: "When This -\> Under These Conditions -\> Do This"

The primary MIDI interface should not initially expose users to a giant
technical mapping spreadsheet.

Mappings should visually communicate signal flow:

**WHEN THIS**\
↓\
**UNDER THESE CONDITIONS**\
↓\
**DO THIS**

For example:

**Any Drum Hit**\
↓\
**Money for Nothing / Intro**\
↓\
**Advance "Intro Drum Looks"**

The Inspector exposes detailed parameters when required.

A table/list view may be provided for bulk management and advanced
users, but the visual mapping workspace should be the primary learning
and editing interface.

------------------------------------------------------------------------

## 5. MIDI Sources

Aurora should discover and manage CoreMIDI-compatible sources including,
as appropriate:

-   Physical MIDI interfaces
-   USB MIDI devices
-   MIDI controllers
-   Drum modules
-   Virtual MIDI buses
-   Network/RTP-MIDI sources
-   Other CoreMIDI endpoints

Each source should have:

-   Enable/disable state
-   Connection/activity status
-   Human-readable name
-   Live activity indication
-   Diagnostic visibility

Incoming MIDI should be observable so users can distinguish "Aurora did
not receive the event" from "Aurora received the event but no rule
matched."

------------------------------------------------------------------------

## 6. MIDI Learn

MIDI Learn should provide a very low-friction entry point.

The MIDI Engine should include a prominent **Learn MIDI** control.

Typical flow:

1.  User clicks **Learn MIDI**.
2.  Aurora enters a listening state.
3.  User strikes a drum, presses a footswitch, turns a knob, etc.
4.  Aurora identifies the incoming message.
5.  Aurora presents both a friendly and technical representation.

Example:

> **Snare detected**\
> Drum Module · Channel 10 · Note 38 · Velocity 121

The user then chooses what the event should control.

The interface should prefer musical/human terminology where possible
while retaining raw MIDI details in the Inspector.

Example:

**Friendly:** `Snare`\
**Technical:** `Drum Module · Ch 10 · Note On · 38`

Users should not need to memorize MIDI note numbers to program Aurora.

------------------------------------------------------------------------

## 7. Supported MIDI Event Types

The architecture should be designed to accommodate at least:

-   Note On
-   Note Off
-   Note velocity
-   Control Change (CC)
-   Program Change
-   Pitch Bend
-   Channel Pressure
-   Polyphonic Pressure where available
-   MIDI Clock / transport where useful
-   SysEx as a future/advanced capability

Velocity and continuous values must remain first-class data and must not
be discarded after trigger detection.

------------------------------------------------------------------------

## 8. Velocity and Value Mapping

Velocity can drive lighting behavior rather than merely acting as an
on/off trigger.

Examples include mapping velocity to:

-   Intensity
-   Effect depth
-   Effect size
-   Fade/decay time
-   Movement amount
-   Color blend
-   Other numeric Aurora parameters

Example:

**Snare velocity 1-127 -\> Accent intensity 20-100%**

This allows lighting response to reflect the musician's actual
performance dynamics.

------------------------------------------------------------------------

## 9. Aurora Actions, Not Direct DMX Manipulation

MIDI mappings should not directly manipulate DMX values as their
fundamental architecture.

Use:

**MIDI -\> MIDI Mapping Engine -\> Aurora Action -\> Lighting Engine -\>
Output**

Examples of first-class Aurora actions include:

-   GO
-   Back
-   Stop
-   Blackout
-   Fire/release cue
-   Select/fire song
-   Fire preset/palette
-   Trigger effect
-   Set fixture/group intensity
-   Set color/position/beam parameters
-   Modify effect rate/depth
-   Trigger busking control
-   Tap tempo
-   Execute compound actions
-   Temporarily override an Aurora parameter

This action abstraction allows the same action system to later be
invoked by MIDI, keyboard shortcuts, the iPad remote, OSC, plugins,
automation, audio analysis, or future systems.

------------------------------------------------------------------------

## 10. Trigger Behaviors

Mappings should explicitly support behavior types such as:

-   **Trigger** - execute once on the event
-   **Toggle** - alternate state on repeated events
-   **Momentary** - active while the source remains active
-   **While Held** - Note On activates, Note Off releases
-   **Continuous / Value** - incoming MIDI value continuously drives an
    Aurora parameter
-   **Gate** - event/value controls whether another behavior is
    permitted

Example:

> Note On -\> crowd blinders active\
> Note Off -\> release crowd blinders

The same architecture can eventually support momentary controls from
Aurora's iPad Busk Panel.

------------------------------------------------------------------------

## 11. Context-Aware Mapping

MIDI behavior must be context-aware.

Mappings should support scopes such as:

1.  **Global**
2.  **Show**
3.  **Song**
4.  **Song Section**

The key requirement is **song-section awareness**.

The same MIDI event can perform different actions in different parts of
a song.

Example for snare Note 38:

-   **Intro:** trigger Action X
-   **Verse 1:** no action
-   **Chorus:** trigger Action Y
-   **Solo:** trigger Action Z
-   **Outro:** trigger a large white accent

This is a core requirement, not optional polish.

------------------------------------------------------------------------

## 12. Song Sections

Song Mode should expose named performance sections that the MIDI Engine
can reference.

Examples:

-   Intro
-   Verse 1
-   Chorus
-   Verse 2
-   Bridge
-   Solo
-   Outro

Sections must also support arbitrary user-defined names.

A song section may define or reference:

-   MIDI Mapping Set
-   Local mappings
-   Mapping overrides
-   Triggered sequences
-   Section-entry actions
-   Section-exit actions

Example:

``` text
MONEY FOR NOTHING

INTRO
  MIDI Mapping Set: MFN Intro
  On Enter: Reset "Intro Drum Looks"

VERSE 1
  MIDI Mapping Set: Standard Verse

CHORUS
  MIDI Mapping Set: MFN Chorus

SOLO
  MIDI Mapping Set: Guitar Reactive
```

Aurora's currently active song section determines which context-specific
MIDI rules are active.

------------------------------------------------------------------------

## 13. Mapping Inheritance

Mappings should support inheritance so users do not duplicate nearly
identical rules for every song section.

Conceptually:

**Global -\> Show -\> Song -\> Section**

A lower-level context may:

-   Inherit a parent mapping
-   Disable a parent mapping
-   Override a parent mapping
-   Add local mappings

Example section header:

> **INTRO**\
> Inherits: Money for Nothing -\> Global\
> 4 local mappings · 1 override · 2 sequences

The UI should communicate inheritance clearly without forcing users to
understand implementation details.

------------------------------------------------------------------------

## 14. Trigger Groups

Multiple MIDI events should be groupable into reusable logical triggers.

For a multi-input drum module:

### Any Drum Hit

-   Kick
-   Snare
-   Rack Tom 1
-   Rack Tom 2
-   Floor Tom
-   Hi-Hat
-   Crash 1
-   Crash 2
-   Ride

Other possible groups:

### Toms

-   Rack Tom 1
-   Rack Tom 2
-   Floor Tom

### Cymbals

-   Crash 1
-   Crash 2
-   China

Mappings can then reference **Any Drum Hit** rather than duplicating
rules for every MIDI note.

The UI should display the friendly trigger-group name while preserving
the underlying MIDI message definitions.

------------------------------------------------------------------------

## 15. Stateful MIDI-Triggered Sequences

This is a major Advanced MIDI Engine requirement.

Aurora must support **stateful sequences whose step is advanced by
incoming MIDI events**.

Example:

### Money for Nothing / Intro

Trigger:

**Any Drum Hit**

Sequence:

**Preset A -\> Preset B -\> Preset C -\> Preset D -\> Preset E -\>
loop**

Each qualifying drum strike advances the sequence exactly one step.

The musician's performance therefore becomes the clock for the lighting
sequence.

No prerecorded automation, fixed BPM, MIDI clock, or timecode is
required.

This permits lighting to remain naturally synchronized to a live drummer
even when tempo and performance timing vary.

------------------------------------------------------------------------

## 16. Sequence Step Modes

Triggered sequences should support at least:

### Advance

`1 -> 2 -> 3 -> 4 -> 1`

### Reverse

`4 -> 3 -> 2 -> 1 -> 4`

### Ping-Pong

`1 -> 2 -> 3 -> 4 -> 3 -> 2 -> 1`

### Random

Select a random step for each qualifying trigger.

### Weighted Random

Allow some steps to have greater probability than others.

### Shuffle Bag

Play every eligible step once in randomized order before reshuffling.

### Reset

A specified event returns the sequence to its defined starting state.

------------------------------------------------------------------------

## 17. Sequence Contents

A triggered sequence should not be restricted to color presets.

Sequence steps should be able to reference appropriate first-class
Aurora objects/actions such as:

-   Presets
-   Palettes
-   Cues
-   Effects
-   Lighting looks
-   Compound Aurora actions

Example:

1.  Purple wash
2.  Blue backlight
3.  White silhouette
4.  Red floor lights
5.  Movement effect A
6.  Loop

This allows sequences to become small event-driven performance machines
rather than simple preset lists.

------------------------------------------------------------------------

## 18. Section Entry / Exit Actions

Song sections should support lifecycle actions.

For example, entering:

**Money for Nothing -\> Intro**

may automatically:

1.  Reset `Intro Drum Looks` to Step 1
2.  Enable Intro-local mappings
3.  Establish an initial lighting look
4.  Initialize required effects

Transitioning to Verse 1 automatically changes the active mapping
context.

This ensures repeatable performance behavior.

------------------------------------------------------------------------

## 19. Visual Sequence Editor

Triggered sequences should be represented visually.

Example:

**ANY DRUM HIT**

↓

**Money for Nothing · INTRO**

↓

**ADVANCE LOOK**

`[Purple] -> [Blue] -> [White] -> [Red] -> [Gold] -> loop`

Preset tiles should reuse Aurora's existing visual language.

Where appropriate:

-   Color presets show color
-   Lighting presets show miniature visual representations
-   Cues show cue name/number
-   Effects show recognizable effect identity

During live input/testing, the current sequence step should visibly
highlight.

Example:

`[Purple] -> [BLUE] -> [White] -> [Red]`

After the next drum hit:

`[Purple] -> [Blue] -> [WHITE] -> [Red]`

This provides immediate visual confirmation of state.

------------------------------------------------------------------------

## 20. Live MIDI Monitor and Diagnostics

The MIDI Engine should include a collapsible live monitor.

Example:

``` text
22:14:31.182  Drum Module  Kick       Vel 103  -> Intro Sequence -> Step 3
22:14:31.391  Drum Module  Snare      Vel 119  -> Intro Sequence -> Step 4
22:14:31.612  Drum Module  Hi-Hat     Vel  72  -> No Mapping
22:14:31.904  Drum Module  Floor Tom  Vel 111  -> Intro Sequence -> Step 1 (Loop)
```

The diagnostic system must show both:

1.  **What Aurora received**
2.  **What Aurora did with it**

Mappings should visibly react in the editor when triggered.

This makes the monitor an actual routing/debugging tool rather than
merely a MIDI packet viewer.

------------------------------------------------------------------------

## 21. MIDI Simulation / Test Mode

Users should be able to test mappings without having the physical MIDI
instrument/controller present.

Provide a simulation panel where the user can specify or select:

-   Source
-   Channel
-   Message type
-   Note/CC/etc.
-   Velocity/value

Example:

``` text
Source: Drum Module
Channel: 10
Message: Note On
Note: 38 / Snare
Velocity: 110

[SEND TEST EVENT]
```

The event should traverse the **same internal pipeline** as a real
incoming MIDI message.

Simulation must therefore test actual mapping behavior rather than
invoke actions through a separate shortcut path.

------------------------------------------------------------------------

## 22. Multiple Actions / Compound Behavior

A single MIDI mapping may execute multiple Aurora actions.

Example:

**Kick Drum**

1.  Flash rear fixtures white
2.  Increase current movement effect speed briefly
3.  Restore effect speed after the configured release/decay

Compound actions should use the same first-class Aurora action
architecture wherever possible.

------------------------------------------------------------------------

## 23. Mapping Sets

Mappings should be reusable.

Example:

### Standard Drum Lighting

-   Kick -\> floor fixture accent
-   Snare -\> white accent
-   Toms -\> position/color behavior
-   Crash -\> large accent

A song may inherit this mapping set and override only the behavior that
differs.

This avoids hundreds of nearly identical mappings across a show.

------------------------------------------------------------------------

## 24. Relationship to the Main Aurora Workspace

The MIDI Engine is a separate window, but it must remain deeply
connected to Aurora's object model.

It should reference existing Aurora entities rather than create
MIDI-only duplicates:

-   Songs
-   Song sections
-   Fixtures
-   Groups
-   Palettes
-   Presets
-   Cues
-   Effects
-   Busking actions
-   Other first-class Aurora actions

Changes made in the MIDI Engine should be part of the project/show data
and persist with the project.

The MIDI Engine should never become an isolated subsystem with its own
incompatible concepts.

------------------------------------------------------------------------

## 25. Relationship to Future Remote Control

The action system designed for MIDI should be reusable by the future
iPad live-show remote.

For example:

**MIDI Note On -\> Begin Momentary Fog Action**

and:

**iPad Busk Button Press -\> Begin Momentary Fog Action**

should eventually invoke the same underlying Aurora action.

Likewise, release events should use the same underlying release
semantics.

This avoids separate implementations for MIDI, remote control, keyboard
input, and future control surfaces.

------------------------------------------------------------------------

## 26. Ease-of-Use Requirements

The Advanced MIDI Engine may be extremely powerful internally, but the
user-facing experience must emphasize musical concepts rather than
protocol plumbing.

Prefer:

-   Snare
-   Any Drum Hit
-   Money for Nothing / Intro
-   Advance Intro Looks
-   White Accent

over interfaces dominated by:

-   Note 38
-   Channel 10
-   Mapping ID 16
-   Sequence ID 4

Technical values remain available in the Inspector and diagnostics.

The default experience should progressively reveal complexity.

A user should be able to create a basic mapping through MIDI Learn
without understanding the entire routing architecture.

------------------------------------------------------------------------

## 27. Initial UX Acceptance Scenario

A representative acceptance scenario for the eventual implementation:

1.  User opens **Window -\> MIDI Engine...**
2.  User selects **Money for Nothing -\> Intro**.
3.  User creates a new Triggered Sequence.
4.  User clicks **Learn MIDI**.
5.  User strikes kick, snare, and toms and groups them as **Any Drum
    Hit**.
6.  User drags several existing Aurora presets/cues into the sequence.
7.  User selects **Advance + Loop**.
8.  User enables **Reset on Section Entry**.
9.  User begins the song in Song Mode.
10. Aurora enters the Intro and resets the sequence.
11. Each qualifying live drum hit advances exactly one sequence step.
12. The MIDI Engine visually highlights each incoming hit, matched
    mapping, and current sequence step.
13. When Aurora enters Verse 1, the Intro mapping is no longer active.
14. Returning/restarting the Intro produces deterministic behavior
    according to the configured reset rules.

If this workflow feels clear without requiring the user to think about
raw MIDI routing, the UX is succeeding.

------------------------------------------------------------------------

## 28. Architectural Direction for Grok

When implementation planning begins, preserve these principles:

1.  **Do not implement MIDI mappings as direct DMX writes.**
2.  Create/reuse a generalized **Aurora Action** layer.
3.  MIDI events should enter a deterministic event-processing pipeline.
4.  Song and song-section context must be available to the mapping
    evaluator.
5.  Triggered sequences must maintain explicit runtime state.
6.  Sequence state and configuration must be clearly separated.
7.  Simulation must traverse the same pipeline as real MIDI.
8.  Trigger groups and mapping sets must be reusable project objects.
9.  Mapping inheritance must have deterministic precedence.
10. The engine must be designed for real-time live-show reliability.
11. UI work should follow Aurora's established design system rather than
    introducing a visually separate utility application.
12. The architecture should anticipate reuse by the iPad remote and
    other future control inputs.

------------------------------------------------------------------------

## 29. Deferred Design Questions

These should be resolved during the dedicated Advanced MIDI Engine
implementation/design round rather than guessed during unrelated UX
work:

-   Exact project data schema
-   Exact inheritance precedence and conflict-resolution behavior
-   Whether Show scope is distinct from Project scope
-   Exact song-section data model
-   Quantization/debounce/retrigger options
-   Velocity curves and transform editor design
-   Simultaneous event/threading behavior
-   Sequence persistence when leaving/re-entering sections
-   Whether sequence state can be shared across sections
-   MIDI clock synchronization behavior
-   Feedback/output MIDI support
-   SysEx scope
-   Undo/redo semantics
-   Import/export of mapping sets
-   Mapping templates
-   Performance safety limits
-   Handling disconnected/reconnected MIDI devices
-   Conflict visualization when multiple mappings match one event

These questions are intentionally deferred so the current Aurora UX/UI
round can be completed without prematurely locking implementation
details.

------------------------------------------------------------------------

## 30. Product Vision

The Advanced MIDI Engine should feel less like configuring a MIDI
control surface and more like **teaching Aurora how to listen to the
band**.

The desired result is a system in which live musical events can drive
sophisticated lighting behavior while remaining understandable to a
lighting programmer:

**Musician performs -\> Aurora understands the event and current musical
context -\> Aurora executes the intended visual behavior.**

For a performance such as the *Money for Nothing* intro, the drummer
should be able to organically drive a looping series of lighting looks
simply by playing the drums. Aurora follows the actual performance
rather than forcing the performance to follow prerecorded lighting
timing.

That combination of musical context, song-section awareness, stateful
triggered sequences, reusable mappings, and first-class Aurora actions
is the defining direction for the Advanced MIDI Engine.

---

# PART II — AURORA MUSICAL ENGINE

## 31. Architectural Status

The **Musical Engine** and **Advanced MIDI Engine (AME)** are separate first-class Aurora subsystems. Neither owns the other.

- **Musical Engine:** authoritative musical time, synchronization, transport, meter, beat/bar phase, musical position, and structural context.
- **AME:** interprets MIDI performance/control events, evaluates rules against Aurora context, maintains triggered-sequence state, and emits Aurora Actions.
- **Effects Engine (future):** consumes Musical Engine timing to generate dynamic visual modulation such as color fans, intensity waves, chases, movement and beam effects.
- **Aurora Action layer:** common command vocabulary used by AME, remote control, keyboard commands, future show control, and other automation sources.

The separation is non-negotiable. In particular, do **not** implement `MusicalEngine` as a thin `MIDIClockManager`. MIDI Clock is only one timing provider.

## 32. Musical Engine Mission

Aurora currently needs a first-class concept of musical time so that future lighting effects and external show-control workflows can operate in beats rather than arbitrary milliseconds.

The Musical Engine answers questions such as:

- Is musical transport running, stopped, or paused?
- What is the current tempo?
- What is the current meter?
- Where are we within the current beat?
- Which beat of the bar is active?
- What musical subdivision is next?
- What bar/position information is known?
- What song and song section are active?
- Which timing source is authoritative?
- Is that source locked, unstable, missing, or freewheeling?

Consumers should not need to know whether timing originated from an internal clock, tap tempo, MIDI Clock, or a future provider.

## 33. Source-Agnostic Timing Provider Model

Define a provider abstraction between timing sources and the Musical Engine.

```text
Internal Tempo ─┐
Tap Tempo ──────┼──> Timing Provider Interface ──> MUSICAL ENGINE
MIDI Clock ─────┤                                  │
Future Link ────┤                                  ├─> AME
Future Audio ───┤                                  ├─> Effects Engine
Show Control ───┘                                  └─> UI / Diagnostics
```

Initial providers:

1. **Internal Tempo Provider**
2. **Tap Tempo Provider**
3. **External MIDI Clock / Transport Provider**

Deferred providers, but architecture must permit them without rewriting consumers:

- Ableton Link
- Audio beat/tempo detection
- OSC or dedicated show-control timing
- Additional network synchronization protocols
- Timecode-oriented integration where appropriate

Audio detection and Ableton Link are explicitly **out of scope for the initial implementation**.

## 34. Canonical Musical State

The Musical Engine should expose a canonical, observable state. Fields should distinguish known data from unavailable data rather than fabricating position.

Candidate state includes:

- `transportState`: stopped / running / paused or equivalent
- `tempoBPM`
- `meterNumerator`
- `meterDenominator`
- `beatIndexInBar`
- `beatPhase` (normalized 0...1 or a similarly precise representation)
- `barIndex` when known
- `musicalPosition` when known
- `activeSongID` when applicable
- `activeSectionID` when applicable
- `timingSourceID`
- `syncState`: unlocked / acquiring / locked / freewheeling / lost
- timing-source capability flags
- timing quality / jitter diagnostics where useful

Do not assume every provider can supply every field.

## 35. MIDI Clock and Transport

Initial external synchronization must support standard MIDI real-time timing behavior, including:

- MIDI Clock
- Start
- Stop
- Continue
- Song Position Pointer where available/useful

MIDI Clock supplies 24 pulses per quarter note. Aurora must use these events to maintain tempo and phase rather than treating clock merely as an approximate BPM measurement.

Clock/transport messages intended for synchronization belong to the Musical Engine path. Performance/controller events such as notes and CCs belong primarily to AME.

A shared low-level MIDI input layer may decode the byte stream, but routing after decoding must preserve this architectural separation.

## 36. Clock Stability, Jitter, and Loss

Live MIDI clocks can jitter. Do not derive a wildly changing tempo from every individual pulse.

The Musical Engine should maintain a stable estimate of tempo and phase while remaining responsive to legitimate tempo changes. The implementation plan should explicitly address:

- pulse timestamp precision
- smoothing/filtering strategy
- phase correction
- tempo-change responsiveness
- clock acquisition
- lock criteria
- clock dropout detection
- freewheel behavior
- fallback behavior
- re-lock behavior without discontinuities

Default product direction: **briefly freewheel at the last known tempo, then fall back to an appropriate configured internal/song tempo when available**, while clearly indicating sync loss. Exact thresholds belong in implementation planning/configuration.

A lost MIDI cable must not cause undefined lighting behavior.

## 37. Internal Tempo and Tap Tempo

Beat exists even when no external clock is present.

Aurora must support an internal timing source with user-defined BPM. Song data may provide a default tempo and meter.

Tap tempo should feed the same Musical Engine rather than creating a parallel timing mechanism. Tap input may eventually originate from:

- UI control
- keyboard shortcut
- MIDI mapping through AME
- iPad remote
- future external control surfaces

## 38. Timing Source Selection and Fallback

The product should support explicit timing-source policies. Candidate modes include:

- **Internal:** always use Aurora's internal/song tempo.
- **External MIDI:** selected MIDI timing source is authoritative.
- **External Preferred / Fallback:** use external clock when healthy; fall back to configured internal/song timing after defined loss behavior.

Do not silently switch timing masters without visible state. The UI must make the active source and sync state obvious.

## 39. Musical Units and Subdivisions

The Musical Engine should provide musical-time calculations for consumers.

At minimum plan for:

- 1/32
- 1/16
- 1/8
- 1/4
- 1/2
- 1 beat
- multiple beats
- 1 bar
- multiple bars

Architecture should permit dotted and triplet values even if UI support is phased.

Consumers should be able to express duration/rate in musical units, e.g. `2 beats`, rather than calculating milliseconds themselves.

## 40. Quantized Scheduling

Provide a central mechanism for scheduling actions against musical boundaries.

Examples:

- execute immediately
- next 1/16
- next 1/8
- next 1/4
- next beat
- next bar

AME should consume this service rather than implementing its own quantizer. The future Effects Engine should use the same timing primitives.

Quantized scheduling must define behavior if transport stops, source changes, clock is lost, or the requested boundary cannot be determined.

## 41. Song and Section Context

Musical time and show structure are related but should not be conflated.

The Musical Engine should expose the active song and song-section context to interested consumers. External show-control software may eventually change that structural context while a separate timing source provides clock.

Example:

```text
Timing source: external MIDI clock
Tempo: 72 BPM
Transport: Running
Song: Comfortably Numb
Section: Guitar Solo 2
```

This allows AME to evaluate section-scoped mappings while Effects remain phase-locked to the same Musical Engine.

## 42. External Show-Control Compatibility

Future professional use must permit Aurora to operate as a specialist lighting application inside a larger distributed show-control environment.

The external show manager may eventually coordinate:

- click distribution
- song/section transitions
- Aurora lighting state
- guitar effects switching
- keyboard patch changes
- audio effects and sound-design playback
- video/media systems
- other production automation

Aurora should retain ownership of lighting programming. External show control should issue semantic commands such as:

- select/start song
- enter section
- GO
- fire/reset/arm sequence
- change transport state
- establish timing source/position where supported

Do not design future integration around raw DMX commands from show-control software.

The architecture must distinguish:

1. **Continuous synchronization**: tempo/beat/phase/transport.
2. **Discrete show-control events**: song, section, cue, sequence, and other semantic commands.

These may originate from different systems simultaneously.

## 43. Future Effects Engine Contract

The forthcoming Effects Engine is expected to depend heavily on the Musical Engine.

Examples include:

- color fans stepping every 1/4 note
- intensity waves over two beats
- fixture chases at 1/8-note rate
- pan/tilt fans opening over one bar
- beam effects synchronized to subdivisions
- effects whose phase remains coherent as external tempo changes

Effects must not implement private clocks. They should consume the Musical Engine's canonical time and scheduling APIs.

A future effect should be able to describe itself in musical terms such as:

```text
Rate: 1/8 note
Duration: 2 bars
Phase Offset: 1/4 beat per fixture
Sync: Musical Engine
```

## 44. AME ↔ Musical Engine Contract

AME consumes Musical Engine state but does not own it.

AME may ask:

- Is transport running?
- What song/section is active?
- What is the current beat/bar/phase?
- Schedule this action on the next beat/bar/subdivision.
- Is timing locked?

AME can also produce actions that influence musical operation, such as a MIDI-mapped Tap Tempo or transport command, but these must travel through defined Musical Engine commands rather than mutating timing state directly.

Example:

```text
Note On 38
   ↓
AME mapping matches
   ↓
Condition: Money for Nothing / Intro
   ↓
Behavior: advance sequence on next 1/8 boundary
   ↓
AME requests quantized execution from Musical Engine
   ↓
Aurora Action executes at boundary
```

## 45. Musical Engine UI

Do not create a giant second creative workspace merely for tempo. Musical Engine status should appear contextually where useful, while detailed configuration/diagnostics can use a focused panel or inspector.

The dedicated MIDI Engine window should expose synchronization status when MIDI is the timing source, for example:

```text
Beat Source: Drum Module MIDI
Tempo: 118.4 BPM
Transport: Running
Beat: 3 / 4
Clock: Locked
Jitter: 0.8 ms
```

Provide an animated beat/phase indicator so synchronization can be verified visually.

The main Aurora performance UI should eventually expose compact, quiet timing status without consuming excessive workspace.

## 46. Reliability and Real-Time Requirements

Both engines are live-performance infrastructure. Implementation planning must explicitly consider:

- deterministic event ordering
- monotonic/high-resolution timestamps
- thread boundaries
- avoiding blocking work on real-time-sensitive paths
- bounded queues/backpressure behavior
- duplicate/reordered event handling where applicable
- safe state restoration
- project load/save behavior
- device reconnects
- clock-source reconnects
- logging that does not compromise timing
- graceful degradation

No implementation should perform direct UI work from timing-critical processing paths.

## 47. Persistence vs Runtime State

Separate persisted configuration from ephemeral runtime state.

Persist examples:

- mapping definitions
- trigger groups
- mapping sets
- sequence definitions
- sequence reset policies
- song/section associations
- timing-source preferences
- song tempo/meter defaults

Runtime examples:

- currently active sequence step
- current clock lock state
- instantaneous phase
- current smoothed BPM
- queued quantized actions
- active held-note gates

Runtime state should only be serialized if there is a deliberate product requirement.

## 48. Diagnostics

A professional system needs observability.

Diagnostics should make it possible to answer:

- Is the MIDI endpoint connected?
- Are clock pulses arriving?
- Which timing source is active?
- Is Aurora locked?
- What tempo is Aurora calculating?
- Where is the beat phase?
- Did a MIDI mapping match?
- Which conditions passed/failed?
- Was an action immediate or quantized?
- Which sequence step fired?
- Did timing fall back after clock loss?

Use structured internal diagnostic events where practical so UI and logs do not require duplicate inference logic.

## 49. Recommended Internal Boundaries

Names are illustrative, not mandated, but Grok's plan should identify equivalent boundaries:

```text
MIDI I/O / CoreMIDI Adapter
        │
        ├── realtime clock/transport ──> Timing Provider ──> Musical Engine
        │
        └── notes/CC/etc. ─────────────> AME Input Router
                                                │
Musical Engine ── context/timing ───────────────┤
                                                ▼
                                         Rule Evaluator
                                                │
                                      Triggered Sequences
                                                │
                                         Aurora Actions
                                                │
                               Lighting / Future Effects Engine
```

Avoid circular ownership. Communication should use explicit protocols/interfaces/events rather than reaching through global singleton internals.

## 50. AME Detailed Evaluation Pipeline

For each incoming performance/control event, AME should conceptually perform:

1. Normalize and timestamp input.
2. Resolve source/device identity.
3. Resolve friendly trigger(s) and trigger groups.
4. Identify candidate mappings.
5. Evaluate enablement and inheritance.
6. Query current song/section and musical state as needed.
7. Evaluate mapping conditions.
8. Apply value/velocity transforms.
9. Apply trigger behavior: trigger/toggle/momentary/gate/continuous.
10. Update stateful sequence state if applicable.
11. Resolve immediate vs quantized execution.
12. Emit one or more first-class Aurora Actions.
13. Record structured diagnostics.
14. Update UI-observable state asynchronously.

This pipeline should be deterministic and testable independently of physical MIDI hardware.

## 51. Mapping Conflict and Precedence Requirements

Implementation planning must define deterministic behavior when several mappings match the same event.

The UX must eventually be able to explain why a mapping fired or did not fire.

Plan for precedence involving:

- Global mappings
- Show/project mappings
- Song mappings
- Section mappings
- Explicit overrides/disables
- Multiple intentionally parallel actions

Do not simply stop at the first matching mapping unless that behavior is explicitly part of the rule model.

## 52. Triggered Sequence Runtime Semantics

The implementation plan must explicitly define:

- whether the first trigger fires step 1 or advances from a pre-step state
- reset-on-section-entry behavior
- reset-on-song-start behavior
- manual reset behavior
- what happens when a section is left and re-entered
- behavior after project reload
- loop/reverse/ping-pong boundaries
- random and shuffle-bag repeat rules
- simultaneous triggers
- debounce/retrigger protection
- quantized step advancement
- whether step state can intentionally be shared between contexts

Defaults should favor deterministic live-show behavior.

## 53. Input Conditioning

AME should be designed for real instruments and controllers, not ideal laboratory MIDI.

Plan for optional conditioning such as:

- velocity thresholds
- min/max value ranges
- dead zones
- hysteresis where relevant
- retrigger suppression/debounce
- rate limiting
- value scaling
- inversion
- curves
- clamping

These should be optional and progressively disclosed, not dumped into the default beginner workflow.

## 54. MIDI Device Identity and Reconnection

Mappings should not become useless merely because CoreMIDI endpoint identifiers change after reconnection.

Grok should investigate robust device/source identity and matching strategies appropriate to CoreMIDI, with clear handling of ambiguity.

Requirements include:

- visible disconnected state
- automatic safe reconnection where unambiguous
- no silent binding to the wrong device
- user-remappable source association
- diagnostic explanation when a source cannot be resolved

## 55. AME Window Detailed UX

The AME remains a dedicated window available from **Window -> MIDI Engine...**.

Recommended regions:

### Left Sidebar

- MIDI Sources
- Global mappings
- Reusable Mapping Sets
- Songs
  - sections beneath each song
- Trigger Groups
- Triggered Sequences where useful

### Center Workspace

Primary visual representation of selected mapping/context:

**WHEN THIS -> UNDER THESE CONDITIONS -> DO THIS**

Complex rules should remain understandable without reading raw protocol values.

### Right Inspector

Advanced properties:

- source/channel/message details
- velocity/value transforms
- trigger behavior
- scope/inheritance
- quantization
- sequence mode/reset
- action parameters
- advanced conditioning

### Bottom Monitor

Collapsible live MIDI/routing monitor showing input and resulting behavior.

## 56. Friendly Musical Vocabulary

Prefer human-readable concepts throughout the primary UI:

- `Snare`
- `Any Drum Hit`
- `Money for Nothing / Intro`
- `Advance Intro Looks`
- `Next Beat`
- `Clock Locked`

Raw values such as `Ch 10 / Note 38` remain available in the Inspector and diagnostics.

## 57. AME Simulation Requirements

The test/simulation facility must inject normalized events at the same logical entry point used by real MIDI after device I/O normalization.

It must be capable of validating:

- mapping resolution
- context conditions
- velocity transforms
- trigger groups
- sequence advancement
- quantization
- compound actions
- diagnostics

Do not implement a fake UI-only shortcut that bypasses the actual engine.

## 58. Unit and Integration Test Expectations

Grok's implementation plan should include automated tests for both subsystems.

### Musical Engine

- BPM calculation from synthetic MIDI Clock
- phase continuity
- Start/Stop/Continue
- Song Position behavior where implemented
- jitter smoothing
- genuine tempo change tracking
- clock loss/freewheel/fallback
- re-lock
- subdivision boundary calculation
- quantized scheduling
- meter/bar calculations
- provider switching

### AME

- note/CC normalization
- trigger-group matching
- inheritance/override precedence
- section-scoped behavior
- velocity transforms
- momentary Note On/Off semantics
- toggle/gate behavior
- sequence modes
- deterministic reset
- simultaneous triggers
- quantized mappings
- multiple actions
- source disconnect/reconnect
- simulation parity with real input

### Cross-System

- external MIDI clock + section-scoped drum sequence
- clock loss during active sequence
- song-section transition with reset-on-entry
- quantized MIDI action across tempo changes
- transport stop with pending quantized action

## 59. Performance Acceptance Scenario: Drum-Driven Intro

A required end-to-end scenario:

1. External drum module is connected.
2. Its MIDI Clock is selected as Musical Engine source.
3. Aurora reports locked tempo/phase.
4. `Money for Nothing / Intro` becomes active.
5. Section entry resets `Intro Drum Looks`.
6. Kick/snare/toms are grouped as `Any Drum Hit`.
7. Each qualifying hit advances one step through a loop of Aurora presets/cues.
8. If configured for quantization, execution occurs at the requested subdivision boundary.
9. The live monitor displays the incoming event, matched rule, timing decision, and resulting step.
10. Entering Verse 1 disables/overrides the Intro behavior according to scope rules.
11. External clock loss produces defined freewheel/fallback behavior and a visible warning, not undefined output.

## 60. Performance Acceptance Scenario: Future Show Control

Architecture must support this future scenario without fundamental redesign:

1. Musicians perform to a shared click.
2. External show-management software controls high-level production structure.
3. A timing source provides continuous musical synchronization.
4. Show control commands Aurora to enter `Comfortably Numb / Guitar Solo 2`.
5. Musical Engine exposes the new structural context and current beat/phase.
6. AME automatically activates the correct section-scoped performance mappings.
7. Future Effects Engine continues beat-synchronized effects without losing phase.
8. Aurora retains ownership of lighting looks, effects, cues, and fixture output.
9. Other systems independently switch guitar effects, keyboard patches, audio FX, video, etc.

## 61. Explicit Initial Scope

### Build / Plan Now

- Separate AME and Musical Engine architecture
- Internal tempo
- Tap tempo architecture and practical initial control
- MIDI Clock
- MIDI Start/Stop/Continue
- Song Position support where justified by planning
- sync state and diagnostics
- song/section context contract
- musical subdivisions
- quantized scheduling foundation
- AME dedicated window
- MIDI Learn
- notes/CC and core performance messages
- velocity/value handling
- trigger groups
- mapping scopes/inheritance
- triggered sequences
- reusable mapping sets
- simulation/testing
- first-class Aurora Actions integration

### Architect For, But Defer

- Ableton Link
- audio beat detection
- sophisticated external show-management application
- broad OSC timing/control integration
- advanced timecode workflows
- full MIDI feedback/output ecosystem
- extensive SysEx tooling
- future Effects Engine itself

The interfaces must permit these later additions without making the initial pass implement them prematurely.

## 62. Non-Goals / Guardrails

- Do not turn AME into the Musical Engine.
- Do not turn Musical Engine into a MIDI-only clock utility.
- Do not let Effects create private tempo clocks.
- Do not make MIDI mappings write raw DMX as their primary architecture.
- Do not require an external show controller for normal Aurora operation.
- Do not implement Ableton Link or audio beat detection in this pass.
- Do not overload the main Programmer/Stage workspace with AME configuration.
- Do not expose every advanced MIDI field in the beginner workflow.
- Do not make timing-source failure silently alter show behavior.

## 63. Grok Planning Deliverables

Before writing implementation code, Grok should produce a plan containing:

1. Audit of existing Aurora MIDI, Song Mode, cue/action, project-model, and output architecture.
2. Identification of reusable existing types and code that must not be duplicated.
3. Proposed AME module boundaries.
4. Proposed Musical Engine module boundaries.
5. Proposed generalized Aurora Action interface/model.
6. Proposed timing-provider protocol.
7. Canonical musical-state model.
8. Threading/concurrency strategy.
9. MIDI event normalization/routing strategy.
10. Mapping/inheritance evaluation semantics.
11. Triggered-sequence state model.
12. Quantized scheduler design.
13. Persistence/schema changes and migrations.
14. UI/window architecture consistent with Aurora's current design system.
15. Diagnostics strategy.
16. Unit/integration test plan.
17. Incremental implementation phases with smoke-test checkpoints.
18. Explicit list of deferred features and extension points.

Grok should flag conflicts with existing Aurora architecture before changing core models.

## 64. Recommended Implementation Phasing

A reasonable planning sequence is:

### Phase A — Repository Audit and Contracts
Establish current reality, Aurora Action boundaries, interfaces, data ownership, and migration plan.

### Phase B — Musical Engine Core
Internal timing, canonical state, provider abstraction, subdivisions, scheduling, diagnostics.

### Phase C — MIDI Timing Provider
MIDI Clock/transport parsing, lock, smoothing, loss/fallback, diagnostics.

### Phase D — AME Core
Normalized MIDI events, rule evaluation, scopes, actions, state model.

### Phase E — Trigger Groups and Sequences
Stateful sequences, reset policies, sequence modes, conditioning.

### Phase F — Dedicated AME UX
Window, sidebar/context browser, visual mapping editor, Inspector, Learn, live monitor.

### Phase G — Quantization Integration
AME actions scheduled through Musical Engine; timing-aware diagnostics.

### Phase H — Song/Section Integration
Inheritance, section entry/exit behavior, contextual mappings, end-to-end performance flows.

### Phase I — Reliability / Smoke-Test Closeout
Hardware MIDI testing, reconnects, clock loss, long-running stability, deterministic behavior.

The exact order may change after repository audit, but the dependency direction must remain clean.

## 65. Final Product Principle

Aurora should eventually understand three complementary dimensions of a live performance:

**Musical Time + Show Structure + Live Performance Events**

The Musical Engine owns musical truth and synchronization.

The Advanced MIDI Engine interprets live MIDI behavior in context.

The future Effects Engine turns musical time into dynamic visual motion.

External show-management systems may coordinate the larger production while Aurora remains the authoritative lighting specialist.

The result should feel less like configuring protocol messages and more like **teaching Aurora how to listen to, understand, and respond to a live show**.
