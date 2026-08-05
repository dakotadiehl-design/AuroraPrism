# Aurora Post-UI-02 Deep Review
## Final Shell Gate and Recommended Fixes Before UI-03

**Review target:** `Aurora_PostUI2.zip`  
**Review purpose:** Verify UI-02 hardening, identify any remaining blockers, and decide whether Aurora can proceed to UI-03.  
**Verdict:** **Conditional GO for UI-03 after a very small closeout pass.**

---

# 1. Executive Summary

Aurora's UI-02 hardening pass was successful.

The architecture introduced during UI-02 is worth keeping:

- Build and Perform remain cleanly separated presentation modes.
- The new production shell remains the real launch path.
- Programmer remains the Build workspace center of gravity.
- Contextual Inspector focus exists independently of fixture selection.
- Native macOS Settings exists and has a sensible app/project scope grammar.
- Cue single-click and double-click semantics are separated.
- Current/Next presentation now uses real cue identity instead of index-as-number.
- Shell health presentation is centralized.
- Debug demo loading is explicit rather than automatic.
- Demo output routing defaults to `.none`.
- Document replacement has a UI reset epoch.
- View-menu commands now correspond to visible production behavior.
- Deferred functionality removed during visual redesign is explicitly owned by UI-03/04/05.

I do **not** recommend another UI-02 redesign or another broad shell-remediation cycle.

There are, however, three items I recommend completing before UI-03 begins:

1. **Fix live cue identity when cue lists are edited or removed.**
2. **Remove the obsolete synchronous dirty-document API that still contains the old broken workflow.**
3. **Create a clean UI-02 checkpoint commit/tag and reconcile stale historical-document references.**

After those items, proceed to UI-03.

Everything else in this review should either be carried directly into UI-03 or tracked for later phases.

---

# 2. Repository Size at This Gate

Aurora has now grown to approximately:

```text
Production Swift files: 203
Test Swift files:        58
Total Swift files:       261

Production Swift LOC:    20,559
Test Swift LOC:           5,234
--------------------------------
Total Swift/Test LOC:    25,793
```

The repository contains approximately **275 XCTest test methods**.

This is now a substantial application, not a small prototype.

---

# 3. Verification Performed

The review covered:

- `ContentView`
- Build/Perform shell
- `AuroraBuildToolbar`
- `AuroraAppStatusBar`
- keyboard-command gating
- `BuildWorkspaceHost`
- `WorkspaceController`
- contextual Inspector
- Cue List interactions
- Fixture Browser interactions
- Programmer state
- Palettes
- Groups
- Songs
- Settings
- document lifecycle
- dirty-document save flow
- performance snapshots
- `PerformanceCueSummary`
- playback update behavior
- demo show
- output routing defaults
- shell health mapping
- remote presentation path
- panel-hosting contract
- UI roadmap ownership
- asset catalog structure
- Xcode project/package composition
- current git/worktree state
- test inventory

## Linux build limitation

`swift test` was attempted.

The build successfully reached the portable Aurora modules and then stopped at the expected Apple-only dependencies:

```text
CoreMIDI
Network
```

This remains an environment limitation of the Linux review container, not an Aurora regression.

Portable targets verified successfully here include:

```text
AuroraModel
AuroraFixtureLib
AuroraDiagnostics
```

All changed/untracked Swift source files were syntax-parsed successfully, excluding the intentionally deleted legacy `WorkspaceView.swift`.

The repository handoff records:

```text
275 tests passing on macOS
Xcode Debug build green
```

That macOS result should remain the final authoritative machine check before UI-03.

---

# 4. What Was Successfully Fixed From the Previous Review

## 4.1 Cue single-click no longer fires

The new Cue List behavior is correctly separated:

```text
single click
    -> select
    -> Inspector focus
    -> no fire

double click
    -> select
    -> fire
```

Context-menu Fire also remains explicit.

This matches the intended Aurora/LightKey-style workflow.

---

## 4.2 Cue/list selection is again synchronized

`CueListPanel.selectCue()` now updates:

```text
selected cue ID
selected cue-list ID
DocumentSession SelectionManager
Inspector focus
```

This restores important cross-panel state that disappeared during the first visual rewrite.

---

## 4.3 Keyboard transport has a centralized editing gate

`KeyboardCommandGate` now recognizes:

- `NSTextView`
- `NSText`
- `NSTextField`
- SwiftUI/AppKit field-editor-style responders

Playback commands dynamically re-check text-editing state before dispatch.

