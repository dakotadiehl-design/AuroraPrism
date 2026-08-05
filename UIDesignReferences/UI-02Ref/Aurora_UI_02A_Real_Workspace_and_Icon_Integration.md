# Aurora UI-02A --- Real Build Workspace + Brand Asset Integration

**Status:** Immediate next UI task\
**Scope:** Actual running Aurora Build workspace only\
**Primary visual reference:** Approved high-fidelity Build Mode render\
**Important:** Do not continue evaluating progress only through the
component gallery. The real application must visibly change.

------------------------------------------------------------------------

# 1. Objective

The UI-01 / UI-01B / UI-01C work created a substantial design-system and
component foundation, but the running Aurora application still presents
legacy workspace chrome and therefore looks substantially unchanged.

The next task is a **vertical slice through the real application**.

> **Make the actual running Aurora Build workspace look substantially
> like the approved high-fidelity Build Mode render. Use the UI-01C
> components already built. Replace the old `WorkspaceView` chrome that
> is currently masking the redesign. Preserve backend behavior. Use a
> populated demo project for visual validation. Do not work on any other
> screen. Stop when the launched application itself, not the component
> gallery, is visually recognizable as the supplied reference.**

This is the success criterion.

Do not measure success by the number of design tokens, components,
previews, or gallery compositions changed behind the scenes.

The launched macOS application is now the thing being judged.

------------------------------------------------------------------------

# 2. Brand Assets Are Already in the Repository

All supplied assets from:

-   `Aurora_Icons_Package`
-   `Aurora_Brand_Assets`

have been placed into:

``` text
App/Assets.xcassets/
```

Treat these as the approved Aurora visual identity assets.

Expected asset groups include items such as:

``` text
Assets.xcassets/
├── AppIcon.appiconset/
├── AuroraMark.imageset/
├── AuroraWordmark.imageset/
└── additional approved icon/image sets from Aurora_Icons_Package
```

Do not regenerate, replace, redraw, or approximate these assets unless
specifically instructed.

Use the supplied assets directly.

------------------------------------------------------------------------

# 3. Integrate the Aurora App Icon Properly

Verify that the macOS application icon is wired correctly through:

``` text
App/Assets.xcassets/AppIcon.appiconset/
```

Requirements:

-   verify `Contents.json` references valid filenames
-   remove obsolete placeholder entries if any remain
-   ensure the Xcode app target uses the correct AppIcon asset
-   verify Debug and Release builds use the Aurora icon
-   verify the icon appears correctly in Finder / Dock / app bundle when
    built

Do not silently fall back to a generic placeholder icon.

------------------------------------------------------------------------

# 4. Integrate the Aurora Brand Mark

Use the approved `AuroraMark` asset as the primary in-application brand
symbol.

Appropriate locations include:

-   top-left application toolbar / title area
-   welcome / no-project state
-   About Aurora
-   future remote branding
-   future splash/launch presentation

For this task, the important use is the **actual Build workspace
toolbar**.

The reference render shows a restrained Aurora identity treatment in the
application chrome.

Implement something similar in spirit:

``` text
[AuroraMark]  AURORA
```

or another polished equivalent using the supplied assets.

Do not overuse the mark.

The logo should establish identity, not become decoration on every
panel.

------------------------------------------------------------------------

# 5. Integrate the Aurora Wordmark

Use `AuroraWordmark` where the full brand treatment is appropriate.

Potential uses:

-   About Aurora
-   welcome/no-project state
-   future splash/launch experience
-   future documentation/remote identity

For the Build workspace, choose whichever treatment best matches the
approved render:

-   AuroraMark + text rendered natively
-   or AuroraWordmark where scale/readability make sense

Do not force the full wordmark into cramped UI locations where the mark
alone works better.

------------------------------------------------------------------------

# 6. Integrate the Remaining Approved Icon Assets

Review all icon/image assets placed into `Assets.xcassets` from
`Aurora_Icons_Package`.

Use them where they map cleanly to Aurora concepts.

Examples may include:

-   fixture
-   beam
-   gobo
-   palette/look
-   position
-   universe/output
-   lighting-specific symbols
-   Aurora-specific toolbar/navigation imagery

Rules:

1.  **Use approved custom icons where they communicate lighting concepts
    better than generic SF Symbols.**
2.  Use SF Symbols where they remain clearer and more native.
3.  Do not mix arbitrary visual styles.
4.  Keep icon sizing, weight, alignment, hover, selected, disabled, and
    active treatment consistent.
5.  Do not invent a second icon system.
6.  Do not use decorative custom icons simply because they exist.

The goal is a coherent icon language, not maximum asset usage.

------------------------------------------------------------------------

# 7. Real Application Shell, Not Another Gallery

