# Aurora UI-02 --- Recommended Amendments to Complete Application Shell Plan

**Applies to:** `UI-02 — Complete Application Shell (post–UI-02A)`\
**Disposition:** Approve the plan with the focused amendments below.

UI-02A is complete. Do **not** reopen or redesign the approved Build
visual language during this phase.

The purpose of UI-02 is now to establish how Aurora behaves as a
complete professional macOS application: selection context, navigation
hierarchy, Settings, Build/Perform mode separation, panel hosting
contracts, and shell-level interaction behavior.

------------------------------------------------------------------------

# 1. Prefer Explicit Inspector Focus Over Hidden Selection Priority

The proposed contextual Inspector architecture is correct, but avoid
relying solely on an implicit priority rule such as:

``` text
cue > group > fixtures > palette > song
```

That can become confusing once multiple kinds of objects remain selected
simultaneously.

Prefer an explicit Inspector-focus concept if it can be introduced
cleanly without disturbing existing selection semantics.

Conceptually:

``` text
SelectionManager
├── selectedFixtures
├── selectedGroup
├── selectedCue
├── selectedPalette
├── selectedSong
└── inspectorFocus
```

Example:

-   Fixtures may remain selected in the Programmer.
-   User clicks Cue 14.
-   Inspector focuses Cue 14.
-   Fixture selection does not need to be destroyed merely because the
    Inspector changed context.

The Inspector should answer:

> **What object or context is the user currently inspecting?**

rather than:

> **Which non-empty selection collection happens to have the highest
> priority?**

If introducing explicit Inspector focus requires invasive backend/domain
changes, document the limitation and use the least surprising
deterministic fallback for UI-02. Do not destabilize the existing
selection model merely to satisfy this preference.

------------------------------------------------------------------------

# 2. Keep the UI-02 MIDI Settings Surface Intentionally Thin

The proposed native Settings shell is strongly approved.

For UI-02, MIDI should be real enough to prove that configuration can
live cleanly outside the Build workspace, but do not accidentally
implement UI-08 during this phase.

A sufficient UI-02 MIDI surface is approximately:

``` text
MIDI
├── Input devices / session status
├── Mapping list
├── Learn
├── Test
└── Scope
```

Reuse existing mapping/device logic.

Do not expand this phase into:

-   advanced MIDI performance workflows
-   large mapping editors beyond existing semantics
-   future MIDI engine features
-   speculative automatic-song behavior
-   unrelated control protocols merely because Settings now exists

The objective is **Settings architecture**, not completion of every
Settings feature.

------------------------------------------------------------------------

# 3. Select Build Navigation Option A

Remove ambiguity between the two proposed Build-navigation approaches.

Use **Option A** unless implementation discovers a concrete
architectural blocker.

Preferred hierarchy:

``` text
GLOBAL TOOLBAR
[Aurora]   Project   Health        BUILD | PERFORM


LEFT COLUMN
Browser | Patch | Groups


CENTER
PROGRAMMER
(always the dominant creative workspace)


LOWER REGION
Palettes | Cues | Song


RIGHT COLUMN
Contextual Inspector
```

This preserves the Programmer as Aurora's creative center of gravity
while making project/technical tools accessible.

Do not turn the central Programmer into a generic tab container where
Patch, Groups, MIDI, or other tools can replace it during normal Build
operation.

The three navigation levels must remain visually distinct:

``` text
Mode selection
    ≠
Workspace/tool selection
    ≠
Panel-local tabs/sections
```

This structure should also remain compatible with future docking.

------------------------------------------------------------------------

# 4. Make UI-02 Perform Mode a Structural Seed for UI-07

UI-02F should remain intentionally limited.

Do **not** implement the full UI-07 performance cockpit yet.

However, avoid creating a disposable temporary Perform screen that will
simply be thrown away later.

The UI-02 Perform shell should structurally foreshadow the final
direction:

``` text
                 SONG / SHOW

CURRENT                              NEXT
Verse 2                              Chorus
Cue 14.0                             Cue 15.0


             BACK    GO    STOP


ENGINE      OUTPUT      MIDI      NETWORK
```

Requirements for UI-02:

-   full-window Perform presentation
-   unmistakably different from Build
-   large Current / Next hierarchy
-   working GO / BACK / STOP through existing live routing
-   GO has dominant visual authority
-   quiet health/status row
-   no structural editing affordances
-   architecture reusable by UI-07

