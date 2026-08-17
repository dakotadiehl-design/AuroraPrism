# Aurora Prism Rebrand --- Codex Implementation Handoff

**Project:** Aurora ecosystem\
**Application being rebranded:** Aurora lighting-control software\
**New product name:** **Prism**\
**Formal ecosystem name:** **Aurora Prism**\
**Implementation intent:** Product rebranding only, with a narrowly
scoped file-format extension migration\
**Primary constraint:** Do **not** rename existing internal `Aurora`
code symbols, data types, modules, schemas, identifiers, or
architectural concepts merely for branding consistency.

------------------------------------------------------------------------

## 1. Objective

The lighting-control application previously called **Aurora** is now
**Prism**.

**Aurora** is the umbrella/family name for the larger ecosystem. The
lighting-control application is one product within that ecosystem.

The naming model should therefore be treated as:

``` text
Aurora
└── Prism — Lighting Control
```

Other Aurora-family applications can retain their own product names
under the Aurora umbrella.

For the lighting application:

-   **Product name:** Prism
-   **Formal name:** Aurora Prism
-   **Short UI name:** Prism
-   **Ecosystem/family name:** Aurora

This task is intentionally a **rebrand**, not an internal architectural
rename.

------------------------------------------------------------------------

# 2. Critical Rule: Do Not Perform a Global Aurora → Prism Rename

Codex must **not** run a repository-wide replacement of:

``` text
Aurora
aurora
AURORA
```

with Prism equivalents.

There are already many legitimate internal code concepts whose names
contain `Aurora`. Those names should remain intact.

Examples include, but are not limited to:

``` text
AuroraModel
AuroraUI
AuroraEngine
AuroraRemote
AuroraMIDI
AuroraAction
AuroraColor
AuroraTypography
AuroraSpacing
AuroraDiagnostics
AuroraLibraryPackage
```

If these names currently exist and function correctly, **leave them
alone**.

The fact that the compiled application is now branded Prism does **not**
require its historical/internal source architecture to be renamed.

### Why this restriction exists

A mass internal rename would create risk without providing meaningful
user benefit. It could:

-   create enormous unnecessary Git churn;
-   obscure meaningful changes during review;
-   introduce merge conflicts;
-   break imports or module references;
-   alter serialization keys;
-   break persisted projects;
-   change stable identifiers;
-   affect remote-control protocols;
-   affect tests;
-   affect package names;
-   affect preferences or Application Support paths;
-   accidentally create behavioral regressions.

A completed Prism rebrand is expected to still contain many occurrences
of `Aurora` in source code.

**That is correct.**

------------------------------------------------------------------------

# 3. Scope of the Rebrand

Change references where `Aurora` currently means **the user-facing
lighting-control product**.

Typical examples include:

-   macOS application display name;
-   Dock/Finder application name;
-   app menu;
-   About window;
-   splash screen;
-   welcome screen;
-   product logo/wordmark;
-   title-bar branding;
-   user-facing error messages;
-   user-facing status messages;
-   Help text;
-   active user documentation;
-   project/document type names;
-   Save/Open panel copy;
-   Finder document descriptions;
-   default user-facing filenames;
-   user-facing export/report headings;
-   remote-control UI branding when it identifies the lighting
    application.

Use either:

``` text
Prism
```

or:

``` text
Aurora Prism
```

depending on context.

### Preferred usage

Use **Prism** for ordinary product UI:

``` text
Prism
Prism Settings
Prism Project
Prism Library
Quit Prism
```

Use **Aurora Prism** where the ecosystem relationship is useful:

``` text
About Prism
Aurora Prism Lighting Control
Aurora Prism documentation
```

Do not repeatedly write "Aurora Prism" in every toolbar, menu, and
alert. The normal product name is simply **Prism**.

------------------------------------------------------------------------

# 4. Explicit Exception: File Extensions Must Be Rebranded

File extensions are the major intentional exception to the internal-name
preservation rule.

All **user-facing Aurora-branded file extensions belonging specifically
to the lighting application** must migrate to Prism-branded extensions.

At minimum:

``` text
.aurora    → .prism
```

If the current codebase contains a library format such as:

``` text
.auroralib
```

change it to:

``` text
.prismlib
```

The same principle applies to fixture profiles and any other externally
visible Prism-specific file formats.

