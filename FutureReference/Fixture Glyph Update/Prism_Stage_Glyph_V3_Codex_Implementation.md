# Prism Stage Glyph System V3
## Codex Implementation Specification

**Status:** Approved direction for implementation handoff  
**Target:** Prism Stage / 2D Preview  
**Primary goal:** Introduce a new, unapologetically 2D orthographic glyph renderer that improves visual polish while preserving every existing Stage interaction and live-light behavior.  
**Critical preservation rule:** The existing V1 glyph renderer must remain intact, functional, selectable, and available from Prism Settings as a rollback/fallback renderer.

---

## 1. Executive intent

Prism Stage is a **2D lighting-stage editor and live semantic preview**, not a partial 3D visualizer. Previous V2 visual explorations pushed too far toward miniature product renders. That direction is rejected.

V3 must use a deliberately flat visual language:

> **Hardware is flat. Light is dimensional.**

Fixture bodies, truss-adjacent fixture symbols, atmospherics, and other Stage equipment should remain orthographic 2D vector representations. Live optical state may use color, lens luminance, bloom, and Prism's existing beam renderer to communicate energy and depth.

The target is best described as:

> **Premium orthographic technical illustration with Prism's visual identity.**

Do not turn Stage into a 3D scene. Do not introduce perspective, camera-angle assumptions, faux depth, or product-thumbnail rendering.

---

## 2. Non-negotiable V1 preservation and rollback architecture

### 2.1 Keep V1 fully intact

The current glyph system is production-proven enough that it must stay "on the bench" as a complete fallback.

Codex must **not**:

- delete V1 renderer code;
- overwrite V1 drawing code in place;
- convert V1 assets into V3-only assets;
- rewrite fixture data to satisfy V3 rendering;
- change `.prism` show-file semantics solely for V3;
- remove V1 tests;
- silently route V1 through V3 helpers if that makes V1 behavior dependent on the new renderer;
- make rollback require project conversion or migration.

V1 should remain independently functional.

### 2.2 Central renderer selection seam

Introduce or formalize a single renderer-selection boundary. The exact type names should follow the repo, but conceptually:

```swift
enum StageGlyphStyle: String, CaseIterable, Codable {
    case legacyV1
    case prismV3
}
```

with a centralized render path:

```text
Authoritative Stage / Fixture State
             |
             v
      StageGlyphContext
             |
             v
    Stage Glyph Renderer
       /           \
      /             \
Legacy V1        Prism V3
(preserved)      (new)
```

Do not scatter `if useV3` checks throughout individual fixture views.

### 2.3 User-facing Settings option

Add a normal Prism preference under an appropriate Stage/Appearance/Preview settings section.

Suggested UI:

**Stage Fixture Glyphs**

- **Prism 2D (V3)**
- **Legacy (V1)**

Recommended supporting text:

> Chooses how fixtures are drawn in Stage Preview. This setting changes appearance only and does not modify show files, patching, fixture data, or output.

The exact wording may be polished to match Prism's existing Settings language.

### 2.4 Persistence of renderer preference

The selected glyph renderer should be an **application preference**, not a show-file property.

Preferred behavior:

- persist with the same preference mechanism Prism already uses for app-level UI settings;
- opening the same `.prism` show on another machine does not require the same renderer selection;
- changing glyph style never dirties the show document;
- switching renderers takes effect immediately in Stage Preview;
- no relaunch should be required.

### 2.5 Default during development

During implementation, it is acceptable to keep **Legacy V1 as the default** until V3 passes the acceptance tests in this document.

Once V3 is accepted, V3 may become the default for new installations while V1 remains available in Settings.

**Do not remove V1 as part of the V3 promotion change.**

---

## 3. Absolute functional preservation requirement

This is a rendering project. V3 must consume Prism's existing authoritative semantic state and must not create a parallel fixture model.

The following must work identically under V1 and V3:

- fixture placement;
- Stage coordinates;
- fixture rotation/orientation;
- dragging and live drag feedback;
- selection;
- multi-selection;
- hover inspection;
- context menus;
- Delete-key behavior;
- grouping behavior;
- fixture IDs;
- undo/redo;
- zoom/pan;
- patch metadata;
- universe/address metadata;
- live output state;
- fixture intensity;
- fixture color;
- multi-cell output;
- sub-fixture selection;
- per-sub-fixture editing;
- per-cell optical state;
- multi-beam output;
- beam origins;
- beam directions;
- beam colors;
- beam intensity/falloff;
- any existing fixture capability routing.

If V3 requires changing any of the above systems, stop and document the blocker before proceeding.

---

# 4. CRITICAL: sub-fixture selection must not regress

This is one of the highest-risk areas in the V3 work.

Prism already supports fixtures whose child elements/sub-fixtures can be independently addressed and selected. The new glyph renderer must **preserve those semantic hit targets and interaction paths**.

### 4.1 Parent fixture versus child element

V3 must visually distinguish, without ambiguity:

- the parent fixture as a Stage object;
- independently controllable cells/elements/sub-fixtures inside that fixture;
- the currently selected parent;
- the currently selected sub-fixture(s).

Do not flatten a multi-cell fixture into a single decorative image if Prism exposes its cells as independently selectable semantic objects.

### 4.2 Hit testing

The V3 drawing layer must not swallow or distort existing sub-fixture hit testing.

Required behavior:

- clicking an independently selectable cell selects that cell according to current Prism semantics;
- clicking fixture chassis/background behaves according to current parent-selection semantics;
- modifier-key multi-selection must continue to work;
- dragging a parent fixture must not accidentally select/reassign a child cell;
- zoom level must not change the semantic identity of the object being selected;
- optical bloom must never become an interactive hit target;
- beams must never intercept pointer events intended for fixture/cell selection.

### 4.3 Selection rendering

Use Prism purple only as an interaction overlay.

Suggested visual hierarchy:

**Parent selected**
- thin purple outline/bounding treatment around the fixture's 2D outer silhouette.

**Single sub-fixture selected**
- retain neutral parent chassis;
- apply a restrained purple ring/outline around that specific emitter/cell;
- do not recolor the emitted optical state itself.

**Multiple sub-fixtures selected**
- each selected cell gets its own restrained selection indication;
- optionally add a subtle aggregate parent hint if current interaction conventions need it;
- do not obscure individual live cell colors.

**Parent + child selection states**
- follow existing Prism semantics. Do not invent a new selection model during this project.

### 4.4 Cell geometry must be data-driven

Where Prism already knows individual cell/element layout, use that authoritative data.

If some imported profiles lack enough geometry to place individual emitters accurately, V3 should gracefully fall back to a generic evenly distributed arrangement **without changing semantic cell IDs or ordering**.

Do not reorder cells because a visually symmetric arrangement looks nicer.

Semantic index/order wins over decorative convenience.

### 4.5 Mandatory regression fixtures

Before V3 can be accepted, test at least:

- a single-emitter PAR;
- a 4-cell linear bar;
- a multi-cell/pixel bar;
- a circular multi-emitter PAR;
- the Haywire 4BAR-style fixture(s) that previously exposed sub-fixture issues;
- at least one fixture imported from the LightKey conversion path with child elements.

Test parent selection, child selection, multi-child selection, live editing, and output for each.

---

# 5. CRITICAL: multi-beam rendering must not regress

The existing Prism beam renderer is visually successful and should be considered **protected behavior**.

V3 is allowed to change **where a beam visually originates inside the new glyph**, but it must not replace the existing semantic beam engine or collapse multiple beams into one.

### 5.1 One semantic emitter can produce one beam origin

For fixtures with independently rendered cells/elements:

```text
Cell 1 -> beam origin 1
Cell 2 -> beam origin 2
Cell 3 -> beam origin 3
Cell 4 -> beam origin 4
```

Do not replace this with:

```text
Entire fixture -> one averaged beam
```

unless that is already the fixture's actual semantic behavior.

### 5.2 Preserve per-beam state

Where the current engine supports it, each beam must retain its own:

- origin;
- direction;
- color;
- intensity;
- active/inactive state;
- falloff/length/visual treatment;
- semantic emitter identity.

### 5.3 Beam origin contract

V3 should expose stable 2D emitter anchor points to the existing beam-rendering layer.

Conceptually:

```swift
struct StageGlyphEmitterAnchor {
    let semanticElementID: FixtureElementID
    let localPoint: CGPoint
}
```

This is illustrative only. Reuse existing types wherever possible.

The key requirement is that **visual emitter geometry and semantic emitter identity remain mapped**.

### 5.4 Renderer switch parity

Switching between V1 and V3 may slightly alter the beam's pixel-level starting position because the glyph artwork differs, but it must not alter:

- number of beams;
- which cell drives which beam;
- beam color;
- beam intensity;
- beam direction semantics;
- DMX output;
- programmer state.

### 5.5 Beam renderer is not part of the beauty rewrite

Do not redesign Prism's existing beam aesthetic during V3 implementation.

It already provides the desired visual contrast:

> **flat hardware + alive light**

Treat the current beam look as a visual north star and integration dependency.

---

## 6. V3 visual language

### 6.1 Hard 2D rule

Every hardware glyph must be drawn as orthographic 2D geometry.

Forbidden:

- three-quarter fixture views;
- visible side faces used to imply object height;
- perspective projection;
- camera-angle perspective;
- cast/contact shadows that imply 3D height;
- beveled product-render styling;
- photorealistic textures;
- fake metallic reflections;
- perspective handles/yokes;
- chassis shading whose primary purpose is to create 3D volume.

Allowed:

- flat charcoal fills;
- one or two restrained value levels for grouping parts;
- clean outlines;
- inset rings represented as 2D lines/shapes;
- simple mounting/yoke geometry in plan view;
- small orientation markers;
- live optical color;
- lens bloom;
- existing beam gradients.

### 6.2 Design equation

```text
2D silhouette
+ semantic optical geometry
+ restrained Prism interaction language
+ live lens state
+ existing beam renderer
= Prism V3 glyph
```

### 6.3 Visual priority order

At normal Stage zoom, a glyph should communicate in this order:

1. fixture family / silhouette;
2. physical orientation;
3. emitter count/layout where meaningful;
4. current optical state;
5. selection/interaction state;
6. fine hardware detail only when zoom permits.

---

## 7. Core fixture families

V3 should use a reusable 2D grammar rather than individually illustrated product thumbnails.

### 7.1 PAR / wash

- circular or compact rounded outer silhouette;
- plan-view yoke only if useful at current zoom;
- central lens or multi-emitter face;
- front/orientation marker;
- multi-cell versions expose cell geometry when semantically relevant.

### 7.2 Linear bar

- flat rounded rectangle or fixture-specific 2D chassis outline;
- N emitter circles/rounded cells;
- emitter spacing follows profile geometry if available;
- each selectable semantic cell remains its own interaction target.

### 7.3 Pixel bar / matrix

- simplified outer housing;
- repeated emitter geometry;
- optimize for readability at normal zoom;
- preserve cell ordering and semantic addressing.

### 7.4 Circular pixel PAR

- circular chassis;
- data-driven emitter array where available;
- generic layout fallback only when profile geometry is absent;
- preserve semantic ordering.

### 7.5 Moving head

This family must remain especially disciplined because previous concepts drifted into 3D.

Use direct top/plan-view geometry:

- base footprint;
- yoke represented as flat lines/shapes;
- head footprint;
- lens/aperture;
- pan/orientation indicator.

No visible side wall, height, or three-quarter view.

### 7.6 Strobe / blinder

- rectangular flat housing;
- panel/cell geometry;
- live optical region may become extremely bright but housing remains readable;
- preserve multiple semantic cells if the fixture exposes them.

### 7.7 Conventional / Fresnel / profile

- top-down technical silhouette;
- aperture indicates front;
- barrel/body represented as plan geometry;
- avoid drafting-symbol abstraction so severe that casual Stage readability suffers.

### 7.8 Laser

