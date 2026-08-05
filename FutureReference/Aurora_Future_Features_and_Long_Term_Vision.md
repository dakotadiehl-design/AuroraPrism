# Aurora Future Features & Long-Term Vision

**Status:** Future-reference design note\
**Purpose:** Preserve ambitious feature ideas while Aurora's core
architecture is still young enough to accommodate them.\
**Priority note:** Advanced MIDI and performance-event processing is a
particularly important part of Aurora's long-term identity.

------------------------------------------------------------------------

## 1. Product Direction

Aurora should ultimately become more than a conventional DMX lighting
controller. The long-term goal is a **lighting performance instrument**:
a system that understands musical structure, accepts expressive
real-time inputs, controls fixtures semantically rather than merely by
channel number, and can assist a performer or lighting operator without
taking creative control away from them.

The near-term product can remain straightforward and deterministic.
These ideas should influence architectural decisions now so that future
capabilities do not require dismantling the core application.

The key architectural themes are:

-   Semantic fixture control
-   Rich musical and performance events
-   Extremely capable MIDI input and mapping
-   Spatial awareness
-   UI-independent show execution
-   Remote clients
-   Deterministic, reproducible show behavior
-   Graceful degradation when hardware or networks fail

------------------------------------------------------------------------

# 2. Advanced MIDI Performance Engine

## 2.1 MIDI Is a Core Aurora Feature

MIDI should not be treated as a thin compatibility layer where:

`MIDI Note 38 -> Trigger Cue 47`

Aurora should treat MIDI as a first-class **performance input
language**.

The MIDI system should eventually be capable of receiving events from
electronic drums, keyboards, foot controllers, DAWs, MIDI control
surfaces, guitar rigs, custom controllers, and other performance
equipment, then transforming those events into expressive lighting
behaviors.

This is one of the most important areas in which Aurora can distinguish
itself from conventional lighting software.

## 2.2 Expressive Event Mapping

Mappings should be able to use more than note identity.

Potential inputs include:

-   Note number
-   Note-on / note-off
-   Velocity
-   MIDI channel
-   Continuous Controller (CC)
-   Program Change
-   Pitch Bend
-   Aftertouch
-   Polyphonic pressure where available
-   Timing between events
-   Repeated-event rate
-   Simultaneous/chorded events
-   Source device or virtual MIDI endpoint

A mapping might therefore mean:

> Snare Note 38 increases the audience fixtures by 25% and decays them
> to their previous level over 180 ms.

rather than:

> Snare Note 38 launches a static cue.

Velocity could control the intensity of the accent, allowing the
lighting response to reflect how hard the drummer actually played.

## 2.3 Conditional MIDI Rules

MIDI behavior should be context-aware.

Example:

``` text
IF:
    source == "Drum Module"
    AND note == 38
    AND currentSong == "Money for Nothing"
    AND currentSection == "Intro"
THEN:
    triggerBehavior("MTV Snare Hit")
```

The same snare note could perform a completely different lighting
function during another song or another section of the same song.

Useful conditions could include:

-   Current song
-   Current song section
-   Current cue
-   Fixture/group state
-   Performance mode
-   Modifier buttons/pedals
-   MIDI source
-   Current energy level
-   Whether a behavior is already active
-   Time since the previous event
-   User-defined variables

This implies that Aurora should eventually contain a lightweight
event/rule engine rather than only a flat MIDI mapping table.

## 2.4 MIDI Behaviors

A MIDI event should be able to invoke reusable **behaviors**.

Examples:

-   Flash a group and decay
-   Temporarily raise intensity
-   Momentarily override color
-   Start a movement envelope
-   Advance a song section
-   Trigger a palette
-   Fire a white hit
-   Apply a spatial ripple
-   Temporarily increase effect speed
-   Toggle a layer
-   Start/stop an effect
-   Change an Aurora variable
-   Trigger GO
-   Trigger a safe, rate-limited strobe effect
-   Execute a compound sequence of actions

Behaviors should ideally be reusable independently of specific fixtures.

## 2.5 Envelopes

