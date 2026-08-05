# Aurora UI-02 Deep Review Remediation --- Recommended Amendments

**Applies to:** `UI-02 Deep Review Remediation (Shell Hardening)`\
**Disposition:** Approve the remediation plan with the focused
amendments below.

The remediation plan correctly prioritizes show-control safety,
shell-state correctness, operational polish, tests, and explicit
ownership of functionality deferred to UI-03/04/05.

Do not redesign the UI-02 shell during this pass.

------------------------------------------------------------------------

# 1. Keep Double-Click-to-Fire Cue Behavior

Aurora **should support double-clicking a cue row to fire that cue**.

This is an intentional workflow choice inspired by LightKey and is
desirable for Aurora.

The important safety distinction is:

``` text
Single click
    → select cue
    → focus/inspect cue
    → DO NOT fire

Double click
    → intentionally fire that cue
```

Also retain explicit execution mechanisms such as:

-   GO
-   context-menu `Fire Cue`
-   future explicit Fire controls where appropriate

The implementation must ensure that the first click of the double-click
sequence does not itself fire the cue.

Recommended semantic split:

``` swift
selectCue(id)
fireCue(id)
```

The row interaction may map:

``` text
single click  -> selectCue
double click  -> fireCue
```

but the underlying actions must remain separate.

## Required tests

``` text
single click:
    selects cue
    updates Inspector
    does not fire

double click:
    selects/inspects as appropriate
    fires cue exactly once

GO:
    fires through normal transport path
```

Avoid accidental duplicate execution caused by both double-click
handling and another row gesture firing the same cue.

------------------------------------------------------------------------

# 2. Strengthen Keyboard Transport Gating

The centralized keyboard-command gate proposed in A2 is the correct
approach.

Make sure the implementation recognizes macOS field-editor behavior.

In particular, account for:

``` text
NSTextView
NSTextField / field editor
SwiftUI TextField
search fields
numeric/editable fields
```

Do not scatter keyboard-suppression logic through individual controls.

## Acceptance behavior

While editing text or a value:

``` text
Space  -> editing behavior, no GO
Return -> editing/commit behavior, no GO unless explicitly intended
Left   -> cursor/navigation behavior, no BACK
B      -> enters "b", no BACK
Escape -> normal editor behavior where applicable, no accidental STOP
```

When no editable control owns keyboard focus:

``` text
Space / Return -> GO as intentionally defined
Left / B       -> BACK as intentionally defined
Escape         -> STOP as intentionally defined
```

This behavior must be manually verified on macOS.

------------------------------------------------------------------------

# 3. Hide Structural Build Actions in Perform Mode

For A3, prefer **hiding** inappropriate Build actions rather than merely
disabling them.

Perform Mode should feel calm and operationally focused.

Do not leave a row of disabled controls such as:

``` text
New
Open
Import
Structural editing
```

visible in Perform merely because they exist in Build.

Preferred shell concept:

``` text
AuroraShellToolbar
├── BuildToolbarContent
└── PerformToolbarContent
```

Perform should retain only what belongs there, such as:

-   Aurora identity
-   show/project title
-   health/status
-   Build/Perform mode control
-   intentional exit back to Build

Save may remain available if desired.

This is not full Show Lock. That remains later work.

------------------------------------------------------------------------

# 4. Prefer the Full Performance Presentation Contract Now

For A4, implement the proper `PerformanceCueSummary`-style presentation
contract rather than relying on the short-term fallback unless a genuine
architectural blocker is discovered.

Suggested concept:

``` swift
struct PerformanceCueSummary: Equatable, Sendable {
    var listID: UUID?
    var cueID: UUID?
    var number: Decimal?
    var name: String
    var sectionLabel: String?
}
```

Expose semantically resolved:

``` text
currentCue
nextCue
```

through `PerformanceSnapshot` or the appropriate presentation layer.

The view should not infer cue identity from:

``` text
array index + 1
```

and should not independently reconstruct Song Mode targets.

This presentation contract is likely to become useful for:

-   Perform Mode
-   Song Mode
-   future web/iPad remote
-   diagnostics
-   status displays
-   future UI-07 performance cockpit

It is worth establishing correctly now.

------------------------------------------------------------------------

# 5. Document Replacement Must Reset All Document-Scoped UI State

For B2, do not limit `didReplaceDocument()` to Inspector focus.

Audit all UI state whose IDs or meaning belong to the previous show.

A centralized hook should reset or validate items such as:

``` text
Inspector focus
selected cue ID
selected cue-list ID
selected palette ID
selected preset/look ID
selected song/entry focus
group/object focus
tool-local document IDs
cached Inspector object identity
other document-specific selection state
```

Conceptually:

``` swift
workspace.didReplaceDocument(project:)
```

Each panel should also remain defensive and self-heal when an ID
disappears.

Example:

``` text
selected cue list no longer exists
    ↓
fall back to first valid cue list
    ↓
synchronize selectedListID
```

Do not depend solely on SwiftUI view remounting to clear stale document
state.

------------------------------------------------------------------------

# 6. Make Save Success Explicit in Dirty-Document Workflows

For B5, prefer an explicit asynchronous save result rather than
inferring success from:

``` text
session.isDirty
```

The workflow should be deterministic:

``` text
User requests New/Open/Demo/Finder replacement
                  ↓
             Project dirty?
                  ↓
          Save / Discard / Cancel
             ↓       ↓       ↓
          await     continue stop
           save
             ↓
       success/failure
         ↓        ↓
      continue   remain
```

A save API should ideally return a meaningful result such as:

``` swift
enum SaveResult {
    case success
    case cancelled
    case failure(Error)
}
```

or an equivalent project-appropriate type.

Do not start an asynchronous save and immediately infer its completion
from dirty state.

Use the same coordinator for all document replacement paths where
practical.

------------------------------------------------------------------------

# 7. Make Shell Health a Pure Shared Presentation Contract

For C4, centralize shell health mapping into one presentation structure
used everywhere.

Conceptually:

``` swift
struct AuroraShellHealthSnapshot {
    var engine: AuroraHealthLevel
    var output: AuroraHealthLevel
    var midi: AuroraHealthLevel
    var network: AuroraHealthLevel?
}
```

Consumers:

``` text
Build toolbar
Aurora bottom status bar
Perform Mode
```

should all render the same semantic state.

Do not allow each view to independently reinterpret engine/output/MIDI
status.

If Aurora does not yet have a truthful aggregate Network state:

> omit Network.

Do not fabricate a permanently disabled Network indicator.

------------------------------------------------------------------------

# 8. Add Mode-Transition State Preservation Acceptance

Add one explicit shell-level acceptance test/manual verification:

``` text
Build
  ↓
Perform
  ↓
Build
```

must preserve the live show state.

Switching modes is a **presentation change**, not a playback change.

Verify that mode transitions do not unintentionally alter:

``` text
current cue
cue-list position
Song Mode position
selected fixtures where appropriate
engine state
output state
MIDI state
playback state
```

The operator should be able to enter Perform Mode and return to Build
without changing what the lighting engine is doing.

This will become increasingly important as UI-07 deepens Perform Mode.

------------------------------------------------------------------------

# 9. Preserve the Existing Remediation Sequence

The proposed implementation sequence is approved:

``` text
Wave A — Show-control safety

A1  cue single-click select / double-click fire
A2  transport text-focus gate
A3  Perform toolbar/menu safety
A4  truthful PerformanceCueSummary
A5  Inspector CURRENT semantics


Wave B — Shell state correctness

B1  explicit fixture click -> Inspector focus
B2  complete document-state reset
B3  CueList self-heal
B4  View menu cleanup
B5  awaited dirty-document save workflow


Wave C — Operational polish

C1  remove/gate demo auto-load
C2  demo protocolHint .none
C3  frame-rate commit on editing end
C4  centralized health
C5  Settings scope
C6  remove easy silent try? failures
C7  deterministic demo cue IDs


Wave D

tests
roadmap ownership
cheap observation cleanup
macOS verification
```

Do not reorder this into cosmetic work before the show-control safety
items are complete.

------------------------------------------------------------------------

# 10. Deferred Functional Ownership Remains Approved

Do not rebuild these workflows during UI-02 hardening.

Explicitly preserve roadmap ownership:

## UI-03 --- Programmer

Decide how Aurora will restore, replace, or intentionally retire:

``` text
Clear All
Fan
Align
technical RGB/W control
other deeper Programmer workflows
```

## UI-04 --- Palettes / Looks

Restore/deepen:

``` text
create from Programmer
delete
rename/edit
record reference to cue
reference semantics
```

## UI-05 --- Cues

Restore/deepen:

``` text
Add Cue List
Delete Cue List
Add Cue
Delete Cue
edit cue name
fade
delay
record/update
explicit Fire UI
cue workflow
```

Double-click-to-fire may already exist from this hardening pass and
should remain compatible with UI-05.

------------------------------------------------------------------------

# 11. Revised Acceptance Checklist

UI-02 hardening is complete when:

``` text
[ ] Single-click cue selects/inspects and does not fire

[ ] Double-click cue intentionally fires exactly once

[ ] GO remains an explicit transport execution path

[ ] Transport shortcuts cannot trigger accidentally during text/value editing

[ ] Perform Mode hides inappropriate structural Build actions

[ ] Perform Current/Next uses semantically resolved cue identity

[ ] Cue numbers use actual Cue.number values

[ ] Song Mode Next follows the actual Song entry target

[ ] Inspector CURRENT uses correct cue/list identity

[ ] Explicit fixture click changes Inspector focus to fixture context

[ ] Document replacement clears/validates all document-scoped UI state

[ ] Cue List self-heals stale list selection

[ ] View menu exposes only commands that actually affect production UI

[ ] Save-before-New/Open awaits and observes explicit save result

[ ] DEBUG demo is not surprise-loaded

[ ] Demo output routing is safe by default

[ ] Frame-rate editing does not repeatedly restart the engine

[ ] Build / status / Perform health use one shared semantic mapping

[ ] Settings app/project scope remains truthful

[ ] Easy silent mutation failures are surfaced/logged

[ ] Demo cue IDs are deterministic

[ ] Build -> Perform -> Build preserves live show/playback state

[ ] UI-03/04/05 restoration ownership is documented

[ ] macOS swift test passes

[ ] Xcode Debug build passes

[ ] Backend domain semantics remain unchanged
```

------------------------------------------------------------------------

# 12. Final Direction

The remediation plan is approved.

The important behavioral rule for cue rows is:

> **Single click selects. Double click fires.**

That is an intentional Aurora workflow and should be implemented safely
with separate selection and execution actions.

Beyond that, keep this pass disciplined.

Do not redesign the shell.

Do not start UI-03 early.

Do not rebuild full cue, palette, or Programmer workflows.

Harden the UI-02 shell until it is:

``` text
safe
truthful
state-correct
operationally predictable
```

Then run the macOS verification, close UI-02, and proceed to UI-03.