This is much safer than per-field keyboard exceptions.

Manual macOS verification is still required because first-responder behavior is inherently platform/runtime-specific.

---

## 4.4 Perform toolbar/menu is safer

Perform Mode now removes structural File commands such as:

- New
- Open
- Import Fixture

Undo/Redo is disabled in Perform.

The toolbar similarly hides New/Open.

Save remains intentionally available.

This is a good UI-02 safety boundary without prematurely implementing full Show Lock.

---

## 4.5 PerformanceCueSummary is now a real contract

This was the right fix.

Aurora now has a presentation type carrying:

```text
listID
cueID
real Decimal cue number
cue name
section label
```

Perform Mode renders the semantic presentation object rather than inventing cue identity from:

```text
cueIndex + 1
```

The included tests correctly cover:

- non-integer cue numbers such as 1.5
- non-adjacent Song targets
- Song targets in another cue list
- CURRENT list identity

This contract will be valuable later for:

- UI-07 Perform
- UI-10 remote
- Song Mode
- diagnostics
- status surfaces

---

## 4.6 Inspector CURRENT is substantially corrected

Inspector now prefers exact playback cue ID and otherwise checks:

```text
playback list ID
+
cue index
```

This removes the prior case where identical indexes in different cue lists could both appear CURRENT.

---

## 4.7 Explicit fixture click now changes Inspector intent

The browser now distinguishes:

```text
programmatic fixture selection change
```

from:

```text
user explicitly clicked fixture(s)
```

An explicit fixture click correctly takes Inspector focus away from stale cue/group/palette context.

This is exactly why explicit Inspector focus was worth adding.

---

## 4.8 Document replacement reset exists

`WorkspaceController.didReplaceDocument()` now resets:

```text
Inspector focus -> project
left tool       -> browser
lower tool      -> cues
document epoch  -> increment
```

Cue List listens for the document epoch and heals stale local list/cue state.

This is a meaningful improvement over relying on SwiftUI view remount behavior.

---

## 4.9 Dirty-document Save/New/Open flow now awaits

New/Open/Demo now use an asynchronous decision path:

```text
Save
Discard
Cancel
```

and await save before continuing.

The previous "save finishes, but requested operation cancels because dirty was checked too soon" bug is no longer present in the active AppModel flow.

---

## 4.10 Dead View-menu panel toggles are gone

The View menu now exposes actions that the current shell actually understands:

```text
Build
Perform

Browser
Patch
Groups

Palettes
Cues
Song
```

It no longer presents the legacy panel-visibility model as if it controlled the new production workspace.

This is much more truthful.

---

## 4.11 Demo behavior is safer

Debug builds no longer automatically replace the current document with the demo.

The demo is explicit via:

```text
Open Demo Show
--load-demo-show
```

The demo universe also now uses:

```text
protocolHint: .none
```

rather than Art-Net.

The demo cannot surprise-send Art-Net merely because the developer previously enabled a network output driver.

Cue IDs are now deterministic as well.

---

## 4.12 Frame-rate Settings no longer restart on every slider tick

Settings maintains a draft value and commits the real frame-rate update only when editing ends.

This avoids repeated engine stop/start cycles while dragging.

Good fix.

---

## 4.13 Shell health mapping is centralized

Build toolbar, bottom status, and Perform now derive health from one shared semantic mapping.

MIDI error state is no longer interpreted differently by different screens.

The unimplemented aggregate Network status is omitted rather than fabricated.

This follows Aurora's "UI must tell the truth" rule.

---

# 5. MUST FIX Before UI-03 — Stable Playback Cue Identity During Live Edits

This is the one substantive runtime issue I recommend fixing before proceeding.

## Files

```text
Sources/AuroraEngine/PlaybackController.swift
Sources/AuroraEngine/PerformanceCuePresentation.swift
```

---

## 5.1 PlaybackController preserves index, not cue identity

`PlaybackController.updateProject()` currently updates the active cue list while preserving:

```text
index
```

rather than:

```text
active cue UUID
```

That is unsafe once cue editing becomes richer.

### Example

Current live list:

```text
index 0 -> Cue 1
index 1 -> Cue 2
index 2 -> Cue 3   <- currently active
```

User inserts a cue before Cue 3:

```text
index 0 -> Cue 1
index 1 -> New Cue
index 2 -> Cue 2
index 3 -> Cue 3
```

If Aurora merely preserves:

```text
index = 2
```