For example, **if these formats actually exist in the repository**:

``` text
.aurorafixture   → .prismfixture
.aurorapreset    → .prismpreset
.aurorapalette   → .prismpalette
.aurorashow      → .prismshow
```

These examples are illustrative only.

**Do not invent new file formats.**

Codex must first inventory the repository and identify every existing
Aurora-branded file extension.

------------------------------------------------------------------------

# 5. Required File-Extension Inventory

Search the entire repository for at least:

``` text
.aurora
.auroralib
Aurora file
Aurora project
Aurora fixture
pathExtension
filenameExtension
UTType
UTExportedTypeDeclarations
UTImportedTypeDeclarations
CFBundleDocumentTypes
allowedContentTypes
contentType
fileImporter
fileExporter
NSOpenPanel
NSSavePanel
```

Produce a definitive mapping of every actual Aurora-branded external
format found.

The desired migration rule is:

> Replace the **product branding in the extension**, while preserving
> the format's existing meaning and internal data representation.

------------------------------------------------------------------------

# 6. Backward Compatibility Is Mandatory

Existing Aurora project files must not become unusable.

Prism must continue to recognize and open legacy files.

At minimum:

``` text
.prism       → current preferred Prism project format
.aurora      → supported legacy Aurora project extension

.prismlib    → current preferred Prism library format
.auroralib   → supported legacy Aurora library extension
```

Apply the same compatibility policy to any other migrated
fixture/preset/etc. extensions discovered in the repository.

### Required behavior

For a legacy project:

``` text
Haywire.aurora
```

Prism must be able to open it.

New projects should default to:

``` text
Haywire.prism
```

When a legacy project is opened, Prism should prompt the user to migrate.
The original `.aurora` package remains untouched until migration. The first
ordinary Save after opening a legacy project must create the corresponding
`.prism` package automatically and move the live document to that new path.
The original `.aurora` package remains intact.

Do not silently destroy or rewrite a legacy file merely because it was
opened.

------------------------------------------------------------------------

# 7. Do Not Change the Internal Project Schema Merely Because the Extension Changed

Changing:

``` text
.aurora → .prism
```

does **not** imply that the data inside the project package must change.

If the current `.aurora` project package contains working JSON, media,
stage assets, fixture data, cue data, or other persisted structures,
preserve them.

Do not rename internal serialized properties such as:

``` text
auroraSomething
```

merely because the application is now called Prism.

Do not change:

-   Codable property names;
-   JSON keys;
-   enum raw values;
-   stable IDs;
-   schema identifiers;
-   package layout;
-   database field names;
-   migration identifiers;

unless a separate functional reason requires it.

Do not bump a project schema version solely because the filename
extension changed.

The initial `.prism` format may be internally identical to `.aurora`.

That is desirable because this task is a rebrand rather than a
data-model migration.

------------------------------------------------------------------------

# 8. Fixture File Extensions

The user specifically wants fixture-related external files rebranded as
well.

Codex must inspect how Prism currently stores, imports, exports, or
identifies fixture definitions.

If an Aurora-branded fixture extension exists, migrate it to the
equivalent Prism-branded extension.

For example:

``` text
.aurorafixture → .prismfixture
```

only if `.aurorafixture` is an actual existing format.

Requirements:

-   new fixture exports use the Prism extension;
-   legacy Aurora fixture files remain importable;
-   fixture data structures themselves remain unchanged;
-   fixture IDs remain unchanged;
-   DMX personalities remain unchanged;
-   manufacturer/model identifiers remain unchanged;
-   imported LightKey fixture conversion behavior remains unchanged;
-   no fixture-library architecture redesign is part of this task.

------------------------------------------------------------------------

# 9. macOS Document Types and UTTypes

Update the application's macOS document registration to support the new
extensions.

Inspect all applicable locations, including:

``` text
Info.plist
generated Info.plist settings
CFBundleDocumentTypes
UTExportedTypeDeclarations
UTImportedTypeDeclarations
UTType extensions
SwiftUI DocumentGroup declarations
fileImporter declarations
fileExporter declarations
NSOpenPanel configuration
NSSavePanel configuration
Quick Look support
Finder metadata
```

The user-visible document types should become Prism-branded.

Examples:

``` text
Prism Project
Prism Library
Prism Fixture Profile
```

