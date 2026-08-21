# Prism Smart Fixture Glyph System

## Feature and Implementation Specification for Codex

**Product:** Aurora Prism\
**Area:** 2D Stage Preview\
**Goal:** Represent the majority of fixture types intelligently without
requiring real-hardware testing for every fixture.

## 1. Core Rule

> **A Stage glyph represents what the fixture physically is, not how
> many DMX channels it consumes.**

Prism MUST NOT require bespoke artwork for every manufacturer/model. It
shall resolve fixture metadata into a semantic visualization descriptor
and compose the glyph from reusable vector primitives.

Examples: - A 12-emitter bar remains a 12-emitter bar in a 4-channel
personality. - A 48-channel moving head does not have 48 emitters. -
Personalities for the same physical fixture should normally share a base
glyph. - A 2x4 blinder must look different from an eight-cell linear
bar. - Visualization errors must never affect DMX output.

## 2. Architecture

``` text
Fixture Definition / Import
          |
          v
 Visualization Resolver
   /             \
explicit data    inference
   \             /
          v
FixtureVisualizationDescriptor
          |
          v
 Glyph Composition Engine
          |
          v
     Stage Glyph
```

Codex MUST audit existing Prism models first and reuse them where
possible.

## 3. Semantic Model

The normalized descriptor should express:

-   **Form factor:** generic, PAR/can, Fresnel, profile/ellipsoidal,
    linear bar/batten, strip, panel, moving head, scanner, multi-head
    bar, blinder, strobe, laser, atmospheric, projector/effect,
    practical.
-   **Emitter topology:** unknown, single, linear(N), grid(rows,
    columns), ring(N), clusters, multi-head(N), custom.
-   **Optical behavior:** wash, spot, beam, profile, pixel, blinder,
    strobe, laser, decorative/effect, none. Multiple values are allowed.
-   **Movement:** static, pan/tilt, scanner mirror, multi-head, unknown.
-   **Secondary capabilities:** color mixing/wheel, gobo, zoom, iris,
    shutter, pixel control, white/amber/UV, fog, haze, fan, independent
    cells/heads.
-   **Physical geometry:** optional width, height, depth, and/or aspect
    ratio.
-   **Resolution diagnostics:** confidence, source, and evidence.

The taxonomy MUST remain extensible. Do not create manufacturer-specific
fixture classes for unusual combinations.

## 4. Inference Hierarchy

Resolve visualization deterministically in this order:

1.  **Explicit Prism visualization metadata.**
2.  **Reliable imported physical metadata.**
3.  **Existing Prism fixture semantics:** cells, beams, movement, color
    capabilities, etc.
4.  **DMX function semantics as supporting evidence.** Pan+tilt suggests
    movement; RGB suggests color mixing; gobo/focus/iris with movement
    suggests spot/profile behavior.
5.  **Fixture/model name heuristics** as low-confidence fallback only,
    e.g. BAR, BATTEN, PAR, WASH, BEAM, SPOT, BLINDER, STROBE, LASER,
    HAZE, FOG.
6.  **Clean generic fallback.**

DMX channel count MUST NOT be interpreted as physical emitter count
unless the profile explicitly establishes that relationship.

For Lightkey imports, investigate and preserve verified
visualization-relevant information such as `type`, `beamType`,
`beamShape`, `beamSpread`, `beamLayout`, `additionalBeamsData`, and
single/row beam-layout structures. Do not assign undocumented fields
authoritative meanings until corpus testing verifies them.

## 5. Confidence and Explainability

Expose confidence such as `explicit`, `high`, `medium`, `low`, and
`fallback`, plus human-readable evidence.

Example:

``` text
Form: Linear Bar
Topology: 1 x 12
Optics: Wash
Movement: Static
Confidence: High

Derived from:
- imported row beam layout
- 12 physical beam records
- static fixture classification
```

This information should be available in developer diagnostics and the
Fixture Editor.

## 6. Glyph Composition

Build glyphs from reusable vector primitives:

-   rectangular/rounded chassis
-   circular body
-   conventional fixture body
-   moving-head base/yoke/head
-   lens/emitter circle
-   rectangular emitter
-   scanner mirror
-   atmospheric nozzle/outlet
-   laser aperture
-   emitter row/grid/ring
-   head cluster

Use Prism's existing vector rendering approach. Avoid model-specific
raster artwork when primitives suffice.

## 7. Visual Rules

Glyphs must remain legible across Stage zoom levels. Use level-of-detail
simplification:

``` text
large -> detailed topology
medium -> simplified emitter marks
small -> silhouette + topology hint
```

Do not attempt to draw hundreds of individually legible pixels at tiny
sizes.

Use reliable physical dimensions when available; otherwise infer a
canonical aspect ratio from form/topology. Never derive aspect ratio
from DMX channel count.

The whole glyph rotates with its Stage object. Labels/badges may remain
screen-oriented if consistent with existing Stage UX.

## 8. Representative Mappings

**COLORBand-type bar:** `linearBar + linear(N) + static + wash/pixel`
-\> long chassis containing N emitter marks.

**RGB PAR:** `par + single + static + wash` -\> compact PAR body with
dominant aperture.

**Moving wash:** `movingHead + single + panTilt + wash` -\>
base/yoke/broad-lens head.

**Moving spot/profile:** `movingHead + single + panTilt + spot/profile`
-\> base/yoke with narrower optical treatment.

**2x4 blinder:** `blinder + grid(2,4)` -\> eight large apertures in
obvious 2x4 arrangement.

**Pixel panel:** `panel + grid(R,C) + pixel` -\> panel body plus grid.

**Four-head moving bar:** `multiHeadBar + multiHead(4)` -\> linear base
with four distinct heads.

