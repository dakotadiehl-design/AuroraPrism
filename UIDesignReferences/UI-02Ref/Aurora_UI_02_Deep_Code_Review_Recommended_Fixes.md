# Aurora UI-02 Deep Code Review

## Shell Review Findings and Recommended Fixes Before UI-03

**Review target:** `Aurora_UI2.zip`\
**Review type:** Deep post-implementation audit\
**Primary question:** Is Aurora's UI-02 shell stable, truthful, and safe
enough to become the foundation for UI-03+?

------------------------------------------------------------------------

# 1. Executive Verdict

Aurora's UI-02 architecture is **fundamentally good and should be
kept**.

The following decisions are worth preserving:

-   the production `ContentView` now composes the new Aurora shell
    rather than the legacy workspace
-   Build and Perform are separate presentation modes
-   `BuildWorkspaceHost` keeps the Programmer visually dominant
-   left-column and lower-region tool navigation are distinct from
    Build/Perform mode
-   explicit `InspectorFocus` exists independently of fixture selection
-   a native macOS `Settings` scene now exists
-   Settings begins to distinguish application-global and project/show
    scope
-   `UI_PANEL_CONTRACT.md` correctly defines host-agnostic panel content
-   approved Aurora brand and lighting icon assets are integrated
-   the deterministic demo show provides a useful visual-development
    environment
-   backend engine/output/MIDI/domain modules remain structurally
    separate from the visual redesign

I do **not** recommend another UI rewrite.

However, UI-02 exposed several behavioral bugs and regressions that
should be addressed before UI-03 deepens the Programmer and Fixture
Browser.

The most important findings are:

1.  Clicking a cue row currently **fires the cue** while also
    selecting/inspecting it.
2.  No-modifier global transport shortcuts are potentially active while
    editing text.
3.  Perform Mode still exposes Build-oriented application actions in the
    global toolbar/menu.
4.  Perform Current/Next presentation can report incorrect cue
    numbers/names.
5.  Inspector focus can remain stuck on an old cue/group/palette after
    the user explicitly clicks fixtures.
6.  Document replacement does not fully reset document-specific UI
    state.
7.  The new Build host ignores the old panel-visibility model while the
    View menu still exposes it, creating controls that appear functional
    but do nothing.
8.  UI redesign removed existing cue/palette/programmer functionality
    that needs an explicit restoration phase.
9.  Settings frame-rate changes restart the engine repeatedly while the
    slider is dragged.
10. App-wide observation remains coarse enough that the 4 Hz
    presentation poll can invalidate much of the UI.
11. The DEBUG demo auto-load can interfere with real project opening and
    can potentially route output to Art-Net if network output was
    previously enabled.

These are fixable and localized.

My recommendation is:

> **Fix P0 and P1 shell issues, document/assign the intentional
> feature-restoration items to UI-03/04/05, run macOS tests/build, then
> close UI-02 and proceed.**

------------------------------------------------------------------------

# 2. Review Validation Performed

The repository was reviewed statically across:

-   app composition
-   shell views
-   workspace controller
-   Inspector routing
-   Settings
-   Build navigation
-   Perform Mode
-   panel registry
-   Fixture Browser
-   Programmer
-   Cue List
-   Palettes
-   Groups
-   Song Mode
-   presentation snapshots
-   selection manager
-   output controller
-   project/document lifecycle
-   Xcode project/resource wiring
-   design-system components
-   demo show model
-   panel-hosting contract
-   prior UI functionality via Git diff against the pre-UI state

I also ran:

``` bash
swift test
```

The build proceeds through portable Aurora modules and then fails on
Linux at the expected Apple-only framework boundaries:

``` text
no such module 'Network'
no such module 'CoreMIDI'
```

This is an environment limitation, not a new Aurora failure.

I additionally syntax-parsed the new/modified UI and shell Swift sources
with `swiftc -parse`; the reviewed UI source parses successfully.

A full macOS Xcode Debug/Release build and test run remains required
after remediation.

------------------------------------------------------------------------

# 3. Severity Definitions

## P0 --- Live-show safety / correctness

Could cause unintended show-control behavior or materially misrepresent
what will happen on stage.

Fix before UI-03.

## P1 --- Shell correctness / data-flow / user-trust

Does not normally corrupt data, but creates misleading UI, broken
workflows, stale state, or disruptive live behavior.

Fix before UI-03 where practical.

## P2 --- Architecture / performance / maintainability

Should be addressed before the UI becomes substantially larger, or
explicitly assigned to the next appropriate phase.

## P3 --- Later product polish