The visible problem is that the running app still uses legacy workspace
chrome.

Replace or refactor the real `WorkspaceView` presentation so that it
visibly uses the new Aurora design system.

The running Build workspace should establish:

-   Aurora toolbar and brand treatment
-   project/show title
-   Build / Perform mode control
-   quiet engine/output/MIDI/network health
-   purposeful workspace navigation
-   modular panel chrome
-   Fixture Browser
-   visually dominant Programmer
-   contextual Inspector
-   palette/look shelf
-   cue area
-   bottom status/performance strip

Do not merely create another preview demonstrating these elements.

They must be visible when Aurora launches normally.

------------------------------------------------------------------------

# 8. Use One Visual Target

For this task, use the **approved high-fidelity Build Mode
main-workspace render** as the primary visual target.

Do not attempt to implement every other render at the same time.

The acceptance question is:

> **When Aurora is launched with the demo project, does the actual Build
> workspace visibly belong to the same product family as the supplied
> Build Mode render?**

Exact pixel reproduction is not required.

The following should converge strongly:

-   hierarchy
-   density
-   panel treatment
-   toolbar treatment
-   visual rhythm
-   Programmer prominence
-   palette presentation
-   cue-list grammar
-   Inspector treatment
-   Aurora branding
-   icon treatment
-   health/status chrome

------------------------------------------------------------------------

# 9. Populate the Visual Test Environment

Create or maintain a deterministic development/demo Aurora project for
visual validation.

It should contain enough realistic content to exercise the UI,
approximately:

-   front lights
-   wash fixtures
-   moving heads
-   audience fixtures
-   several fixture groups
-   at least one universe
-   several color palettes
-   position palettes
-   beam/look presets
-   approximately 15--20 cues
-   at least one song with sections/entries

Use real Aurora model objects and normal project-loading paths where
practical.

Do not hard-code fake show data directly into production views solely to
make screenshots look populated.

The same demo project should be reusable for screenshots throughout UI
development.

------------------------------------------------------------------------

# 10. Workspace Navigation Must Gain Hierarchy

The current application visually treats several different navigation
concepts too similarly.

Correct this.

Visually distinguish between:

-   global Build / Perform mode
-   primary workspace/tool selection
-   tabs inside an individual panel
-   contextual Inspector sections

These are different levels of navigation and should not all use the same
segmented-control grammar.

Use the high-fidelity render as guidance.

------------------------------------------------------------------------

# 11. Programmer Is the Build-Mode Center of Gravity

The real Programmer should receive the strongest creative emphasis in
the Build workspace.

Use the UI-01C components already created for supported fixture
capabilities such as:

-   intensity
-   color
-   position
-   beam
-   gobo

Respect backend truth and mixed/unavailable states.

The Programmer should visually communicate:

> **This is where the lighting look is created.**

Do not let Patch, Song, MIDI, or technical configuration compete equally
for attention in the default Build workspace.

------------------------------------------------------------------------

# 12. Panel Hierarchy

The real application should no longer read as several nearly identical
dark rectangles.

Establish clear visual hierarchy between:

``` text
application background
workspace
panel
panel header
interactive control surface
selected / active content
```

Panel headers should feel intentional and should not simply be generic
`.bar` surfaces.

Adjacent panels should feel like parts of one professional workstation.

Avoid floating-card soup.

------------------------------------------------------------------------

# 13. Fixture Browser

Bring the actual Fixture Browser into the new visual language.

The browser should feel:

-   compact
-   precise
-   searchable
-   selection-oriented
-   appropriate for large fixture counts
-   visually subordinate to the Programmer

Use the approved custom assets for lighting-specific concepts where
appropriate.

Preserve multi-selection and existing selection semantics.

------------------------------------------------------------------------

# 14. Inspector

The Inspector should be clearly contextual and visually subordinate to
the Programmer.

It should answer:

> **What is selected, and what can I change about it?**

Use compact professional controls and clear grouping.

Do not use the Inspector as a dumping ground for unrelated application
configuration.

------------------------------------------------------------------------

# 15. Palette / Look Shelf

The palette/look shelf should become one of the most visually creative
parts of Build Mode.

Use:

-   actual palette colors
-   meaningful visual representation
-   approved palette/look icons where useful
-   clear selected/referenced state
-   compact labels

Avoid ordinary gray utility-button styling.

The shelf should immediately communicate that Aurora is a creative
lighting application.

------------------------------------------------------------------------

# 16. Cue Area

The cue area should use the purpose-built UI-01C cue grammar.

Establish a strong scan path such as:

``` text
STATE | CUE NUMBER | NAME | TRIGGER / TIMING / STATUS
```

