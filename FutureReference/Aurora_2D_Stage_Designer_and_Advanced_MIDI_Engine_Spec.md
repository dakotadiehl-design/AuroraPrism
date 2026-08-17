# Aurora Feature Specification: 2D Stage Designer / Live Preview + Advanced MIDI Engine

**Status:** Planned feature specification\
**Audience:** Grok / Aurora development\
**Date:** 2026-08-13\
**Priority:** High

> Review this specification against the current Aurora repository before
> coding. Preserve existing engine authority, architectural guardrails,
> migrations, and tests. Stop after producing a repo-aware
> implementation plan unless explicitly told to implement.

## 1. Product Goal

Plan two first-class Aurora systems:

1.  **2D Stage Designer and Live Preview**
2.  **Advanced MIDI Performance Engine**

Both must use Aurora's authoritative semantic show state. Do not create
a preview-only lighting engine, MIDI-only fixture state, direct
MIDI-to-DMX path, or SwiftUI-owned output state.

``` text
UI / MIDI / OSC / Remote
          |
          v
 ControlActionRouter
          |
          v
 LightingEngine / DocumentSession
          |
          v
     OutputManager
          |
          v
 DMX / Art-Net / sACN
```

# Part I: 2D Stage Designer and Live Preview

## 2. Reference and Intent

Use the supplied Lightkey screenshot as a UX reference, not a
pixel-for-pixel cloning requirement. Aurora should provide a spatial
stage layout with fixture symbols, beams/glow, scenic context,
labels/regions, and live fixture output.

A critical Lightkey behavior to reproduce is the **stage/background
color following the dominant color of the active lighting look**. In
Aurora this must be derived from the **resolved live output**, not
merely the selected cue, because Programmer changes, effects, MIDI
behaviors, masters, overrides, and transitions may all affect the
visible result.

## 3. One Authoritative Output State

``` text
Cue Playback ---------+
Effects --------------+
Programmer ------------+
MIDI Behaviors --------+
Overrides -------------+
Masters ---------------+
                       |
                       v
              Aurora Resolved State
                       |
              +--------+--------+
              |                 |
              v                 v
       Physical Output      Preview Snapshot
              |                 |
              v                 v
      DMX/Art-Net/sACN      2D Stage View
```

The preview and physical fixtures must observe the same resolved state.

## 4. Semantic Preview Snapshot

Do not reverse-engineer fixture semantics from universe bytes in
SwiftUI. Introduce a read-only semantic presentation snapshot derived
from authoritative resolved engine state.

Conceptually:

``` swift
struct StagePreviewSnapshot {
    var frameIndex: UInt64
    var timestamp: TimeInterval
    var fixtures: [FixturePreviewState]
    var dominantColor: PreviewColor
    var activeCueContext: PreviewCueContext?
}

struct FixturePreviewState {
    var fixtureID: FixtureID
    var intensity: Double
    var color: PreviewColor?
    var pan: Double?
    var tilt: Double?
    var beam: BeamPreviewState?
    var strobe: StrobePreviewState?
}
```

Adapt names/ownership to current Aurora conventions.

## 5. Persisted Stage Model

Persist visual/spatial layout separately from transient output. It
should support canvas configuration, fixture placements, scenic
elements, visual regions, labels, and later view presets.

Fixture placement should reference the existing fixture ID and include
X/Y position, rotation, and presentation scale. Leave an extensible path
for future height/Z and orientation metadata without building full 3D
now.

Changing visual placement must not alter DMX patching.

## 6. Edit Mode

Support:

-   Drag/rotate fixtures
-   Multi-select
-   Align/distribute
-   Snap and optional grid
-   Add/remove scenic objects
-   Labels and visual regions
-   Layer ordering
-   Lock/hide elements
-   Zoom, pan, fit-to-view
-   Undo/redo using existing Aurora editing conventions where
    appropriate

## 7. Live Mode

Support:

-   Real-time fixture visualization
-   Locked geometry
-   Fixture/group selection
-   Current output feedback
-   Dominant background response
-   Cue/song context where useful
-   Smooth, low-overhead updates

Live Mode must prevent accidental geometry edits.

## 8. Fixture Symbols

Initial categories:

-   PAR/wash
-   Bar
-   Moving head
-   Spot/profile
-   Blinder
-   Strobe
-   Laser
-   Fog
-   Haze
-   Generic fixture

Symbols may show fixture name/number, current color, intensity,
selection, offline/error state, and beam direction. Keep them schematic
and legible rather than photorealistic.

## 9. Color, Intensity, Beam, and Strobe

Use semantic fixture/output state to approximate visible color for
RGB-family fixtures and semantic color-wheel fixtures where data
permits. Intensity should influence symbol illumination, glow, beam
opacity, and dominant-color contribution.