Valid issue, but can naturally land in UI-03+ or final polish if clearly
tracked.

------------------------------------------------------------------------

# 4. P0 --- Cue Selection Fires the Cue

**File:** `Sources/AuroraUI/Panels/CueListPanel.swift`

The redesigned cue row currently performs all three actions in one
click:

``` swift
selectedCueID = cue.id
onInspectCue(cue.id)
onFire(cue.id)
```

This means a normal click intended to select or inspect a cue also
executes it through the lighting engine.

That is not safe behavior for professional show-control software.

## Failure scenario

Operator is running a show.

They click Cue 16 merely to inspect its timing.

Aurora immediately fires Cue 16.

The stage changes.

## Required fix

Separate **selection/inspection** from **execution**.

Recommended behavior:

### Single click

``` text
Select cue
Update Inspector focus
Do NOT fire
```

### Execution

Use one or more explicit mechanisms:

-   GO
-   dedicated Fire button
-   clearly intentional double-click if desired and documented
-   context menu `Fire Cue`
-   keyboard transport command

Do not make ordinary row selection execute lighting.

## Additional recommendation

Restore selection synchronization into `SelectionManager`:

``` text
selected cue ID
selected cue-list ID
```

The previous Cue List implementation published cue/list selection for
cross-panel workflows.

That behavior disappeared during the visual rewrite.

## Regression test

Add a testable interaction layer or extracted action model proving:

``` text
selectCue(id) -> no engine fire
fireCue(id)   -> engine fire
```

This is the highest-priority UI-02 fix.

------------------------------------------------------------------------

# 5. P0/P1 --- Global Transport Shortcuts Can Collide With Text Editing

**File:** `Sources/Aurora/AuroraApp.swift`

The global Playback menu defines no-modifier shortcuts:

``` swift
Space   -> GO
Return  -> GO
Escape  -> STOP
Left    -> BACK
B       -> BACK
```

These are declared at application-command scope.

The Settings page itself tells the user:

> Space for GO when focused.

But the implementation is not obviously focus-scoped.

As Aurora gains editable cue names, palette names, song metadata,
numerical fields, search fields, and Settings text entry, global
no-modifier commands become dangerous.

## Potential failure scenarios

-   typing a space into a cue name triggers GO
-   pressing Return to finish text entry triggers GO
-   Left Arrow while editing a field triggers BACK
-   pressing `b` in ordinary text triggers BACK depending on AppKit
    command routing

This needs explicit macOS validation.

## Required fix

Establish transport-command suppression while a text-editing control
owns keyboard focus.

Preferred approaches include:

-   focused-command values
-   AppKit first-responder inspection
-   a centralized keyboard-command coordinator aware of text editing
-   mode-aware transport shortcuts

Do not scatter ad-hoc checks through individual text fields.

## Required acceptance test

On macOS, verify:

``` text
TextField focused + Space  -> enters space, no GO
TextField focused + Return -> completes/edit behavior, no GO unless explicitly intended
No text editing + Space    -> GO
Perform Mode + Space       -> GO
```

This should be solved before UI-03 adds substantially more editable
Programmer/UI controls.

------------------------------------------------------------------------

# 6. P1 --- Perform Mode Still Exposes Build Actions

**Files:**

-   `Sources/Aurora/ContentView.swift`
-   `Sources/Aurora/Shell/AuroraBuildToolbar.swift`
-   `Sources/Aurora/AuroraApp.swift`

`ContentView` always displays:

``` swift
AuroraBuildToolbar()
```

even when:

``` swift
workspace.mode == .perform
```

Therefore Perform Mode still visibly exposes toolbar actions such as:

-   New Show
-   Open
-   Save

The global menu also continues to expose structural/editing actions.

This conflicts with UI-02F's requirement that Perform Mode be
operationally distinct and not advertise structural editing.

## Required fix

Make the top chrome mode-aware.

Recommended structure:

``` text
AuroraShellToolbar
    Build -> BuildToolbarContent
    Perform -> PerformToolbarContent
```

Perform toolbar should retain:

-   Aurora identity
-   show title
-   health
-   mode switch / intentional exit from Perform

but should hide or disable casual structural actions.

## Menu behavior

At minimum, structural commands should be disabled or guarded in Perform
Mode:

-   New Show
-   Open
-   import fixture definitions
-   destructive project editing

Saving may remain available if desired.

Do not implement full Show Lock yet; simply make Perform truthfully
safer.

------------------------------------------------------------------------

# 7. P1 --- Perform Current/Next Presentation Can Be Wrong

**Files:**

