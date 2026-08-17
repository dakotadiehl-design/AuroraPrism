# Aurora Feature Request: Lightkey Fixture Profile Importer and Compatibility Layer

**Status:** Proposed\
**Priority:** High\
**Target:** Aurora macOS\
**Feature Area:** Fixture Library / Fixture Engine / Import & Migration\
**Primary Input Format:** `.lightkeyfxt`\
**Implementation Language:** Swift / Foundation\
**Scope:** Read/import compatibility only. Aurora must retain its own
native fixture schema and must not depend on Lightkey at runtime.

------------------------------------------------------------------------

## 1. Executive Summary

Implement a robust **Lightkey Fixture Profile Importer** for Aurora.

The goal is to allow a user to select one or more Lightkey
`.lightkeyfxt` fixture-profile files and import them into Aurora's
native fixture library. Aurora should decode the Lightkey archive,
translate recognized fixture semantics into Aurora-native models,
validate the result, report any unsupported or ambiguous constructs, and
save a fully independent Aurora fixture profile.

This is not intended to make Aurora internally use Lightkey's object
model. Lightkey compatibility must exist as a boundary-layer importer:

``` text
.lightkeyfxt
    ↓
Lightkey Archive Decoder
    ↓
Intermediate Lightkey Import Model
    ↓
Semantic Mapper + Validator
    ↓
Aurora Native Fixture Model
    ↓
Aurora Fixture Library / Patch / Programmer / 2D Stage Designer
```

The supplied sample files establish that `.lightkeyfxt` is an **Apple
binary property list serialized with `NSKeyedArchiver`**. The archives
expose recognizable Lightkey model-class names such as
`LXFixtureProfile`, `LXPersonality`, `LXSetting`, capability classes,
beam-layout classes, UUIDs, and version metadata. This makes a native
Swift/Foundation importer technically realistic without executing
Lightkey or parsing an opaque custom byte stream.

The importer should be designed conservatively: **never silently invent
fixture behavior**. Unknown fields or classes must be preserved in
diagnostics where practical and surfaced to the user when they affect
fidelity.

------------------------------------------------------------------------

## 2. Why Aurora Needs This

Aurora is intended to become a serious macOS lighting-control
application with a workflow competitive with Lightkey while adding
Aurora-specific capabilities such as advanced MIDI control, integrated
stage visualization, Song Mode, remote control, and richer performance
workflows.

Fixture migration is a major adoption barrier. A user who already has
working Lightkey profiles should not have to manually recreate every
personality, DMX channel, color component, gobo, prism, movement
parameter, pixel mapping, and physical beam layout before evaluating
Aurora.

A Lightkey importer provides several benefits:

1.  **Migration:** Existing Lightkey users can bring fixture profiles
    into Aurora.
2.  **Fixture-library bootstrapping:** Aurora can rapidly gain usable
    profiles from fixture files the user legally possesses.
3.  **Semantic fidelity:** Lightkey profiles contain much richer
    information than a flat DMX-channel list.
4.  **2D visualization:** Beam and multi-cell information can feed
    Aurora's Stage Designer and Live Preview.
5.  **Programmer integration:** Imported semantic capabilities can
    populate Aurora's Intensity, Color, Position, Beam, and custom
    controls.
6.  **Future compatibility:** The same import architecture can later
    support GDTF, SSL2, FXT, PFF, QLC+, or other fixture formats.

------------------------------------------------------------------------

## 3. Evidence From the Supplied Fixture Corpus

The implementation should be based on actual observed archive
structures, not guesses.

The supplied corpus includes:

-   Generic `Switch.lightkeyfxt`
-   Generic `Fog Machine.lightkeyfxt`
-   Generic `LED Matrix (Mono).lightkeyfxt`
-   `Chauvet - 4Bar Hex ILS.lightkeyfxt`
-   `Unity - RAW 1.7_3_5_10.lightkeyfxt`
-   `Chauvet - Obsession HP.lightkeyfxt`
-   `Chauvet - Rogue R1E Spot.lightkeyfxt`
-   `Chauvet - Intimidator Spot 475ZX.lightkeyfxt`
-   `American DJ - Jolt Bar FX2.lightkeyfxt`

Observed archive sizes range from tiny single-channel generic profiles
to the Jolt Bar archive containing thousands of serialized objects. This
gives us useful coverage across simple switches, fog, intensity,
RGB-family color mixing, lasers/custom channels, moving heads, color
wheels, gobos, prisms, 16-bit parameters, and multi-cell/pixel layouts.