Do **not** add yet:

-   full master grid
-   busking/look surface
-   Show Lock
-   advanced performance safety boundary
-   full remote parity

Those belong to UI-07.

------------------------------------------------------------------------

# 5. Establish a Reusable App-vs-Project Scope Grammar in Settings

The plan correctly requires Settings to distinguish application-global
settings from project/show settings.

Do not repeatedly plaster every individual control with large labels
such as:

``` text
PROJECT SETTING
```

Instead, establish a reusable visual convention at the section/page
level.

Example:

``` text
MIDI Mappings                                  PROJECT
─────────────────────────────────────────────────────
...

MIDI Devices                              APPLICATION
─────────────────────────────────────────────────────
...
```

Possible semantic scope labels:

``` text
APPLICATION
PROJECT
```

or similarly concise terminology consistent with Aurora's language.

This should become a reusable Settings grammar for later UI-08 work.

The distinction must remain clear without creating visual noise.

------------------------------------------------------------------------

# 6. Add Basic Keyboard-Navigation Acceptance

Aurora is becoming a serious native macOS application. Establish basic
keyboard behavior now rather than retrofitting it after the remaining UI
phases.

UI-02 does **not** need full shortcut customization.

At minimum verify sensible keyboard focus traversal through:

-   application toolbar
-   Build/Perform mode selection
-   workspace tabs
-   Fixture Browser
-   Programmer controls
-   Cue List
-   Inspector
-   Settings navigation and controls

Requirements:

-   visible accessible focus
-   logical traversal order
-   no obvious focus traps
-   controls reachable without a mouse where appropriate
-   existing native macOS keyboard behavior preserved

Advanced shortcut mapping remains later work.

------------------------------------------------------------------------

# 7. Explicitly Forbid Duplicated Panel Implementations

Strengthen UI-02D with this rule:

> **Do not duplicate panel content merely to achieve the current Build
> layout.**

The future docking system should move/rehost the same panel content
rather than requiring alternate versions of each panel.

Conceptually:

``` text
FixtureBrowserContent
ProgrammerContent
PaletteContent
CueListContent
InspectorContent
```

should remain host-agnostic content roots.

Today:

``` text
BuildWorkspaceHost
    ↓
hosts panel content
```

Later:

``` text
DockHost
    ↓
hosts the SAME panel content
```

Panel content must not own:

-   fixed window placement
-   assumptions about a specific `HSplitView` / `VSplitView`
-   application-level window chrome
-   duplicate state created only for a particular host

`BuildWorkspaceHost` should primarily perform composition.

Do not allow future docking compatibility to become three alternate
copies of the same panel implementation.

------------------------------------------------------------------------

# 8. Preserve the Approved UI-02A Visual Foundation

UI-02A is complete.

Do not reopen:

-   Aurora visual identity
-   AppIcon pipeline
-   custom lighting icon system
-   primary Build workspace geometry
-   Programmer visual dominance
-   established panel chrome
-   palette/cue visual grammar

Changes to the existing Build surface during UI-02 should be limited to
those necessary for:

-   navigation hierarchy
-   contextual Inspector behavior
-   shell integration
-   Settings migration
-   panel-hosting architecture
-   genuine defects/regressions

UI-02 is an application-shell phase, not another visual-identity pass.

------------------------------------------------------------------------

# 9. Recommended Implementation Order

Keep Grok's primary implementation order:

``` text
1. UI-02B — Contextual Inspector architecture
2. UI-02E — Build navigation hierarchy
3. UI-02F — Perform distinct chrome
4. UI-02C — Settings shell + thin real MIDI page
5. UI-02D — Panel contract + light refactors
6. UI-02G — Welcome / empty-project state
7. UI-02H — Binding hygiene / optional tests
8. SHELL REVIEW
9. STOP before UI-03
```

This creates a useful progression:

``` text
selection context
      ↓
navigation
      ↓
mode separation
      ↓
configuration
      ↓
hosting architecture
      ↓
empty state / hygiene
```

Do not begin UI-03 opportunistically during this work.

------------------------------------------------------------------------

# 10. Settings Shell Direction

The proposed Settings information architecture is approved:

``` text
General

Control
├── MIDI
├── RTP-MIDI / OSC
└── Keyboard

Output
└── Local DMX / Art-Net / sACN

Remote

Plugins

Advanced
```