-   `Sources/Aurora/Shell/PerformWorkspaceShell.swift`
-   `Sources/Aurora/Controllers/PerformanceSnapshot.swift`
-   `Sources/Aurora/SongDirector.swift`

The Perform shell currently displays:

``` swift
cueIndex + 1
```

as the cue number.

That is not necessarily the cue's actual `Cue.number`.

Aurora cue numbers are Decimals and may be:

``` text
1
1.5
10
10.1
100
```

Index + 1 is not a cue number.

## Next-cue problem

`nextCueName` is resolved by taking:

``` text
current cue list
current cue index + 1
```

But Song Mode entries may intentionally target:

-   a different cue
-   a non-adjacent cue
-   a different cue list

This can produce a UI such as:

``` text
NEXT: Chorus
Cue: "Verse B"
```

where the section label and cue name refer to different targets.

That violates Aurora's "UI must tell the truth" principle.

## Required fix

Do not synthesize presentation identity from array indices inside the
view.

Extend the presentation contract with resolved cue descriptors.

Suggested type:

``` swift
struct PerformanceCueSummary: Equatable, Sendable {
    var listID: UUID?
    var cueID: UUID?
    var number: Decimal?
    var name: String
    var sectionLabel: String?
}
```

Then expose:

``` text
currentCue
nextCue
```

through `PerformanceSnapshot` or a closely related presentation
structure.

The view should render already-resolved semantic presentation state.

## Short-term acceptable fix

If changing the snapshot is too much for UI-02:

-   resolve the actual current cue number by `cueListID + cueIndex`
-   when a Song is active, display `nextEntryLabel` without inventing a
    mismatched next cue name

Do not display a fabricated cue number/name.

------------------------------------------------------------------------

# 8. P1 --- Cue Inspector Can Mark the Wrong Cue as CURRENT

**File:** `Sources/AuroraUI/Panels/InspectorPanel.swift`

Current-cue detection is:

``` swift
if index == playbackCueIndex {
    Text("CURRENT")
}
```

It does not verify that the inspected cue belongs to the currently
active cue list.

Two different cue lists can both have an item at index 3.

Inspecting list B cue index 3 while list A index 3 is playing can
incorrectly display:

``` text
CURRENT
```

## Required fix

Inspector needs the current `cueListID` in addition to
`playbackCueIndex`.

Current status should require:

``` text
list.id == currentPlaybackListID
AND
index == playbackCueIndex
```

Better still, compare actual cue ID if the presentation snapshot exposes
it.

------------------------------------------------------------------------

# 9. P1 --- Inspector Focus Does Not Follow Explicit Fixture Clicks Correctly

**Files:**

-   `Sources/Aurora/Controllers/WorkspaceController.swift`
-   `Sources/Aurora/Shell/BuildWorkspaceHost.swift`
-   `Sources/AuroraUI/Panels/FixtureBrowserPanel.swift`

`noteFixtureSelectionChanged` intentionally preserves non-fixture
Inspector focus:

``` swift
case .cue, .group, .palette, .preset, .song:
    break
```

This is useful when fixture selection changes programmatically.

But `FixtureBrowserPanel` does not tell the shell whether selection was
caused by an explicit user click.

## Failure scenario

1.  User clicks Cue 10.
2.  Inspector shows Cue 10.
3.  User clicks Fixture `Mover 1`.
4.  Fixture selection changes.
5.  Inspector remains on Cue 10.

The user explicitly changed inspection intent, but Aurora keeps stale
focus.

## Required fix

Differentiate:

``` text
fixture selection state changed
```

from:

``` text
user explicitly clicked fixture/group for inspection
```

Recommended addition:

``` swift
FixtureBrowserPanel(
    ...,
    onInspectFixtures: { ids in ... }
)
```

A user click should explicitly set:

``` text
.fixtures
.multiFixtures
```

Programmatic selection changes may preserve a non-fixture Inspector
focus.

## Group rows

If a group row is intended to inspect the group, set:

``` text
.group(id)
```

If it is purely a fixture-selection shortcut, make that behavior
visually clear.

------------------------------------------------------------------------

# 10. P1 --- Document Replacement Does Not Reset Document-Specific UI State

**Files:**

-   `Sources/Aurora/AppModel.swift`
-   `Sources/Aurora/Controllers/WorkspaceController.swift`
-   `Sources/AuroraUI/Panels/CueListPanel.swift`

When Aurora:

-   creates a New Show
-   opens another project
-   opens the demo show

the workspace's Inspector focus and panel-local state are not
comprehensively reset.