- flat projector footprint and aperture/orientation marker;
- no laser simulation changes in this project unless existing Prism behavior already provides it;
- design glyph to support later visual extensions without implying unsafe beam geometry.

### 7.9 Fog / haze

- flat top/plan-view machine silhouette;
- outlet and handle/vent hints may be represented as line work;
- no three-quarter appliance thumbnail;
- output visualization, if any exists, remains separate from hardware glyph.

---

## 8. Optical state rendering

The **lens is the bridge** between flat hardware and living light.

### 8.1 0% / idle

- flat dark optical fill;
- subtle 2D ring/outline;
- no housing tint from previous output;
- no glow;
- emitter geometry remains readable.

### 8.2 Low output

- color appears inside the lens/cell;
- small controlled luminance increase;
- minimal bloom.

### 8.3 Medium output

- stronger hue and luminance;
- subtle local bloom;
- housing remains visually flat.

### 8.4 High output

- bright optical core;
- restrained bloom outside lens geometry;
- color should not immediately clip to white;
- beam remains primary projected-light visualization.

### 8.5 Important separation

Do not use lens gradients to make the **fixture body** appear 3D.

Optical gradients are acceptable because they represent emitted/energized light, not physical chassis depth.

---

## 9. Selection and interaction system

### 9.1 Prism purple means UI state

Never use Prism purple to fake fixture output.

Purple may indicate:

- hover;
- selection;
- multi-selection bounds;
- drag/transform handles;
- orientation/interaction affordances.

### 9.2 Hover

- thin restrained highlight;
- existing hover inspector behavior preserved;
- no large glow that interferes with beam/lens color.

### 9.3 Selected fixture

- clean purple perimeter/bounds treatment;
- keep hardware colors neutral;
- keep output colors untouched.

### 9.4 Selected sub-fixture

- purple indication localized to that emitter/cell;
- preserve lens/output visibility underneath or inside the selection treatment.

### 9.5 Multi-select

- retain existing semantics;
- aggregate bounding box may be used;
- individual selected fixtures/cells remain identifiable.

### 9.6 Dragging

- do not substitute a static drag ghost if current Prism behavior provides live fixture movement;
- beam origins should track live movement the same way they do today;
- child-cell semantic mapping must not be rebuilt during drag.

---

## 10. Zoom / Level of Detail

V3 should become simpler as the user zooms out, but **LOD must never change semantics**.

### Far zoom

Show:

- dominant fixture silhouette;
- active lens color if readable;
- selection state;
- orientation only when necessary.

May hide:

- emitter micro-detail;
- secondary hardware lines;
- nonessential label detail.

### Normal zoom

Show:

- full silhouette;
- semantically relevant cells;
- main housing lines;
- optical state;
- orientation;
- selection state.

### Close / inspect zoom

May reveal:

- finer emitter layout;
- yoke/mount details;
- additional 2D hardware lines;
- cell boundaries.

**Never make child fixtures unselectable merely because their decorative circles are visually simplified at far zoom.** If interaction at that zoom is impractical, preserve current Prism behavior rather than inventing a V3-specific semantic change.

---

## 11. Labels

Glyph V3 should not increase Stage text clutter.

Preserve the current label system unless a separate UI/UX change has been approved.

If Codex touches labels while integrating V3:

- avoid label overlap with cells and selection overlays;
- do not bake labels into glyph artwork;
- labels must remain renderer-independent;
- switching V1/V3 must not change fixture names or metadata.

---

## 12. Architecture guidance

### 12.1 StageGlyphContext

Prefer feeding both renderers from a shared semantic context containing only authoritative Stage/fixture state.

Potential contents:

```text
fixture ID
fixture family/type
profile/mode
stage transform
selection state
hover state
parent/child semantic relationships
emitter/cell definitions
emitter/cell live optical state
orientation
renderer scale / zoom level
beam anchor requirements
```

Do not duplicate DMX/programmer logic in the renderer.

### 12.2 Separate three concerns

Keep these layers conceptually distinct:

```text
Fixture semantics / live state
            |
            v
Glyph geometry + interaction anchors
            |
            +------> selection / hit testing
            |
            +------> lens/cell drawing
            |
            +------> beam emitter anchors
                            |
                            v
                    Existing Beam Renderer
```

### 12.3 V3 should map state, not own it

The renderer should answer questions like:

- "Where is emitter 3 drawn?"
- "How should this fixture family be represented?"
- "How should this cell look at 62% cyan?"

It should not answer:

- "What is emitter 3's DMX value?"
- "Which cell should be selected?"
- "What color should the programmer generate?"

Those belong to existing authoritative systems.

---

## 13. Settings implementation acceptance criteria

The Settings selector is complete only when all of the following are true:

- V1 and V3 appear as clear user-facing options;
- switching styles updates all open Stage views immediately;
- no `.prism` document dirty flag is created;
- closing and reopening Prism retains the user's preference;
- switching to V1 restores the pre-project glyph rendering path;
- beams continue to render in both modes;
- sub-fixture selection continues in both modes;
- no fixture/profile migration occurs;
- no show-file schema version change is required solely for glyph style.

---

## 14. Required automated tests

Add tests appropriate to the repo's current architecture. At minimum cover the underlying contracts even if pixel-perfect snapshot testing is not currently practical.

### Renderer preference tests

- preference round trip: V1;
- preference round trip: V3;
- renderer switch does not mutate document model;
- invalid/unknown preference value safely falls back to supported style.

### Semantic mapping tests

For a multi-cell fixture:

- emitter count is identical under V1 and V3;
- semantic emitter IDs remain identical;
- V3 anchor count equals expected semantic beam emitter count;
- V3 anchor ordering matches semantic element ordering;
- selected child IDs remain unchanged when renderer changes.

### Multi-beam tests

- four independently active cells produce four emitter anchors/beams where existing semantics require four;
- one inactive child does not incorrectly suppress sibling beams;
- per-cell colors are not averaged into one fixture color;
- switching V1 <-> V3 does not change beam semantic inputs.

### Interaction tests

- parent fixture hit target resolves to parent;
- child emitter hit target resolves to correct child;
- multi-select modifier behavior preserved;
- dragging parent preserves child IDs and beam associations;
- hover does not steal selection.

---

## 15. Manual smoke-test matrix

Codex must perform or document these manual tests in the running Prism app, not only in previews/component galleries.

| Test | V1 | V3 |
|---|---|---|
| Single PAR selects | Required | Required |
| Single PAR live color/intensity | Required | Required |
| 4-cell bar parent selects | Required | Required |
| 4-cell bar each child selects | Required | Required |
| Multiple child cells can be selected | Required | Required |
| Each child can be edited independently | Required | Required |
| Four different cell colors display correctly | Required | Required |
| Four beams render independently | Required | Required |
| Beams track fixture rotation | Required | Required |
| Beams track fixture drag live | Required | Required |
| Fixture multi-select | Required | Required |
| Undo/redo after transform | Required | Required |
| Hover inspector | Required | Required |
| Renderer switch while show is open | Required | Required |
| Renderer switch does not dirty show | Required | Required |
| Reopen app retains renderer preference | Required | Required |

### Haywire full-rig validation

Use the Haywire full-rig Stage project as a real-world visual and functional validation case.

Specifically inspect:

- front-light bars;
- uplights;
- circular backlights;
- dance-floor fixtures;
- side bars;
- atmospherics;
- any multi-cell fixtures;
- child-element selection;
- simultaneous multi-color beam output.

The goal is not merely for V3 to look attractive in isolation. It must remain readable and operable in a crowded real Stage layout.

---

## 16. Performance requirements

The visual overhaul must not make Stage interaction feel heavier.

Pay particular attention to:

- live fixture dragging;
- zoom/pan;
- multi-selection;
- high fixture counts;
- many simultaneously active emitters;
- multi-beam fixtures;
- rapid intensity/color changes from MIDI or song playback.

Avoid expensive effects on hardware glyphs. The new flat 2D direction should make V3 **cheaper**, not more expensive, than the rejected pseudo-3D concepts.

