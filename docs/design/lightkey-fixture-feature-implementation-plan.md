# LightKey Fixture Import Feature Implementation Plan

## Purpose

This plan addresses the unsupported-feature warnings found while importing the LightKey fixture test corpus. It separates importer correctness problems from genuine Prism fixture-model gaps so that Prism does not acquire LightKey-specific architecture unnecessarily.

The reference report contains 3,318 warnings across 19 fixture files and 102 personalities:

| Warning code | Count | Initial disposition |
| --- | ---: | --- |
| `conditionalCapability` | 2,884 | Importer defect until proven otherwise |
| `unknownColorEmitter` | 250 | Add fine-channel recognition and pairing |
| `unsupportedBeamLayout` | 90 | Translate into a Prism-native emitter geometry model |
| `unsafeCommand` | 41 | Add protected command semantics |
| `compoundChannel` | 32 | Add range-specific capability semantics |
| `unknownCapability` | 21 | Add standard mappings where appropriate |

## Guiding decisions

1. Prism will model lighting-domain concepts, not LightKey implementation classes.
2. LightKey class names may be retained as import provenance, but they will not enter playback or programming APIs.
3. The importer must distinguish data loss, reduced semantics, safety concerns, and informational metadata.
4. A warning must describe a real limitation. Null archive references, ordinary single-beam layouts, and successfully translated data must not require user review.
5. Existing Prism fixture files must remain readable throughout the work.
6. New fixture semantics must be useful to native Prism fixture creation and future importers, not only LightKey imports.

## Phase 0 — Establish a fixture-import regression corpus

### Objective

Make the current 19-file corpus a repeatable compatibility test before changing decoding or fixture semantics.

### Work

- Add a sanitized, redistribution-safe set of representative fixture archives to test resources, or document a local corpus test harness if the original files cannot be committed.
- Select minimal representatives for:
  - UID-zero null conditions
  - A genuinely non-null condition, if one can be found
  - RGBW fine channels
  - Strip, grid, ring, row, and hexagonal emitter layouts
  - Frost and fine beam attributes
  - Lamp/reset/service commands
  - Channels containing multiple semantic ranges
- Add a machine-readable import summary containing warning counts by code.
- Add a golden-test mechanism for imported channel attributes, resolutions, functions, geometry, commands, and warning classifications.

### Acceptance criteria

- The corpus can be imported non-interactively in tests.
- Tests report warning-count changes clearly.
- Each later phase has at least one fixture that fails before the implementation and passes afterward.

## Phase 1 — Correct keyed-archive null and condition decoding

### Problem

LightKey keyed archives use UID `0` to reference the archive's shared `$null` object. The importer currently sees the UID as a non-null value and emits a conditional-capability warning. This appears to account for most of the 2,884 condition warnings.

### Work

- Add a keyed-archive reference resolver that:
  - Resolves UIDs through `$objects` with bounds checking.
  - Treats UID `0` or any UID resolving to `$null` as absent.
  - Detects cycles and excessive reference depth.
  - Preserves the current rule that imported archives never instantiate archived Objective-C classes.
- Replace the current `condition` presence check with resolved-value inspection.
- Decode the shape of genuinely non-null conditions before deciding whether Prism needs a corresponding semantic model.
- Preserve unresolved real conditions as provenance metadata and emit one actionable warning per affected channel rather than repeated warnings per incidental capability.
- Deduplicate identical warnings within each personality.

### Warning behavior

- Null condition: no warning.
- Recognized condition translated without loss: informational entry at most.
- Real condition retained but not evaluated: `requiresReview` with decoded operands when safe and available.
- Malformed or unsafe condition object: warning or fatal issue depending on whether channel data can still be imported safely.

### Acceptance criteria

- UID-zero conditions generate no warning.
- Archive references remain bounded and safe against malicious files.
- The corpus's conditional warning count falls from 2,884 to the number of genuinely non-null conditions.
- The imported DMX channel and function data is unchanged by null-resolution fixes.

## Phase 2 — Support fine color and fine beam channels

### Objective

Represent fine bytes as higher-resolution forms of their coarse attributes instead of unrelated generic controls.

### Prism-native model work

- Confirm or extend the channel-resolution model so a semantic attribute can identify coarse and fine bytes reliably.
- Represent an attribute's multi-byte value without assuming that coarse and fine channels are adjacent.
- Ensure programmer values, palette values, cue storage, interpolation, output rendering, and fixture exchange preserve 16-bit precision.
- Define deterministic behavior when only a fine channel exists or pairing is ambiguous.

### Import mappings

- Map:
  - `RedFine` → fine byte of Red
  - `GreenFine` → fine byte of Green
  - `BlueFine` → fine byte of Blue
  - `CoolWhiteFine` → fine byte of Cool White
  - `LXZoomFineCapability` → fine byte of Zoom
  - `LXFocusFineCapability` → fine byte of Focus
  - `LXPrismAngleFineCapability` → fine byte of Prism Angle
