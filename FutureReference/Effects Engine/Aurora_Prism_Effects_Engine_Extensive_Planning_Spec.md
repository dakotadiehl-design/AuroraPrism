# Aurora Prism Effects Engine
## Extensive Feature Planning & Implementation Specification
### Status: First Implementation Planning Baseline
### Companion Visual Reference: `a_high_resolution_screenshot_of_a_dark_themed_appl.png`

> **IMPORTANT FOR IMPLEMENTATION:** The companion rendered UI image supplied alongside this document is an approved **first-pass visual target** for the Prism Effects workspace. It is not merely mood-board material. Grok should use it as the primary reference for window hierarchy, density, visual organization, interaction prominence, and overall UX direction. Exact labels and controls may evolve where this specification requires additional functionality, but implementation should remain visibly recognizable as the same product shown in the reference image.

---

# 1. Executive Summary

Aurora Prism requires a first-class **Effects Engine** for creating, editing, previewing, storing, recalling, synchronizing, and compositing dynamic lighting behaviors.

LightKey's effects workflow is an important conceptual starting point: effects must remain editable, must support common lighting properties, must work across fixtures and multi-cell fixtures, and must make fixture ordering, grouping, phase, timing, and fanning accessible to the programmer.

Prism must go further.

The Prism Effects Engine shall be built around five cooperating concepts:

1. **Generators** - mathematical or procedural sources such as sine, triangle, chase, sparkle, noise, paths, and custom curves.
2. **Timing** - a first-class clock and synchronization system supporting both musical and absolute-time workflows from the initial implementation.
3. **Distribution / Fanning** - a general system for distributing values, phase, colors, positions, and other properties across fixtures or cells.
4. **Property Mapping** - mapping normalized effect output onto semantic fixture properties such as intensity, color, pan/tilt, zoom, iris, frost, and other supported attributes.
5. **Composition** - deterministic layering of effects with programmer, cue, palette, preset, and live-output state.

The Effects Engine must be powerful mathematically, but **UX/UI quality is an equal implementation requirement**. A technically sophisticated engine hidden behind dense forms, disclosure triangles, modal dialogs, or an overloaded main workspace is not acceptable.

The Effects Engine shall therefore live in a **dedicated macOS Effects window**, visually modeled after the supplied reference render.

---

# 2. Non-Negotiable Product Principles

## 2.1 Dedicated Effects Window

Effects must **not** be implemented as another tab in the main Prism workspace.

The Effects workspace is a separate, document-aware macOS window.

The main Prism workspace remains available behind or beside it and continues to show the actual Stage/Live Preview.

The Effects window is optimized for effect authoring and visualization. The main Stage is optimized for showing the resulting lighting design.

## 2.2 Timing Is V1, Not Future Architecture

Timing synchronization must be fully implemented and exposed from the first usable Effects Engine release.

The implementation must not ship with only a free-running timer while leaving musical synchronization as a future placeholder.

V1 must support:

- absolute duration / period;
- frequency;
- internal BPM;
- musical beat divisions;
- bars;
- straight, dotted, and triplet timing;
- phase;
- fixture/cell phase spread;
- quantized starts;
- Music Engine timing;
- MIDI Clock timing;
- AME timing/events;
- free-running operation.

The timing architecture must also permit a future Conductor clock/timeline provider without redesigning the effect evaluator.

## 2.3 Musical Language Must Never Be Mandatory

Prism is music-centered, but not every lighting effect should be expressed musically.

The programmer must be able to choose whichever timing representation best describes the desired behavior.

Examples:

- `Period = 850 ms`
- `Period = 17.5 sec`
- `Frequency = 0.2 Hz`
- `1/8 note`
- `2 Bars`
- `Dotted 1/4`
- `Triplet 1/8`

Musical and absolute-time modes are peers.

## 2.4 Fanning Is a Core Primitive

Fanning must not be implemented as a color-only utility.

A **Distribution/Fan Engine** shall be a reusable primitive capable of operating on:

- color;
- intensity;
- pan;
- tilt;
- position;
- zoom;
- iris;
- focus;
- frost;
- compatible continuous custom attributes;
- effect phase;
- effect amplitude;
- timing offsets where appropriate;
- multi-cell fixture elements.

This architecture is essential.

## 2.5 Everything Important Is Visual

Prism must favor direct manipulation and immediate visual feedback.

Where a value can reasonably be understood graphically, the UI should visualize it.

Examples include:

- waveform shape;
- movement path;
- gradient;
- gradient stops;
- fixture order;
- fixture phase;
- distribution curve;
- effect playhead;
- bars/beats;
- spatial fan direction;
- stage result.

Numerical fields remain available for precision.

## 2.6 Non-Destructive Editing

Effects must remain editable after they are assigned to programmer state, presets, or cues.

Do not "bake" an effect into generated DMX values.

## 2.7 Semantic Properties, Not DMX Channels

The Effects Engine must operate on fixture semantics.

It should produce values such as:

- intensity;
- color;
- pan/tilt;
- zoom;
- frost.

Fixture capability/property translation remains responsible for converting those semantic results into device-specific DMX output.

The effect layer must not contain fixture-specific DMX math.

---

# 3. Companion UI Render

The supplied companion image is:

`a_high_resolution_screenshot_of_a_dark_themed_appl.png`

