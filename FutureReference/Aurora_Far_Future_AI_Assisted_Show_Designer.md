# Aurora Far-Future Feature: AI-Assisted Show Designer

**Status:** Far-future concept  
**Purpose:** Preserve the architectural and product vision for multimodal AI-assisted lighting design without turning it into a current implementation requirement.

## 1. Vision

A future version of Aurora could include an **AI-Assisted Show Designer** capable of using creative reference material to build a starting lighting design for a song.

The user could provide some combination of:

- Song audio
- Performance video
- Music video
- Concert footage
- Stage photographs
- Lighting-reference photographs
- Existing Aurora shows
- Existing Band Lighting DNA
- Stage and fixture configuration
- Text instructions describing the desired mood or dramatic intent

Example:

> “Here is the recording and two concert videos. Keep the verses dark and atmospheric, make the choruses progressively larger, and make the final guitar solo enormous.”

Aurora would analyze those inputs and generate an editable **Aurora Song Profile**.

The key design principle is:

> **AI should propose creative intent. Aurora should remain responsible for producing deterministic lighting output.**

The AI must not directly generate or transmit DMX values.

## 2. High-Level Architecture

```text
Photos / Video / Audio / Prompt
               |
               v
     +-----------------------+
     | AI Analysis Layer     |
     | multimodal reasoning  |
     +-----------+-----------+
                 |
                 v
        Aurora Song Profile
          structured data
                 |
                 v
     +-----------------------+
     | Aurora Show Designer  |
     | validation/compiler   |
     +-----------+-----------+
                 |
                 v
       Palettes / Behaviors
       Sections / MIDI Rules
       Effects / Transitions
                 |
                 v
        Aurora Show Engine
                 |
                 v
       DMX / Art-Net / sACN
```

This separation is critical.

The AI layer deals with concepts such as mood, energy, color, movement, focus, contrast, musical sections, dramatic progression, performer emphasis, audience engagement, and suggested MIDI interactions.

Aurora's semantic fixture and show engines translate those concepts into valid behavior for the actual patched rig.

## 3. Structured Aurora-Native Output

The AI should be required to produce data matching a strict Aurora schema, rather than arbitrary prose.

```json
{
  "song": "Example Song",
  "character": {
    "mood": ["brooding", "cinematic"],
    "baseEnergy": 0.35,
    "dominantPalette": ["deep_blue", "lavender"]
  },
  "sections": [
    {
      "name": "Verse 1",
      "energy": 0.25,
      "palette": "deep_blue",
      "movement": {
        "style": "slow_sweep",
        "amount": 0.15
      },
      "audienceLighting": 0.0
    },
    {
      "name": "Final Chorus",
      "energy": 0.90,
      "palette": "blue_white",
      "movement": {
        "style": "wide",
        "amount": 0.75
      },
      "audienceLighting": 0.55
    }
  ]
}
```

Importantly, this structure contains no DMX addresses.

The AI should express semantic intent such as:

```text
Palette = Deep Blue
Energy = 0.35
Movement = Slow / Wide
Focus = Lead Guitar
Audience Engagement = Low
```

Aurora should remain responsible for mapping that intent onto patched fixtures.

## 4. Provider-Independent AI Architecture

The preferred long-term design is hybrid and provider-independent.

```text
Aurora
 |
 +-- Core Engine
 +-- MIDI Engine
 +-- Fixture Engine
 +-- Song Engine
 +-- AI Provider Abstraction
       |
       +-- Cloud Provider
       +-- Alternate Cloud Provider
       +-- Local Model
       +-- Future Provider
```

A conceptual Swift interface might resemble:

```swift
protocol AIShowDesigner {
    func analyze(
        request: ShowDesignRequest
    ) async throws -> SongProfile
}
```

Possible implementations:

```text
CloudShowDesigner
LocalShowDesigner
HybridShowDesigner
```

The concrete service or model should remain replaceable.

## 5. Cloud First, Hybrid Later

A cloud multimodal model would likely be the most practical initial approach because it can provide image understanding, natural-language interpretation, structured-data generation, visual style analysis, and cross-modal reasoning without requiring Aurora to become an AI-model training project.

Over time, Aurora could support:

```text
AI Processing

(*) Aurora Cloud
( ) Local
( ) Hybrid

[ ] Keep source media on this Mac
[ ] Allow cloud fallback for complex analysis
```

Local inference could handle lightweight edits and transformations. Cloud inference could handle large-context multimodal work such as long video analysis, multiple reference images, new-show generation, or Lighting DNA extraction.

