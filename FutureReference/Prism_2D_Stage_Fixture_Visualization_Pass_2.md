# Prism 2D Stage Fixture Visualization

## Pass Two --- Lightkey Parity Remediation Specification

**Product:** Aurora Prism\
**Area:** 2D Stage Preview / Fixture Library / Lightkey Import\
**Implementation target:** Codex\
**Reference corpus:** `StageLayoutTest.lightkeyproj`, `Test Show.prism`,
and the paired Stage screenshots supplied with this pass.

## 1. Purpose

The first Smart Fixture Glyph implementation proved that Prism can
classify broad visual families and render useful live state. It is a
prototype, not the target.

The supplied Lightkey and Prism projects contain substantially the same
fixture corpus. Lightkey communicates physical identity through compact
glyphs: battens look linear, multi-head fixtures expose their heads,
movers communicate orientation, scanners are distinct, panels
communicate grids, and atmospheric devices are separate from luminaires.
Prism currently collapses too many physically different fixtures into
similar single-aperture forms.

The goal is **not to copy Lightkey artwork**. The goal is comparable
semantic readability using Prism's own visual language.

## 2. Evidence From the Supplied Projects

Readable data in the supplied Lightkey project confirms fixture-profile
concepts including:

``` text
type
beamType
beamSpread
beamLayout
additionalBeamsData
```

and layout implementations including:

``` text
LXStripBeamLayout
LXRowsBeamLayout
LXRingsBeamLayout
LXArrayBeamLayout
LXNoBeamLayout
```

Layout-specific keys visible in the project include `length`,
`beamShape`, `rowSegments`, `rowHeights`, and `beamsByRing`.

Concrete project evidence includes:

-   `COLORado PXL Curve 12` associated with `LXStripBeamLayout`.
-   `Jolt Bar FX` associated with `LXRowsBeamLayout`, `rowSegments`, and
    `rowHeights`.
-   `Rogue R1X Wash` associated with `LXRingsBeamLayout` and
    `beamsByRing`.
-   `Rogue R1 FX-B` associated with `LXArrayBeamLayout`.
-   `Hurricane Haze 4D` associated with `LXNoBeamLayout`.

This establishes that Lightkey carries physical-layout semantics beyond
DMX channel count.

The supplied Prism project separately stores fixture definitions,
physical fixtures, patched fixtures, and Stage layout. Stage layout
already persists position, scale, rotation, aim direction, beam
spread/length/visibility, labels, locking, and z-order. Preserve those
behaviors.

## 3. Architectural Rule

> **Physical construction, DMX ownership, visualization override,
> resolved visualization, and live state are separate concepts.**

Required flow:

``` text
Imported / Native Fixture Facts
          |
          v
FixturePhysicalMetadata
          |
          +----------------------+
          |                      |
          |        FixtureVisualizationMetadata
          |             (user overrides)
          |                      |
          +----------+-----------+
                     v
        FixtureVisualizationResolver
                     |
                     v
       FixtureVisualizationDescriptor
                     |
                     v
          FixtureGlyphRenderer
                     |
             static geometry
                     |
                  live state
                     |
                     v
              StageCanvasView
```

`StageCanvasView` must become a consumer, not an inference engine.

## 4. Required Model Separation

### FixtureVisualizationMetadata

Optional, versioned, persisted user overrides only. It MUST NOT rewrite
channels, cell blocks, DMX footprint, programmer ownership, or output
behavior.

It may override form factor, physical topology, optical behavior,
movement representation, aspect ratio, and compositional group
visualization.

### FixturePhysicalMetadata

Source-neutral physical facts. It should express physical
dimensions/aspect ratio when known, beam/emitter count and positions,
beam shape/type/spread, row/column/strip/ring/array layouts, physical
heads, compositional groups, movement relationships, provenance, and
unrecognized imported values.

Physical metadata should normally be shared across personalities
belonging to the same real fixture.

### FixtureVisualizationDescriptor

Complete resolved result consumed by the renderer: form, topology,
optical behaviors, movement, secondary capabilities, geometry,
compositional groups, confidence, evidence, and warnings.

### Live State

Live color, intensity, pan/tilt, atmospheric output, etc. remain
separate from static physical topology.

## 5. Physical Components vs DMX Ownership

`ChannelDef.elementID` remains programming/DMX ownership. It MUST NOT
become physical-emitter identity.

Physical components require independent identity. Support:

``` text
one DMX element -> many physical emitters
many DMX elements -> one physical component
one-to-one mappings
physical emitters without independent DMX ownership
```

A 12-emitter bar in grouped mode and the same bar in pixel mode MUST
resolve to the same base physical topology unless explicitly overridden.

Add a **personality invariance regression test**.

## 6. Compositional Physical Groups

Do not model unusual fixtures by endlessly adding special fixture
classes. Support physical component groups with role, topology,
normalized positions, dimensions, movement relationship, and provenance.

This must naturally describe:

``` text
Moving head
├── central beam
└── RGB pixel ring
```

and:

``` text
Linear chassis
├── multiple moving heads
└── white strobe cells
```

A hybrid is a composition, not a manufacturer-specific enum case.

## 7. Resolver Precedence

Implement one centralized deterministic resolver:

``` text
explicit visualization override
        ↓
verified physical metadata
        ↓
existing Prism physical cell/beam semantics
        ↓
DMX semantic evidence
        ↓
low-confidence name heuristics
        ↓
generic fallback
```

Rules:

1.  Never infer visualization as a side effect of fixture decoding.
2.  Never mutate channels because of visualization inference.
3.  Never infer physical emitter count solely from repeated DMX color
    channels.
4.  Name heuristics are weak evidence only.
5.  Clamp/reject malformed geometry safely.
6.  Output confidence and evidence.
7.  Conflicting evidence generates diagnostics rather than unexplained
    guesses.

## 8. Evidence vs Warnings

Keep these separate.

``` text
Evidence
✓ Imported layout is row-based
✓ Imported layout describes multiple physical segments

Warnings
⚠ Unknown beamShape value retained
⚠ Imported topology conflicts with legacy inference
```

Expose both in developer diagnostics and Fixture Editor UI.

## 9. Lightkey Physical Layout Mapping

Preserve Lightkey physical metadata before normalization.

Investigate/map at least `LXStripBeamLayout`, `LXRowsBeamLayout`,
`LXRingsBeamLayout`, `LXArrayBeamLayout`, `LXNoBeamLayout`, plus any
single/grid/hexagonal/custom layouts found during corpus expansion.

Preserve where present:

``` text
type
beamType
beamShape
beamSpread
beamLayout
additionalBeamsData
length
rowSegments
rowHeights
beamsByRing
physical beam records
physical positions
```

A field name alone is not proof of semantics. Only verified mappings
affect normalized physical metadata with high confidence. Unknown values
should remain available diagnostically.

Physical metadata belongs to the physical fixture whenever possible.
Personality-specific DMX mapping remains personality-specific.

## 10. Required Visualization Taxonomy

**Form:** generic, PAR/can, Fresnel, profile/ellipsoidal, linear
bar/batten, panel, moving head, scanner, multi-head bar, blinder,
strobe, laser, atmospheric, effect/practical.

**Topology:** unknown, single, linear(N), grid(rows,columns), variable
rows, ring/rings, normalized array, clusters, multi-head(N), no-beam,
compositional/custom.

**Optical behavior:** wash, spot, beam, profile, pixel, blinder, strobe,
laser, atmospheric/none, effect.

**Movement:** static, pan/tilt, scanner mirror, independently moving
heads, unknown.

## 11. Core Composition Renderer

Extract fixture drawing from `StageCanvasView`.

Create dedicated components along the lines of:

``` text
FixtureGlyphRenderer.swift
FixtureGlyphGeometry.swift
FixtureGlyphPrimitives.swift
```

Names may follow existing project conventions.

The renderer accepts only the resolved descriptor, requested detail
level, and live state required for appearance. It MUST NOT inspect raw
fixture names or DMX channel definitions to decide physical form.

Core vector primitives should cover generic fixture, PAR/can, linear
chassis, panel/grid, moving-head base/yoke/head, scanner body/mirror,
blinder, strobe, laser, atmospheric device, circular/rectangular
emitters, rows, grids, rings, arrays, and multiple physical heads.

## 12. Geometry as a First-Class Result

The renderer should produce deterministic geometry, not merely draw
calls.

Geometry should expose:

-   body bounds/path;
-   emitter/aperture centers and bounds;
-   head positions;
-   optical origin points;
-   orientation reference;
-   hit-test shape;
-   optional sub-element geometry.

Beam origins MUST use the same aperture geometry used to draw the glyph.
Do not duplicate beam-origin calculations elsewhere.