The render depicts the approved first-pass Effects workspace direction.

Key characteristics to preserve:

- native professional dark macOS creative-workstation appearance;
- independent Effects window;
- restrained Prism/Aurora accent use;
- toolbar across the top;
- explicit Preview / Programmer / Live modes;
- effect library on the left;
- large central visualization;
- Effect Inspector on the right;
- substantial timing workspace rather than tiny timing fields;
- waveform/curve visualization;
- fixture phase visualization;
- large gradient/fanning controls;
- effect presets;
- persistent Apply controls at the bottom;
- high information density without becoming visually noisy.

### 3.1 Reference Render Regions

The implementation should broadly preserve this hierarchy:

```text
+-----------------------------------------------------------------------+
| Toolbar / Mode / Preview Status / Window Controls                     |
+---------------+--------------------------------------+----------------+
|               |                                      |                |
| Effect        |       Main Effect Visualization      | Effect         |
| Library       |                                      | Inspector      |
|               |       Fixture / Stage Preview        |                |
| My Effects    |                                      | Generator      |
|               |                                      | Distribution   |
| Recent        |                                      | Gradient       |
|               |                                      | Presets        |
+---------------+--------------------------------------+----------------+
|               Timing / Clock / Phase / Spread                         |
+--------------------------------------+--------------------------------+
| Waveform / Curve / Path Editor       | Fixture Phase Visualizer       |
+--------------------------------------+--------------------------------+
| Status                      Revert | Apply to Programmer | Take Live   |
+-----------------------------------------------------------------------+
```

This is not a demand for pixel-identical reproduction. It **is** a demand that the finished application preserve the workflow and visual priorities of the reference.

---

# 4. Effects Window Behavior

## 4.1 Window Ownership

The Effects window should be associated with the currently open Prism show/document.

Closing the Effects window must not close the show.

Closing the show should close or safely detach its Effects window.

## 4.2 Window Persistence

Persist at minimum:

- window frame;
- inspector width;
- library width;
- timing panel height;
- lower visualizer height;
- selected library category;
- last selected effect;
- Follow Selection state;
- preview/application mode;
- selected inspector subsection;
- visualizer mode.

## 4.3 Full Screen

The Effects workspace should support standard macOS full-screen behavior.

## 4.4 Main Workspace Synchronization

The Effects window and main Prism window must share model state.

The user may:

1. select fixtures in Prism;
2. open Effects;
3. edit an effect;
4. watch the real Prism Stage visualization update.

A **Follow Selection** control must be visible in the Effects toolbar.

When enabled, fixture/group selection changes in Prism update the Effects target.

When disabled, the Effects editor retains its current target.

## 4.5 One Primary Effects Window Per Show for V1

V1 should use one primary Effects workspace per document.

The internal architecture should avoid unnecessary assumptions that make multiple editors impossible later, but multiple Effects windows are not required initially.

---

# 5. Preview, Programmer, and Live Safety Model

The reference render exposes three clear modes:

- Preview
- Programmer
- Live

This distinction is mandatory.

## 5.1 Preview

Preview is non-destructive.

Effect changes animate inside:

- the Effects visualization;
- the appropriate preview pipeline;
- optionally the main Prism 2D Stage as a preview overlay.

They do **not** alter actual live DMX output.

The UI must make this unmistakable.

## 5.2 Programmer

The effect becomes part of current Prism Programmer state and follows normal programmer/output rules.

Edits remain editable and undoable.

## 5.3 Live

Live mode deliberately routes the editing result into the live-output path.

Entering Live mode should be explicit.

The Effects window must never silently transition from Preview to Live because an effect was selected or opened.

## 5.4 Apply Controls

Persistent bottom actions should include equivalents of:

- Revert
- Apply to Programmer
- Apply & Take Live

The exact wording may be refined during implementation, but the distinction must remain obvious.

## 5.5 Busking Compatibility

The Effects system must be compatible with Prism's busking philosophy:

- existing live output can continue;
- the operator can construct/edit an effect privately;
- the operator can deliberately commit or take the new look live.

The Effects Engine should use the same underlying preview/commit concepts as the broader Programmer/Busking architecture rather than inventing an incompatible second system.

---

# 6. Core Effect Model

A useful conceptual model is:

```text
Effect
  -> Timing
  -> Generator
  -> Target Property
  -> Distribution
  -> Mapping
  -> Layer/Composition
  -> Semantic Fixture Output
```

Suggested domain types:

```text
PrismEffect
PrismEffectInstance
PrismEffectTemplate
EffectLayer
EffectGenerator
EffectTiming
EffectClockSource
EffectTarget
EffectParameter
EffectCurve
EffectPath
EffectMask

FixtureDistribution
DistributionOrder
DistributionCurve
DistributionGrouping
DistributionSymmetry

FanDefinition
FanStop
FanInterpolator

EffectEvaluator
EffectCompositionEngine
EffectEvaluationContext
```

Names may change to fit existing Prism conventions.

The architecture and responsibilities should not.

---

# 7. Effect Families

The UI may organize effects into approachable categories even though the underlying evaluator uses common primitives.

Initial library categories should include:

- Favorites
- Color
- Intensity
- Movement
- Beam
- Pixel
- Atmosphere
- Custom
- My Effects

## 7.1 Pattern Effects