Aurora should eventually support musical envelopes for lighting
parameters.

For example:

``` text
Snare Hit
   |
   +-- Attack: 0 ms
   +-- Peak: +35% intensity
   +-- Hold: 40 ms
   +-- Decay: 220 ms
   +-- Curve: exponential
```

This would allow percussion-triggered lighting to feel organic rather
than like buttons being switched on and off.

## 2.6 Drum-Aware Lighting

Electronic drums are an especially interesting Aurora input.

Rather than treating every drum as an unrelated trigger, Aurora could
classify events by musical role:

-   Kick -\> pulse / low-level intensity energy
-   Snare -\> accent
-   Hi-hat -\> motion or texture
-   Toms -\> positional or spatial movement
-   Crash -\> major accent or transition
-   Ride -\> sustained movement/texture

This should remain configurable. Aurora should not assume that every
drummer or show wants the same behavior.

## 2.7 Performance Energy Model

A future MIDI subsystem could calculate a continuously changing
**performance energy value** from incoming events.

For example:

``` text
Energy
100 |                       ████
 80 |                 ██████████
 60 |          █████████████████
 40 |     ██████████████████████
 20 |████████████████████████████
  0 +----------------------------
       Verse     Build    Chorus
```

Kick frequency, snare velocity, cymbal activity, note density, or other
signals could contribute to the energy value.

Lighting effects could then respond to energy without being tied
directly to individual notes.

Examples:

-   Movement becomes larger as energy increases.
-   Saturation increases.
-   Audience fixtures gradually participate.
-   Effect speed rises.
-   Beam width changes.
-   Chorus lighting becomes naturally larger when the band actually
    plays harder.

This should complement programmed song structure, not replace it.

## 2.8 MIDI Safety and Predictability

Because MIDI may directly influence live output, the system must remain
deterministic and safe.

Future design should consider:

-   Rate limiting
-   Event debouncing
-   Maximum strobe rates
-   Runaway-controller protection
-   Stuck-note handling
-   MIDI source disconnect detection
-   Per-mapping intensity limits
-   Panic/reset command
-   Clear indication of active overrides
-   Logging/debug visualization
-   Ability to globally disable performance MIDI without stopping the
    show

A performer should be able to hit a drum pad enthusiastically without
accidentally creating a lighting denial-of-service attack.

------------------------------------------------------------------------

# 3. Music-Aware Song Mode

Song Mode should eventually represent musical structure rather than
merely storing a linear cue list.

Example:

``` text
Intro
Verse 1
Chorus
Verse 2
Chorus
Solo
Bridge
Final Chorus
Outro
```

Each section could contain a lighting character:

-   Palette
-   Intensity range
-   Movement style
-   Effect layers
-   Audience participation
-   Performer specials
-   MIDI rules
-   Transition behavior

The operator should be able to extend a chorus, skip a section, repeat a
solo, or follow an improvised arrangement without losing
synchronization.

Aurora should follow the performance rather than force the band to
follow a rigid timeline.

------------------------------------------------------------------------

# 4. Aurora Look Generator

Aurora could eventually generate useful starting looks from semantic
instructions.

Example parameters:

``` text
Fixtures: Back Pars + Movers
Mood: Brooding
Energy: 35%
Movement: Slow
Colors: Cool
Era: 1980s Arena Rock
```

Aurora could produce several candidate looks that the designer can
audition, edit, and save.

This should be built on a deterministic lighting-design grammar rather
than uncontrolled random DMX generation.

The workflow could be:

`Generate -> Audition -> Tweak -> Save as Palette/Look`

This could dramatically reduce the time required to build a large song
library.

------------------------------------------------------------------------

# 5. Busking Mode

Aurora should eventually provide a dedicated surface for improvisational
lighting.

Possible high-level controls:

``` text
COLOR
RED | BLUE | GOLD | WHITE

ENERGY
SLOW | MEDIUM | FAST | EXTREME

STYLE
WASH | BEAMS | CROWD | SILHOUETTE

MOMENTARY
HIT | BLINDER | STROBE | BLACKOUT
```

