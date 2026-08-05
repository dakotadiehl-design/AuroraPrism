# Aurora UI-02A --- Recommended Amendments to Grok's Plan

**Applies to:** Grok's
`UI-02A — Real Build Workspace + Brand Asset Integration` plan\
**Disposition:** Approve the plan with the focused amendments below.

------------------------------------------------------------------------

## 1. Make the Legacy Workspace Explicitly Legacy

Grok's plan correctly stops using the existing `WorkspaceView` as the
main `ContentView` root.

Do not leave the old workspace implementation available as an ambiguous
fallback that future code can accidentally drift back toward.

Preferred options:

1.  Rename it to something unmistakable such as:

``` text
LegacyWorkspaceView
```

2.  Mark it deprecated/internal if it must temporarily remain.
3.  Remove it from normal production composition.
4.  Preserve reusable layout/state infrastructure separately where still
    useful.

The new Aurora shell should become the clear production path.

------------------------------------------------------------------------

## 2. Make the Populated Demo Project Mandatory for Visual Approval

The deterministic demo show is not merely a convenience. It is part of
the UI acceptance environment.

> **UI-02A must not be visually approved using an empty project.**

The same populated demo project should be used for every UI-02A
screenshot and review so visual comparisons remain meaningful.

It should exercise, at minimum:

-   multiple fixture types
-   fixture groups
-   at least one universe
-   color palettes
-   position palettes
-   beam/look presets
-   approximately 15--20 cues
-   at least one song with sections/entries

Use real Aurora project/model objects and the normal load path. Do not
hard-code fake content into production views.

------------------------------------------------------------------------

## 3. Add a Visual Comparison Checkpoint Before Handoff

Before declaring UI-02A complete, compare the **actual running
application screenshot** directly against the approved Build Mode
render.

Perform a short qualitative self-review covering:

``` text
Toolbar / Aurora identity
Surface hierarchy
Programmer prominence
Navigation hierarchy
Panel treatment
Fixture Browser density
Palette richness
Cue-list grammar
Inspector hierarchy
Status / health chrome
Overall creative character
```

For each area, identify any obvious remaining visual discrepancy.

Do not invent a numeric similarity score. The purpose is to force a
final visual inspection rather than merely confirming that required
components exist.

The handoff should include this discrepancy review.

------------------------------------------------------------------------

## 4. Prioritize Phase C Work

If implementation time or context becomes constrained, prioritize the
visible Build workspace in this order:

``` text
1. Real application shell / toolbar / panel chrome
2. Programmer
3. Fixture Browser
4. Palettes / Looks
5. Cue List
6. Inspector
```

The shell and Programmer matter most.

A polished Inspector should not come at the expense of leaving the
primary workspace or Programmer visually unfinished.

The Inspector should support the hierarchy rather than define it.

------------------------------------------------------------------------

## 5. Use the Aurora Brand Assets Deliberately

The approved Aurora assets already placed in `Assets.xcassets` should be
integrated into the project.

Verify and use:

``` text
AppIcon.appiconset
AuroraMark.imageset
AuroraWordmark.imageset
approved custom lighting/interface icons
```

### Toolbar identity

For permanent application toolbar chrome, prefer a restrained treatment
such as:

``` text
[AuroraMark] AURORA
```

using the mark plus native typography when that provides better sizing
and flexibility.

Do not force the full `AuroraWordmark` into the permanent toolbar if it
consumes excessive horizontal space.

### Wordmark

Prefer the full wordmark for surfaces such as:

-   welcome / no-project state
-   About Aurora
-   future splash/launch experience
-   future web/iPad remote branding

### Functional icons

Use approved custom icons where they communicate lighting-specific
concepts better than generic SF Symbols.

Continue using SF Symbols where they are clearer and more native.

Do not use custom assets merely because they exist. Maintain one
coherent icon language.

------------------------------------------------------------------------

## 6. Keep the Running Application as the Acceptance Target

The component gallery is no longer the primary success metric.

The central acceptance criterion remains:

> **Launch Aurora, open the deterministic demo show, and immediately see
> a Build workspace that visibly belongs to the same product family as
> the approved high-fidelity render.**

UI-02A is not complete merely because:

-   components exist
-   tokens changed
-   previews look correct
-   the component gallery looks correct
-   new shell files were created

The actual application window must visibly demonstrate the redesign.

------------------------------------------------------------------------

## 7. Preserve Grok's Existing Strong Decisions

The following parts of Grok's plan should remain unchanged:

-   keep `AuroraUI` independent of the executable target
-   keep app-owned brand assets in app-target composition
-   preserve `ControlActionRouter`
-   preserve save/output behavior
-   avoid high-rate DMX in broad SwiftUI observation
-   use focused bindings where practical
-   make Programmer the Build-mode center of gravity
-   distinguish Build/Perform mode from workspace and panel-local
    navigation
-   use structured health state
-   create purposeful empty states
-   give GO greater visual authority than ordinary utility actions
-   defer full Perform, MIDI Settings, Patch, Effects, Output, web
    remote, and advanced docking redesigns
-   stop after UI-02A for human visual review

------------------------------------------------------------------------

## 8. Revised Handoff Requirements

When UI-02A is complete, provide:

1.  Updated repository.
2.  Screenshot of the **actual running Aurora application** with the
    deterministic demo project.
3.  Screenshot at a typical MacBook-sized window.
4.  Screenshot at a larger desktop-sized window.
5.  Confirmation that the production AppIcon is correctly wired.
6.  Confirmation that `AuroraMark` and `AuroraWordmark` resolve
    correctly.
7.  List of approved custom icons integrated.
8.  Summary of legacy workspace chrome removed/replaced.
9.  List of UI-01C components now used by the real application.
10. Confirmation that backend/domain semantics were unchanged.
11. A short visual discrepancy review against the approved Build Mode
    render covering:
    -   toolbar / identity
    -   surface hierarchy
    -   Programmer prominence
    -   navigation
    -   panels
    -   Fixture Browser
    -   palettes
    -   cues
    -   Inspector
    -   status chrome
    -   overall creative character

Then **STOP**.

Do not proceed to the remainder of UI-02 until the launched Build
workspace is explicitly approved.

------------------------------------------------------------------------

# Final Direction

Grok's UI-02A plan is approved with these amendments.

This phase is intentionally narrow:

> **Make one real Aurora screen beautiful from end to end.**

Do not optimize for the amount of UI code changed.

Optimize for the moment Aurora launches and the difference is
immediately, unmistakably visible.