## 13. Visual Parity Requirements

The target is equivalent **semantic readability**, not pixel-for-pixel
Lightkey copying.

At a glance, distinguish:

-   PAR vs moving head;
-   moving wash vs generic box;
-   linear bar vs panel;
-   multi-head bar vs pixel batten;
-   scanner vs moving head;
-   blinder vs wash panel;
-   strobe/effect vs ordinary wash;
-   atmospheric device vs luminaire;
-   single-aperture vs multi-emitter fixture.

### Relative Proportion

When real dimensions are unavailable, use canonical proportions by
form/topology. A long batten must not collapse into a small square. A
multi-head bar should be visibly wider than a PAR.

Canonical dimensions are visualization defaults, not claimed physical
measurements.

## 14. Reference-Corpus Acceptance Targets

Use the supplied Lightkey and Prism projects as a repeatable
visual-regression corpus.

### Linear bars / battens

Verified strip/linear topology must render as an elongated fixture with
topology hints or individual emitters according to LOD.

The COLORband-type case must no longer render as a single square
aperture when physical metadata describes a linear multi-emitter
fixture.

### Multi-head bars

A four- or five-head fixture must visibly communicate multiple heads on
a shared chassis.

### Moving heads

Moving fixtures must communicate moving-head form, optical aperture, and
orientation/aim identity. Add a Prism-native orientation marker or
equivalent treatment.

### Scanner

Scanner glyphs must be visually distinct from moving heads and generic
square fixtures.

### Panels / blinders / strobes

Grid/row layouts must be reflected in the fixture face. Variable-row
layouts must not be flattened into one generic aperture.

### Atmospheric

No-beam/fog/haze fixtures must use atmospheric-device geometry and must
not masquerade as luminaires.

## 15. Level of Detail

Introduce explicit detail levels.

**Large:** complete topology where practical, individual emitters/heads,
detailed orientation cues.

**Medium:** reduced emitter representation while preserving topology.

**Small:** silhouette plus topology hint.

Dense pixel fixtures must simplify intelligently rather than producing
tiny-circle noise.

## 16. Live State Preservation

Preserve working behavior:

-   live emitter color;
-   live intensity representation;
-   per-element beam state;
-   atmospheric level display;
-   selection and existing sub-element selection;
-   rotation;
-   aim direction;
-   labels.

Static topology comes from the descriptor. Live state remains
frame-driven.

## 17. Fixture Editor

Add or complete a **Visualization** section in
`FixtureProfileEditorPanel` with:

-   Automatic / Override mode
-   Live glyph preview
-   Form selector
-   Topology selector and dimensions/counts
-   Optical behavior
-   Movement
-   Physical/canonical aspect ratio
-   Confidence
-   Evidence
-   Warnings
-   Override Automatic Visualization
-   Reset to Automatic

The editor must permit physical emitters to be declared independently of
channel rows.

Saving overrides must use the existing document command/undo system.

## 18. Persistence

Use optional versioned visualization metadata rather than a broad
project migration.

Requirements:

-   missing metadata invokes automatic resolution;
-   old fixture definitions continue decoding;
-   unknown JSON keys are ignored safely;
-   invalid enum values degrade safely where practical;
-   overrides survive show, user-library, and fixture-package round
    trips;
-   physical/import metadata survives required round trips;
-   visualization remains optional for compilation and DMX output.

## 19. Caching

Do not resolve visualization every Stage frame.

Use a content-derived fingerprint:

``` text
fingerprint(
    physical metadata,
    visualization overrides,
    relevant fixture semantics
) -> resolved descriptor
```

Then:

``` text
descriptor + LOD -> static glyph geometry
descriptor + live state -> frame appearance
```

Definition ID may help organize caches, but correctness MUST NOT depend
on ID alone.

## 20. Tests

### Resolver

Test explicit override precedence, physical-metadata precedence, DMX
isolation, low-confidence name heuristics, malformed geometry fallback,
and unknown source-metadata retention.

### Personality invariance

Create one synthetic 12-emitter bar with grouped, 12-channel, 36-channel
pixel, and 48-channel extended personalities. All MUST resolve to the
same base physical topology unless explicitly overridden.

### Geometry

Validate body geometry, aperture count/positions, beam origins, head
positions, orientation markers, and hit-test geometry.

### LOD and rotation

Test multiple zoom levels and rotations at 0°, 45°, 90°, 180°, plus
arbitrary angles.