The important distinction is that busking controls should be able to
manipulate properties or layers of the current look rather than always
replacing the entire cue.

This makes Aurora playable as an instrument.

------------------------------------------------------------------------

# 6. Aurora Remote as a Performance Surface

The remote web/iPad experience should eventually provide purpose-built
views instead of simply shrinking the desktop application.

Potential modes:

### Stage View

-   Current song
-   Current section
-   Next section
-   GO
-   Back
-   Blackout
-   Haze
-   Engine status
-   MIDI status
-   Network/output status

### Lighting View

-   Fixture groups
-   Palettes
-   Busking controls
-   Effects
-   Intensity masters
-   Overrides

### Performer View

A deliberately simplified surface assigned to a band member.

For example, a drummer could receive four large pads for approved
lighting accents while the guitarist/vocalist receives song navigation
and status controls.

Multiple remote clients should eventually be able to connect
simultaneously with independent roles and permissions.

------------------------------------------------------------------------

# 7. Fixture-Independent Semantic Programming

Aurora should increasingly describe **intent** rather than raw fixture
values.

Instead of:

``` text
Chauvet LP12 #3
Red = 255
Green = 40
Blue = 0
Dimmer = 184
```

prefer concepts such as:

``` text
Stage Left Wash
Color = Warm Amber
Intensity = 72%
```

Aurora's fixture engine resolves the requested intent into the
capabilities of the patched device.

This creates a path toward portable shows.

A future **Adapt Show to New Rig** feature could translate a programmed
show onto replacement or rented fixtures while preserving:

-   Color intent
-   Relative intensity
-   Fixture roles
-   Movement
-   Beam characteristics
-   Spatial effects

------------------------------------------------------------------------

# 8. Stage Spatial Awareness

Fixtures should eventually be able to carry spatial metadata:

-   X position
-   Y position
-   Z position
-   Orientation
-   Role
-   Coverage region

Aurora could then execute semantic spatial effects such as:

> Sweep from stage left to stage right.

or:

> Ripple outward from the drummer.

The engine determines which fixtures participate and calculates timing
based on physical position.

Spatial information would also support visualization, automated rig
adaptation, performer tracking, and more sophisticated effects.

------------------------------------------------------------------------

# 9. Performer Tracking

A much later capability could allow Aurora to understand the approximate
location of performers.

Potential technologies might include:

-   UWB tags
-   Camera/computer vision
-   Bluetooth-based systems
-   External tracking systems
-   OSC/network position feeds

A moving-light special could then target a semantic performer:

``` text
Target: Lead Guitar
```

rather than storing a fixed pan/tilt position.

This is deliberately a far-future feature, but semantic performer
targets are worth keeping in mind when designing the control model.

------------------------------------------------------------------------

# 10. Lighting DNA

Aurora could eventually capture the visual vocabulary of a band, show,
venue, or designer.

A show's Lighting DNA might describe tendencies such as:

-   Warm amber/red base
-   Restrained verse movement
-   Saturated chorus washes
-   White snare accents
-   Audience lighting during singalong sections
-   Aggressive movement during guitar solos
-   Minimal unnecessary strobing

A command such as:

**Create Song From Haywire DNA**

could produce a starting design that already resembles the rest of that
band's show.

The designer would refine the generated result rather than begin from an
empty cue list.

------------------------------------------------------------------------

# 11. Rehearsal Recorder

Aurora could record a rehearsal as an event timeline.

Recorded information might include:

-   MIDI events
-   MIDI velocity
-   Cue changes
-   Song navigation
-   Section changes
-   Operator actions
-   Busking actions
-   Tempo information
-   Effect changes
-   Performance energy
-   Manual fixture/group overrides

The user could scrub through the recording afterward.

Example:

``` text
01:42:31 | Chorus 2 | Snare | White Hit | GO
```

If an improvised lighting moment worked especially well, the user could
select it and choose:

**Create Cue From Performance**

This turns improvisation into a programming tool.

------------------------------------------------------------------------