Static washes may render simple translucent cones. Moving fixtures
should eventually show pan, tilt, beam direction, and approximate beam
width. Initial geometry should remain deliberately simple.

Strobe/dynamic output may be preview-rate-limited for usability, but
preview throttling must never alter physical output timing.

## 10. Dominant Background Color

**Required.**

For each relevant active color-capable fixture:

1.  Obtain resolved visible color.
2.  Obtain resolved intensity.
3.  Apply a weighting factor.
4.  Accumulate weighted color contribution.
5.  Normalize.
6.  Smooth over time.
7.  Map into a restrained background treatment.

``` text
fixture contribution = fixtureColor * intensity * visualWeight
```

Possible weights include intensity, fixture role, visibility, and
optional importance. Use temporal smoothing so rapid effects do not make
the entire canvas flicker. When no meaningful colored output exists, use
Aurora's neutral stage background.

## 11. Selection Integration

Selection must be bidirectional:

``` text
Fixture Browser <-> 2D Stage View <-> Programmer / Inspector
```

Use Aurora's existing selection authority.

## 12. Scenic Elements and Regions

Initial useful elements include performers, vocalist, guitarist,
bassist, drummer/drum kit, keyboard, riser, truss, stage edge, audience
area, dance floor, generic regions, and text labels.

Allow future semantic roles such as `leadGuitar`, `audience`, or
`drumRiser`.

Support labeled regions such as `Stage Rear Uplights`, `Front Wash`, or
`Dance Floor`. A visual region may optionally reference an existing
Aurora fixture group. Avoid contradictory group authorities.

## 13. UI Integration

Do not cram the designer into a small panel. Treat it as a first-class
workspace or substantial workspace surface and reconcile the final
location against the current UI-11 workspace/layout architecture. A
compact read-only preview may exist elsewhere later.

## 14. Performance Requirements

-   Never block the engine frame loop
-   Bounded snapshot generation
-   Independently throttled UI rendering
-   Prefer immutable snapshot transfer
-   Avoid expensive per-frame allocations
-   Do not decode raw DMX in SwiftUI
-   Cache/compile presentation metadata where appropriate
-   30-60 FPS visual refresh is desirable, but physical output timing
    always wins

## 15. Future Stage Extensions

Preserve paths toward height/Z, full orientation, spatial
sweeps/ripples, 3D visualization, photometric approximation, camera
calibration, performer tracking, AI Show Designer integration,
venue-specific layouts, and focus/target objects. Do not implement them
now.

# Part II: Advanced MIDI Performance Engine

## 16. Goal

Evolve MIDI from event-to-command mapping into a rich **performance
control engine**:

``` text
MIDI Event
    |
    v
Normalize / Classify
    |
    v
Rules + Context
    |
    v
Behavior
    |
    v
Envelope / Modulation
    |
    v
Aurora Action / Engine Parameter
```

MIDI should become one of Aurora's defining differentiators while
remaining deterministic and inspectable.

## 17. Preserve Rich MIDI Events

Preserve source endpoint, channel, message type, note, velocity, CC
number/value, Program Change, Pitch Bend, channel pressure/aftertouch,
poly pressure where supported, timestamp, and note-on/off. Leave future
room for MIDI 2.0/UMP without requiring it initially.

## 18. Processing Pipeline

``` text
MIDI Sources
     |
     v
Event Parser / Normalizer
     |
     v
Contextual Rule Engine
     |
     v
Behavior Engine
     |
     v
Envelope / Modulation
     |
     v
Existing Aurora Action / Engine Authority
```

Context may include current Song, Song Section, Cue List, Cue,
Performance Energy, user variables, modifier state, and time. Do not
execute behavior logic in SwiftUI.

## 19. Rule Model and Context

A rule conceptually contains Trigger, Conditions, Behavior, Priority,
and Safety Constraints.

Example:

``` text
TRIGGER
    Source: Drum Module
    Channel: 10
    Note: 38
    Velocity: >= 30

CONDITIONS
    Song: Money for Nothing
    Section: Intro

BEHAVIOR
    MTV Snare Accent
```

Potential scopes: Global, Show, Song, Song Section, Cue List, Cue,
Performance Mode. The same MIDI event may intentionally do different
things in different musical contexts.

## 20. Reusable Behaviors

Prefer semantic reusable behaviors such as White Accent, Audience Punch,
Kick Pulse, Snare Flash, Cymbal Bloom, Tom Ripple, Guitar Solo Lift,
Chorus Energy Boost, Color Shift, and Movement Burst.

Example:

``` text
Behavior: Snare White Accent
Target: Audience Pars
Parameter: Intensity
Operation: Add
Peak: +35%
Envelope: Attack 0 ms / Hold 40 ms / Decay 220 ms
Velocity Scaling: Enabled
```

## 21. Envelopes and Velocity