Initial patterns should include at least:

- Chase
- Scanner
- Bounce / Yo-Yo
- Fill
- Wipe
- Rain
- Meteor
- Sparkle
- Twinkle
- Fire
- Pulse Train
- Theater Chase
- Random Chase
- Color Roll
- Color Wipe
- Gradient Roll
- Comet
- Ripple
- Alternator
- Noise / Shimmer

Avoid implementing each as a completely unrelated engine.

Patterns should reuse common generator/distribution/timing infrastructure wherever possible.

## 7.2 Curve Effects

Initial waveform/generator shapes should include:

- Sine
- Triangle
- Saw Up
- Saw Down
- Square
- Pulse
- Ramp
- Bounce
- Exponential
- Logarithmic
- Smoothstep
- Random
- Smooth Noise
- Custom Drawn Curve

Common controls should include, as applicable:

- amplitude;
- base/offset;
- phase;
- period/frequency;
- duty cycle;
- direction;
- fixture spread;
- start phase;
- end phase.

## 7.3 Movement Effects

Initial movement templates:

- Circle
- Ellipse
- Figure Eight / Infinity
- Diamond
- Square
- Triangle
- Horizontal Sweep
- Vertical Sweep
- Diagonal Sweep
- Arc
- Fan Sweep
- Random Wander
- Custom Path

Movement paths should be editable visually.

Support interpolation modes such as:

- smooth;
- linear;
- point/step where meaningful.

## 7.4 Relative Movement

Movement must support relative operation.

Example:

Four movers are independently focused on four musicians. Applying a small relative circle should make each mover orbit its own existing focus position.

It must not force every fixture onto a common absolute center.

Absolute movement should also remain available.

---

# 8. Timing Engine

Timing is one of the most important parts of the system.

## 8.1 Common Clock Interface

Effect evaluation should consume time through an abstraction rather than reading a system timer directly.

Conceptually:

```text
EffectClockProvider
    currentTime
    beatPosition
    barPosition
    tempo
    transportState
    synchronizationQuality
```

Not every provider needs every field.

The evaluator should receive a normalized timing context appropriate to the selected source.

## 8.2 V1 Timing Sources

Implement and expose:

### Free Run / Absolute Time

Allow:

- milliseconds;
- seconds;
- minutes where useful;
- frequency in Hz;
- period.

Examples:

```text
Period: 850 ms
Period: 3.5 sec
Period: 17.5 sec
Frequency: 0.25 Hz
```

### Internal BPM

User-defined tempo.

Controls:

- BPM numeric entry;
- Tap Tempo;
- optional transport start/reset;
- sync indicator.

### Music Engine

Consume the existing/defined Prism Music Engine timing model.

Expose meaningful:

- tempo;
- beat;
- bar;
- transport/play state;
- relevant song context.

### MIDI Clock

Support external MIDI clock synchronization.

The UI must indicate:

- clock present/absent;
- synchronized/unstable state;
- current derived BPM;
- transport state if available.

Loss of MIDI clock must be handled safely and deterministically.

### AME

Allow Advanced MIDI Engine events/control to participate in effect timing and triggering.

This should not be limited to raw MIDI clock if the AME has richer event semantics.

### Future Conductor

Do not require Conductor now.

Design the provider interface so Conductor can later become another timing/transport provider without replacing the Effects timing architecture.

## 8.3 Musical Divisions

Support at minimum:

- 1/32
- 1/16
- 1/8
- 1/4
- 1/2
- 1 beat
- 1 bar
- 2 bars
- 4 bars
- 8 bars where reasonable

The actual UI should avoid redundant representations where meter makes them equivalent, while preserving a clear mental model.

## 8.4 Timing Modifiers

Support:

- Straight
- Dotted
- Triplet

## 8.5 Phase

Every cyclic effect should support phase.

Provide:

- numerical degree input where applicable;
- visual knob or circular control;
- direct waveform visualization;
- reset to zero.

## 8.6 Fixture Phase Spread

Fixture/cell phase distribution must be independent from base effect phase.

Example:

```text
Base phase: 0 degrees
Fixture spread: 360 degrees
```

Eight fixtures should sample distributed phases across the cycle according to selected distribution order.

## 8.7 Quantized Starts

Effects should be able to begin:

- immediately;
- next beat;
- next bar;
- selected musical boundary where supported.

Quantization is especially important for live triggering.

## 8.8 Clock Loss Behavior

For synchronized external sources, define explicit fallback policy.

Possible policies may include:

- hold current phase;
- continue using last known tempo;
- stop effect;
- fall back to internal clock.

Do not silently pick inconsistent behavior.

The chosen policy should be persisted per effect or source as appropriate.

## 8.9 Timing Visualization

Timing cannot be a spreadsheet of fields.

The UI should show:

- bars;
- beats;
- playhead;
- waveform;
- source status;
- tempo;
- phase;
- fixture phase;
- loop state.

Absolute-time mode should adapt labels appropriately rather than pretending seconds are bars.

---

# 9. Distribution and Fanning Engine

This is a foundational Prism subsystem.

## 9.1 General Model

Given a target set of N fixtures/cells, the distribution engine assigns each target a normalized distribution position:

```text
0.0 ... 1.0
```

The Fan/Mapping layer evaluates a value at that position.

