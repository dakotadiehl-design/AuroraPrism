# Aurora C5.1 Multi-Monitor / Undockable Workspace Closeout

## Window Lifecycle, True Surface Reuse, Persistence, Monitor Recovery, and Dock/Redock Correctness

**Project:** Aurora Lighting Control\
**Target:** `Aurora_C5.zip`\
**Phase:** C5.1 corrective closeout\
**Status:** Required before C6\
**Purpose:** Preserve the very strong first C5 implementation while
fixing the lifecycle/state-sharing issues found during deep code review.

------------------------------------------------------------------------

# 1. Executive Review Verdict

C5 is visually and conceptually a major success.

The current repository correctly establishes several important
foundations:

-   real macOS floating windows via `WindowGroup`,
-   shared `AppModel`,
-   persisted per-surface presentation records,
-   explicit docked / floating / hidden state,
-   discoverable Move to Window and Dock commands,
-   multiple independently floatable surfaces,
-   UserDefaults-based workspace state separate from show/project
    content,
-   minimum/default window sizes,
-   an architecture that can support future workspace presets.

This work should **not** be discarded or redesigned.

However, deep review found several C5 requirements that are only
partially implemented despite the checkpoint report describing them as
complete.

The major issues are:

1.  **Floating-window position and size are not actually updated when
    the user moves/resizes a window.**
2.  **Redocking from the main View menu or a main-window placeholder
    does not close the corresponding floating window, allowing duplicate
    visible hosts.**
3.  **The floating-window Dock button closes a window by scanning
    `NSApp.windows` by title/key status instead of closing the exact
    window that belongs to the surface.**
4.  **`onDisappear` redocks a floating surface, which can interfere with
    preserving floating layouts across application termination.**
5.  **Several floating surfaces are not actually the same production
    surface as their docked equivalents.**
    -   Browser float loses the Groups tool.
    -   Creative Shelf float always shows Cue List only.
    -   Stage Preview float hosts `StagePanel`, a separate older outer
        Stage workflow rather than the production DESIGN Stage surface.
6.  **Monitor recovery uses the geometric union of screens and full
    screen frames rather than per-screen visible frames, which can leave
    windows in monitor gaps or underneath unusable regions.**
7.  **The current large dock placeholders consume much of the space the
    user expected to reclaim by undocking.**
8.  **C5 tests validate the state structs but do not validate the real
    window lifecycle or same-content hosting claims.**

These are targeted closeout issues. The windowing concept is correct.

------------------------------------------------------------------------

# 2. What Is Already Good and Must Be Preserved

Do not rewrite C5 from scratch.

Preserve:

``` text
FloatSurfaceID
PanelPresentationKind
FloatSurfaceRecord
WorkspaceFloatState
WorkspaceFloatStore
WorkspaceController floatState
WindowGroup(id: "float-surface")
shared AppModel
explicit undock/redock commands
real macOS windows
future preset-ready state representation
```

The high-level architecture:

``` text
one application state
+
multiple presentation hosts
```

is correct.

C5.1 should make that architecture truthful and robust.

------------------------------------------------------------------------

# 3. Finding A --- Window Frame Persistence Is Not Actually Wired

## 3.1 Existing infrastructure

`WorkspaceController` already exposes:

``` swift
func updateFloatingFrame(
    _ surface: FloatSurfaceID,
    frame: CGRect,
    screenID: String?
)
```

and `FloatSurfaceRecord` can persist:

``` text
frameX
frameY
frameW
frameH
screenID
```

This is good.

## 3.2 Actual defect

A repository-wide search shows no production caller for:

``` swift
updateFloatingFrame(...)
```

There are no window move/resize notifications currently feeding the
controller.

Therefore:

> Moving or resizing a floating window does not update the persisted
> `WorkspaceFloatState`.

The window opens using whatever frame was originally recorded during
undock, not the frame the user actually established.

This violates C5B:

> Persist window size, window position, and display association.

------------------------------------------------------------------------

# 4. Implement Per-Window Frame Tracking

Each floating window must report actual window changes.

Preferred implementation:

-   resolve the exact `NSWindow` for each `FloatSurfaceID`,
-   install a narrow coordinator/delegate or notification observer,
-   listen for:
    -   move,
    -   resize,
    -   screen change,
-   call:

``` swift
appModel.workspace.updateFloatingFrame(
    surface,
    frame: window.frame,
    screenID: resolvedScreenIdentifier
)
```

Recommended AppKit events:

``` text
NSWindow.didMoveNotification
NSWindow.didResizeNotification
NSWindow.didChangeScreenNotification
```

or an `NSWindowDelegate` equivalent.

Debouncing already exists in `WorkspaceFloatStore`, so do not persist
every frame synchronously to disk.

## Required test

1.  Float Programmer.
2.  Move it to a recognizable position.
3.  Resize it.
4.  Quit Aurora.
5.  Relaunch.
6.  Confirm Programmer restores at approximately the same size and
    position.

------------------------------------------------------------------------

# 5. Finding B --- Redock State and Window Lifetime Are Not Synchronized

## 5.1 Main View menu defect

The current menu path:

``` swift
appModel.workspace.redock(surface)
```

changes workspace state but does **not** close the actual floating
`NSWindow`.

Result can become:

``` text
main docked Programmer visible
+
old Programmer floating window still visible
```

This violates the single-presentation expectation and can produce
confusing duplicate surfaces.

## 5.2 Placeholder `Dock Here` defect

`FloatedSurfacePlaceholder` currently invokes a callback that redocks
state.

It does not own or close the corresponding floating window.

The same duplicate-host problem can occur.

## Required rule

> A surface transitioning from `.floating` to `.docked` must close the
> exact floating window associated with that surface.

State and window lifetime must be one coordinated operation.

------------------------------------------------------------------------

# 6. Introduce a Narrow Floating Window Coordinator

Create a small coordinator responsible for:

``` text
FloatSurfaceID ↔ NSWindow
```

Conceptually:

``` swift
@MainActor
final class FloatingSurfaceWindowCoordinator {
    func register(window: NSWindow, for surface: FloatSurfaceID)
    func unregister(surface: FloatSurfaceID, window: NSWindow)
    func window(for surface: FloatSurfaceID) -> NSWindow?
    func closeWindow(for surface: FloatSurfaceID)
    func focusWindow(for surface: FloatSurfaceID)
}
```

Exact ownership may live in `AppModel`, `WorkspaceController`, or a
shell-level controller.

Do not make this a giant generic window framework.

Its responsibilities are only:

-   know which real window belongs to which surface,
-   close the correct one,
-   focus the correct one,
-   receive move/resize/screen updates,
-   help restore/recover frame state.

------------------------------------------------------------------------

# 7. Remove Unsafe Window Scanning

The floating Dock button currently searches:

``` swift
NSApp.windows
```

using logic similar to:

``` text
title contains surface.title
OR window is key window
```

This is unsafe.

Potential failures:

-   closes the wrong floating panel,
-   closes whichever unrelated auxiliary window happens to be key,
-   title changes break lookup,
-   duplicate titles become ambiguous.

Replace this with direct registration of the exact `NSWindow`.

Required:

``` text
Dock Programmer
→ close Programmer's registered window
```

not:

``` text
search all windows and hope
```

------------------------------------------------------------------------

# 8. Finding C --- `onDisappear` Is the Wrong Place to Own Redock Policy

Current `FloatingSurfaceWindow` behavior redocks in:

``` swift
.onDisappear {
    if workspace.isFloating(surface) {
        workspace.redock(surface)
    }
}
```

This conflates:

``` text
user intentionally closed this floating panel
```

with:

``` text
SwiftUI scene disappeared because the application is terminating,
window hierarchy is rebuilding,
or some other lifecycle event occurred
```

The latter must not automatically rewrite persisted layout to docked.

Otherwise C5's restart restoration can become unreliable.

## Required policy

Use the actual floating `NSWindow` close lifecycle to distinguish
intentional close.

Preferred:

``` text
user clicks red close button
→ windowWillClose
→ if Aurora is not terminating and surface is still floating
→ apply documented close policy: redock
```

Application termination should preserve `.floating` state.

## App termination

Aurora already calls:

``` swift
workspace.flushLayoutPersistence()
```

during shutdown.

That is good.

Ensure floating-window teardown during quit does not subsequently mutate
those records to `.docked`.

------------------------------------------------------------------------

# 9. Add an Application-Termination Guard

Use one clear lifecycle signal such as:

``` swift
appModel.isTerminating
```