Support time-based modulation with an initial Attack/Hold/Decay/Release
model. Initial curves may include Linear, Ease-in, Ease-out,
Exponential, and Logarithmic.

Velocity should scale behavior magnitude with configurable response
curves rather than a fixed linear assumption.

## 22. Continuous Controllers, Pitch Bend, Aftertouch

CC should continuously control semantic parameters with input/output
range, invert, deadband, smoothing, curve, and relative/absolute options
where appropriate.

Examples:

``` text
CC1  -> Master effect intensity
CC11 -> Audience lighting level
CC20 -> Movement speed
CC21 -> Movement size
CC22 -> Color blend
```

Pitch Bend and aftertouch should fit cleanly into the event model for
expressive palette, intensity, or effect modulation.

## 23. Multiple Actions Per Event

One event may trigger coordinated behaviors:

``` text
Crash Note 49
 |
 +-- White stage hit
 +-- Audience flash
 +-- Movement-speed burst
 +-- Temporary color desaturation
```

Support controlled fan-out without duplicate low-level mappings.

## 24. Drum-Aware Processing

Electronic drums are a primary use case. Allow optional semantic roles
such as Kick, Snare, Hi-Hat, Tom 1, Tom 2, Floor Tom, Ride, Crash,
China, and Other.

A device/drum profile should map hardware notes into semantic instrument
roles:

``` text
Roland Kit Note 38 -> Semantic Instrument: Snare -> Song Rule -> Snare Accent Behavior
```

Changing drum hardware should ideally require changing the device
profile rather than every song.

## 25. Performance Energy

Eventually derive a continuously changing performance-energy value from
MIDI activity. Inputs may include note density, kick rate, snare
velocity, cymbal activity, tom fills, average velocity, and user-defined
weights.

Use it to modulate effect speed, movement size, saturation, audience
participation, beam intensity, and accent magnitude. It complements
programmed Song structure rather than replacing it.

## 26. Behavior Blending

Define explicit coexistence with Playback, Effects, Programmer, Masters,
and other MIDI behaviors. Potential operations: Replace, Add, Multiply,
Max, Min, Temporary Override.

Do not allow precedence to emerge accidentally from implementation
order. Document and test priority/resolution semantics.

## 27. MIDI Learn and Monitor

MIDI Learn should identify source, channel, type, note/CC, and value,
then let the user select an action/behavior and optionally configure
conditions, envelope, and scaling. Keep simple footswitch-to-GO mapping
easy.

Provide a MIDI Monitor showing timestamp, source, channel, type,
note/CC, value, velocity, matched rule, triggered behavior, and result.

## 28. MIDI Safety

Required considerations:

-   Rate limiting
-   Configurable debouncing
-   Stuck-note handling
-   Device disconnect handling
-   Flood protection
-   Maximum behavior concurrency
-   Strobe safety limits
-   Configurable intensity constraints
-   Panic/reset
-   Global MIDI-behavior disable
-   Clear active-override indication

MIDI processing must never block the lighting frame loop.

## 29. Progressive UX

Basic mode:

``` text
Input -> Action
```

Advanced mode:

``` text
Input
Conditions
Behavior
Envelope
Scaling
Priority
Safety
```

## 30. Song Mode Relationship

Design context for future music-aware sections such as Intro, Verse,
Chorus, Solo, Bridge, and Outro. Do not require full advanced Song Mode
before building the MIDI foundation.

# Part III: Integration and Architecture

## 31. Stage + MIDI

A MIDI-triggered accent should automatically appear in Stage Preview
because the preview observes resolved engine state. There must be no
special MIDI-to-preview path.

Future spatial examples:

``` text
Tom 1      -> Stage Left
Tom 2      -> Center
Floor Tom  -> Stage Right
Crash      -> Full Stage
```

or:

``` text
Tom Fill -> Ripple outward from drummer
```

A major workflow goal is to let the user program MIDI behavior and watch
it immediately in Stage Preview without physical fixtures connected.

## 32. Shared Behavior Abstraction

``` text
MIDI --------+
UI ----------+
Remote ------+
OSC ---------+
Future AI ---+
             |
             v
         Behavior
             |
             v
       Aurora Engine
```

A behavior should not care which control source triggered it.

## 33. Determinism and Persistence

Given identical show state, input event, time, and rule configuration,
Aurora should produce predictable behavior. AI/probabilistic logic does
not belong in this live critical path.

Persisted concepts will likely include StageLayout,
StageFixturePlacement, StageElement, StageRegion, MIDIRule,
MIDIBehavior, Envelope, and Device/DrumProfile. Use existing Aurora
schema-versioning and migration conventions.

## 34. Testing