### 3.1 Archive Technology

Observed `.lightkeyfxt` files are:

-   Apple binary property lists
-   serialized through `NSKeyedArchiver`
-   composed of an object graph with `$objects`, `$top`, class
    descriptors, Foundation container types, UUIDs, index sets, data
    objects, etc.

Do **not** treat `.lightkeyfxt` as JSON, XML, SQLite, or an undocumented
fixed-offset binary structure.

### 3.2 Important Observed Model Classes

The corpus exposes at least the following Lightkey classes.

#### Core fixture model

``` text
LXFixtureProfile
LXPersonality
LXSetting
LXCapabilityCondition
```

#### Intensity / output

``` text
LXIntensityCapability
LXIntensityFineCapability
LXOnOffCapability
LXFogCapability
```

#### Color

``` text
LXColorComponentCapability
LXColorWheelCapability
LXRGBColor
LXCorrectionColor
LXSplitColor
```

#### Movement

``` text
LXPanCapability
LXPanFineCapability
LXTiltCapability
LXTiltFineCapability
LXPanTiltSpeedCapability
```

#### Beam / optical system

``` text
LXFocusCapability
LXZoomCapability
LXIrisCapability
LXShutterStrobeCapability
```

#### Gobos

``` text
LXGoboCapability
LXGoboAngleCapability
LXGoboRotationCapability
```

#### Prisms

``` text
LXPrismCapability
LXPrismAngleCapability
LXPrismRotationCapability
```

#### Modes, commands, and vendor-specific behavior

``` text
LXModeCapability
LXCommandCapability
LXCustomCapability
```

#### Physical beam layout

``` text
LXSingleBeamLayout
LXRowsBeamLayout
LXUndefinedBeamLayout
```

This list is **observed, not exhaustive**. The importer must assume
future files can contain additional `LX*` classes.

------------------------------------------------------------------------

## 4. Observed Fixture-Level Fields

`LXFixtureProfile` archives expose fields including:

``` text
name
manufacturer
UUID
revisionUUID
type
personalities
panRange
tiltRange
panTime
tiltTime
tiltCenter
beamType
beamSpread
beamShape
beamLayout
embeddedGobos
colorMergeMode
intensityMergeMode
comments
additionalInfo
sourceFilename
flexible
additionalBeamsData
```

Not every fixture contains every field.

### Requirement

The decoder must distinguish:

-   absent field
-   explicit null/nil-equivalent field
-   recognized field with a value
-   recognized field with an unexpected representation
-   unknown field

Do not flatten these cases into one generic default during decoding.

------------------------------------------------------------------------

## 5. Personalities

Lightkey models fixture operating modes/personality variants explicitly
with `LXPersonality`.

Observed fields include:

``` text
customName
footprint
capabilities
```

For example, the supplied Chauvet 4Bar Hex ILS contains multiple
personalities with different DMX footprints.

### Aurora behavior

An imported fixture must preserve all successfully decoded
personalities.

The user should be able to choose the desired personality when
adding/patching the fixture in Aurora.

A personality should map to an Aurora-native object conceptually similar
to:

``` swift
struct AuroraFixturePersonality {
    let id: UUID
    var name: String
    var footprint: Int
    var parameters: [AuroraFixtureParameter]
    var validationState: FixtureValidationState
}
```

Use the project's actual models/naming conventions rather than creating
duplicate concepts if Aurora already has equivalents.

------------------------------------------------------------------------

## 6. Capability Model

The central design principle is:

> **Import semantics, not merely channel numbers.**

A Lightkey capability communicates what a DMX channel or group of
channels means. Aurora should translate that into its own semantic
fixture parameter model.

Observed capability data includes fields such as:

``` text
channel
condition
beamIndexes
settings
customName
showsDMXValues
goboWheelIndex
prismWheelIndex
holdTime
```

Some values may be stored indirectly through archived objects,
dictionaries, index sets, or `params`.

### 6.1 Intensity

Map:

``` text
LXIntensityCapability
LXIntensityFineCapability
```

to Aurora's intensity/dimmer parameter system.

Where a fine capability is associated with a coarse capability, Aurora
should construct a coherent 16-bit parameter rather than exposing
unrelated 8-bit sliders.

### 6.2 RGB-family color emitters

Map `LXColorComponentCapability` to Aurora's additive color system.

The supplied 4Bar Hex ILS demonstrates semantic components including:

``` text
Red
Green
Blue
Amber
Cool White
Ultraviolet
```

Do not hard-code Aurora to RGB only. The native fixture model should
support arbitrary emitter components such as RGBW, RGBA, RGBWAUV, lime,
cyan, warm white, cool white, UV, etc.

### 6.3 Color wheels

Map:

``` text
LXColorWheelCapability
LXRGBColor
LXCorrectionColor
LXSplitColor
```

into Aurora's discrete color-wheel representation.

`LXSplitColor` indicates that Lightkey can semantically represent split
positions between adjacent wheel colors. Aurora should preserve that
concept if its native model supports it. If not, add an appropriate
native representation rather than reducing it to an unlabeled DMX range.

### 6.4 Movement

Map:

``` text
LXPanCapability
LXPanFineCapability
LXTiltCapability
LXTiltFineCapability
LXPanTiltSpeedCapability
```

into Aurora's Position parameter group.

Preserve fixture-level information such as:

``` text
panRange
tiltRange
panTime
tiltTime
tiltCenter
```

where meaning is understood.

Coarse/fine pan and tilt must become proper 16-bit controls.

### 6.5 Gobos

Map:

``` text
LXGoboCapability
LXGoboAngleCapability
LXGoboRotationCapability
```

into Aurora's Beam/Gobo model.

Preserve wheel identity through fields such as `goboWheelIndex`.

Do not assume a fixture has only one gobo wheel.

### 6.6 Prism

Map:

``` text
LXPrismCapability
LXPrismAngleCapability
LXPrismRotationCapability
```

into Aurora's Beam/Prism model.

Preserve `prismWheelIndex` and support multiple prism systems if
encountered.

### 6.7 Focus, zoom, iris, shutter/strobe

Map:

``` text
LXFocusCapability
LXZoomCapability
LXIrisCapability
LXShutterStrobeCapability
```

to the corresponding Aurora Beam controls.

For shutter/strobe, preserve discrete settings/ranges rather than
assuming the entire channel is a linear strobe-frequency control.

### 6.8 Switch and fog

Map:

``` text
LXOnOffCapability
LXFogCapability
```

to native Aurora semantics.

A generic switch should not masquerade as a dimmer solely because both
use a one-channel footprint.

### 6.9 Mode, command, and custom capabilities

Map:

``` text
LXModeCapability
LXCommandCapability
LXCustomCapability
```

conservatively.

These are particularly important because manufacturer-specific channels
often contain reset commands, automatic programs, sound-active modes,
macros, lamp controls, calibration actions, or other non-continuous
behavior.

Do not infer a semantic type unless the Lightkey archive provides enough
evidence.

Unknown/custom behavior should remain accessible through Aurora's
custom/raw parameter controls.

------------------------------------------------------------------------

## 7. Settings and DMX Ranges

`LXSetting` appears throughout the corpus and is fundamental to
interpreting discrete/ranged behavior.

The importer must reconstruct, where supported by the archive:

-   setting name
-   DMX start/end value
-   physical/semantic value
-   associated color
-   associated gobo/prism state
-   open/closed/off/on state
-   rotation direction
-   speed range
-   command/macro meaning
-   any conditional applicability

Do not assume settings are single DMX values. Many fixture channels
encode behavior in ranges.

Example conceptual Aurora model:

``` swift
struct AuroraParameterRange {
    var dmxLower: UInt16
    var dmxUpper: UInt16
    var label: String?
    var semanticValue: AuroraSemanticValue?
}
```

Adapt this to Aurora's existing architecture.

------------------------------------------------------------------------

## 8. Capability Conditions and Mode Dependencies

The corpus contains:

``` text
LXCapabilityCondition
```

and observed fields such as:

``` text
settingIndexes
modeChannel
```

This indicates some capabilities/settings are conditional on another
mode or channel state.

This must **not** be discarded.

Aurora needs a representation for conditional fixture behavior, even if
the first importer release cannot fully execute every condition.

Minimum behavior:

1.  Decode the condition.
2.  Preserve it in the intermediate import model.
3.  Attempt to map it to Aurora-native conditional semantics.
4.  If unsupported, mark the affected capability as partially imported.
5.  Display a specific warning to the user.

Never silently make a conditional capability unconditional.

------------------------------------------------------------------------

## 9. Multi-Cell / Pixel Fixtures

The American DJ Jolt Bar FX2 is a critical test fixture.

Its archive exposes:

``` text
LXRowsBeamLayout
beamIndexes
```

and contains a very large object graph compared with ordinary fixtures.

This demonstrates that Lightkey represents physical beam/cell topology
explicitly.

### Aurora requirement

The importer must map Lightkey beam/cell information into Aurora's
native multi-cell fixture representation.

This information should eventually be consumable by:

-   Fixture Programmer
-   color controls
-   pixel/cell selection
-   group/subfixture operations
-   Stage Designer
-   2D Live Preview
-   future effects engine

### Important design rule

Do not model a pixel fixture merely as hundreds of unrelated channels.

Aurora should understand:

``` text
Fixture
 ├── master/global parameters
 ├── cell 1
 │    ├── Red
 │    ├── Green
 │    └── Blue
 ├── cell 2
 │    ├── Red
 │    ├── Green
 │    └── Blue
 └── ...
```

while also preserving the physical ordering/layout of those cells.

`beamIndexes` should be investigated as a mapping between capabilities
and physical beams/cells.

`LXRowsBeamLayout` should be decoded into a topology appropriate for
Aurora.

Do not assume that all future layouts will be rows. The existence of
`LXSingleBeamLayout`, `LXRowsBeamLayout`, and `LXUndefinedBeamLayout`
strongly implies additional layout classes may exist.

------------------------------------------------------------------------

## 10. 16-bit Coarse/Fine Parameters

The corpus establishes at least:

``` text
LXIntensityFineCapability
LXPanFineCapability
LXTiltFineCapability
```

Aurora must not expose these as independent controls.

The mapper should pair fine channels with their coarse semantic
parameter and create an Aurora-native high-resolution parameter.

Example:

``` text
Lightkey:
Channel 1 → LXPanCapability
Channel 2 → LXPanFineCapability

Aurora:
Pan
  resolution: 16 bit
  coarseChannel: 1
  fineChannel: 2
```

The architecture should be extensible to other future coarse/fine pairs.

------------------------------------------------------------------------

## 11. Archive Decoder Architecture

Do not directly unarchive arbitrary classes with insecure object
instantiation.

Implement a **constrained decoder** that reads the binary plist and
walks the `NSKeyedArchiver` graph as data.

Recommended layers:

``` text
LightkeyFixtureImportService
    │
    ├── LightkeyArchiveReader
    │      └── reads binary plist
    │
    ├── NSKeyedArchiveGraphDecoder
    │      └── resolves UID references safely
    │
    ├── LightkeyObjectDecoder
    │      ├── LXFixtureProfile
    │      ├── LXPersonality
    │      ├── LXSetting
    │      ├── LX*Capability
    │      └── LX*BeamLayout
    │
    ├── LightkeyToAuroraMapper
    │
    ├── FixtureImportValidator
    │
    └── FixtureImportReport
```

### Security requirement

Treat imported fixture files as **untrusted input**.

Do not use an API path that causes arbitrary archived class names to be
dynamically instantiated.

Validate:

-   file size
-   plist structure
-   object count
-   UID bounds
-   recursion/depth
-   array/dictionary sizes
-   integer ranges
-   channel ranges
-   footprint
-   malformed references
-   cyclic graph behavior
-   unreasonable cell counts
-   unsupported archive types

A malformed fixture file must fail cleanly without crashing Aurora.

------------------------------------------------------------------------

## 12. Intermediate Import Model

Create a Lightkey-specific intermediate representation rather than
mapping raw archive dictionaries directly into production Aurora models.

Example conceptual types:

``` swift
struct LKImportedFixtureProfile
struct LKImportedPersonality
struct LKImportedCapability
struct LKImportedSetting
struct LKImportedCondition
struct LKImportedBeamLayout
struct LKUnknownObject
```

Benefits:

-   isolates reverse-engineered format details
-   makes unit testing easier
-   prevents Lightkey naming from leaking throughout Aurora
-   allows future format-version handling
-   supports diagnostics
-   allows unknown fields/classes to be recorded
-   lets Aurora's native fixture schema evolve independently

The `LK*` types should exist only inside the importer module.

------------------------------------------------------------------------

## 13. Unknown-Class and Unknown-Field Handling

This is a hard requirement.

Future Lightkey versions may add classes that are absent from our sample
corpus.

If the decoder encounters:

``` text
LXSomeFutureCapability
```

it must not crash and must not silently throw the entire fixture away.

Instead:

``` text
Unknown Lightkey object
├── archived class name
├── raw decoded fields where safe
├── object path / context
└── severity
```