This same machinery can distribute:

- scalar values;
- colors;
- positions;
- phases;
- effect parameters.

## 9.2 Distribution Orders

Support at minimum:

- Selection Order
- Fixture Number
- DMX Address
- Custom Order
- Stage Left -> Right
- Stage Right -> Left
- Stage Front -> Back
- Stage Back -> Front
- Center -> Outside
- Outside -> Center
- Random
- Spatial Radial
- Spatial Angular where useful

## 9.3 Stage-Aware Distribution

Prism's Stage Designer must be leveraged.

When using spatial distribution, derive order from actual fixture stage coordinates rather than requiring manual fixture ordering.

Examples:

- left-to-right color gradient;
- front-to-back intensity wave;
- center-out chase;
- radial color fan.

## 9.4 Custom Order

Provide a visual way to reorder fixtures/cells.

Do not require the user to edit numeric indexes in a table.

## 9.5 Deterministic Randomness

Random distributions and random generators must support a stored seed.

Reopening the same show must reproduce the same programmed look unless the user explicitly requests non-deterministic behavior.

## 9.6 Grouping

Allow targets to be grouped.

Examples:

```text
Grouping: 1
Grouping: 2
Grouping: 4
```

This permits pairs, quads, etc. to behave as units.

## 9.7 Repetition

Allow distribution indexes/patterns to repeat across a larger target selection.

## 9.8 Symmetry

First-class modes should include:

- Asymmetric / normal;
- Mirror;
- Center Out;
- Outside In.

Symmetry must work for color, scalar properties, and movement/property fans where mathematically appropriate.

---

# 10. Color Fanning and Gradient Editor

Color fanning is a flagship workflow and deserves premium UX.

## 10.1 Multi-Stop Gradients

Do not limit color fanning to two endpoints.

Support arbitrary practical gradient stops.

Example:

```text
Blue -> Cyan -> White -> Purple -> Red
```

Each stop contains:

- normalized position;
- color/palette reference;
- interpolation behavior where applicable.

## 10.2 Direct Manipulation

The gradient editor should permit:

- adding stops;
- removing stops;
- dragging stops;
- precise position entry;
- changing stop colors;
- reversing gradient;
- mirroring;
- saving gradient as a reusable preset.

## 10.3 Color Interpolation

Support multiple interpolation strategies where technically appropriate:

- RGB
- HSB/HSV
- Hue shortest path
- Hue clockwise
- Hue counter-clockwise
- fixture-native/capability-aware behavior where supported

Avoid blindly interpolating every gradient in raw RGB if that produces undesirable intermediate hues.

## 10.4 Palette Integration

Gradient stops should be able to reference Prism color palettes.

A linked palette stop should update according to the existing palette-reference rules.

## 10.5 Animated Gradient Position

The gradient itself may be animated by a generator.

Examples:

- gradient slides left/right;
- gradient rotates through a spatial group;
- gradient breathes center-out;
- gradient phase follows musical timing.

This should use the same generator/timing/distribution system rather than a special color-animation engine.

---

# 11. Scalar and Position Fanning

The same visual fan system should support continuous scalar values.

Examples:

## Intensity

```text
20% -> 100%
```

## Pan

```text
-40 degrees -> +40 degrees
```

## Tilt

```text
+15 degrees -> -15 degrees
```

## Zoom

```text
Narrow -> Wide
```

## Frost

```text
0% -> 60%
```

Property-specific UI can provide appropriate units while reusing the same underlying normalized distribution system.

---

# 12. Distribution Curves

Linear interpolation is insufficient.

Provide distribution shapes such as:

- Linear
- Ease In
- Ease Out
- Ease In/Out
- Exponential
- Logarithmic
- Custom Curve

The reference render includes a large visual distribution-curve editor. Preserve this concept.

The user should be able to see immediately how values cluster across the selected fixtures.

---

# 13. Multi-Cell / Pixel Fixture Support

Effects must work at:

- Fixture level
- Cell level

A multi-cell bar, matrix, or multi-beam fixture must be addressable as individual logical elements where its fixture definition exposes those elements.

## 13.1 Cell Ordering

Cell order should derive from fixture metadata where possible.

Allow reversal/customization where required.

## 13.2 Grouping Cells

Permit cell grouping.

Example: a 24-cell fixture grouped by four becomes six logical effect groups.

## 13.3 Mixed Selections

The evaluator should gracefully handle selections containing fixtures with differing cell counts and capabilities.

Unsupported targets must not crash or corrupt evaluation.

The UI should clearly identify unsupported or partially supported targets.

---

# 14. Property Mapping

The Effects Engine should work through semantic adapters/mappers.

Possible conceptual adapters:

```text
ScalarPropertyAdapter
ColorPropertyAdapter
PositionPropertyAdapter
DiscretePropertyAdapter
```

Discrete properties require special care.

Do not continuously interpolate a property that only supports discrete states unless an explicit mapping strategy exists.

---

# 15. Effect Layers and Composition

Multiple effects may operate on the same target/property.

Prism should make this visible rather than hiding composition rules.

Conceptual UI:

```text
COLOR FX

1. Gradient Roll       100%   enabled
2. White Sparkle        35%   enabled
3. Saturation Wave      20%   enabled
```

Each layer should support, where applicable:

- enable/disable;
- amount/intensity;
- priority;
- blend/composition behavior;
- mask;
- timing;
- reorder.

## 15.1 Deterministic Composition

Composition order must be explicit and testable.

The same project state must produce the same output.

## 15.2 Blend Semantics

Do not copy image-editor blend modes blindly.

Define lighting-meaningful composition behaviors per property class.

For example, intensity composition may require different semantics from color composition or pan/tilt.

Document these rules in code and tests.

---

# 16. Masks

Effects should optionally operate through masks.

Initial mask concepts may include:

- Fixture Group
- Odd
- Even
- First Half
- Second Half
- Center
- Edges
- Every Nth
- Spatial Region
- selected cells

Architecture should permit future dynamic masks driven by system state or Music Engine information without requiring the initial release to expose every advanced possibility.

---

# 17. Templates, Presets, and Instances

Distinguish between reusable definitions and effect instances.

## 17.1 Effect Template

Reusable starting behavior.

Example:

`Slow Color Wave`

## 17.2 Effect Instance

The configured effect used in a programmer/cue.

Example:

```text
Template: Slow Color Wave
Colors: Blue / Purple
Timing: 2 Bars
Distribution: Center Out
Spread: 100%
```

## 17.3 Linked vs Embedded

Support a model analogous to Prism's reusable palette philosophy:

- Linked Effect
- Embedded/Detached Effect

A linked effect can inherit updates from its reusable definition.

A detached effect becomes independently editable.

The UX must clearly indicate whether an effect is linked.

## 17.4 Fan Presets

Distribution/fan definitions should themselves be reusable.

Examples:

- Full Stage Left -> Right
- Mirror
- Center Out
- Outside In
- Pairs
- Quads
- Radial

## 17.5 Gradient Presets

Examples:

- Blue -> Purple
- Red -> Amber
- Blue -> White
- Purple -> Pink
- Red -> White -> Blue

Gradient and distribution presets should be composable rather than requiring hundreds of nearly identical full effects.

---

# 18. Effect Library UX

The left rail shown in the reference render should contain:

- search;
- categories;
- favorites;
- user effects;
- recently used effects;
- New Effect action.

## 18.1 Search

Search should match:

- effect name;
- category;
- tags where supported;
- property.

## 18.2 Favorites

Allow frequently used templates/effects to be starred.

## 18.3 Recently Used

Display useful visual thumbnails/cards where appropriate.

## 18.4 Drag and Drop

Where natural, support dragging an effect/preset onto an appropriate target or layer.

Do not make drag-and-drop the only way to perform essential operations.

---

# 19. Central Effect Visualization

The large central canvas is one of the defining elements of the approved render.

It should not be decorative.

Its job is to answer:

> "What is this effect doing to my selected fixtures?"

Depending on effect type it may show:

- fixture icons;
- beam color;
- beam intensity;
- movement;
- spatial arrangement;
- cell states;
- fixture ordering;
- phase relationships.

## 19.1 View Modes

Potential modes:

- 3D-ish fixture visualization
- Top
- Front
- Stage/fixture layout
- abstract effect view

The implementation should use Prism's existing visualization infrastructure where sensible rather than creating a completely separate renderer.

## 19.2 Actual Stage Remains Authoritative

The central Effects visualization explains the effect.

The main Prism Stage/2D Live Preview shows the final result after all relevant composition.

Both should update in real time.

---

# 20. Effect Inspector

The right-hand inspector should be contextual.

The reference render's structure is a strong baseline:

- Effect
- Timing
- Output

Within Effect:

- effect type;
- target property;
- generator;
- generator parameters;
- distribution/fan;
- symmetry;
- ordering;
- gradient/property mapping;
- effect presets.

Avoid giant forms containing every possible property.

Only show controls relevant to the selected effect/property.

---

# 21. Waveform / Curve Editor

The lower visual editor should display the actual generated shape.

Requirements:

- live playhead;
- amplitude visualization;
- base/offset;
- cycle boundaries;
- direct curve editing for custom curves;
- zoom where useful;
- loop preview;
- preview speed control for authoring only.

Changing a parameter should update the graph immediately.

Changing the graph should update the parameter immediately.

---

# 22. Fixture Phase Visualizer

The reference render's Fixture Phase Visualizer should be implemented as a real programming aid.

It should show:

- selected fixtures/cells;
- their order;
- phase offset;
- grouping;
- symmetry;
- resulting gradient/property state where useful.

This is especially important when a mathematical effect sounds correct in a parameter field but visually behaves differently than expected.

---

# 23. Movement Path Editor

For movement effects, the lower/central editor should become a path editor.

Support:

- control points;
- handles where applicable;
- center;
- scale;
- rotation;
- direction;
- path start;
- fixture phase indicators;
- relative/absolute toggle;
- pan mirror;
- tilt mirror.

Path editing must be reversible and undoable.

---

# 24. Undo / Redo

Every meaningful Effects operation must integrate with Prism's normal undo system.

Examples:

- add/remove effect;
- change generator;
- edit parameter;
- drag gradient stop;
- reorder fixture distribution;
- change timing;
- edit movement path;
- add/remove layer;
- change mask;
- save/detach/link effect.

Continuous drags should coalesce into sensible undo operations rather than creating hundreds of history entries.

---

# 25. Persistence