Legacy Aurora extensions should remain registered/importable where
needed for backward compatibility.

### Important

Internal UTType identifiers do not need to be renamed merely because
they contain Aurora.

For example, an internal identifier such as:

``` text
com.example.aurora.project
```

may be safer to preserve if changing it could disrupt compatibility.

Prioritize:

1.  correct `.prism` behavior;
2.  legacy `.aurora` compatibility;
3.  user-facing Prism naming;
4.  stability.

Do not pursue cosmetic purity inside invisible identifiers.

------------------------------------------------------------------------

# 10. Xcode Target, Module, and Scheme Names

Do not automatically rename:

``` text
Aurora.xcodeproj
Aurora target
Aurora scheme
AuroraModel module
AuroraUI module
AuroraEngine module
```

These are development architecture identifiers.

The application can present itself as Prism while retaining those names
internally.

Prefer changing packaging/display metadata rather than restructuring the
Xcode project.

Review:

``` text
CFBundleDisplayName
CFBundleName
PRODUCT_NAME
application menu name
About-panel name
window-title product name
```

The desired user experience is approximately:

``` text
Finder application: Prism
Dock application: Prism
macOS app menu: Prism
About panel: Prism
```

If safely changing the app target's packaging `PRODUCT_NAME` is
necessary to produce `Prism.app`, that narrow packaging change is
acceptable.

It must **not** cascade into a mass source/module rename.

------------------------------------------------------------------------

# 11. Bundle Identifier

Do not change the bundle identifier as part of this task unless there is
an unavoidable technical requirement and it is explicitly documented
before implementation.

Changing the bundle identifier can affect:

-   application identity;
-   signing;
-   notarization;
-   App Store identity;
-   preferences;
-   sandbox containers;
-   Keychain access;
-   saved state;
-   document associations;
-   updates.

The bundle identifier is not normal user-facing branding.

Preserve it for this rebrand.

------------------------------------------------------------------------

# 12. Application Support, Preferences, and Existing User Data

Do not automatically rename internal filesystem locations such as:

``` text
~/Library/Application Support/Aurora/
```

Do not rename:

-   UserDefaults suites;
-   preference domains;
-   cache directories;
-   saved-state identifiers;
-   Keychain service names;
-   internal database names;

merely for branding.

Those names may be part of persistent application identity.

Renaming them could make existing data appear to disappear.

A migration of those internal locations, if ever desired, should be a
separate explicitly designed task.

------------------------------------------------------------------------

# 13. Remote-Control and Network Compatibility

Do not rename stable protocol identifiers just because they contain
Aurora.

This includes, where applicable:

-   JSON keys;
-   API route names;
-   Bonjour service identifiers;
-   discovery identifiers;
-   network message types;
-   OSC paths;
-   MIDI action identifiers;
-   enum raw values;
-   remote protocol versions;
-   persisted mapping identifiers.

The visible remote-control UI should say **Prism** when referring to the
lighting product.

The underlying protocol should remain compatible.

------------------------------------------------------------------------

# 14. User-Facing String Audit

Search all visible UI strings for references such as:

``` text
Aurora
Welcome to Aurora
About Aurora
Aurora Project
Aurora Library
Open Aurora Project
Save Aurora Project
Aurora Lighting Control
Quit Aurora
Aurora could not open...
```

Convert appropriately.

Examples:

``` text
Welcome to Prism
About Prism
Prism Project
Prism Library
Open Prism Project
Save Prism Project
Aurora Prism Lighting Control
Quit Prism
Prism could not open...
```

Use context.

If a string genuinely refers to the **Aurora ecosystem**, leave it as
Aurora.

------------------------------------------------------------------------

# 15. Menus

Expected product menu:

``` text
Prism
├── About Prism
├── Settings…
├── Services
├── Hide Prism
└── Quit Prism
```

Do not unnecessarily put "Prism" into every File/Edit/View command.

Follow normal macOS conventions.

------------------------------------------------------------------------

# 16. Window Titles

Update visible product branding where necessary.

Examples:

``` text
Haywire — Prism
Untitled — Prism
Effects — Prism
MIDI Engine — Prism
```

If the current macOS window design does not need the product suffix,
leaving the document title alone is also acceptable.

Do not rename internal window IDs or Swift type names solely for
branding.

------------------------------------------------------------------------