or coordinator-owned shutdown state.

Conceptual behavior:

``` text
normal user close:
    redock

application quit:
    preserve floating state
    persist final frame
    close naturally
```

Do not use timing hacks.

------------------------------------------------------------------------

# 10. Finding D --- Floating Surfaces Are Not Always the Same Production Surface

The C5 roadmap explicitly requires:

> Do not clone these views. The same production content should be
> hostable inside the main workspace or an independent macOS window.

Several surfaces currently violate the spirit or letter of this
requirement.

------------------------------------------------------------------------

# 11. Browser Float Loses the Groups Surface

## Docked DESIGN browser

The docked leading column contains:

``` text
Fixtures
Groups
```

driven by:

``` swift
appModel.workspace.leftTool
```

and switches between:

``` swift
FixtureBrowserPanel
GroupsPanel
```

## Floating Browser

The current floating implementation does only:

``` swift
PanelRegistry.view(id: .fixtureBrowser, ...)
```

Therefore "Browser" float is not the Fixture/Group Browser surface
described by C5.

It loses:

-   Groups tab,
-   current left-tool selection,
-   exact docked header/tab UX,
-   potentially some docked callbacks such as Reveal on Stage.

## Required fix

Extract the production Browser surface into a reusable view.

Conceptually:

``` swift
BuildBrowserSurface
```

with:

-   Fixtures / Groups tabs,
-   shared `workspace.leftTool`,
-   same panel callbacks,
-   same behavior in docked and floating hosts.

Use it in both places.

Do not independently reconstruct the browser in `FloatingSurfaceWindow`.

------------------------------------------------------------------------

# 12. Creative Shelf Float Is Incorrect

## Docked lower shelf

The production creative shelf supports:

``` text
Palettes
Cues
Song
Diagnostics
```

using:

``` swift
appModel.workspace.lowerTool
```

It includes:

-   selected tool state,
-   Cue List,
-   Palettes,
-   Song Mode,
-   Diagnostics,
-   associated inspector callbacks.

## Floating Creative Shelf

The current float host always renders:

``` swift
PanelRegistry.view(id: .cueList, ...)
```

inside a `VStack`.

That means:

> Floating "Creative Shelf" is actually Floating "Cue List".

This is a functional C5 defect.

## Required fix

Extract the entire lower creative shelf body/tab chrome into a reusable
production surface:

``` swift
CreativeShelfSurface
```

Use the same:

``` swift
workspace.lowerTool
```

in both main and floating hosts.

If the user floats the shelf while `Song` is selected:

``` text
floating window must show Song
```

If they click `Palettes` in the floating shelf:

``` text
workspace.lowerTool becomes Palettes
```

and that state remains when redocked.

------------------------------------------------------------------------

# 13. Stage Preview Float Uses the Wrong Host

This is the most important surface-reuse issue.

## Docked production Stage

The actual DESIGN Stage uses:

``` swift
designStagePreviewRegion
```

around:

``` swift
StageCanvasView
```

with the current C3/C4/C4.4 Stage editing workflow:

-   DESIGN/Edit Stage integration,
-   Stage Object palette,
-   corrected transform architecture,
-   direct beam aiming,
-   current Stage chrome,
-   current camera state,
-   current selection semantics.

## Floating Stage Preview

The current C5 float host constructs:

``` swift
StagePanel(...)
```

`StagePanel` is a separate outer Stage host with its own local state:

``` swift
@State mode
@State scale
@State pan
@State rotationDegrees
@State leftRail
```

and its own older toolbar/edit workflow.

This means the floating Stage surface is not the same production DESIGN
Stage surface.

It can drift from the current Stage UX and may already lack later C4
interactions/chrome.

## Required fix

Extract the current production DESIGN Stage surface into a reusable
host.

Conceptually:

``` swift
DesignStageSurface
```

or:

``` swift
StageWorkspaceSurface
```

It should contain the actual current Stage chrome + `StageCanvasView`
used by DESIGN.

Then:

``` text
docked center host
→ DesignStageSurface

floating Stage window
→ DesignStageSurface
```

Do not keep two independently evolving Stage shells.

------------------------------------------------------------------------

# 14. Stage Camera and Edit State Must Be Shared Appropriately

The current floating `StagePanel` owns separate:

``` text
scale
pan
mode
```