Hybrid mode could preprocess locally, perform complex creative reasoning in the cloud, then validate and compile locally.

## 6. Audio Analysis Pipeline

Audio should not necessarily be delegated entirely to an LLM.

Aurora can extract useful musical information using conventional signal processing and machine-learning techniques.

```text
                   Song Audio
                       |
          +------------+------------+
          |            |            |
          v            v            v
        Tempo        Energy      Spectral
       Detection     Envelope     Analysis
          |            |            |
          +------------+------------+
                       |
                       v
               Musical Timeline
                       |
                       v
                  AI Reasoner
```

Useful locally derived information could include tempo, beat positions, loudness, dynamic changes, onsets, silence, crescendos, section boundaries, repeated structures, and energy curves.

Example:

```text
00:00  Intro
00:18  Verse
00:47  Chorus
01:14  Verse
01:44  Chorus
02:11  Guitar Solo
03:04  Bridge
03:32  Final Chorus
04:15  Outro
```

The AI can reason over this structured musical information instead of inferring everything from raw audio alone.

## 7. Video Analysis Pipeline

Video should also be preprocessed intelligently.

```text
Video
 |
 +-- Scene-change detection
 +-- Representative-frame extraction
 +-- Dominant-color sampling
 +-- Brightness analysis
 +-- Motion/activity analysis
 +-- Timestamp correlation
 |
 +--> Selected Frames + Metadata
                |
                v
        Multimodal AI Model
```

The system could infer characteristics such as dominant palette, contrast, front/backlight balance, movement intensity, audience illumination, solo treatment, and overall visual character.

## 8. Reference-Photo Analysis

The user should eventually be able to provide photographs with instructions such as:

> “I love this look.”

Aurora could extract dominant colors, brightness, contrast, front/back/side-light balance, silhouette usage, beam density, apparent haze, audience illumination, symmetry, performer isolation, and other visual traits.

The goal is not to reproduce another rig literally.

The goal is:

> **Interpret the visual language and adapt it to the user's actual rig.**

## 9. Lighting DNA Integration

AI Show Designer fits naturally with Aurora's future Lighting DNA concept.

```text
Aurora Lighting Knowledge
          |
          v
     Band DNA
          |
          v
    Show / Tour DNA
          |
          v
     Song Profile
```

A user could request:

> “Analyze this recording and create a starting profile using our existing Lighting DNA, but make this song darker and more cinematic.”

The AI receives band style, stage layout, fixture capabilities, song analysis, existing design conventions, and user instructions, then returns an Aurora-native Song Profile.

## 10. Integration With Advanced MIDI

One of the most valuable applications is combining AI Show Designer with Aurora's future MIDI Performance Engine.

Aurora could detect a major drum fill before a final chorus and suggest:

```text
Detected Event:
    Major drum fill before Final Chorus

Suggested MIDI Behavior:
    Tom sequence -> spatial ripple
    Crash -> full-rig white hit
    Following downbeat -> Final Chorus transition
```

Because MIDI mappings can be contextual, those behaviors could apply only during the relevant song section.

AI-assisted design would therefore help **author** sophisticated MIDI behavior rather than replace Aurora's deterministic MIDI architecture.

## 11. Human Review and Approval

AI-generated content must not silently become live show output.

Aurora should always provide an approval and editing stage before generated content is committed.

A future UI could expose:

```text
AI SONG DESIGN

Detected Sections
[x] Intro
[x] Verse 1
[x] Chorus
[x] Solo
[x] Final Chorus

Suggested Palette
[Deep Blue]
[Purple]
[White]

MIDI Suggestions
Snare -> White Accent
Crash -> Section Hit
Tom Fill -> Spatial Ripple

Movement
Intro          10%
Verse          20%
Chorus         45%
Solo           65%
Final Chorus   80%

[ Preview ]
[ Edit ]
[ Regenerate ]
[ Add to Show ]
```

The lighting designer remains the creative authority.

## 12. Validation and Safety Boundary

AI output should be treated as **untrusted design input**.

Before any generated Song Profile becomes part of the show, Aurora should validate it against:

- The Song Profile schema
- Available fixture capabilities
- Allowed effect types
- Strobe safety limits
- Intensity limits
- MIDI safety rules
- Fixture roles
- Stage geometry
- Show-engine constraints
- User-defined restrictions