Do not add per-frame allocations or redundant semantic recomputation merely for visual polish.

---

## 17. Explicitly rejected V2 directions

Codex should not use the previous V2 render packs as literal implementation references.

Rejected traits include:

- product-render fixture thumbnails;
- three-quarter perspective;
- faux chassis depth;
- metallic shading;
- visible side surfaces;
- dimensional handles;
- miniature 3D moving heads;
- 3D-looking fog/haze machines;
- cast/contact shadows intended to place a fixture in 3D space.

The current approved direction is **V3 flat orthographic 2D**.

---

## 18. Scope boundaries

Do **not** use this project as an excuse to redesign:

- fixture profile schema;
- LightKey importer semantics;
- patching;
- programmer;
- DMX output;
- Art-Net/sACN;
- Music Engine;
- AME;
- Effects Engine;
- Stage persistence;
- selection semantics;
- beam physics/appearance;
- sub-fixture architecture;
- project file extensions/schema.

Small adapters are acceptable where required to expose existing semantic data cleanly to the V3 renderer, but any model-level change must be justified and reviewed before implementation.

---

## 19. Recommended implementation sequence

1. **Inventory V1 render and interaction paths.**
   - Identify fixture drawing, child hit-testing, emitter anchors, beam integration, selection overlays, zoom LOD, and preferences architecture.

2. **Add renderer abstraction without changing appearance.**
   - Route current behavior through the centralized boundary.
   - Prove V1 still works unchanged.

3. **Add Settings preference.**
   - V1 can temporarily back both values until V3 exists.
   - Verify setting is application-level and does not dirty show files.

4. **Implement V3 primitives.**
   - Flat housing.
   - emitter/lens.
   - orientation marker.
   - selection overlays.
   - data-driven emitter layout.

5. **Implement single-emitter fixtures first.**
   - Establish visual grammar without multi-cell complexity.

6. **Implement multi-cell bars and pixel fixtures.**
   - Treat child selection and beam-anchor parity as release-blocking requirements.

7. **Implement moving heads and atmospherics.**
   - Carefully enforce orthographic rule.

8. **Integrate existing beam renderer.**
   - Reuse semantic multi-beam behavior.
   - Only adapt origin anchors to V3 geometry.

9. **Implement zoom LOD.**
   - Preserve semantic interactions.

10. **Run automated parity tests.**

11. **Run Haywire full-rig smoke test.**

12. **Provide screenshots of the actual running Prism Stage in both V1 and V3.**
   - Do not submit only isolated glyph sheets or SwiftUI previews.

---

## 20. Definition of done

V3 is complete only when:

- the Stage clearly reads as a 2D orthographic environment;
- glyphs look materially more polished than V1 without looking 3D;
- fixture-family silhouettes are immediately distinguishable;
- live lens color looks beautiful;
- the existing beam renderer remains visually intact;
- multi-cell fixtures retain independent visual cells;
- sub-fixture selection is fully preserved;
- multiple selected child elements remain independently identifiable;
- multi-beam fixtures still emit the correct number of independent beams;
- beam color/intensity/direction remains semantically correct;
- dragging/rotation updates beam origins correctly;
- V1 remains available and functional;
- users can switch **Prism 2D (V3)** / **Legacy (V1)** from Settings;
- switching styles does not modify show data;
- V3 performs acceptably with the Haywire full rig;
- the running application, not just a design preview, matches the approved flat-2D visual direction.

---

# 21. Final instruction to Codex

Treat this as a **renderer replacement option, not a semantic rewrite**.

The highest-priority failure to avoid is a beautiful V3 renderer that breaks the reasons Prism's Stage is useful.

In particular:

> **Do not sacrifice sub-fixture selection, per-cell control, or multi-beam behavior for visual simplicity.**

Those behaviors are part of Prism's functional contract. V3 must make them clearer and prettier, not flatten them away.

And throughout the implementation, preserve the guiding visual principle:

> **Hardware is flat. Light is dimensional.**