**Hybrid:** central beam plus 12-pixel ring must be representable
compositionally without a manufacturer-specific class.

**Fogger/hazer:** `atmospheric + fog/haze` -\> recognizable
atmospheric-device symbol, not a fake light aperture.

## 9. Fixture Editor

Add a **Visualization** section with a live preview.

Show: - Mode: Automatic/Override - Form - Emitter layout - Primary
optics - Movement - Aspect ratio - Confidence - Evidence/derivation

Provide **Override Automatic Visualization** and **Reset to Automatic**.

Overrides are visualization-only and MUST NOT rewrite unrelated DMX
semantics.

## 10. Persistence

Add optional, versioned visualization metadata to `.prismfxt`.

Requirements: - Older fixtures continue to load. - Missing visualization
metadata triggers inference. - Unknown future visualization keys do not
make fixtures unloadable. - Visualization metadata is never required for
DMX output. - Overrides survive save/reload/export/import. - Do not
migrate unrelated fixture data unnecessarily.

## 11. Lightkey Importer

Update the importer so useful physical metadata is not discarded.
Validate mappings using known fixture families: PAR, bar, moving wash,
moving spot/beam, blinder, strobe, panel/pixel, laser, atmospheric, and
multi-head.

Unknown source values should be preserved or logged where practical.
Verified mappings require clear comments and tests.

## 12. Hardware-Independent Testing

Create a synthetic fixture corpus covering at least:

-   generic unknown
-   RGB and conventional PAR
-   Fresnel/profile
-   8- and 12-emitter bars
-   high-density pixel bar
-   2x2 and 2x4 blinders
-   4x4 pixel panel
-   moving wash/spot/beam
-   scanner
-   four-head moving bar
-   central beam + pixel-ring hybrid
-   strobe
-   laser
-   fogger/hazer
-   incomplete, conflicting, and malformed metadata

Also use real fixture definition files from multiple manufacturers as
regression inputs without requiring hardware.

Unit-test resolver precedence and fallbacks. Add deterministic
snapshot/golden-image tests for canonical glyphs. Test multiple zoom
levels and rotations including 0, 45, 90, and 180 degrees.

## 13. Performance and Compatibility

Inference MUST NOT run every frame. Resolve when visualization-relevant
data changes and cache reusable geometry where appropriate.

Preserve existing Stage behavior: placement, hit testing, dragging,
resize, rotation, selection, grouping, undo/redo, save/load, labels,
ordering, beam visualization, and live output visualization.

Emitter marks remain part of one fixture Stage object unless a future
cell-editing feature explicitly changes this.

## 14. Future Live-State Support

Design topology so future overlays can show: - current emitter
color/intensity - individual cell colors - moving-head orientation -
beam origins from correct physical apertures

These future capabilities are not prerequisites for the initial Smart
Glyph implementation.

## 15. Implementation Phases

### SG-1: Semantic Foundation

Audit models; add only missing abstractions; implement descriptor,
resolver, confidence/evidence, persistence, and unit tests.

### SG-2: Core Renderer

Implement generic, PAR, bar, panel, mover, blinder, strobe, laser,
atmospheric, plus single/linear/grid topology.

### SG-3: Advanced Composition

Add Fresnel/profile, scanner, multi-head, ring, clusters/hybrids,
dense-emitter simplification, and zoom LOD.

### SG-4: Fixture Editor

Add preview, resolver explanation, overrides, reset, validation, and
undo/redo.

### SG-5: Importer Integration

Preserve and translate verified Lightkey physical metadata and add
corpus tests.

### SG-6: Regression and Polish

Snapshot tests, scale/rotation tests, large-Stage performance tests,
accessibility review, and visual polish.

## 16. Codex Constraints

1.  Audit before editing; reuse existing Prism architecture.
2.  No DMX regressions.
3.  Do not overfit Prism's internal model to Lightkey.
4.  Do not overfit to fixtures currently available for testing.
5.  Never use channel count as emitter count by default.
6.  Keep inference centralized, deterministic, and testable.
7.  Heavily comment inference rules and importer mappings.
8.  Preserve backward compatibility.
9.  Maintain undo/redo for visualization overrides.
10. Keep rendering deterministic for snapshot tests.

## 17. Acceptance Criteria

-   [ ] Existing Prism fixtures/projects load normally.
-   [ ] Fixtures lacking visualization metadata receive useful automatic
    glyphs.
-   [ ] PAR, bar, panel, mover, blinder, strobe, laser, and atmospheric
    forms are visually distinct.
-   [ ] Linear/grid emitter topology is visibly represented.
-   [ ] Multi-head and hybrid fixtures are representable without bespoke
    artwork.
-   [ ] DMX channel count is not treated as physical emitter count by
    default.
-   [ ] Fixture Editor shows live preview and resolver reasoning.
-   [ ] Overrides persist and can be reset.
-   [ ] Malformed/unknown visualization metadata cannot crash Stage or
    DMX.
-   [ ] Resolver unit tests pass.
-   [ ] Canonical glyph snapshot tests pass.
-   [ ] Scale/rotation tests pass.
-   [ ] Existing Stage manipulation behavior remains intact.
-   [ ] Lightkey importer preserves/maps verified visualization
    metadata.
-   [ ] Real fixture files can be reviewed without owning the hardware.
-   [ ] Large fixture counts do not cause material Stage performance
    regression.

## 18. Definition of Success

A user should be able to import or create a fixture Prism has never
encountered before and, in most cases, immediately receive a Stage glyph
that communicates the fixture's physical nature.

The system should understand reusable ideas such as **linear chassis +
twelve emitters**, **moving head + wash lens**, **2x4 blinder**, or
**four-head moving bar**, rather than requiring prior knowledge of every
product name.

That is the long-term design target: **semantic fixture visualization,
not an icon lookup table.**