- Prefer explicit source metadata when pairing; use validated name/order heuristics only as a fallback.
- Emit a focused ambiguity warning when no unique coarse attribute can be selected.

### Acceptance criteria

- Fine RGB/RGBW controls participate in Prism color mixing, palettes, effects, and output.
- Imported 16-bit values round-trip without loss.
- The 250 fine-color warnings are eliminated when pairing is unambiguous.
- Zoom Fine, Focus Fine, and Prism Angle Fine no longer import as generic controls.

## Phase 3 — Add missing standard capability mappings

### Objective

Translate lighting-domain features that Prism should understand independently of LightKey.

### Frost

- Add a `frost` beam attribute.
- Define normalized control behavior and DMX function labels.
- Expose Frost in the appropriate Programmer beam controls.
- Ensure palettes, cues, effects, and output support it.

### Color filter

- Inspect `LXColorFilterCapability` settings to determine whether each instance represents:
  - A discrete color wheel/filter slot
  - A continuous filter control
  - LightKey-only UI metadata
- Translate discrete filters to Prism color-wheel functions when slot/range data is available.
- Preserve unknown filters as labeled generic ranges rather than inventing color values.

### Lamp capability

- Route `LXLampCapability` through the protected-command model described in Phase 4.
- Do not expose lamp controls as ordinary continuous attributes.

### Acceptance criteria

- Frost has a native Programmer control and survives cue/palette round trips.
- Recognized color filters retain their names and DMX ranges.
- Known standard capabilities no longer emit `unknownCapability`.
- Unrecognized LightKey-only classes remain generic and produce a precise warning.

## Phase 4 — Introduce protected command functions

### Objective

Prevent accidental transmission of reset, lamp, calibration, and service commands while retaining access for intentional operation.

### Model

Add generic command metadata to a channel function, including:

- Command category: reset, lamp on, lamp off, calibration, service, or custom.
- DMX activation range.
- Safe/rest value.
- Optional required hold duration.
- Whether explicit user confirmation is required.
- Human-readable label and imported provenance.

### Runtime and UI

- Exclude protected functions from ordinary attribute faders, effects, and automatic value sweeps.
- Provide a deliberate action UI such as confirmation plus press-and-hold.
- Return to the safe value after the required duration unless the fixture protocol explicitly requires latching.
- Log command invocation without logging unrelated show content.
- Ensure cue playback cannot trigger protected commands accidentally. Explicit command cues should require a separately designed and validated workflow.

### Importer

- Map `LXCommandCapability` and `LXLampCapability` function ranges into protected commands.
- Infer command category from source labels conservatively.
- Leave ambiguous functions protected and categorized as custom.

### Acceptance criteria

- Imported service ranges cannot be reached through normal fader movement or effects.
- An operator can intentionally invoke a recognized command with confirmation.
- Default, highlight, release, and blackout operations never enter a protected range.
- The 41 `unsafeCommand` warnings become either translated informational notices or focused warnings for ambiguous commands.

## Phase 5 — Model range-specific capabilities on compound channels

### Objective

Allow one physical DMX channel to expose different semantics in different value ranges.

### Model

- Extend channel functions so each DMX range may carry an optional semantic capability in addition to its label.
- Keep one physical output byte per channel while permitting several programmer-facing actions.
- Define conflict resolution when multiple semantic controls target the same channel.
- Preserve current simple-channel behavior as the fast/common path.

### Initial combinations

- Gobo angle versus gobo rotation.
- Prism angle versus prism rotation.
- Shutter/strobe versus a custom function.
- Commands sharing a channel with other functions.

### Programmer behavior

- Selecting a range-specific function should place the channel within that function's DMX range.
- Controls should operate over the selected function's local normalized range.
- Switching functions should be explicit and deterministic.
- Effects must not cross into unrelated or protected ranges unless specifically configured.

### Importer

- Convert multiple LightKey capabilities sharing an offset into range-specific Prism capabilities when their DMX ranges and semantics are compatible.
- Warn only for overlapping, ambiguous, or unrepresentable combinations.
- Retain all original labeled ranges even when semantic translation is incomplete.

### Acceptance criteria

- Gobo/prism angle and rotation combinations can be programmed independently while sharing one DMX address.
- Command ranges remain protected inside compound channels.
- No DMX functions are dropped during import.
- Most of the 32 compound warnings are eliminated; remaining warnings identify a concrete ambiguity.

## Phase 6 — Add Prism-native emitter geometry

### Objective

Represent the spatial arrangement of multi-emitter fixtures for previews, cell selection, and pixel effects.

### Model

Introduce a generic emitter geometry independent of LightKey classes:

- Single emitter.
- Linear strip with orientation and ordering.
- Rectangular rows/grid with dimensions and traversal order.
- Ring with start angle and direction.
- Hexagonal arrangement.
- Explicit normalized two-dimensional coordinates as a fallback and future-proof representation.
- Mapping from each logical emitter/cell to its geometry position.