Current, next, selected, normal, and warning states should be distinct
without turning every row into a bright colored block.

Use approved icons where they improve clarity.

------------------------------------------------------------------------

# 17. Empty States

Real users will encounter empty projects and empty panels.

Replace tiny upper-left placeholder text floating in large dark regions
with restrained, purposeful empty states.

Examples:

``` text
No Cue List

Create a cue list to begin programming.

[ Create Cue List ]
```

or:

``` text
No Universe Patched

Add a universe, then patch fixtures from the Fixture Browser.

[ Add Universe ]
```

Use Aurora brand/icon assets sparingly where appropriate.

Do not turn empty states into oversized consumer-app onboarding pages.

------------------------------------------------------------------------

# 18. Transport Hierarchy

`GO` must not have the same visual authority as ordinary utility actions
such as:

-   New Song
-   Clone
-   Remove
-   Add Universe

Even in Build Mode, show transport should have recognizable visual
grammar.

Perform Mode will make this stronger later.

For now, establish the hierarchy.

------------------------------------------------------------------------

# 19. Health / Status Chrome

Use the structured presentation snapshots already available.

Healthy indicators should remain quiet.

Warnings and failures should escalate visually.

The high-fidelity render is the target:

``` text
ENGINE   OUTPUT   MIDI   NETWORK
```

or equivalent existing backend-supported health categories.

Do not build status UI from stale compatibility strings when structured
state exists.

------------------------------------------------------------------------

# 20. Preserve Backend Architecture

Do not:

-   rewrite Aurora's engine/controller architecture
-   bind views directly to high-rate DMX frames
-   move live-control dispatch onto `MainActor`
-   change domain semantics for visual convenience
-   duplicate model state inside views
-   flatten SPM modules into the app target
-   make `AuroraUI` depend on the executable target

Use the existing UI/backend contracts.

If a genuine presentation-contract gap is discovered, document it before
changing backend semantics.

------------------------------------------------------------------------

# 21. Scope Boundary

This task is **UI-02A only**.

Do not implement the full redesign of:

-   Perform Mode
-   MIDI Settings
-   Patch
-   Effects
-   Output Settings
-   Web Remote
-   advanced docking
-   final About/splash experience

Those supplied renders and assets remain future visual references.

The purpose of this task is to make **one actual application screen
beautiful from end to end**.

------------------------------------------------------------------------

# 22. Acceptance Criteria

UI-02A is ready for review when:

``` text
[ ] Launching Aurora visibly shows the new design system

[ ] The legacy WorkspaceView chrome no longer masks UI-01C

[ ] The approved Aurora AppIcon is wired to the Xcode app target

[ ] AppIcon.appiconset Contents.json is valid

[ ] AuroraMark is used appropriately in the actual app shell

[ ] AuroraWordmark is available and integrated where appropriate

[ ] Approved custom icon assets are used where they improve lighting-specific clarity

[ ] Icon treatment is visually consistent

[ ] Build / Perform mode is visually distinct from panel tabs

[ ] Workspace navigation has intentional hierarchy

[ ] Fixture Browser visibly matches the new product language

[ ] Programmer is the visual center of the workspace

[ ] Inspector is contextual and visually subordinate to Programmer

[ ] Palette / look shelf is visually creative

[ ] Cue area uses purpose-built cue grammar

[ ] Health / status chrome is quiet when healthy

[ ] Empty states are intentional

[ ] GO has appropriate visual authority

[ ] A populated deterministic demo project is available

[ ] The running-app screenshot is recognizably in the same product family as the approved Build render

[ ] Backend domain semantics remain unchanged
```

------------------------------------------------------------------------

# 23. Required Handoff

When complete, provide:

1.  updated repository
2.  screenshot of the **actual running Aurora application** using the
    demo project
3.  screenshot at a typical MacBook-size window
4.  screenshot at a larger desktop window
5.  confirmation that the production AppIcon appears correctly in
    macOS/Xcode
6.  confirmation that `AuroraMark` and `AuroraWordmark` resolve
    correctly from the asset catalog
7.  list of approved custom icons actually integrated
8.  summary of which legacy `WorkspaceView` chrome was replaced
9.  list of UI-01C components now used by the real application
10. confirmation that backend domain semantics were not changed

Then **STOP for visual review**.

Do not proceed to the rest of UI-02 until the launched Build workspace
is approved.

------------------------------------------------------------------------

# 24. Guiding Statement

The success metric is no longer:

> "How many UI components changed behind the scenes?"

The success metric is:

> **Launch Aurora, open the demo show, and immediately see the product
> represented in the approved Build Mode render.**

Use the existing UI-01C work.

Use the approved Aurora icons and brand assets.

Connect them to the application the user is actually looking at.