Severity examples:

-   **Info:** irrelevant metadata ignored
-   **Warning:** capability imported as raw/custom
-   **Error:** personality cannot be represented safely
-   **Fatal:** archive cannot be decoded

Unknown fields on otherwise recognized objects should generally be
retained in import diagnostics but should not automatically fail import.

------------------------------------------------------------------------

## 14. Version Handling

The sample files originate from multiple Lightkey generations and
contain archive/application version metadata.

The importer should extract and record:

``` text
savingAppVersion
requiredAppVersion
```

Do not hard-code support to one Lightkey version.

Define a compatibility policy such as:

``` text
Known compatible format → normal import
Newer/unknown Lightkey version → attempt conservative import + warning
Structurally unsupported archive → reject with useful diagnostic
```

The UI should report the source Lightkey version when available.

------------------------------------------------------------------------

## 15. Identity and UUID Handling

Observed fixture profiles include:

``` text
UUID
revisionUUID
```

Aurora should preserve source identity as **import provenance**, but
should not blindly use Lightkey UUIDs as Aurora's internal global
identity if that can cause namespace or ownership problems.

Recommended approach:

``` text
Aurora fixture UUID: newly generated Aurora UUID
Source:
    format: lightkey
    sourceUUID: <Lightkey UUID>
    sourceRevisionUUID: <Lightkey revision UUID>
    sourceFilename: ...
    sourceSavingAppVersion: ...
```

This enables future duplicate detection and re-import/update workflows.

------------------------------------------------------------------------

## 16. Duplicate and Re-Import Behavior

When importing a Lightkey profile whose source UUID has previously been
imported, Aurora should detect the relationship.

Initial UX can offer:

-   Replace/update existing imported fixture
-   Import as new copy
-   Cancel

Do not overwrite a user-modified Aurora fixture without explicit user
action.

Longer term, `revisionUUID` may help determine whether a source profile
changed.

------------------------------------------------------------------------

## 17. User Interface

Add an import entry point in the Fixture Library/Fixture Manager.

Suggested command:

``` text
File
  → Import
      → Lightkey Fixture Profile…
```

or the equivalent location consistent with Aurora's existing
fixture-library UX.

Support:

-   single file selection
-   multi-file selection
-   drag-and-drop into Fixture Library, if appropriate
-   `.lightkeyfxt` filtering

### 17.1 Import Preview

Before committing an import, show a concise preview:

``` text
Chauvet
Rogue R1E Spot

Source: Lightkey Fixture Profile
Lightkey version: <decoded version>

Personalities:
✓ <mode name> — <N> channels
✓ <mode name> — <N> channels

Features detected:
✓ 16-bit Pan/Tilt
✓ Intensity
✓ Color Wheel
✓ Gobo
✓ Gobo Rotation
✓ Prism
✓ Focus
✓ Iris
✓ Shutter/Strobe

Warnings:
⚠ <specific unsupported/ambiguous construct>
```

Do not overwhelm normal users with archive internals.

Provide a disclosure such as **Technical Details** for diagnostic
information.

### 17.2 Result States

Use clear states:

-   Imported successfully
-   Imported with warnings
-   Could not import

For warnings, identify exactly what was lost or approximated.

Bad:

> Some properties could not be imported.

Good:

> Personality "23 Channel" imported, but one manufacturer-specific
> command channel could not be mapped to an Aurora semantic parameter.
> It was preserved as a Custom control.

------------------------------------------------------------------------

## 18. Import Provenance

Every imported fixture should record provenance:

``` text
Imported from Lightkey
Original filename
Original manufacturer/name
Source UUID
Source revision UUID
Source Lightkey version
Aurora import date
Importer schema/version
Warnings generated during import
```

This metadata should be available in Fixture Inspector/Fixture Editor
but need not clutter ordinary programming UI.

------------------------------------------------------------------------

## 19. Native Aurora Independence

This is one of the most important architectural requirements.

After import:

-   Aurora must not require Lightkey.
-   Aurora must not require the original `.lightkeyfxt`.
-   runtime DMX output must not operate on `LX*` models.
-   the Programmer must not operate on `LX*` models.
-   Stage Designer must not operate on `LX*` models.
-   project files should reference Aurora-native fixture definitions.

The Lightkey model terminates at the importer boundary.