# 17. Splash Screen

Preserve the existing splash-screen implementation and animation
behavior.

Only update its identity.

Preferred branding:

``` text
AURORA
PRISM

Lighting Control
```

The visual hierarchy should make **Prism** the product and **Aurora**
the family.

Do not redesign the splash state machine, initialization flow, timing,
or startup architecture during this task.

------------------------------------------------------------------------

# 18. Main Application Branding

The primary application UI should no longer present the lighting
controller simply as "Aurora."

Preferred compact identity:

``` text
PRISM
```

with an optional restrained family endorsement:

``` text
AURORA
PRISM
```

Aurora should feel like the ecosystem parent, not a second competing
product name.

Do not plaster the full logo across the workspace.

The existing professional dark-mode workstation direction remains
unchanged.

------------------------------------------------------------------------

# 19. App Icon and Product Graphics

The lighting application needs its own **Prism** identity.

The Prism visual concept should communicate:

-   lighting;
-   optics;
-   spectral separation;
-   precision;
-   professional show-control software;
-   membership in the Aurora family.

A strong conceptual direction is:

``` text
single light beam
       ↓
 optical prism
       ↓
restrained spectral output
```

Keep the existing Aurora visual DNA through restrained violet/aurora
accents.

Avoid:

-   generic rainbow branding;
-   cartoon prisms;
-   a giant letter P;
-   excessive neon glow;
-   visual clutter;
-   breaking the existing professional macOS workstation aesthetic.

------------------------------------------------------------------------

# 20. Required Asset Structure

Keep application identity assets separate by purpose.

Recommended asset-catalog structure:

``` text
App/
└── Assets.xcassets/
    ├── AppIcon.appiconset/
    ├── PrismMark.imageset/
    ├── PrismWordmark.imageset/
    ├── AuroraPrismLockup.imageset/
    ├── PrismProjectDocument.imageset/
    ├── PrismLibraryDocument.imageset/
    └── PrismFixtureDocument.imageset/
```

### AppIcon

The application icon should be Prism-specific.

Use the existing macOS app-icon asset set rather than creating competing
icon catalogs.

Verify the standard macOS representations are correctly populated.

### PrismMark

Compact product mark for:

-   toolbar identity;
-   About UI;
-   welcome surfaces;
-   compact branding.

### PrismWordmark

Product wordmark for larger branded surfaces.

### AuroraPrismLockup

Formal family/product lockup for:

-   splash screen;
-   About window;
-   documentation;
-   family-facing material.

### Document icons

Provide distinct but related Finder icons for:

-   Prism Project;
-   Prism Library;
-   Prism Fixture Profile, if a discrete fixture file type exists.

------------------------------------------------------------------------

# 21. Preserve Existing Aurora Family Assets

Do not delete the existing Aurora master branding merely because the
lighting product is becoming Prism.

Aurora is still the ecosystem name.

Existing assets such as:

``` text
AuroraMark
AuroraWordmark
```

may remain useful for ecosystem-level branding and other Aurora-family
applications.

The lighting application should simply stop using the Aurora-only
identity as its primary product mark.

------------------------------------------------------------------------

# 22. Important Naming Collision: Prism Product vs Fixture Prism Attribute

Lighting fixtures themselves can have a **prism** optical parameter.

The codebase may therefore already contain an icon, property,
capability, or type called something like:

``` text
Prism
PrismIcon
PrismAttribute
```

Do not confuse the product name with the lighting fixture feature.

Where an actual collision occurs, use explicit asset names such as:

``` text
PrismBrandMark
FixturePrismIcon
```

Do **not** rename functioning fixture-domain data types unless necessary
to resolve a real compiler or asset-name collision.

------------------------------------------------------------------------

# 23. Repository Classification Pass

Search for:

``` text
Aurora
AURORA
aurora
.aurora
```

Every result should be classified before modification.

Use these categories:

### A. User-facing product branding

**Change** to Prism/Aurora Prism.

### B. External file extension/document type

**Change** to Prism extension, while retaining legacy compatibility.

### C. Internal code symbol/module/type

**Keep unchanged.**

### D. Serialized or protocol-stable identifier

**Keep unchanged.**

### E. Application Support/preferences/internal persistence identifier

**Keep unchanged.**

### F. Historical/internal developer documentation