state.

That creates undesirable transitions:

``` text
dock Stage at zoom 150%
→ undock
→ new Stage window starts with unrelated camera/mode
```

or vice versa.

Decide explicitly which Stage presentation values belong to workspace
state.

Recommended:

``` text
Stage camera:
- designPreviewScale
- designPreviewPan

Stage editing mode:
- workspace.stageEditActive

Stage selection:
- existing shared session selection
```

At minimum:

-   undock/redock should not unexpectedly reset the user's camera,
-   Edit Stage state must not fork between windows,
-   only one production Stage workflow should exist.

------------------------------------------------------------------------

# 15. Programmer and Inspector Surface Reuse

The current Programmer and Inspector floats use `PanelRegistry`, which
is much closer to the desired architecture.

Retain them, but confirm the docked versions invoke the same production
views and callback contracts.

Add regression acceptance:

``` text
select fixture in floating Browser
→ docked/floating Inspector follows

change intensity in floating Programmer
→ Stage updates
```

------------------------------------------------------------------------

# 16. Finding E --- Monitor Recovery Math Is Too Weak

Current recovery computes:

``` text
union of all screen rectangles
```

and tests whether a window intersects that union.

This can fail with real monitor arrangements.

Example:

``` text
Monitor A       gap        Monitor B
┌─────────┐               ┌─────────┐
│         │               │         │
└─────────┘               └─────────┘
```

The geometric bounding union can include empty space between monitors.

A window can therefore be:

``` text
inside the union
but
not visible on any actual display
```

## Required recovery rule

Evaluate frames against **individual screen visible frames**, not only
the bounding union.

Use:

``` swift
NSScreen.visibleFrame
```

rather than full `.frame` where possible so windows avoid:

-   menu bar,
-   Dock,
-   reserved screen regions.

------------------------------------------------------------------------

# 17. Recovery Algorithm

Recommended:

1.  Collect current screen records:

``` text
screenID
visibleFrame
```

2.  For each floating window record:
    -   if its saved screen still exists, restore/clamp to that screen;
    -   else choose the screen with greatest intersection;
    -   if no intersection, use main/nearest screen;
    -   resize window if it is larger than the chosen `visibleFrame`;
    -   clamp enough of the title bar/window onto-screen to guarantee
        recovery.
3.  Update persisted record if recovery changed the frame.

## Multi-monitor removal acceptance

``` text
Float Inspector entirely on monitor 2
Quit
Disconnect monitor 2
Launch
Inspector must appear completely usable on monitor 1
```

------------------------------------------------------------------------

# 18. Screen Identity

Current code stores values such as:

``` swift
NSScreen.main?.localizedName
```

`localizedName` is human-friendly but not guaranteed to be a durable
unique monitor identity.

Prefer a best-effort stable display identifier derived from
AppKit/CoreGraphics where practical, such as the screen number/display
ID available through `NSScreen.deviceDescription`.

A human-readable name may also be stored for diagnostics.

Exact persistence across radically changing display hardware cannot be
guaranteed, but the model should not rely solely on localized display
names.

------------------------------------------------------------------------

# 19. Finding F --- Undocking Does Not Fully Reclaim Main Workspace Space

Current Browser/Inspector/Stage/Programmer floats leave relatively large
`FloatedSurfacePlaceholder` regions in the main workspace.

Examples:

``` text
Browser placeholder keeps full browser column width
Inspector placeholder keeps full inspector width
Programmer placeholder can keep most of center region
Stage placeholder consumes Stage height
```

This weakens the purpose of multi-monitor operation.

The user undocks a panel partly to gain **more main-window canvas
space**.

## Recommended behavior

When a major surface is floating:

-   collapse its docked region,
-   allow neighboring content to reclaim the area,
-   retain only a compact restore affordance where useful.

Examples:

``` text
Browser floated:
main Stage/Programmer expands leftward
small "Browser ↗" restore chip in chrome/menu

Inspector floated:
center expands to right edge

Stage floated:
Programmer expands vertically

Programmer floated:
Stage can expand vertically
```

The lower shelf already behaves closer to this model because `showLower`
becomes false when floated.

Do not require giant placeholders.

## Exception

A compact placeholder strip is acceptable if it improves
discoverability, but it should not reserve the original panel's full
geometry.