``` text
WRONG:
Programmer → LXFixtureProfile → DMX

RIGHT:
.lightkeyfxt → importer → AuroraFixtureProfile
                           ↓
             Programmer / Patch / Stage / DMX
```

------------------------------------------------------------------------

## 20. Legal/Product Boundary

Implement **user-driven interoperability**, not bulk copying of
Lightkey's fixture library.

The feature should import fixture files that the user selects/provides.

Do not:

-   scrape Lightkey's online fixture library
-   bundle Lightkey's fixture database with Aurora
-   present Lightkey fixture content as Aurora-authored content
-   depend on Lightkey proprietary assets at runtime

The importer should be described as compatibility/migration
functionality.

Before public release, licensing/trademark wording and distribution
behavior should receive appropriate review.

------------------------------------------------------------------------

## 21. Logging and Diagnostics

Add structured import logging suitable for development and support.

Example:

``` text
[LightkeyImport] archive opened
[LightkeyImport] savingAppVersion = ...
[LightkeyImport] fixture = Chauvet / Rogue R1E Spot
[LightkeyImport] personalities = ...
[LightkeyImport] recognized capability LXPanCapability
[LightkeyImport] paired LXPanFineCapability
[LightkeyImport] unknown field ...
[LightkeyImport] validation completed: 0 errors, 2 warnings
```

Avoid dumping huge binary blobs or entire archives into normal logs.

For debug builds, provide an optional detailed decoded-object report.

------------------------------------------------------------------------

## 22. Developer Reverse-Engineering Utility

Add a small developer-only diagnostic utility/test helper capable of
producing a human-readable summary of a `.lightkeyfxt` archive.

Example output:

``` text
Fixture: American DJ Jolt Bar FX2
Archive objects: 3641

Classes:
  LXFixtureProfile
  LXPersonality
  LXColorComponentCapability
  LXIntensityCapability
  LXIntensityFineCapability
  LXShutterStrobeCapability
  LXCustomCapability
  LXRowsBeamLayout
  LXSetting
  ...

Unknown classes:
  none

Personalities:
  ...

Beam layout:
  type: rows
  ...
```

This will be invaluable when we encounter a future fixture containing a
new Lightkey class.

The tool must be development/support infrastructure, not a dependency of
the production UI.

------------------------------------------------------------------------

## 23. Test Corpus

Add copies of legally appropriate test fixtures or sanitized/generated
fixture archives to the test resources as permitted.

At minimum, tests should cover the semantic categories demonstrated by
the supplied corpus:

### Generic Switch

Tests:

-   one-channel footprint
-   `LXOnOffCapability`
-   discrete settings

### Generic Fog Machine

Tests:

-   `LXFogCapability`

### LED Matrix (Mono)

Tests:

-   intensity
-   `LXSingleBeamLayout`

### Chauvet 4Bar Hex ILS

Tests:

-   multiple personalities
-   RGB + Amber + White + UV emitters
-   intensity
-   shutter/strobe
-   mode/custom channels
-   capability conditions

### American DJ Jolt Bar FX2

Tests:

-   large archive
-   multi-cell topology
-   `LXRowsBeamLayout`
-   `beamIndexes`
-   color components
-   intensity
-   fine intensity
-   strobe
-   custom/global controls

### Chauvet Intimidator Spot 475ZX

Tests:

-   pan/tilt
-   pan/tilt fine
-   movement speed
-   color wheel
-   correction/RGB color objects
-   gobo
-   gobo angle/rotation
-   prism
-   focus
-   zoom
-   shutter/strobe
-   command/custom controls

### Chauvet Rogue R1E Spot

Tests:

-   16-bit intensity
-   16-bit movement
-   color wheel
-   gobo
-   prism
-   prism angle
-   prism rotation
-   focus
-   iris
-   shutter/strobe
-   wheel indexes
-   hold-time/additional-beam metadata

### Chauvet Obsession HP

Tests:

-   `LXSplitColor`
-   capability conditions
-   mode behavior
-   gobo behavior

### Unity RAW

Tests:

-   custom-heavy fixture
-   graceful preservation of behavior without rich recognized semantics

------------------------------------------------------------------------

## 24. Unit Tests

Required unit-test areas:

### Archive parser

-   valid binary plist
-   invalid plist
-   missing `$objects`
-   invalid UID
-   out-of-range UID
-   cyclic reference
-   excessive nesting
-   missing class descriptor
-   malformed Foundation container
-   unexpected primitive type

### Fixture decoding