### Snapshot tests

Create canonical snapshots for PAR, 12-emitter bar, 2x4 blinder,
variable-row strobe/panel, moving wash, moving spot/beam, scanner,
multi-head bar, ring topology, hybrid composition, and atmospheric
fixture.

### Performance

Exercise large Stages and confirm static resolution/geometry is not
recomputed every frame.

## 21. Migration Strategy

Preserve working behavior while replacing architecture incrementally:

1.  Introduce physical metadata, override metadata, descriptor, and
    resolver beside legacy structures.
2.  Add persistence, validation, diagnostics, and tests.
3.  Preserve Lightkey source metadata before changing rendering.
4.  Implement deterministic glyph geometry.
5.  Adapt currently working bar and atmospheric cases first.
6.  Add PAR and core mover primitives.
7.  Add row/grid/ring/array topology.
8.  Add scanner and multi-head composition.
9.  Add hybrid composition and LOD.
10. Add Fixture Editor controls.
11. Remove legacy Stage inference only after parity tests pass.
12. Add snapshot/performance regression gates.

Do not perform a big-bang Stage rewrite.

## 22. Current Implementation Disposition

### Keep

-   `ChannelDef.elementID` for programming/DMX ownership;
-   per-element programmer routing;
-   independent preview color/beam state;
-   atmospheric live-state plumbing;
-   rotation and selection behavior;
-   normalized custom element geometry where useful;
-   Stage placement/label/aim persistence.

### Replace or evolve

-   broad `FixtureVisualRole` into the complete descriptor taxonomy;
-   `FixtureVisualInference` into the centralized resolver;
-   legacy provenance into versioned overrides plus diagnostics;
-   rendering-time `resolvedVisual` into cached resolution;
-   Stage role checks/inline shapes into composition rendering;
-   decoder-time repeated-channel inference into non-mutating resolver
    evidence.

## 23. Codex Constraints

1.  Audit before editing.
2.  Do not break working DMX behavior.
3.  Never infer physical construction from channel count alone.
4.  Never mutate fixture channels during visualization inference.
5.  Do not overfit Prism's internal model to Lightkey.
6.  Preserve unknown imported metadata where practical.
7.  Keep inference centralized, deterministic, and heavily commented.
8.  Preserve backward compatibility and undo/redo.
9.  Keep static geometry deterministic for snapshot testing.
10. Preserve the working Stage interaction model while replacing visual
    internals.

## 24. Pass-Two Acceptance Checklist

-   [ ] Physical metadata is independent from DMX ownership.
-   [ ] Visualization overrides are versioned and non-destructive.
-   [ ] Resolver runs outside fixture decoding and outside per-frame
    Stage drawing.
-   [ ] Resolver reports confidence, evidence, and warnings.
-   [ ] Lightkey strip/rows/rings/array/no-beam metadata is preserved
    before normalization.
-   [ ] Linear fixtures render with meaningful elongation/topology.
-   [ ] Multi-head fixtures visibly communicate multiple heads.
-   [ ] Moving heads communicate orientation.
-   [ ] Scanners are distinct from moving heads.
-   [ ] Panels/blinders/strobes reflect physical row/grid structure.
-   [ ] Atmospheric fixtures are visually distinct from luminaires.
-   [ ] Beam origins derive from glyph aperture geometry.
-   [ ] Canonical proportions are used when dimensions are unknown.
-   [ ] Dense topology uses LOD rather than visual noise.
-   [ ] Fixture Editor supports automatic resolution, diagnostics,
    overrides, and reset.
-   [ ] Personality invariance tests pass.
-   [ ] Snapshot and rotation tests pass.
-   [ ] Large-Stage performance remains acceptable.
-   [ ] Existing DMX, selection, rotation, labels, beams, and
    atmospheric live state remain functional.

## 25. Definition of Success

Pass Two succeeds when the supplied Prism Stage can be compared
side-by-side with the supplied Lightkey Stage and the fixtures are
similarly understandable **without reading their labels**.

Prism does not need Lightkey's exact glyph shapes. It does need the same
fundamental clarity:

> **The physical character of the rig should be visible in the Stage
> plot.**

A bar should read as a bar. A multi-head fixture should reveal its
heads. A mover should reveal its movement/orientation. A scanner should
look like a scanner. A panel should reveal its topology. A hazer should
not look like a lamp.

The renderer should become simple because the semantic and physical
model has already done the difficult thinking.