## Inspector failure

If Inspector focus is:

``` text
.cue(oldProjectCueID)
```

then a new project can open while the Inspector remains focused on an ID
from the prior project.

The view falls back to:

``` text
Cue not found
Selection is out of date.
```

This should not be the normal experience immediately after opening a
valid project.

## CueList state failure

`CueListPanel` stores:

``` swift
@State private var selectedListID
```

`currentList` currently behaves as:

``` swift
if let selectedListID {
    return lists.first { $0.id == selectedListID }
}
return lists.first
```

If a new document replaces the project and the old `selectedListID` does
not exist, `currentList` becomes `nil` even when the new project
contains cue lists.

`onAppear` will not necessarily run again because the same panel view
remains mounted.

## Required fix

Create an explicit workspace/document-change reset hook.

Suggested:

``` swift
workspace.didReplaceDocument(project:)
```

At minimum reset:

-   Inspector focus
-   document-specific selected cue/list state
-   stale tool-local selection IDs
-   any document-specific Inspector IDs

Panel state should also self-heal if selected IDs disappear.

Example:

``` swift
currentList = matching selected list ?? lists.first
```

and synchronize `selectedListID` accordingly.

------------------------------------------------------------------------

# 11. P1 --- View Menu Exposes Panel Visibility Controls That No Longer Control the Production Workspace

**Files:**

-   `Sources/Aurora/AuroraApp.swift`
-   `Sources/Aurora/Controllers/WorkspaceController.swift`
-   `Sources/Aurora/Shell/BuildWorkspaceHost.swift`
-   `Sources/AuroraUI/Workspace/WorkspaceLayout.swift`

The View menu still iterates:

``` swift
WorkspacePanelID.allCases
```

and calls:

``` swift
appModel.togglePanel(panel)
```

This changes:

``` text
WorkspaceLayout.visiblePanels
```

But the new production `BuildWorkspaceHost` does not consume that
visibility model.

Therefore the menu can show a checkmark and toggle internal state while
the visible application does nothing.

This violates UI truthfulness.

## Required fix

Choose one of two approaches.

### Preferred for UI-02

Remove/deactivate legacy panel-visibility commands from the production
View menu until UI-11 docking/layout work.

Expose only shell actions that currently work:

``` text
Build Mode
Perform Mode
Browser / Patch / Groups
Palettes / Cues / Song
```

### Alternative

Wire current production host visibility into `WorkspaceLayout`.

Do not partially recreate docking now merely to preserve an old menu.

## Also clean up

If `WorkspaceLayout` is now a legacy/future layout structure, document
that clearly.

Do not let production commands manipulate dead state.

------------------------------------------------------------------------

# 12. P1 --- "Save Before New/Open" Async Workflow Is Still Broken

**Files:**

-   `Sources/Aurora/AppModel.swift`
-   `Sources/Aurora/Controllers/ProjectController.swift`

This issue was previously identified and remains present.

Current logic:

``` text
Prompt -> user chooses Save
        -> starts async save
        -> immediately checks session.isDirty
        -> still dirty
        -> returns false
        -> requested New/Open operation is cancelled
```

The save may complete successfully afterward, but the user must invoke
New/Open again.

This is safe from a data-loss standpoint but is broken UX and should not
remain in the polished shell.

## Required fix

Make the discard confirmation flow async.

Suggested shape:

``` swift
enum DirtyDocumentDecision {
    case save
    case discard
    case cancel
}
```

Then:

``` text
await prompt
if save:
    await save
    if success -> continue requested operation
if discard:
    continue
if cancel:
    stop
```

Use the same workflow for:

-   New
-   Open
-   Finder-open replacement
-   demo replacement

Quit already uses an awaitable flow and can serve as the model.

------------------------------------------------------------------------

# 13. P1 --- DEBUG Demo Auto-Load Should Be Removed or Made Explicitly Safe

**File:** `Sources/Aurora/AuroraApp.swift`

Current Debug behavior:

``` swift
if appModel.session.project.fixtures.isEmpty {
    appModel.openDemoSummerNight()
}
```

This runs automatically on app appearance.

There are three problems.

## Problem A --- welcome state is hidden in Debug

The actual empty-project experience cannot naturally be tested because
DEBUG immediately replaces it with the demo.

## Problem B --- Finder/project-open timing

If a real show is opened at launch and happens to have zero fixtures, or
app/open timing races with `onAppear`, the Debug demo can replace
legitimate state.

## Problem C --- the demo is configured for Art-Net

`demoSummerNight()` creates:

``` swift
protocolHint: .artNet
```