Rules:

-   real existing features may have thin functional surfaces
-   future/unavailable features must be clearly unavailable
-   placeholders must not imply unsupported functionality
-   Settings must open through the standard macOS Settings command/scene
-   do not move configuration back into permanent Build chrome
-   Inspector must not become a substitute Settings panel

------------------------------------------------------------------------

# 11. Welcome / Empty-Project Direction

The proposed welcome state is approved.

When Aurora has no loaded show/project, provide a restrained native
surface using the approved Aurora branding.

Primary actions:

``` text
New Show
Open…
Open Demo Show
```

Use `AuroraWordmark` where appropriate.

Avoid:

-   giant onboarding cards
-   tutorials forced into the launch screen
-   decorative animation
-   fake recent-project data
-   excessive marketing copy

The screen should feel like opening a professional creative application.

------------------------------------------------------------------------

# 12. Binding Hygiene

For new UI-02 surfaces, prefer focused dependencies.

Examples:

``` text
Settings view
    → settings store / specific callbacks

Inspector view
    → selected presentation model + focused actions

Perform shell
    → PerformanceSnapshot + transport callbacks
```

Avoid injecting the entire `AppModel` simply because it is convenient.

Do not perform a risky whole-application dependency rewrite during
UI-02.

Apply the cleaner pattern to new/refactored surfaces and continue
reducing broad coupling incrementally.

------------------------------------------------------------------------

# 13. Revised UI-02 Acceptance Criteria

UI-02 is complete when:

``` text
[ ] UI-02A Build production path remains intact

[ ] Approved Build visual language has not regressed

[ ] Inspector supports multiple relevant selection/context kinds

[ ] Inspector focus behavior is explicit or deterministically documented

[ ] Native macOS Settings scene exists

[ ] Settings information architecture is navigable

[ ] Application vs project scope has a reusable visual convention

[ ] MIDI has a thin but real Settings surface

[ ] Unsupported Settings features are truthfully unavailable/placeholders

[ ] Build navigation uses intentional hierarchy

[ ] Programmer remains the Build center of gravity

[ ] Mode selection ≠ workspace navigation ≠ panel-local tabs

[ ] Perform mode is unmistakably different from Build

[ ] Perform Current / Next / GO / BACK / STOP are functional

[ ] Perform shell architecture can grow into UI-07

[ ] Panel content roots are host-agnostic

[ ] No duplicate panel implementations were introduced for layout purposes

[ ] Panel docking contract is documented

[ ] Welcome / empty-project state is intentional

[ ] Basic keyboard focus/navigation has been verified

[ ] New/refactored surfaces prefer focused bindings

[ ] Demo show continues to work

[ ] swift test is green

[ ] Xcode Debug build is green

[ ] Backend/domain semantics remain unchanged

[ ] SHELL REVIEW completed
```

Then stop.

------------------------------------------------------------------------

# 14. Shell Review Handoff

At the end of UI-02, provide:

1.  updated repository
2.  screenshot of Build Mode with deterministic demo show
3.  screenshot of Perform Mode
4.  screenshot of native Settings
5.  screenshot demonstrating at least two different Inspector contexts
6.  summary of Build navigation hierarchy
7.  summary of Inspector-focus behavior
8.  panel-hosting/docking contract document
9.  confirmation that no duplicate panel implementations were introduced
10. confirmation of basic keyboard-navigation review
11. test/build results
12. remaining shell-level discrepancies only
13. confirmation that backend/domain semantics were unchanged

Then mark:

> **UI-02 COMPLETE --- SHELL REVIEW**

and stop before UI-03 unless explicitly instructed to continue.

------------------------------------------------------------------------

# Final Direction

UI-02A answered:

> **What does Aurora look like?**

UI-02 should now answer:

> **How does Aurora behave as a complete macOS application?**

The goal is a stable professional shell:

-   Build remains beautiful
-   selection drives contextual inspection
-   navigation has hierarchy
-   Settings contains complexity without cluttering the workspace
-   Perform is a genuine separate mode
-   panels are ready to be rehosted later
-   keyboard interaction begins behaving like a native desktop
    application

Once this shell passes review, freeze it and move into UI-03 rather than
continuing to polish the container.

UI-03 can then focus on making the Fixture Browser and Programmer
exceptional lighting-programming instruments.