Effects must serialize as model data, not runtime state.

Persist:

- generator type and parameters;
- timing source/mode;
- musical/absolute timing values;
- phase;
- spread;
- target property;
- target references;
- distribution;
- stage-aware ordering rules;
- random seed;
- grouping;
- symmetry;
- gradient stops;
- palette links;
- masks;
- layer composition;
- template link;
- overrides;
- movement path;
- clock-loss policy;
- quantization.

Project migration/versioning must be considered from the beginning.

---

# 26. Evaluation Pipeline

A recommended conceptual evaluation sequence:

```text
1. Acquire EffectEvaluationContext
2. Resolve clock/timing source
3. Calculate normalized effect time/phase
4. Evaluate generator
5. Resolve target fixture/cell list
6. Calculate distribution index for each target
7. Apply target phase/spread/grouping/symmetry
8. Evaluate fan/property mapping
9. Apply mask
10. Compose effect layers
11. Produce semantic fixture-property result
12. Feed existing Prism programmer/output/capability pipeline
```

The evaluator should be as close to a deterministic pure computation as practical.

UI code must not perform effect mathematics.

DMX output code must not contain effect-authoring logic.

---

# 27. Performance Requirements

Lighting effects are real-time systems.

The engine must:

- avoid allocating excessively in the per-frame evaluation path;
- avoid blocking the main UI thread;
- remain deterministic;
- scale across large fixture/cell selections;
- avoid recomputing static distribution data every frame;
- cache safely where appropriate;
- separate UI refresh rate from output/evaluation rate where useful.

The UI should remain responsive while effects are running.

No effect editor interaction should stall DMX output.

---

# 28. Threading and State Safety

Effect evaluation, UI editing, project persistence, and output may operate on different execution contexts.

Define ownership clearly.

Do not solve concurrency by allowing arbitrary mutable shared model state.

Use immutable/snapshot evaluation state where practical.

An edit should become visible to the evaluator atomically.

---

# 29. MIDI Clock Robustness

MIDI Clock deserves explicit testing.

Test:

- stable clock;
- tempo change;
- clock jitter;
- start;
- stop;
- continue where supported;
- clock disappearance;
- clock restoration;
- source switching;
- project reopening without source available.

UI status must truthfully represent synchronization state.

---

# 30. Music Engine / AME Integration

Effects should be able to derive timing from Prism's Music Engine from V1.

The integration should use stable interfaces, not direct coupling to Music Engine UI state.

AME integration should permit effect triggers/control without treating raw MIDI messages as the effect model itself.

Examples of future/advanced behaviors the architecture should permit:

- restart effect on an AME event;
- alter amplitude from a mapped CC;
- trigger sparkle on drum notes;
- change gradient position from performance input;
- synchronize cycle boundaries with Music Engine bars.

Only functionality explicitly scheduled for the initial phase must be exposed immediately, but the V1 timing integrations listed earlier are mandatory.

---

# 31. Accessibility and Precision

Do not make visual controls unusable without a mouse.

Important values should support:

- keyboard focus;
- numeric entry;
- arrow-key adjustment where sensible;
- labels/tooltips;
- sufficient contrast;
- meaningful accessibility descriptions.

Color programming must not rely solely on distinguishing hues.

---

# 32. UX Acceptance Workflows

The implementation is not accepted merely because unit tests pass.

These workflows must feel obvious.

## Workflow A: Static Color Fan

1. Select eight back wash fixtures in Prism.
2. Open Effects.
3. Confirm Follow Selection.
4. Choose Color / Gradient.
5. Set Blue and Magenta.
6. Choose Left -> Right.
7. Preview.
8. See immediate gradient across selected fixtures and Stage.

No documentation should be necessary.

## Workflow B: Center-Out Gradient

1. Use the same fixtures.
2. Choose Center -> Outside.
3. Enable symmetry.
4. Observe the gradient rearrange immediately.

## Workflow C: Absolute-Time Wave

1. Choose an intensity sine wave.
2. Choose Free Run.
3. Set Period to `3.5 sec`.
4. Set fixture spread to `100%`.
5. Preview.
6. Observe waveform and fixture phase visualization.

The UI must not force the user through BPM controls.

## Workflow D: Musical Wave

1. Change source to Music Engine.
2. Set rate to `2 Bars`.
3. Choose Straight.
4. Quantize to next bar.
5. Preview.
6. Observe beat/bar timeline and synchronized playhead.

## Workflow E: MIDI Clock

1. Select MIDI Clock.
2. Receive external clock.
3. UI reports synchronized BPM.
4. Run effect at 1/4 division.
5. Remove MIDI clock.
6. UI visibly reports loss and applies configured fallback behavior.
7. Restore clock.
8. Synchronization recovers predictably.

## Workflow F: Relative Mover Circle

1. Select movers already focused on different stage positions.
2. Choose Movement / Circle.
3. Enable Relative.
4. Reduce size.
5. Preview.
6. Each mover circles around its own base position.

## Workflow G: Multi-Cell Chase

1. Select a multi-cell fixture.
2. Choose Cell mode.
3. Choose Chase.
4. Set grouping.
5. Change direction.
6. Observe the actual cell order in the phase visualizer and Stage preview.

## Workflow H: Safe Live Editing