`OutputController` persists whether Art-Net is enabled.

A developer who previously enabled Art-Net can launch a DEBUG build,
auto-load the demo, and potentially begin routing demo output toward a
real Art-Net destination.

That is not a safe demo default.

## Required fix

Remove automatic demo loading.

Keep:

``` text
File -> Open Demo Show
Welcome -> Open Demo Show
```

If auto-load remains useful for screenshot automation, gate it behind an
explicit launch argument:

``` text
--load-demo-show
```

or a development-only environment variable.

## Demo routing

Default demo universe routing should preferably be:

``` text
.none
```

unless the operator explicitly chooses to test network output.

A visual demo should never surprise-send Art-Net.

------------------------------------------------------------------------

# 14. P1 --- Settings Frame-Rate Slider Reconfigures/Restarts the Engine on Every Drag Tick

**Files:**

-   `Sources/Aurora/Settings/AuroraSettingsRoot.swift`
-   `Sources/Aurora/AppModel.swift`
-   `Sources/AuroraEngine/LightingEngine.swift`

The Settings slider calls:

``` swift
appModel.setPreferredFrameRateHz($0)
```

for each slider value update.

`applyPreferredFrameRate()` calls:

``` swift
engine.updateConfiguration(config)
```

and `LightingEngine.updateConfiguration()` does:

``` text
if running:
    stop()
    start()
```

Therefore dragging the Settings slider can repeatedly stop/start the
engine.

This is unnecessary and can cause output/timing disruption.

## Required fix

Do not commit engine configuration on every slider tick.

Options:

-   stepper / popup with discrete values
-   local `@State` while dragging and Apply on end
-   debounce
-   slider editing callback committing only when editing ends

Recommended values can remain 20...44 if that is the engine contract.

## UX

Clearly label that frame-rate changes affect the running engine.

------------------------------------------------------------------------

# 15. P1 --- Perform Health Indicators Are Inconsistent / Partly Fabricated

**Files:**

-   `AuroraBuildToolbar.swift`
-   `AuroraAppStatusBar.swift`
-   `PerformWorkspaceShell.swift`

Health mapping is duplicated in multiple views and differs.

## MIDI inconsistency

Toolbar:

``` text
error -> warning
off   -> disabled
else  -> healthy
```

Perform / bottom status:

``` text
off   -> disabled
else  -> healthy
```

Therefore an actual MIDI error can display as healthy in Perform.

## Network issue

Perform hard-codes:

``` swift
AuroraStatusIndicator(label: "Network", level: .disabled)
```

regardless of Art-Net, sACN, RTP-MIDI, remote server, or OSC state.

This is not truthful.

## Required fix

Centralize health presentation mapping.

Example:

``` swift
struct AuroraShellHealthSnapshot {
    var engine: AuroraHealthLevel
    var output: AuroraHealthLevel
    var midi: AuroraHealthLevel
    var network: AuroraHealthLevel?
}
```

If Aurora does not yet have a meaningful aggregate Network-health
contract:

> omit the Network indicator

rather than permanently displaying disabled.

One semantic state should render the same way in Build toolbar, status
bar, and Perform.

------------------------------------------------------------------------

# 16. P1/P2 --- UI-02 Removed Existing Functional Workflows

The visual rewrite simplified several existing panels by deleting
functionality.

Some simplification is reasonable because UI-03/04/05 will deepen these
surfaces, but the loss must be explicit and assigned.

Do not let useful backend features silently disappear from the product.

------------------------------------------------------------------------

# 17. Functional Regression --- Cue List

## Previous functionality

The prior Cue List supported:

-   Add Cue List
-   Add Cue
-   Delete Cue
-   select cue without firing
-   publish cue/cue-list selection
-   edit cue name
-   edit fade-in
-   edit delay
-   Apply edits
-   explicit Fire button

## Current functionality

The new panel primarily supports:

-   transport
-   displaying cues
-   clicking row to fire

Most editing functionality has disappeared.

## Recommendation

Because full Cue workflow is UI-05, do **not** rebuild the entire old
stock editor inside UI-02.

But before closing UI-02:

-   fix unsafe click-to-fire
-   restore correct cue/list selection state
-   provide a minimal intentional way to create a cue list/cue if the
    show is empty, OR explicitly track this as UI-05 required
    restoration

The UI-05 plan must explicitly own:

``` text
Add List
Add Cue
Delete Cue
Cue properties editing
record/update
explicit Fire
```

No feature should simply vanish because its old UI was ugly.

------------------------------------------------------------------------