then the semantic CURRENT cue silently changes from Cue 3 to Cue 2.

Stable UUID identity should win.

This is especially important because Aurora deliberately gave cues stable IDs for exactly this reason.

---

## Required behavior

Before replacing the cue list, capture the currently active cue ID when available.

After project update:

### If the active list still exists and active cue ID still exists

Re-find the cue by ID:

```text
new index = updatedList.index(of activeCueID)
```

Preserve that semantic cue.

### If the active list exists but active cue was deleted

Do not silently substitute another cue at the old index.

Recommended safe behavior:

```text
keep current stage look
set playback cue index -> -1
set phase -> idle
clear follow/loop state
keep updated list loaded
```

Then the next manual GO behavior should be explicitly documented.

### If the active cue list was deleted

Recommended:

```text
keep current stage look
detach playback list
index -> -1
phase -> idle
clear follow/loop state
```

Do not keep a stale active index.

---

# 6. MUST FIX Before UI-03 — Performance Resolver Must Never Fall Back to an Unrelated First Cue List

`PerformanceCuePresentation.resolveCues()` currently contains logic equivalent to:

```swift
project.cueLists.first(where: { $0.id == playback.listID })
    ?? project.cueLists.first
```

for CURRENT resolution.

That fallback can produce a plausible but incorrect CURRENT cue.

## Failure scenario

Playback snapshot is temporarily:

```text
listID = deleted/stale list
cueIndex = 2
```

New project/list state contains:

```text
first list -> cue index 2 = "Chorus"
```

Aurora can show:

```text
CURRENT
Cue 3
Chorus
```

even though the actual playback list no longer exists.

A professional control UI should prefer:

```text
unknown / unavailable
```

over a convincing lie.

---

## Required resolution rule

Prefer semantic identity in this order:

```text
1. playback cueID + playback listID
2. playback cueID lookup by stable ID if appropriate
3. playback listID + valid cue index
4. playback textual cueName fallback with no fabricated number
5. empty/unknown
```

Never resolve CURRENT from an arbitrary first cue list merely because one exists.

---

## Required tests

Add tests for:

```text
active cue list removed
    -> no unrelated current cue

active cue moved to another index in same list
    -> same cue ID remains CURRENT

cue inserted before current cue
    -> current cue identity preserved

active cue deleted
    -> no substitute cue silently becomes CURRENT

stale playback list ID + valid index in another list
    -> presentation does not use the unrelated list
```

This is a small but important identity/truthfulness repair.

---

# 7. MUST CLEAN UP Before UI-03 — Remove the Obsolete Synchronous Dirty-Document API

**File:**

```text
Sources/Aurora/Controllers/ProjectController.swift
```

The old method still exists:

```swift
confirmDiscardIfDirty(actionName:save:)
```

Its own comment correctly says it is legacy.

It also still contains the old broken pattern:

```text
start save
immediately check dirty state
```

There are currently no call sites.

That makes this an ideal time to delete it.

Leaving a known-broken but callable API in the codebase is an invitation for a future agent to accidentally reuse it.

Keep only the async prompt/save continuation path.

---

# 8. MUST DO Before UI-03 — Create a Clean UI-02 Git Checkpoint

The supplied repository currently has the entire UI era represented as a large uncommitted working tree on top of the old backend HEAD.

`git status` contains:

- modified app sources
- modified UI sources
- deleted legacy workspace
- new Settings
- new Shell
- new design system
- new tests
- new assets
- updated docs
- generated Xcode project changes

This is too large a delta to carry directly into UI-03 without a checkpoint.

## Recommendation

After the remaining identity fixes:

```text
1. run macOS tests
2. run Xcode Debug build
3. inspect git diff
4. commit all intended UI-01/UI-02 work
5. create a clear checkpoint/tag
```

Suggested commit:

```text
UI-02 complete: hardened Aurora application shell
```

Optional tag:

```text
ui-02-complete
```

Then begin UI-03 from a clean tree.

This will make future regression analysis dramatically easier.

---

# 9. Documentation Hygiene Before Checkpoint

`docs/PROJECT_HANDOFF.md` still references several historical root-level review Markdown files as historical documents, while those files are currently deleted from the working tree.

Choose one policy.

## Option A — Preserve review history

Move historical reviews into:

```text
docs/history/
```

or:

```text
UIDesignReferences/history/
```

and update references.

## Option B — Remove them intentionally

Delete stale references from the handoff.

Do not leave documentation pointing to files that no longer exist.

Also run:

```bash
git diff --check
```

The current diff reports trailing whitespace in `PROJECT_HANDOFF.md`.

This is cosmetic but easy to clean before the UI-02 checkpoint.

---

# 10. UI-03 Carry-In — Programmer State Must Become Live/Derived Rather Than First-Fixture @State

This does **not** need to delay UI-03.

It should become an explicit UI-03 requirement.

`ProgrammerPanel` currently stores local UI state such as:

```text
intensity
RGB/W
pan
tilt
HSV
```

and reloads primarily on:

```text
onAppear
fixture selection change
```

This has two limitations.

---

## 10.1 External Programmer changes can leave controls visually stale

Example:

```text
selected fixtures stay the same
MIDI CC changes intensity
Programmer changes
AppModel refreshes
local @State intensity remains old
```

The real lighting output changes while the onscreen fader can remain stale.

UI-03 should establish a proper Programmer presentation/state layer so UI controls reflect:

- mouse edits
- MIDI edits
- palette application
- Locate/Home
- other future control sources

without relying on reselecting fixtures.

---

## 10.2 First fixture does not represent multi-selection

`loadFromProgrammer()` currently uses:

```text
first selected fixture
```

to populate values.

That is explicitly insufficient for UI-03's mixed-state semantics.

UI-03 needs derived states such as:

```text
common(value)
mixed
unset
unsupported
partially supported
```

This is already conceptually in the UI roadmap and should now be implemented properly.

---

# 11. UI-03 Carry-In — Preserve Ordered Fixture Selection

Aurora intentionally maintains:

```text
orderedFixtureIDs
```

for phase-sensitive operations such as Fan.

Some newer UI paths still convert fixture IDs into an unordered `Set`.

Example:

```text
GroupsPanel -> Select
```

uses a Set-based fixture selection path.

UI-03 should normalize fixture/group selection around ordered selection where ordering matters.

Recommended:

```text
group.fixtureIds
    -> selectFixturesOrdered(...)
```

This becomes important as soon as Fan/Align is restored.

---

# 12. UI-03 Carry-In — Broad AppModel Invalidation Still Exists

`AppModel` still forwards every child controller's:

```text
objectWillChange
```

through its own `objectWillChange`.

`ShowControlController` refreshes performance presentation approximately every:

```text
0.25 seconds
```

Therefore broad views observing `AppModel` may refresh at roughly 4 Hz even when the specific panel data they care about has not changed.

This was acceptable while the UI was smaller.

UI-03 will add:

- multi-fixture capability analysis
- mixed Programmer state
- richer Programmer controls
- ~80 fixture selection acceptance
- more derived state

That is where broad invalidation may start becoming expensive.

## Recommendation for UI-03

Do not perform a giant observation rewrite.

Instead, introduce focused presentation stores while deepening the affected surfaces.

Examples:

```text
Programmer presentation store
Fixture Browser presentation store
Performance snapshot store
Workspace controller
Settings store
```

The UI-03 performance acceptance should include a large-selection test.

---

# 13. UI-03 Carry-In — Restore Programmer Functionality Intentionally

The roadmap correctly records the features temporarily lost during the visual redesign.

UI-03 owns explicit decisions for:

```text
Clear All
Fan
Align
technical RGB/W
```

For each one, choose:

```text
restore directly
replace with better interaction
move to Inspector/context menu
intentionally retire with documented reason
```

Do not silently omit Fan/Align.

They are especially relevant to moving-head and multi-fixture programming.

---

# 14. Later Phase — Cue List Interaction Test Is a Contract Test, Not a Real Gesture Test

`CueListInteractionTests` correctly documents:

```text
select != fire
```

but it does not actually exercise SwiftUI's combined single/double-click recognizers.

This is acceptable for portable logic testing, but macOS manual verification should remain explicit:

```text
single click -> select only
double click -> fire exactly once
```

Verify this with the real application before the UI-02 checkpoint.

If gesture behavior ever becomes unreliable, prefer a macOS-specific gesture implementation rather than weakening the intended double-click workflow.

---

# 15. Later Phase — Remote Still Uses Legacy Cue-Index Presentation

The macOS Perform shell now has truthful cue identity.

The existing remote protocol/web view still uses:

```text
cueIndex
cueIndex + 1
```

and its snapshot builder retains some first-list fallback behavior.

This does not need to block UI-03.

Assign it explicitly to:

```text
UI-10 Web / iPad Remote
```

At that point, the remote should consume the same semantic cue presentation concepts as Mac Perform.