1. Existing live look is active.
2. Open Effects in Preview.
3. Build a new gradient effect.
4. Confirm live DMX is unchanged.
5. Apply to Programmer.
6. Deliberately Take Live.
7. Output changes only at the explicit commit point.

---

# 33. Visual Acceptance Criteria

Grok must provide screenshots of the **actual running Effects window**, not only SwiftUI previews or component galleries.

The implementation should be compared directly with the supplied companion render.

Reject a pass if:

- Effects is placed in a main-workspace tab;
- the central visualization is missing or trivial;
- timing is reduced to a few small inspector controls;
- fanning is hidden in a menu;
- waveform/phase visualization is absent;
- Preview/Programmer/Live state is ambiguous;
- the interface visually resembles a settings form rather than a creative tool;
- the Stage does not respond live during editing;
- major controls require repeated modal dialogs;
- absolute-time timing is treated as secondary or hidden;
- musical synchronization is deferred.

The success criterion is:

> **Launch Prism, select fixtures, open Effects, and immediately see a professional visual effects-programming environment recognizable as the workspace shown in the supplied reference render.**

---

# 34. Engineering Acceptance Criteria

At minimum:

- effect models serialize/deserialize correctly;
- deterministic evaluation tests pass;
- random effects reproduce from seed;
- timing conversions are unit-tested;
- straight/dotted/triplet conversions are tested;
- phase wrapping is tested;
- fixture distribution orders are tested;
- spatial ordering is tested;
- center-out/outside-in behavior is tested for odd and even fixture counts;
- grouping/repetition is tested;
- gradient interpolation is tested;
- multi-cell addressing is tested;
- unsupported properties fail safely;
- relative movement is tested;
- clock source switching is tested;
- clock loss is tested;
- layer composition is deterministic;
- undo/redo is tested;
- project round-trip persistence is tested;
- preview mode cannot accidentally modify live output.

---

# 35. Recommended Implementation Phases

The exact branch/PR structure may be adapted after inspecting the current Prism codebase, but do not use phasing as justification to defer required V1 timing or UX.

## Phase FX-0 - Architecture and Existing-System Audit

Before implementation:

- inspect Programmer architecture;
- inspect fixture semantic property model;
- inspect palette/preset model;
- inspect Stage visualization;
- inspect Music Engine;
- inspect AME;
- inspect MIDI clock infrastructure;
- inspect undo/redo;
- inspect project serialization;
- inspect output composition;
- inspect busking/preview concepts;
- identify reusable components.

Deliver an implementation map before large-scale coding.

## Phase FX-1 - Core Models and Deterministic Evaluator

Implement:

- effect models;
- generator protocol/model;
- timing model;
- distribution model;
- property mapping;
- deterministic evaluator;
- serialization;
- unit tests.

No giant UI should be built on unstable effect semantics.

## Phase FX-2 - Clock and Timing System

Implement V1 clock providers:

- Free Run;
- Internal BPM;
- Music Engine;
- MIDI Clock;
- AME integration.

Implement:

- divisions;
- dotted/triplet;
- bars;
- phase;
- spread;
- quantization;
- source state;
- clock loss policy.

Build tests before relying on the UI.

## Phase FX-3 - Dedicated Effects Window Shell

Build the actual macOS Effects window following the supplied render.

Include:

- toolbar;
- Preview/Programmer/Live;
- library rail;
- central visualization;
- inspector;
- timing area;
- lower visualizer;
- status/action footer;
- persistence;
- Follow Selection.

This should already visually resemble the companion render.

## Phase FX-4 - Curve / Intensity Effects

Implement first end-to-end effect family:

- sine;
- triangle;
- saw;
- square;
- pulse;
- custom curve baseline;
- intensity mapping;
- timing;
- phase;
- distribution;
- waveform visualization.

This proves the architecture.

## Phase FX-5 - Fan Engine and Color Gradient

Implement:

- generalized fan/distribution;
- spatial ordering;
- symmetry;
- grouping;
- deterministic random;
- distribution curves;
- color interpolation;
- multi-stop gradients;
- palette references;
- fan/gradient presets;
- visual gradient editor.

Treat this as a major UX milestone.

## Phase FX-6 - Movement Effects

Implement:

- path model;
- movement templates;
- path editor;
- relative/absolute movement;
- mirrors;
- fixture phase visualization;
- pan/tilt mapping.

## Phase FX-7 - Pattern and Procedural Effects

Implement:

- chase;
- scanner;
- fill;
- wipe;
- sparkle;
- meteor;
- fire;
- noise;
- other approved patterns.

Reuse existing timing/distribution infrastructure.

## Phase FX-8 - Multi-Cell / Pixel

Implement and harden:

- cell targets;
- cell ordering;
- cell grouping;
- mixed selections;
- pixel-specific patterns;
- visualization.

If the current fixture architecture already fully supports cells, portions may move earlier, but the effects design must be cell-capable from FX-1.

## Phase FX-9 - Layers, Masks, Reusable Effects

Implement:

- effect stacks;
- composition rules;
- masks;
- linked templates;
- detached instances;
- favorites;
- My Effects;
- preset workflows.

## Phase FX-10 - UX Closeout and Real-Rig Validation

Do not call the feature complete until tested against:

- real RGB/RGBW fixtures;
- dimmer-only fixtures;
- movers;
- multi-cell fixtures;
- MIDI Clock;
- Music Engine;
- AME;
- live output;
- Preview safety;
- cue/programmer persistence.

Perform a dedicated UX review against the supplied render.

---

# 36. Code Quality Requirements

Effects code is foundational and will eventually be used by show-scale automation.

Requirements:

- clear comments around mathematical transforms and timing behavior;
- documentation for public/internal protocols whose responsibilities are non-obvious;
- no magic constants for timing/distribution;
- no DMX-specific assumptions inside general effect math;
- no UI-specific assumptions inside evaluator;
- deterministic tests;
- meaningful logging around clock/sync failures;
- avoid silent fallback behavior;
- preserve existing Prism architectural conventions where they are sound.

Complex effect math should include comments explaining **why** the math is structured that way, not comments that merely restate the code.

---

# 37. Important Edge Cases

Explicitly design/test:

- one selected fixture;
- two fixtures;
- odd fixture count;
- even fixture count;
- zero eligible fixtures;
- mixed supported/unsupported fixtures;
- fixture removed after effect creation;
- group membership changes;
- stage positions changed after spatial fan creation;
- duplicate stage coordinates;
- fixture selection order changes;
- project opened without MIDI device;
- Music Engine stopped;
- tempo changes during an effect;
- very slow effects;
- very fast effects;
- phase beyond 360 degrees / negative phase;
- gradient stops at identical positions;
- color-wheel-only fixture in color gradient;
- movement fixture with constrained pan/tilt;
- multi-cell fixture with unusual cell topology;
- live effect edited while cue transition is active;
- undo during running preview;
- effect deleted while referenced;
- linked template changed while instances are active.

---

# 38. Stage-Aware Distribution Persistence Decision

Spatial distribution should generally store the **rule**, not only a frozen ordered fixture list.

Example:

```text
Order Rule: Stage Left -> Right
```

If fixtures move in the Stage Designer, Prism can re-evaluate their ordering.

However, the user should be able to convert/freeze a spatial order into Custom Order if they want the current order preserved regardless of later stage-layout edits.

This distinction should be visible.

---

# 39. Preview Rendering vs Output Evaluation

Avoid two separate effect implementations.

The Stage preview and live DMX pipeline should consume results derived from the same semantic evaluator.

The visualizer may render extra explanatory metadata, but the effect value shown in preview must correspond to the value the output engine would use.

This prevents the classic failure where the editor preview looks correct while actual fixtures behave differently.

---

# 40. Future-Compatible Capabilities

The initial architecture should make the following possible without requiring them all immediately:

- Conductor timeline clock;
- audio-analysis modulation;
- parameter automation;
- musician-driven effect triggers;
- external control surfaces;
- iPad remote effect triggering;
- effect macros;
- effect morphing;
- cue-transition-aware effects;
- 3D spatial distribution;
- AI-assisted effect creation;
- show-level global effect buses.

Do not overbuild these now.

Do avoid architecture that makes them impossible.

---

# 41. Definition of Done

The Prism Effects Engine first major release is complete when:

1. Effects opens as a dedicated macOS window.
2. The actual window strongly matches the supplied approved render's workflow and hierarchy.
3. The operator can create useful intensity, color, movement, pattern, and multi-cell effects.
4. Fanning is a generalized distribution primitive.
5. Multi-stop color gradients are easy and visual.
6. Spatial stage-aware distribution works.
7. Free-running absolute timing is fully implemented.
8. Internal BPM timing is fully implemented.
9. Music Engine synchronization is fully implemented.
10. MIDI Clock synchronization is fully implemented.
11. AME timing/event integration is implemented to the planned V1 level.
12. Musical divisions, bars, dotted/triplet values, phase, spread, and quantization work.
13. Timing and phase are graphically visualized.
14. Effects preview safely without modifying live output.
15. Effects can deliberately be applied to Programmer/live state.
16. The main Prism Stage responds while effects are edited.
17. Effects remain editable and persist through save/reload.
18. Randomized behavior is deterministic when programmed.
19. Multi-cell fixtures are first-class effect targets.
20. Unit, persistence, timing, distribution, and output tests pass.
21. Real fixtures have been used for smoke testing.
22. A screenshot of the actual running Effects window passes visual review against the companion render.
23. A musician/operator can complete the primary acceptance workflows without needing documentation.

---

# 42. Final Direction to Grok

Do not treat this as "add some effect math to Prism."

This is a new **creative programming workspace** within Prism.

The mathematical engine, timing system, fixture distribution model, visualization, and UX are one feature.

The companion render is the first approved visual target. Use it aggressively.

In particular:

- preserve the dedicated-window approach;
- preserve the large central effect visualization;
- preserve the prominent timing workspace;
- preserve the waveform and fixture-phase visualizers;
- preserve the large visual fanning/gradient controls;
- preserve explicit Preview / Programmer / Live state;
- preserve the professional dark Prism workstation aesthetic.

If an implementation technically supports all requested parameters but buries them in forms, menus, disclosure triangles, or the main Prism tab stack, it has **not** met this specification.

The desired experience is immediate and visual:

> Select fixtures. Open Effects. See them. Shape the effect. See the waveform. See the fan. See the timing. See the stage react. Preview safely. Push it live deliberately.

That is the Prism Effects Engine.