# 18. Functional Regression --- Palettes / Presets

## Previous functionality

The prior palette UI supported:

-   New Color from Programmer
-   New Preset from Programmer
-   Apply
-   Record Ref to Cue
-   Delete Palette
-   Delete Preset / related management

## Current functionality

The new shelf supports visual application and inspection, but not
creation/deletion/reference recording.

## Recommendation

UI-04 is the natural owner for the full restoration.

Before UI-03 begins, update the UI roadmap/handoff so UI-04 explicitly
includes:

``` text
Create palette from Programmer
Create preset/look from Programmer
Delete
Rename/edit
Record palette reference to cue
Reference semantics
```

Do not reintroduce the old generic controls merely to check a box in
UI-02.

Track the functionality so it cannot be forgotten.

------------------------------------------------------------------------

# 19. Functional Regression --- Programmer

## Previous functionality

The prior Programmer exposed:

-   Locate
-   Home
-   Clear selection
-   Clear all
-   Fan
-   Align
-   direct RGB/W sliders
-   Pan
-   Tilt
-   HSV

## Current functionality

The redesign currently exposes:

-   Locate
-   Home
-   Clear selected
-   intensity
-   position pad
-   color wheel
-   selected fixture chips

Missing:

-   Clear All
-   Fan
-   Align
-   explicit RGB/W technical control

## Recommendation

These belong naturally to UI-03, which is specifically the Browser +
Programmer deepening phase.

The UI-03 acceptance criteria should explicitly include a decision for
each prior function:

``` text
restore
replace with better interaction
move to Inspector/context menu
intentionally retire with documented reason
```

Do not accidentally lose fan/align functionality.

------------------------------------------------------------------------

# 20. P2 --- Broad AppModel Invalidation Remains Expensive

**Files:**

-   `Sources/Aurora/AppModel.swift`
-   shell views using `@EnvironmentObject AppModel`

`AppModel` subscribes to all child controller `objectWillChange`
publishers and re-emits:

``` swift
self?.objectWillChange.send()
```

`ShowControlController` refreshes presentation state every 0.25 seconds.

Therefore a regular 4 Hz performance-status update can invalidate any
view observing the broad `AppModel`, including the entire Build shell.

Additionally, many controller methods manually call
`objectWillChange.send()` despite mutating `@Published` properties, and
many app methods call `notifyUI()` afterward.

This can produce redundant renders.

UI-03 is about to add:

-   larger selections
-   richer Programmer controls
-   mixed-state resolution
-   fixture capability analysis

The broad invalidation model will become more expensive.

## Recommendation

Before or during early UI-03, reduce high-frequency shell coupling.

Examples:

``` text
Toolbar -> focused shell presentation store
Perform -> PerformanceSnapshot observable store
Settings -> AppSettingsStore / specific controllers
Workspace -> WorkspaceController
```

Do not perform another architecture rewrite.

Incrementally stop making every status tick invalidate every product
panel.

## Also remove redundant sends

Where an `@Published` assignment already emits change, do not
immediately send `objectWillChange` again unless there is a specific
reason.

------------------------------------------------------------------------

# 21. P2 --- `PanelRegistry` Still Carries Broad AppModel Coupling

`PanelRegistry.view(...)` accepts:

``` swift
appModel: AppModel
```

and performs many cross-controller bindings.

This is transitional and was allowed during UI-02, but it means Option A
is not really complete.

The panel contract correctly says focused dependencies are preferred.

## Recommendation

Do not block UI-03 on a complete rewrite.

Instead, as each panel is redesigned:

``` text
UI-03 Programmer/Browser -> focused inputs
UI-04 Palettes -> focused inputs
UI-05 Cues -> focused inputs
UI-06 Songs -> focused inputs
```

Retire corresponding `AppModel`-wide registry branches progressively.

Track this as an architectural migration, not a one-shot refactor.

------------------------------------------------------------------------

# 22. P2 --- Settings Output Scope Is Misleading

**File:** `Sources/Aurora/Settings/AuroraSettingsRoot.swift`

The Output page begins with:

``` text
APPLICATION
```

but also tells the user:

> Network output is configured from the show's universe protocol hints.

Universe routing is project/show state.

The current page therefore mixes application-global output driver
configuration with project-level output routing under one scope header.

## Required fix

Split the grammar.

Example:

``` text
APPLICATION
Driver availability / destination defaults / local device preferences

PROJECT
Universe routing / protocol hints
```

Even if UI-09 will eventually redesign Output Settings, UI-02 should not
establish a misleading scope convention.

------------------------------------------------------------------------