------------------------------------------------------------------------

# 20. Finding G --- View Menu Undock Uses a Different Initial Frame Path

The panel chrome `UndockSurfaceButton` computes a centered default
frame.

The View-menu path calls:

``` swift
workspace.undock(surface)
```

without a frame, and the controller falls back to:

``` swift
CGRect(origin: .zero, size: surface.defaultSize)
```

That can result in inconsistent first-open positioning.

Unify undock behavior through one coordinator API.

Conceptually:

``` swift
floatCoordinator.undock(surface, preferredScreen: current/main)
```

which:

-   computes default frame,
-   updates state,
-   opens the correct WindowGroup,
-   registers the window,
-   later tracks frame changes.

Every UI entry point should call the same operation.

------------------------------------------------------------------------

# 21. Hidden State

`PanelPresentationKind.hidden` exists but is not central to this
checkpoint.

Do not expand C5.1 into a full hidden-panel management feature unless
existing behavior requires it.

However:

-   ensure `.hidden` cannot accidentally produce a floating window,
-   keep schema ready for future View-menu visibility handling.

------------------------------------------------------------------------

# 22. WorkspaceFloatStore Thread Safety

`WorkspaceFloatStore` uses static mutable:

``` text
pending
workItem
```

while delayed saves execute on a private queue and flushes may occur
from application shutdown.

Review this for race safety under Swift concurrency.

A simple solution is to make float persistence main-actor-owned because
workspace mutations already originate from UI state.

Alternatively protect shared pending state with one serial execution
context.

Do not create an elaborate persistence service for this.

This is a reliability cleanup, not the main blocker.

------------------------------------------------------------------------

# 23. Tests Need to Validate More Than the Data Model

The existing `WorkspaceFloatC5Tests` are useful but primarily prove:

-   state transitions,
-   JSON round-trip,
-   simple off-screen recovery,
-   catalog completeness.

They do not prove the actual C5 acceptance claims.

Add testable logic around the following.

------------------------------------------------------------------------

# 24. Required Automated Test Additions

## Frame update

``` text
record starts at frame A
window-frame update B
→ persisted state reflects B
```

## Screen recovery

Test:

-   two separated monitors with a gap,
-   frame entirely in gap,
-   frame on removed monitor,
-   frame larger than available display,
-   partially visible frame,
-   use visible-frame geometry.

## Presentation lifecycle

Test state/coordinator logic:

``` text
undock
→ floating true
→ window registered

redock
→ floating false
→ exact surface window close requested
```

## App termination

Test conceptual policy:

``` text
surface floating
→ app termination
→ record remains floating
```

whereas:

``` text
surface floating
→ user closes float
→ record becomes docked
```

## Surface-host completeness

Where practical, make reusable surface enums/builders testable so C5
cannot regress into:

``` text
Creative Shelf float = Cue List only
```

At minimum add catalog/contract tests asserting that Browser and
Creative Shelf expose their expected subtools.

------------------------------------------------------------------------

# 25. Manual Acceptance --- Single Display

Perform in the actual production app.

## Every floatable surface

For each:

``` text
Browser
Stage Preview
Programmer
Inspector
Creative Shelf
Diagnostics
```

-   [ ] Undock from panel chrome.
-   [ ] Redock from floating window.
-   [ ] Undock from View menu.
-   [ ] Redock from View menu.
-   [ ] Undock and use `Dock Here`/main restore command.
-   [ ] Confirm floating window actually closes after redock.
-   [ ] Confirm only one visual host remains.

## Frame persistence

-   [ ] Move each floating window.
-   [ ] Resize it.
-   [ ] Quit.
-   [ ] Relaunch.
-   [ ] Confirm size/position restore.

------------------------------------------------------------------------

# 26. Manual Acceptance --- Surface Fidelity

## Browser

-   [ ] Float Browser.
-   [ ] Fixtures tab available.
-   [ ] Groups tab available.
-   [ ] Switch to Groups.
-   [ ] Redock.
-   [ ] Groups remains selected.
-   [ ] Reveal/inspect behavior matches docked Browser.

## Creative Shelf

-   [ ] Select Song in docked shelf.
-   [ ] Float Creative Shelf.
-   [ ] Floating shelf opens on Song.
-   [ ] Switch to Palettes.
-   [ ] Redock.
-   [ ] Palettes remains selected.
-   [ ] Cue firing works while floated.