The explicit-coordinate form should be capable of representing all predefined layouts so future importers do not require new layout enums for every vendor convention.

### Import translation

- `LXSingleBeamLayout` → ordinary single-emitter geometry; no review warning.
- `LXStripBeamLayout` → linear strip.
- `LXRowsBeamLayout` → rows/grid after dimensions and ordering are decoded.
- `LXGridBeamLayout` → rectangular grid.
- `LXRingsBeamLayout` → ring or rings.
- `LXHexagonsBeamLayout` → hexagonal or explicit-coordinate geometry.
- If required dimensions are missing, retain beam count and provenance and emit a precise warning describing the missing field.

### Consumers

- Fixture preview and patch visualization.
- Per-cell selection and naming.
- Spatial and pixel effects.
- Stage representation where appropriate.
- Fixture profile editor.

### Acceptance criteria

- Geometry round-trips through Prism project and user-library fixture formats.
- Existing fixtures without geometry decode as single-emitter or unspecified without migration failures.
- Imported cell indexes correspond to the correct visual positions.
- Single-beam imports generate no unsupported-layout warning.
- Supported multi-cell layouts render and respond correctly to a spatial test pattern.

## Phase 7 — Warning taxonomy and importer UX cleanup

### Objective

Make warnings proportional, actionable, and useful in both the importer and exported reports.

### Severity rules

- `information`: translated successfully; provenance or approximation is worth noting.
- `warning`: non-critical metadata or convenience behavior was lost.
- `requiresReview`: programming/playback semantics may differ or require operator choice.
- `fatal`: a safe, structurally valid fixture personality cannot be produced.

### Work

- Deduplicate issues by fixture, personality, channel, code, and relevant details.
- Aggregate repetitive cell warnings where the same limitation affects a contiguous group.
- Distinguish imported-but-generic from dropped data.
- Include the exact source class, source field, Prism mapping, and practical consequence.
- Add summary counts by severity and warning code to the importer and text export.
- Allow warning-report export before and after import.
- Consider a filter for all issues versus only selected personalities.

### Acceptance criteria

- No warning claims a behavior is unsupported when it was translated successfully.
- Each `requiresReview` entry describes a decision or concrete playback risk.
- Exported warning counts match the importer UI.
- A large pixel fixture does not produce hundreds of identical messages for one underlying limitation.

## Data migration and compatibility

- Add new fields using backward-compatible decoding defaults.
- Treat absent geometry as unspecified/single-emitter according to existing fixture behavior.
- Treat absent function semantics as today's labeled DMX range.
- Treat absent command metadata as an ordinary function only for existing trusted Prism definitions; imported ambiguous command ranges must default to protected.
- Version fixture definitions only if the current decoder cannot safely distinguish missing fields from explicit values.
- Add round-trip tests for fixtures written before and after each schema extension.

## Testing strategy

### Decoder safety

- UID bounds, cycles, excessive depth, malformed `$objects`, and oversized collections.
- UID-zero and indirect-null resolution.
- No archived classes instantiated during inspection.

### Model tests

- Coarse/fine pairing and 16-bit composition.
- Range-specific normalization and conflict resolution.
- Protected command safe/rest behavior.
- Geometry validation, ordering, and serialization.

### Importer tests

- Exact semantic mappings for every newly supported LightKey class.
- Ambiguous input retains DMX data and emits the intended warning.
- Warning deduplication and stable exported summaries.
- Batch import continues after one malformed fixture.

### Integration tests

- Programmer → cue/palette → playback → DMX output for fine color and beam values.
- Compound function selection and output.
- Command confirmation, hold, release, and prevention during effects.
- Multi-cell geometry preview and spatial effect traversal.

### Performance tests

- Import large multi-personality and high-cell-count fixtures off the main actor.
- Ensure geometry and compound capabilities do not regress DMX rendering deadlines.
- Keep warning aggregation linear in capability count.

## Proposed delivery order

1. Phase 0: regression corpus.
2. Phase 1: UID/null fix and warning deduplication.
3. Phase 2: fine color and beam pairing.
4. Phase 3: frost and other standard mappings.
5. Phase 4: protected commands.
6. Phase 5: range-specific compound capabilities.
7. Phase 6: emitter geometry.
8. Phase 7: final warning taxonomy and UX refinement.

Phases 0–3 are importer-focused and should substantially reduce false or avoidable warnings. Phases 4–6 are broader Prism capabilities and should be developed as native fixture features with LightKey import acting as one producer of the data.

## Completion definition

The initiative is complete when:

- UID-zero null references never produce conditional warnings.
- All supported fine attributes provide true high-resolution control.
- Frost and recognized color-filter functions have native semantics.
- Reset, lamp, calibration, and service ranges are protected from accidental output.
- Common multi-function channels retain independently usable semantics.
- Supported emitter layouts drive previews, cell selection, and spatial effects.
- Remaining warnings identify genuine, specific information loss or risk.
- The reference corpus imports with no false-positive `requiresReview` warnings and no dropped DMX ranges.