-   fixture metadata
-   UUID
-   personalities
-   footprint
-   capabilities
-   settings
-   conditions
-   beam layouts

### Semantic mapping

-   intensity
-   16-bit intensity
-   RGB components
-   non-RGB emitter components
-   pan/tilt coarse/fine
-   color wheel
-   split color
-   gobo
-   prism
-   focus
-   zoom
-   iris
-   strobe
-   fog
-   switch
-   custom capability

### Error behavior

-   unknown class
-   unknown field
-   unsupported beam layout
-   malformed capability
-   invalid DMX channel
-   footprint mismatch
-   duplicate source UUID

------------------------------------------------------------------------

## 25. Integration Tests

For each representative fixture:

1.  Import `.lightkeyfxt`.
2.  Verify fixture appears in Aurora Fixture Library.
3.  Verify manufacturer/name.
4.  Verify all expected personalities.
5.  Patch each personality.
6.  Verify footprint.
7.  Select fixture.
8.  Verify Programmer exposes expected semantic controls.
9.  Verify coarse/fine controls behave as one high-resolution parameter.
10. Verify generated DMX addresses correspond to imported channel
    definitions.
11. For multi-cell fixtures, verify cell selection and topology.
12. Verify Stage Designer receives appropriate beam/cell data.
13. Save project.
14. Quit Aurora.
15. Reopen project.
16. Verify fixture functions without the source `.lightkeyfxt` being
    present.

------------------------------------------------------------------------

## 26. DMX Safety Tests

Fixture import directly affects physical output, so validation must be
strict.

Test:

-   channel indexes remain within personality footprint
-   coarse/fine channel pairing does not overlap illegally
-   DMX values are clamped to valid ranges
-   setting ranges do not exceed valid resolution
-   personality footprint cannot exceed supported universe/address
    constraints
-   malformed imports cannot write outside the patched fixture range
-   unknown capabilities do not emit unintended default values
-   command/reset channels do not fire merely because a fixture was
    selected or imported

**Especially important:** reset/lamp/control commands must never become
active by default.

------------------------------------------------------------------------

## 27. Performance Requirements

The Jolt Bar FX2 demonstrates that real fixture archives can contain
thousands of serialized objects.

Import should therefore:

-   avoid pathological recursive decoding
-   resolve archive UIDs efficiently
-   avoid repeatedly traversing the same object graph
-   avoid quadratic behavior when mapping cells/capabilities
-   perform expensive import work away from latency-sensitive DMX/output
    paths

Fixture import is not a live-performance operation, so absolute
millisecond speed is not important. Reliability and correctness are more
important than premature optimization.

------------------------------------------------------------------------

## 28. Suggested Implementation Phases

### Phase 1: Archive Research Harness

Implement:

-   binary plist loading
-   safe UID graph traversal
-   class enumeration
-   field enumeration
-   fixture metadata dump
-   diagnostic report

No production UI yet.

**Exit criterion:** All supplied fixtures can be opened and summarized
without crashing.

### Phase 2: Core Fixture Decode

Decode:

-   `LXFixtureProfile`
-   `LXPersonality`
-   `LXSetting`
-   UUIDs
-   common Foundation containers
-   metadata
-   footprint
-   capabilities as typed/unknown objects

**Exit criterion:** All personalities and capabilities can be enumerated
correctly.

### Phase 3: Basic Semantic Import

Implement:

-   intensity
-   switch
-   fog
-   RGB-family color
-   shutter/strobe
-   custom capability

Use simple supplied fixtures first.

**Exit criterion:** Generic fixtures and 4Bar Hex can become valid
Aurora-native profiles.

### Phase 4: Moving Head Import

Implement:

-   pan/tilt
-   coarse/fine
-   movement speed
-   color wheels
-   split colors
-   gobos
-   gobo rotation/angle
-   prisms
-   prism angle/rotation
-   focus
-   zoom
-   iris
-   commands

**Exit criterion:** Rogue R1E Spot and Intimidator Spot import with high
semantic fidelity.

### Phase 5: Multi-Cell Import

Implement:

-   beam indexes
-   `LXRowsBeamLayout`
-   cell topology
-   master/global vs cell-level parameters
-   Stage Designer handoff

**Exit criterion:** Jolt Bar FX2 imports as a true multi-cell fixture,
not a flat anonymous channel list.

### Phase 6: Conditions and Edge Cases

Implement or safely preserve:

-   `LXCapabilityCondition`
-   mode channels
-   setting indexes
-   conditional capability behavior
-   unknown classes
-   version differences