# 23. P2 --- Settings Uses Silent `try?` for Destructive MIDI Mapping Changes

**File:** `Sources/Aurora/Settings/AuroraSettingsRoot.swift`

Deleting a MIDI mapping uses:

``` swift
try? session.perform(...)
```

If the command fails, the UI provides no feedback.

Other new UI panels use similar silent `try?` operations.

## Recommendation

Use a shared UI command/error helper or explicit `do/catch`.

At minimum:

-   log the error
-   display a lightweight status/error message
-   do not silently pretend the delete succeeded

This becomes more important as Settings moves more project mutation into
polished surfaces.

------------------------------------------------------------------------

# 24. P2 --- "Deterministic" Demo Still Uses Random Cue IDs

**File:** `Sources/AuroraModel/ShowProject+DemoSummerNight.swift`

The demo correctly uses fixed IDs for most entities, but cue creation
uses:

``` swift
id: UUID()
```

The demo therefore is not fully deterministic.

Song entries reference the newly generated IDs correctly within one
invocation, so this does not break runtime behavior.

However, stable fixture/cue IDs are useful for:

-   screenshot automation
-   repeatable UI tests
-   serialized demo comparisons
-   deterministic selection state
-   integration testing

## Recommendation

Assign fixed cue UUIDs too.

------------------------------------------------------------------------

# 25. P2 --- DEBUG Auto-Demo Hides Welcome-State Testing

Even apart from the output-safety concern, automatic demo loading means
the new UI-02G welcome experience is not naturally exercised during
normal Debug launches.

Since `Open Demo Show` now exists explicitly:

> remove implicit demo loading.

This makes both empty-state and demo-state development easier to test
intentionally.

------------------------------------------------------------------------

# 26. P2 --- WorkspaceController Emits Redundant Change Notifications

`WorkspaceController` uses `@Published` properties and also calls:

``` swift
objectWillChange.send()
```

after assigning them.

Example:

``` swift
mode = ...
objectWillChange.send()
```

`@Published` already emits.

The same pattern appears in other controllers.

## Recommendation

Remove duplicate manual sends unless a method mutates non-published
state that SwiftUI needs to observe.

This is not a correctness blocker, but it contributes to unnecessary
redraws.

------------------------------------------------------------------------

# 27. P2 --- No UI-02 Shell Integration Tests Exist

The portable test suite includes strong engine/model coverage, but there
is little/no automated coverage for:

-   Inspector focus state
-   workspace tool state
-   document-replacement reset
-   Perform presentation resolution
-   dirty-document New/Open workflow
-   mode-aware command availability

UI view pixel tests are not required.

## Recommended tests

### WorkspaceController

``` text
fixture explicit focus
cue focus
document reset
Build tool selection
lower tool selection
mode transition
```

### Performance presentation

``` text
actual cue number != array index
song next target in same list
song next target in another list
song non-adjacent next cue
```

### Dirty-document flow

Test an extracted decision coordinator rather than NSAlert itself.

### Cue selection

Test an extracted interaction action:

``` text
select != fire
```

### Settings scope/presentation

Pure model tests where practical.

A small Xcode app integration test target would now be useful, but it
does not need to become a large UI-test suite.

------------------------------------------------------------------------

# 28. UI-03 Gate --- What Must Be Fixed First

I would not hold UI-03 for every P2 item.

I **would** fix these before UI-03:

``` text
P0
[ ] Cue row selection no longer fires cue
[ ] Transport shortcuts cannot trigger while ordinary text editing owns focus

P1
[ ] Perform toolbar/menu does not expose casual structural editing
[ ] Perform Current/Next is truthful
[ ] Cue Inspector CURRENT checks active list/cue
[ ] Explicit fixture click updates Inspector focus
[ ] New/Open/document replacement resets stale UI state
[ ] CueList stale selectedListID self-heals
[ ] View menu no longer toggles dead panel visibility state
[ ] Save-before-New/Open awaits save correctly
[ ] DEBUG demo auto-load removed or explicitly gated
[ ] Demo does not surprise-route Art-Net
[ ] Frame-rate Settings does not restart engine on every slider tick
[ ] Shell health mapping is centralized/truthful
```

Then explicitly assign restoration items:

``` text
UI-03
- Programmer Fan/Align/Clear-All/technical controls

UI-04
- Palette/preset create/delete/edit/reference recording

UI-05
- Cue list create/delete/edit/record/update/fire workflow
```

Once that is documented, UI-03 can proceed.

------------------------------------------------------------------------

# 29. What I Would Not Change