Usually **keep unchanged** when it references real code names.

### G. Active user-facing documentation

**Update** to Prism.

### H. Legacy compatibility fixture/test

**Keep legacy Aurora name intentionally.**

This classification step is mandatory.

------------------------------------------------------------------------

# 24. No Blind Search-and-Replace

The implementation workflow should be:

1.  inventory all Aurora references;
2.  classify them;
3.  identify actual external Aurora file extensions;
4.  update visible product strings;
5.  implement Prism extensions;
6.  retain legacy-extension support;
7.  update macOS document registration;
8.  update product graphics;
9.  update active user documentation;
10. build;
11. run tests;
12. open legacy files;
13. save new Prism files;
14. search again for Aurora references;
15. manually review the remaining hits.

A large number of remaining `Aurora` source references is expected.

Do not treat them as unfinished rebranding.

------------------------------------------------------------------------

# 25. Project File Compatibility Test Matrix

At minimum verify:

-   [ ] Creating a new project uses `.prism`.
-   [ ] Save As proposes `.prism`.
-   [ ] `.prism` projects open.
-   [ ] `.prism` projects save.
-   [ ] Atomic save/replace behavior still works.
-   [ ] Project media persists correctly.
-   [ ] Stage assets persist correctly.
-   [ ] Existing package validation still works.
-   [ ] Legacy `.aurora` projects open.
-   [ ] Existing legacy schema migration still works.
-   [ ] Opening `.aurora` does not corrupt or unexpectedly rewrite it.
-   [ ] Save As from `.aurora` can create a valid `.prism`.
-   [ ] Corrupt `.aurora` files still produce appropriate errors.
-   [ ] Corrupt `.prism` files produce appropriate errors.
-   [ ] No cue/programmer/fixture data changes after a round trip.

------------------------------------------------------------------------

# 26. Library Compatibility Test Matrix

If `.auroralib` exists, verify:

-   [ ] New libraries use `.prismlib`.
-   [ ] `.prismlib` opens.
-   [ ] `.prismlib` saves.
-   [ ] Legacy `.auroralib` opens.
-   [ ] Save As from `.auroralib` defaults to `.prismlib`.
-   [ ] Library contents are unchanged.
-   [ ] Invalid current libraries fail safely.
-   [ ] Invalid legacy libraries retain previous error behavior.
-   [ ] Failed saves do not destroy the previous valid library.

------------------------------------------------------------------------

# 27. Fixture and Other File Compatibility Tests

For each additional migrated extension discovered in the repository:

-   [ ] New exports use the Prism extension.
-   [ ] New files import correctly.
-   [ ] Legacy Aurora-extension files remain importable.
-   [ ] Finder/Open panels recognize appropriate formats.
-   [ ] Save/export panels prefer the Prism extension.
-   [ ] Internal serialized content remains compatible.
-   [ ] Stable fixture IDs remain unchanged.

------------------------------------------------------------------------

# 28. Branding QA

Verify the actual running application, not merely source files or an
asset gallery.

-   [ ] Finder identifies the application as Prism.
-   [ ] Dock identifies it as Prism.
-   [ ] Cmd-Tab identifies it as Prism.
-   [ ] App menu says Prism.
-   [ ] About panel says Prism.
-   [ ] Splash screen presents Aurora Prism correctly.
-   [ ] Main workspace presents Prism as the lighting product.
-   [ ] Welcome/no-project UI says Prism.
-   [ ] User-facing alerts say Prism.
-   [ ] New `.prism` documents have correct Finder association.
-   [ ] New library/fixture extensions have correct associations.
-   [ ] No prominent old Aurora-only lighting-product branding remains.
-   [ ] Aurora remains available as ecosystem branding.
-   [ ] App icon is correct at Retina and small sizes.
-   [ ] Document icons are correct.

------------------------------------------------------------------------

# 29. Functional Regression Guardrail

This rebrand must not alter lighting-control behavior.

Verify no regressions in:

-   [ ] fixture patching;
-   [ ] fixture definitions;
-   [ ] DMX addressing;
-   [ ] Programmer;
-   [ ] palettes/presets;
-   [ ] Color Engine;
-   [ ] cue lists;
-   [ ] cue playback;
-   [ ] Song Mode;
-   [ ] Effects Engine;
-   [ ] Advanced MIDI Engine;
-   [ ] Music Engine;
-   [ ] MIDI mappings;
-   [ ] DMX USB output;
-   [ ] Art-Net;
-   [ ] sACN;
-   [ ] remote-control protocol;
-   [ ] stage/live visualization;
-   [ ] workspace persistence;
-   [ ] floating windows;
-   [ ] project autosave/recovery;
-   [ ] splash initialization behavior.

If a behavioral change appears necessary to complete the rebrand, stop
and document why before expanding scope.

------------------------------------------------------------------------

# 30. Explicitly Out of Scope

Do not use this work item to:

-   rename Swift modules;
-   rename all Aurora-prefixed classes;
-   rename all Aurora-prefixed structs;
-   rename all Aurora-prefixed protocols;
-   rename internal model concepts;
-   rewrite serialization schemas;
-   rename persisted JSON keys;
-   rename stable IDs;
-   change cue data;
-   change fixture semantics;
-   redesign fixture storage;
-   alter DMX behavior;
-   alter MIDI behavior;
-   alter AME behavior;
-   alter Music Engine behavior;
-   redesign Patch;
-   redesign Stage;
-   redesign Effects;
-   redesign Perform Mode;
-   migrate Application Support folders;
-   change preference domains;
-   change remote protocol identifiers;
-   change bundle identifier;
-   remove Aurora ecosystem branding;
-   perform unrelated cleanup/refactors.

Keep the diff focused.

------------------------------------------------------------------------

# 31. Suggested Commit Structure

Keep the work reviewable.

A sensible sequence is:

``` text
1. Prism user-facing branding and macOS display metadata
2. Prism document extensions + legacy Aurora compatibility
3. Prism UTType/document registration
4. Prism icon/brand/document assets
5. User-facing documentation and tests
```

Do not mix unrelated refactors into these commits.

------------------------------------------------------------------------

# 32. Required Codex Completion Report

When implementation is complete, provide a concise but specific report
containing:

1.  every user-facing branding area changed;
2.  every Aurora-branded external file extension discovered;
3.  the exact old → new extension mapping;
4.  how legacy `.aurora` compatibility is implemented;
5.  how legacy library/fixture compatibility is implemented;
6.  macOS UTType/document-registration changes;
7.  app icon and graphics integrated;
8.  active documentation updated;
9.  tests added or changed;
10. build/test results;
11. confirmation that internal Aurora data types/modules were
    intentionally preserved;
12. confirmation that serialized/stable identifiers were preserved;
13. confirmation that no unrelated functionality was refactored;
14. any remaining visible use of the Aurora name and why it correctly
    refers to the ecosystem rather than the Prism product.

Also provide screenshots of the **actual running application** showing:

-   splash screen;
-   main workspace;
-   About window;
-   Prism app icon;
-   a `.prism` project in Finder if practical.

------------------------------------------------------------------------

# 33. Acceptance Criteria

The rebrand is complete when the user experience is:

``` text
I launch Prism.

It is clearly a member of the Aurora ecosystem, but the lighting-control
product itself is named Prism.

My existing .aurora projects still open.

New projects use .prism.

Aurora-branded fixture/library formats have equivalent Prism extensions,
while their legacy versions remain supported.

Nothing about programming lights, MIDI, cues, effects, DMX, Art-Net,
sACN, projects, fixtures, or live operation changed simply because the
product was renamed.
```

The developer experience should simultaneously be:

``` text
The existing Aurora-prefixed internal architecture remains intact.

There was no repository-wide Aurora → Prism symbol replacement.

The diff is overwhelmingly branding, macOS product/document metadata,
assets, external file-extension handling, compatibility tests, and
user-facing documentation.

Existing stable data and protocol contracts remain stable.
```

That is the intended implementation boundary.

------------------------------------------------------------------------

# 34. Final Instruction to Codex

**Treat this as a surgical product rebrand.**

Change what the operator sees.

Change the external Aurora-branded file extensions to Prism equivalents.

Maintain backward compatibility with the old extensions.

Preserve the existing internal Aurora architecture, data types, schemas,
identifiers, and protocol contracts unless a specific change is
technically required for the external file-extension migration.

Do not "clean up" Aurora names simply because they now look historical.

**Aurora is still a valid name. It now names the ecosystem. Prism names
the lighting application.**