# 12. Resilience and Safe-Look System

Aurora should be designed for live performance, where failures cannot
simply produce a modal error dialog and stop the show.

If an Art-Net node disappears:

``` text
Stage Right Node Lost
14 fixtures affected
Output continues on remaining nodes
```

Aurora should preserve as much of the show as possible.

Future resilience features could include:

-   Node health monitoring
-   DMX interface monitoring
-   MIDI source monitoring
-   Automatic output recovery
-   Effect adaptation when fixtures disappear
-   Network reconnect
-   Clear degraded-state indication
-   Event logging

## Safe Look

Aurora should eventually provide an immediate **SAFE LOOK** command.

The exact look could be user configurable, but a typical configuration
might produce:

-   Front wash
-   Stage wash
-   Static safe color
-   No movement
-   No strobe
-   Predictable intensity

If a controller, MIDI device, effect, or network component behaves
unexpectedly, the operator can instantly return the rig to a useful
state while the performance continues.

------------------------------------------------------------------------

# 13. Aurora Show Engine

The ultimate architecture should allow the show engine to exist
independently of the primary desktop UI.

Conceptually:

``` text
                    +------------------+
                    |   Aurora macOS   |
                    | Programming/UI   |
                    +--------+---------+
                             |
                             |
                    +--------v---------+
                    |                  |
 MIDI ------------->|  AURORA ENGINE   |------------> DMX
 OSC -------------->|                  |------------> Art-Net
 Remote ----------->|                  |------------> sACN
 Tracking ---------->|                  |
                    +--------+---------+
                             |
                       Show State
```

The macOS application programs and supervises the engine, but the engine
owns live show execution.

That creates a path toward a dedicated headless machine such as a Mac
mini installed in the lighting rack.

A future startup screen might simply report:

``` text
AURORA ENGINE

Show: Haywire Summer 2028

Fixtures       38 / 38
Art-Net        ONLINE
DMX            ONLINE
MIDI           ONLINE
Remote         2 CONNECTED

             READY
```

The main laptop would no longer need to remain physically on stage or at
FOH for the entire performance.

------------------------------------------------------------------------

# 14. Architectural Guidance for Today's Aurora

Most features in this document should **not** be implemented yet.

However, today's architecture should avoid decisions that make them
unnecessarily difficult later.

In particular, preserve clean abstractions for:

1.  **Events**\
    MIDI, UI actions, OSC, remote actions, song events, and future
    tracking inputs should be capable of entering a common event
    architecture.

2.  **Behaviors**\
    A lighting action should increasingly be representable independently
    of the device that triggered it.

3.  **Semantic fixture parameters**\
    Prefer concepts such as intensity, color, position, beam, role, and
    group over leaking raw DMX channel assumptions throughout the
    application.

4.  **Show state**\
    Current song, section, cue, layers, overrides, and performance state
    should have a clear authoritative model.

5.  **Engine/UI separation**\
    Avoid making critical show execution dependent on SwiftUI view
    lifecycle or desktop-window state.

6.  **Spatial metadata**\
    Fixture models should be extensible enough to carry physical
    position and orientation later.

7.  **Multiple control clients**\
    Commands should not inherently assume that the desktop UI is the
    only controller.

8.  **Deterministic execution**\
    Even future intelligent/generative features should ultimately
    resolve into inspectable, reproducible show data.

------------------------------------------------------------------------

# 15. Long-Term North Star

Aurora should eventually feel less like software that **plays lighting
cues** and more like an instrument that **performs lighting alongside
the band**.

The drummer can contribute accents.

The guitarist can trigger transitions.

The operator can busk.

Song Mode understands where the performance is.

The rig understands where fixtures are.

The engine understands what those fixtures are capable of.

The remote understands what each performer needs to control.

And underneath all of it, Aurora remains deterministic enough that when
the band hits the first note in front of a crowd, the lighting designer
knows exactly what the system is going to do.

That combination of **musical intelligence, expressive MIDI, semantic
lighting control, and live-show reliability** should be Aurora's
long-term differentiator.