## Stage

-   [ ] Enter Edit Stage in DESIGN.
-   [ ] Float Stage.
-   [ ] Confirm same current Stage UX appears.
-   [ ] Objects palette available.
-   [ ] Performer move/resize/rotate works.
-   [ ] Beam aim works.
-   [ ] Stage camera does not unexpectedly reset.
-   [ ] Redock.
-   [ ] Continue editing without mode fork.

## Programmer

-   [ ] Float Programmer.
-   [ ] Select fixture from main or floating Browser.
-   [ ] Programmer follows.
-   [ ] Change intensity/color.
-   [ ] Stage updates.

## Inspector

-   [ ] Float Inspector.
-   [ ] Change selection elsewhere.
-   [ ] Inspector follows immediately.

------------------------------------------------------------------------

# 27. Manual Acceptance --- Two Displays

-   [ ] Connect second display.
-   [ ] Float Stage to display 2.
-   [ ] Move Programmer to display 2.
-   [ ] Keep Browser/Inspector on display 1.
-   [ ] Program fixtures.
-   [ ] Verify all surfaces share current selection/state.
-   [ ] Resize and reposition floating windows.
-   [ ] Quit Aurora.
-   [ ] Relaunch with both monitors.
-   [ ] Confirm useful layout restoration.

------------------------------------------------------------------------

# 28. Manual Acceptance --- Monitor Removal

-   [ ] Float Programmer and Inspector to external monitor.
-   [ ] Position windows near external-screen edges.
-   [ ] Quit.
-   [ ] Disconnect external monitor.
-   [ ] Relaunch.
-   [ ] Confirm both windows recover fully onto an available display.
-   [ ] Confirm title bars are reachable.
-   [ ] Confirm windows are not sitting in a former monitor gap.
-   [ ] Reconnect display and continue normally.

------------------------------------------------------------------------

# 29. Main Workspace Reflow Acceptance

For each major surface:

## Browser floated

-   [ ] Main center content expands into browser space.

## Inspector floated

-   [ ] Main center content expands into inspector space.

## Stage floated

-   [ ] Programmer gains substantially more vertical space.

## Programmer floated

-   [ ] Stage gains substantially more vertical space.

A small restore indicator is fine.

A full-size empty placeholder defeating the reclaimed space is not.

------------------------------------------------------------------------

# 30. Window Close Policy

Retain the approved policy:

> **Closing a floating panel redocks it into the main window.**

But implement it through real window close events.

Required distinction:

``` text
user closes panel window
→ redock
```

versus:

``` text
Aurora quits
→ preserve floating layout for next launch
```

and:

``` text
user clicks Dock
→ redock + close exact window
```

All three must be deterministic.

------------------------------------------------------------------------

# 31. Recommended Refactoring Boundary

The most important C5.1 refactor is not a generic window framework.

It is **reusable production surface extraction**.

Recommended reusable surface views:

``` text
BrowserWorkspaceSurface
StageWorkspaceSurface
ProgrammerWorkspaceSurface
InspectorWorkspaceSurface
CreativeShelfWorkspaceSurface
DiagnosticsWorkspaceSurface
```

Some can simply wrap existing `PanelRegistry` entries.

Others, notably Browser, Stage, and Creative Shelf, need to encapsulate
the full production chrome/tool state currently embedded in
`BuildWorkspaceHost`.

Then hosting becomes:

``` text
DockedSurfaceHost
└── BrowserWorkspaceSurface

FloatingSurfaceWindow
└── BrowserWorkspaceSurface
```

This fulfills the C5 requirement literally.

------------------------------------------------------------------------

# 32. Avoid Massive BuildWorkspaceHost Duplication

Do not copy/paste:

``` text
designStagePreviewRegion
lowerRegion
leftColumn
```

into `FloatingSurfaceWindow`.

Extract reusable composition once.

The goal is to make future C4/C7 fixes land in both docked and floating
modes automatically.

This is particularly important for Stage: the floating Stage must never
become a forgotten second implementation.

------------------------------------------------------------------------

# 33. Recommended Implementation Order

## Step 1 --- Window coordinator

Register exact `NSWindow` per `FloatSurfaceID`.

## Step 2 --- Frame tracking