Do **not** throw away the UI-02 shell.

Preserve:

``` text
ContentView
  -> AuroraBuildToolbar
  -> BuildWorkspaceHost / PerformWorkspaceShell
  -> AuroraAppStatusBar
```

Preserve:

-   Option A Build layout
-   Programmer as center of gravity
-   explicit Inspector focus concept
-   native Settings scene
-   app/project scope grammar
-   panel hosting contract
-   custom Aurora icon system
-   new visual design system
-   Build/Perform separation
-   deterministic demo concept
-   focused future docking direction

The issues in this review are behavior/integration problems, not
evidence that the shell architecture is wrong.

------------------------------------------------------------------------

# 30. Recommended Fix Order

## Wave A --- Show-control safety

1.  Separate cue selection from firing.
2.  Make transport shortcuts text-focus safe.
3.  Make Perform toolbar/menu safe.
4.  Fix Perform Current/Next truthfulness.
5.  Fix Cue Inspector CURRENT semantics.

## Wave B --- Shell state correctness

6.  Explicit fixture click -\> Inspector fixture focus.
7.  Reset Inspector/tool-local state on document replacement.
8.  Make CueList selection self-heal across project changes.
9.  Remove dead View-menu panel toggles.
10. Fix Save-before-New/Open async continuation.

## Wave C --- Operational polish

11. Remove/gate DEBUG demo auto-load.
12. Make demo output route safe by default.
13. Stop frame-rate slider from repeatedly restarting engine.
14. Centralize health presentation.
15. Correct Settings output scope.

## Wave D --- Performance/maintainability

16. Remove redundant objectWillChange sends.
17. Begin focused observation migration.
18. Add shell/controller tests.
19. Make demo cue IDs fully deterministic.
20. Replace silent `try?` mutation failures.

## Wave E --- Phase ownership

21. Update UI roadmap with removed-function restoration:
    -   UI-03 Programmer
    -   UI-04 Palettes
    -   UI-05 Cue workflow

Then run shell review again.

------------------------------------------------------------------------

# 31. Required Regression Tests

At minimum add tests or testable extracted logic covering:

``` text
Cue click:
    inspect only
    no fire

Fire command:
    explicit fire

Perform cue number:
    uses Cue.number, not index + 1

Song next:
    non-adjacent cue
    different cue list

Inspector current:
    same index, wrong list -> not CURRENT

Inspector fixture intent:
    cue focused -> user clicks fixture -> fixture Inspector

Document replacement:
    stale cue focus -> reset
    stale cue-list selection -> valid first list

Dirty New/Open:
    choose Save
    await successful save
    operation continues exactly once

Health:
    MIDI error -> warning everywhere
    no fake Network disabled state

Demo:
    explicit load only
    no live Art-Net route by default
```

------------------------------------------------------------------------

# 32. macOS Manual Verification Checklist

After fixes, verify on a Mac:

``` text
[ ] Debug build succeeds
[ ] Release build succeeds
[ ] full tests pass

[ ] Click cue row -> only selects/inspects
[ ] GO explicitly fires cue

[ ] Type spaces/Return/Left/B in editable text -> no transport accident
[ ] transport shortcuts work when not editing

[ ] switch Build -> Perform
[ ] New/Open structural toolbar actions are absent/disabled
[ ] Current cue number matches real cue number
[ ] Next cue matches Song target
[ ] MIDI error health is consistent

[ ] inspect cue, then click fixture -> Inspector becomes fixture
[ ] open new show -> Inspector does not show stale old IDs
[ ] open different show -> Cue List selects a valid list

[ ] dirty project -> New -> Save -> New continues after save
[ ] dirty project -> Open -> Save -> Open continues after save

[ ] View menu contains only commands that visibly work

[ ] Debug launch does not unexpectedly replace project with demo
[ ] demo does not emit Art-Net without explicit operator intent

[ ] dragging/changing preferred frame rate does not repeatedly restart engine

[ ] Welcome screen can be tested in Debug
```

------------------------------------------------------------------------

# 33. Final Recommendation

Aurora UI-02 is **not a failed phase**.

It is a successful shell implementation that uncovered exactly the kinds
of cross-cutting interaction problems a shell phase is supposed to
uncover.

The architecture is good enough to keep.

The next action should not be another redesign.

It should be a focused shell-hardening pass.

When the P0/P1 list is clean and the removed-function restoration is
explicitly assigned to UI-03/04/05, close UI-02 and proceed.

The next milestone should then be:

> **UI-03 --- make Fixture Browser + Programmer exceptional without
> destabilizing the shell.**