Stage tests should cover layout persistence, placement, patch/deletion
changes, selection synchronization, snapshot generation, color
resolution, dominant-color calculation, background smoothing, moving
fixture state, missing definitions, offline fixtures, and performance
bounds where practical.

MIDI tests should cover parsing, source/channel matching, velocity/CC
ranges, context conditions, rule priority, multiple matches, envelope
timing, velocity scaling, CC smoothing, behavior blending,
disconnect/flood handling, stuck notes, panic/reset, and
persistence/migration.

Maintain Aurora's existing test discipline.

# Part IV: Implementation Strategy

## 35. Suggested Phasing

Do not implement both features as one giant PR.

### Phase A: 2D Stage Foundation

-   Persisted stage model
-   Fixture placement
-   Basic symbols
-   Edit/Live modes
-   Selection synchronization
-   Semantic preview snapshot
-   Real-time color/intensity rendering
-   Dominant background color

### Phase B: 2D Stage Expansion

-   Beam visualization
-   Moving-head orientation
-   Scenic elements
-   Visual regions
-   Better layout tools
-   Performance tuning

### Phase C: MIDI Core Refactor

-   Rich normalized event model
-   Rule model
-   Context interface
-   Behavior abstraction
-   Compatibility with current mappings

### Phase D: MIDI Behaviors

-   Envelopes
-   Velocity scaling
-   CC modulation
-   Blending
-   Multiple actions
-   MIDI Monitor

### Phase E: Music Performance Features

-   Drum profiles
-   Semantic drum roles
-   Performance Energy
-   Song-context rules
-   Advanced diagnostics

Each phase should be independently testable and shippable.

## 36. Compatibility

Existing shows and MIDI mappings must continue to function. A simple
mapping such as `Note 60 -> GO` must remain easy to represent. The
advanced engine should generalize existing behavior rather than
invalidate it.

## 37. Initial Non-Goals

Do not let scope balloon into full 3D/ray tracing, accurate
photometrics, CAD import, camera/performer tracking, AI show generation,
MIDI 2.0, Ableton-style timeline synchronization, audio beat detection,
automatic choreography, or cloud services.

# Part V: Acceptance Criteria

## 38. 2D Stage Designer

Successful when:

1.  User can create a visual stage layout.
2.  Patched fixtures can be placed and labeled.
3.  Layout persists with the show/project.
4.  Fixture selection synchronizes with Aurora's normal selection model.
5.  Live fixture color and intensity are visible.
6.  Preview represents resolved engine state.
7.  Canvas background subtly follows dominant resolved lighting color.
8.  Edit and Live modes are clearly separated.
9.  Preview remains responsive without degrading physical output.
10. Architecture supports future spatial metadata without requiring 3D
    now.

## 39. Advanced MIDI Engine

Successful when:

1.  Existing simple mappings still work.
2.  Events preserve source, channel, type, and expressive values.
3.  Rules can use contextual conditions.
4.  Rules can trigger reusable behaviors.
5.  Behaviors can use time envelopes.
6.  Velocity can scale magnitude.
7.  CC can continuously modulate parameters.
8.  One event can trigger multiple coordinated actions.
9.  MIDI Learn remains easy for simple mappings.
10. MIDI Monitor explains events and resulting behavior.
11. MIDI processing cannot destabilize the live engine.
12. Architecture leaves a clean path toward drum semantics, Performance
    Energy, and future Song context.

# 40. Guiding Product Principle

The Stage Designer lets Aurora **see and represent the rig spatially**.

The MIDI Engine lets Aurora **respond musically to performers**.

Together they move Aurora toward the long-term goal:

> **Aurora should feel less like software that merely plays lighting
> cues and more like a lighting instrument that performs alongside the
> band.**

The foundation must remain deterministic, inspectable, safe, testable,
responsive, fixture-aware, independent of SwiftUI lifecycle, and
reliable enough for live performance.

# 41. Instructions to Grok Before Coding

Before writing code:

1.  Review the current Aurora repository and this specification
    together.
2.  Identify exact existing types/modules that should own Stage layout
    persistence, preview snapshot generation, Stage rendering, MIDI
    rules, MIDI behaviors, and MIDI context.
3.  Preserve `ControlActionRouter`, engine authority, and output
    architecture unless a clearly justified change is required.
4.  Do not decode semantic preview state from raw DMX if resolved
    semantic engine state is available earlier.
5.  Do not execute behavior/envelope logic in SwiftUI.
6.  Do not create a parallel engine for preview or MIDI.
7.  Propose schema changes and migrations before persisted-model
    changes.
8.  Split implementation into bounded phases/PRs.
9.  Identify compatibility risks for existing shows and MIDI mappings.
10. Identify tests required for every phase.
11. **Stop after producing the repo-aware implementation plan unless
    explicitly instructed to begin coding.**

The immediate objective is a **repo-aware implementation plan**, not
immediate implementation.