The AI should never have direct access to DMX output buffers, Art-Net transmission, sACN output, physical DMX interfaces, blackout logic, safety overrides, or engine-critical real-time threads.

The live show remains entirely under Aurora's deterministic control.

## 13. Privacy

Users may submit rehearsal recordings, concert footage, stage photographs, and unreleased music. Aurora should treat privacy as a first-class concern.

Future design should consider clear cloud-upload disclosure, local-only mode, temporary-upload policies, minimal media upload, local preprocessing, deletion controls, and explicit control over provider data handling.

## 14. Cost and Resource Management

Aurora should avoid sending unnecessary raw data.

Audio can be locally analyzed first. Video can be reduced to representative frames and selected clips. Existing shows can be represented semantically rather than uploading irrelevant binary/runtime data.

This improves cost, latency, privacy, reliability, and model-context efficiency.

## 15. Semantic Architecture Is the Enabler

This feature becomes practical only if Aurora itself understands meaningful lighting concepts.

Aurora should increasingly understand:

```text
Fixture Roles
Groups
Colors
Palettes
Positions
Energy
Effects
Behaviors
Song Sections
Performers
MIDI Events
Spatial Relationships
Transitions
Lighting DNA
```

If a show is internally represented only as raw DMX values, AI integration becomes fragile and difficult.

If Aurora understands:

> “Warm backlight at medium energy during Chorus 2”

then humans and AI can reason about the show while the fixture engine separately determines how to realize that request.

## 16. Example End-to-End Workflow

1. Create a new song.
2. Add a song recording, live performance video, inspiration photographs, and existing band Lighting DNA.
3. Enter creative direction in natural language.
4. Aurora performs local audio/video preprocessing.
5. The AI analyzes structured features plus selected multimodal references.
6. The AI generates a Song Profile with sections, palettes, energy curves, movement concepts, performer focus, MIDI behavior suggestions, and transitions.
7. Aurora validates the profile against actual fixture capabilities and safety constraints.
8. The user previews the design in Aurora's visualizer.
9. The user edits or regenerates as desired.
10. The approved profile is committed as normal editable Aurora show data.

## 17. Offline Live Performance Requirement

AI Show Designer should primarily be a **programming-time feature**, not a live-show dependency.

Once a generated design is accepted:

```text
AI-generated intent
        |
        v
Approved Song Profile
        |
        v
Aurora Show Data
        |
        v
Normal deterministic execution
```

A lost internet connection must never affect playback of an already programmed show.

A generated show must remain fully functional offline.

## 18. Far-Future Conversational Editing

Once the semantic architecture exists, Aurora could support edits such as:

> “Make the second chorus bigger than the first, but save the audience lights for the final chorus.”

> “Give the guitar solo more motion.”

> “Keep everything the same but replace the purple with a colder blue.”

> “The snare accents are too aggressive during the verses.”

> “Make the last thirty seconds feel like the entire show is opening up.”

The AI would convert these into proposed structured edits that the user can review before applying.

## 19. Architectural Guidance for Present-Day Aurora

This feature should **not** be implemented during the current early Aurora milestones.

However, present-day Aurora should avoid architectural choices that would make it unnecessarily difficult later.

Avoid:

- Raw DMX as the primary high-level show representation
- MIDI mappings permanently restricted to cue triggering
- Critical show state living inside UI objects
- Effects that cannot be represented semantically
- Fixture roles that exist only as display labels
- Hard-wiring the app to one AI vendor
- Show files that cannot evolve to contain semantic metadata

Favor:

- Strong semantic fixture abstractions
- Structured Song Profiles
- Reusable Behaviors
- Rich MIDI Events
- Explicit show state
- Extensible fixture spatial metadata
- Versioned schemas
- Engine/UI separation
- Provider abstractions
- Deterministic compilation from intent to output

## 20. North Star

The goal is not:

> “Put an AI chatbot inside Aurora.”

The goal is:

> **Allow Aurora to understand creative intent well enough that an AI, a human designer, a MIDI controller, or a remote performer can all speak the same semantic lighting language.**

The AI might say:

> “Make the final guitar solo enormous.”

Aurora understands which song is running, where the final solo occurs, which performer is the lead guitar, which fixtures can focus on that performer, which palettes belong to the show's visual language, what “larger” means relative to earlier sections, which MIDI accents belong there, what the stage geometry looks like, what the patched fixtures can physically do, and which safety limits must be respected.

The AI proposes the artistic intention.

Aurora turns that intention into a reliable show.

That distinction should remain fundamental to the design of this feature.