Wire move/resize/screen-change events to `WorkspaceFloatState`.

## Step 3 --- Fix redock lifecycle

All redock entry points close the exact surface window.

## Step 4 --- Replace `onDisappear` redock ownership

Use user-close-aware window lifecycle and preserve floats during app
termination.

## Step 5 --- Improve monitor recovery

Per-screen `visibleFrame`, real screen identity, no monitor-gap recovery
bugs.

## Step 6 --- Extract Browser production surface

Fixtures + Groups, one shared tool state.

## Step 7 --- Extract Creative Shelf production surface

Palettes + Cues + Song + Diagnostics, one shared `lowerTool`.

## Step 8 --- Extract production DESIGN Stage surface

Float the actual current Stage workflow, not legacy `StagePanel` chrome.

## Step 9 --- Make main workspace reclaim floated regions

Replace large placeholders with compact restore affordances or zero-size
dock regions.

## Step 10 --- Unify all undock entry points

Panel chrome and View menu use the same window coordinator.

## Step 11 --- Strengthen tests

Lifecycle, recovery, frames, surface contracts.

## Step 12 --- Production multi-monitor validation

Perform the full acceptance sequence and STOP.

------------------------------------------------------------------------

# 34. Severity Summary

## Blocker --- fix before C6

1.  Floating frame changes are not persisted.
2.  Redock from menu/placeholder can leave duplicate float windows.
3.  User-close vs app-quit lifecycle can destroy intended floating
    restoration.
4.  Browser float is not full Fixtures/Groups Browser.
5.  Creative Shelf float is Cue List only.
6.  Floating Stage is not the same production DESIGN Stage surface.

## High

7.  Monitor recovery can place windows in invalid/gap geometry.
8.  Exact surface window is not tracked; title/key-window scanning is
    unsafe.

## UX / High-value

9.  Full-size placeholders prevent main workspace from reclaiming
    floated-panel space.
10. View-menu first-undock positioning differs from panel undock.

## Reliability cleanup

11. Review `WorkspaceFloatStore` pending-save concurrency.

------------------------------------------------------------------------

# 35. Completion Criteria

C5 is complete when:

-   every required surface can be undocked into a real macOS window,
-   every floating surface is the same production content/workflow as
    its docked equivalent,
-   Browser float includes Fixtures and Groups,
-   Creative Shelf float includes Palettes/Cues/Song/Diagnostics,
-   Stage float uses the current production DESIGN/Edit Stage
    implementation,
-   selection/programming/playback state remains shared,
-   window positions and sizes update as users move/resize them,
-   frames restore after relaunch,
-   display association updates when moved between monitors,
-   redocking closes the exact floating window,
-   no duplicate docked + floating hosts remain after redock,
-   user-closing a float redocks it,
-   quitting Aurora preserves floating layout,
-   disconnected displays recover windows safely,
-   windows are not restored into monitor gaps,
-   main workspace meaningfully reclaims space when surfaces float,
-   tests pass,
-   native Xcode build passes,
-   single-display acceptance passes,
-   dual-display acceptance passes,
-   monitor-removal acceptance passes.

------------------------------------------------------------------------

# 36. STOP CONDITION

After C5.1:

> **STOP and produce a final C5 checkpoint for human review. Do not
> begin C6 automatically.**

The checkpoint report should include:

-   window coordinator design,
-   frame persistence implementation,
-   close/redock lifecycle rules,
-   app-termination behavior,
-   screen identifier and recovery algorithm,
-   extracted reusable surface components,
-   confirmation that legacy `StagePanel` is no longer used as the C5
    floating DESIGN Stage host,
-   production screenshots on one and two displays,
-   persistence test results,
-   monitor-removal test results.

If all acceptance criteria pass:

> **C5 CLOSED → proceed to C6 Splash & Brand Fidelity.**

------------------------------------------------------------------------

# 37. Product Standard

C5 is not merely "Aurora can open extra windows."

The real goal is:

> **Take the exact surface you are already using, move it onto another
> monitor, and keep working as though nothing changed except that you
> suddenly have more room.**

That means no cloned mini-version of the Stage, no Cue-only "Creative
Shelf," no forgotten Groups tab, no stale window geometry, and no
phantom duplicate window after redocking.

One Aurora state. One production surface implementation. As many
monitors as the operator wants.