Avoid creating a second competing definition of CURRENT/NEXT.

---

# 16. Later Cleanup — ShowControl `engineStatus` Still Uses Index-Based Cue Text

`ShowControlController.refreshEngineStatus()` still formats:

```text
cue \(cueIndex + 1)
```

inside the legacy `engineStatus` string.

The polished shell no longer appears to rely on this value.

Either:

- update it to use semantic cue identity, or
- simplify it to frame/phase status without claiming a cue number.

This is not a UI-03 blocker, but it should not remain as a misleading diagnostic string indefinitely.

---

# 17. Later Cleanup — Remaining Silent `try?` UI Mutations

Several older panels still contain silent project-mutation failures, including areas such as:

```text
SongPanel
GroupsPanel
MIDIMappingsPanel
```

These are mostly panels scheduled for deeper redesign in later UI phases.

Do not derail UI-03 to rewrite all of them.

As each panel is redesigned, replace silent mutation failure with:

```text
do/catch
diagnostic logging
operator-visible lightweight error state where appropriate
```

---

# 18. Later Cleanup — PanelRegistry Still Carries Broad AppModel Coupling

`PanelRegistry` remains a transitional bridge accepting:

```text
appModel: AppModel
```

This is known and documented.

Do not block UI-03 on a complete registry rewrite.

Instead, retire broad bindings progressively:

```text
UI-03 Browser / Programmer
UI-04 Palettes
UI-05 Cues
UI-06 Songs
```

The panel-hosting contract is sound; continue migrating toward it.

---

# 19. Suggested Final UI-02 Closeout Sequence

## Step 1 — Playback identity

Fix:

```text
PlaybackController.updateProject
PerformanceCuePresentation fallback
```

Add stable-ID tests.

## Step 2 — Remove dead dirty-document API

Delete:

```text
ProjectController.confirmDiscardIfDirty(actionName:save:)
```

Keep async flow only.

## Step 3 — macOS manual verification

Verify:

```text
single-click cue -> select only
double-click cue -> fire once

text editing -> no transport shortcut accident

Build -> Perform -> Build -> playback unchanged

Current/Next -> real cue identity

Open/New/Demo -> no stale Inspector or cue-list state

frame-rate slider -> update only on release

demo -> no network routing
```

## Step 4 — machine verification on Mac

Run:

```bash
swift test
xcodebuild -project Aurora.xcodeproj \
  -scheme Aurora \
  -destination 'platform=macOS' \
  -configuration Debug \
  CODE_SIGN_IDENTITY="-" build
```

The project handoff currently records:

```text
275 passing tests
Debug build green
```

Re-run after the final identity fix.

## Step 5 — repository hygiene

- resolve historical review-doc references
- clean trailing whitespace
- inspect `git diff`
- commit UI-02
- optional `ui-02-complete` tag

## Step 6 — proceed to UI-03

---

# 20. UI-03 Go/No-Go Decision

## Current status

```text
Shell architecture:        GO
Build visual system:       GO
Perform shell foundation:  GO
Inspector architecture:    GO
Settings shell:            GO
Document lifecycle:        GO
Cue interaction safety:    GO, pending final macOS gesture check
Performance identity:      SMALL FIX REQUIRED
Repository checkpoint:     REQUIRED
```

## Final verdict

> **Aurora is ready to proceed to UI-03 after the small playback-identity cleanup and UI-02 checkpoint described above.**

There is no justification for another broad UI-02 remediation cycle.

The shell has done its job.

UI-03 should now focus on making:

```text
Fixture Browser
+
Programmer
```

exceptional professional lighting-programming tools.

---

# 21. What Not to Do

Do **not**:

- redesign the shell again
- reopen UI-02A visual identity
- rewrite AppModel wholesale
- rebuild palettes during UI-03
- rebuild cues during UI-03
- redesign the remote during UI-03
- add speculative future features
- postpone UI-03 for cosmetic P2/P3 cleanup

Fix the small identity issue, checkpoint UI-02, and move forward.

---

# 22. Final Recommendation

UI-02 should be considered **functionally successful**.

The hardening work addressed the previously identified operator-safety and shell-truthfulness issues in a disciplined way.

The only remaining issue I consider worth fixing before UI-03 is the stable playback identity edge around cue-list edits/removal, plus removal of the obsolete dirty-document API and repository checkpoint hygiene.

After that:

> **Close UI-02. Start UI-03.**

Aurora is ready for the next phase.