### Phase 7: Production UX

Add:

-   menu/Fixture Library import command
-   file picker
-   preview
-   warnings
-   duplicate handling
-   import provenance
-   batch import

### Phase 8: Regression and Hardening

Run:

-   complete unit suite
-   malformed archive fuzz-style cases
-   supplied fixture corpus
-   patch/programmer/output tests
-   project save/reload tests

------------------------------------------------------------------------

## 29. Non-Goals for Initial Release

Do not expand this feature into unrelated work.

Initial Lightkey import does **not** require:

-   exporting `.lightkeyfxt`
-   modifying Lightkey files
-   importing complete Lightkey show/project files
-   importing cues/scenes
-   importing Lightkey MIDI mappings
-   downloading profiles from Lightkey
-   cloning Lightkey's Fixture Manager UI
-   perfectly supporting every undocumented `LX*` class ever created

The first objective is reliable **fixture-profile import**.

------------------------------------------------------------------------

## 30. Future Extensions

Design the importer framework so other adapters can eventually target
the same Aurora-native fixture schema:

``` text
Lightkey .lightkeyfxt ─┐
GDTF ──────────────────┤
SSL2 ──────────────────┤
FXT ───────────────────┤
PFF ───────────────────┼──> AuroraFixtureProfile
QLC+ ──────────────────┤
Aurora native ─────────┘
```

GDTF should be considered a particularly important future format because
it can provide standardized physical and semantic fixture descriptions.

------------------------------------------------------------------------

## 31. Acceptance Criteria

This feature is complete only when all of the following are true:

-   [ ] Aurora recognizes `.lightkeyfxt`.
-   [ ] Aurora safely reads the binary plist / keyed archive without
    dynamically instantiating arbitrary archived classes.
-   [ ] Fixture name and manufacturer import correctly.
-   [ ] Fixture source UUID/revision provenance is retained.
-   [ ] All supported personalities are imported.
-   [ ] Personality footprint is correct.
-   [ ] Recognized capabilities become Aurora semantic parameters.
-   [ ] 16-bit coarse/fine parameters are paired correctly.
-   [ ] RGB-family emitter components retain their identities.
-   [ ] Color-wheel settings are represented semantically.
-   [ ] Split colors are preserved or explicitly reported if
    unsupported.
-   [ ] Pan/tilt parameters map into Position.
-   [ ] Gobos, prisms, focus, zoom, iris, and strobe map into Beam where
    supported.
-   [ ] Fog and switch capabilities retain their correct semantics.
-   [ ] Custom/command capabilities remain accessible without unsafe
    defaults.
-   [ ] Capability conditions are preserved and never silently
    discarded.
-   [ ] Multi-cell fixtures retain beam/cell relationships.
-   [ ] Jolt Bar FX2 imports as a structured multi-cell fixture.
-   [ ] Unknown Lightkey classes do not crash import.
-   [ ] Unsupported behavior produces precise warnings.
-   [ ] Importing never silently invents fixture semantics.
-   [ ] Duplicate/re-import behavior is safe.
-   [ ] Imported profiles are converted to Aurora-native data.
-   [ ] Aurora does not require Lightkey or the source file after
    import.
-   [ ] Imported fixtures survive project save/reload.
-   [ ] Imported fixture parameters produce correct DMX addressing.
-   [ ] Dangerous command/reset channels do not activate automatically.
-   [ ] The importer has automated tests using representative fixtures.
-   [ ] A developer diagnostic tool can summarize new/unknown Lightkey
    archives.

------------------------------------------------------------------------

## 32. Definition of Success

A successful implementation should allow the following workflow:

``` text
User owns a Lightkey fixture profile
        ↓
File → Import Lightkey Fixture Profile…
        ↓
Aurora inspects the archive
        ↓
Aurora shows manufacturer, fixture, personalities, features, warnings
        ↓
User confirms
        ↓
Aurora creates native fixture profile
        ↓
User patches fixture
        ↓
Programmer shows proper Intensity / Color / Position / Beam controls
        ↓
Multi-cell fixtures expose their cells
        ↓
Stage Designer understands physical beams/cells
        ↓
DMX output behaves correctly
```

The user should not need to understand `NSKeyedArchiver`,
`LXFixtureProfile`, or any other reverse-engineered implementation
detail.

From the user's perspective, it should feel like:

> **"I already have this fixture in Lightkey. Aurora can import it."**

That is the feature.
