# Aurora C3.1 Final Closeout Addendum

## Keyboard Scope, Drag Validation, and Stage-Object Interaction Foundation

**Project:** Aurora Lighting Control\
**Phase:** C3.1 Final Closeout\
**Status:** Required before C4\
**Purpose:** Close the remaining C3.1 review findings and prepare the
Stage interaction architecture for C4 without beginning C4 feature work.

------------------------------------------------------------------------

# 1. Executive Summary

The C3.1 implementation successfully established the correct interaction
architecture for:

-   natural Stage camera panning,
-   collapsible lower creative shelf,
-   transient live fixture dragging,
-   single-commit drag operations,
-   multi-fixture movement,
-   zoom-aware drag math,
-   lock-aware movement.

The review found no reason to redesign C3.1. Two closeout items remain
before C4:

1.  **Space-key handling must be scoped to the active Stage interaction
    context.**
2.  **Automated validation should exercise the actual drag/commit
    preparation path rather than merely proving that
    `UpdateStageLayoutCommand` itself supports Undo.**

C3.1 should also establish one forward-looking invariant for C4:

> The transient direct-manipulation model created for fixture dragging
> must be reusable for other Stage objects such as truss, shapes, text,
> and images.

Do not implement the C4 object library in this closeout. Only avoid
hard-coding the interaction layer in a way that prevents C4 from sharing
it.

------------------------------------------------------------------------

# 2. Fix Space-Key Capture Scope

## Problem

The current Stage keyboard monitor uses a local AppKit event monitor for
`.keyDown` and `.keyUp`. Space is recognized by key code and the event
can be returned as `nil`.

A local event monitor returning `nil` consumes the event.

If this monitor is alive whenever `StageCanvasView` exists, Aurora can
accidentally claim Space globally even when the user is interacting with
another part of the application.

Potential failure:

``` text
User clicks a text field
User types: "Front Wash Stage Left"
Result: "FrontWashStageLeft"
```

This is unacceptable.

## Required Rule

> Space belongs to Stage navigation only when the Stage is the active
> interaction surface.

Space must remain available to:

-   text fields,
-   search fields,
-   text editors,
-   naming controls,
-   unrelated keyboard shortcuts,
-   controls outside the active Stage interaction.

## Required Behavior

### When Stage is actively being navigated

In Edit Stage:

``` text
Space held + drag = pan camera
```

The Stage may consume the Space event only when necessary to implement
this interaction.

### When typing/editing text

Space must pass through normally.

At minimum detect text-entry responders such as:

-   `NSTextView`,
-   field editor used by `NSTextField`,
-   `NSSearchField` editing context,
-   other standard AppKit text-entry responders.

Do not maintain a brittle list if a more general
first-responder/text-input check is practical.

### When Stage is not active

Do not consume Space.

Prefer explicit Stage focus/interaction ownership rather than treating
the existence of a Stage view as keyboard ownership.

## Cursor Cleanup

Do not unconditionally force `NSCursor.arrow` on Space release if
another interaction currently owns cursor presentation.

Keep cursor handling local to the Stage pan interaction.

------------------------------------------------------------------------

# 3. Verify Gesture Arbitration

Physically validate these combinations in the production app.

  -----------------------------------------------------------------------
  Context                 Input                   Required result
  ----------------------- ----------------------- -----------------------
  DESIGN                  drag empty Stage        camera pans

  DESIGN                  click fixture           fixture selects

  DESIGN                  drag fixture            no geometry move; no
                                                  accidental pan from
                                                  fixture gesture

  Edit Stage              drag movable fixture    fixture moves live

  Edit Stage              Space + drag empty      camera pans
                          Stage                   

  Edit Stage              Space + drag over       camera pans; fixture
                          fixture                 does not move

  Edit Stage              empty drag without      existing
                          Space                   selection/marquee
                                                  behavior

  Text field active       type Space              normal space character
  -----------------------------------------------------------------------

There must never be a state where the same pointer gesture both moves
fixture geometry and pans the camera.

------------------------------------------------------------------------

# 4. Strengthen Drag Tests

## Existing Weakness

A test that manually modifies `StageLayout`, performs one
`UpdateStageLayoutCommand`, and then checks Undo proves that the command
system works.

It does **not** prove that the C3.1 drag architecture produces one final
mutation from a drag interaction.

## Required Improvement

Extract or expose pure/testable drag-finalization logic if necessary.

Conceptually:

``` text
committed StageLayout
+ StageFixtureDragState
+ final snapped drag delta
+ lock rules
= final StageLayout
```

The test should exercise the same calculation used by production drag
completion.

Then verify that the production completion path performs one logical
command with that final layout.

Avoid brittle UI/pixel automation if pure interaction math plus
command-level tests can prove the behavior.

## Required Cases

### Single fixture

``` text
origin: (100,100)
delta: (+40,-20)
result: (140,80)
```

Verify:

-   transient preview math,
-   final layout calculation,
-   one logical final mutation,
-   Undo restores `(100,100)`.

### Multi-selection

Verify:

-   same final delta is applied to all movable selected fixtures,
-   relative spacing remains unchanged,
-   group snapping does not distort spacing,
-   one Undo restores the entire group.

### Locked fixture

Verify:

-   locked fixture is omitted from movable origins,
-   final layout leaves it unchanged.

### Zoom-aware calculation

Verify view-space translation is correctly converted to Stage/world
movement.

------------------------------------------------------------------------

# 5. Manual Production Acceptance

Perform this sequence in the **actual launched Aurora application**.

## Camera

-   [ ] Open DESIGN.
-   [ ] Drag empty Stage space.
-   [ ] Confirm Stage tracks the pointer naturally.
-   [ ] Zoom.
-   [ ] Pan again.
-   [ ] Use Fit.
-   [ ] Pan after Fit.
-   [ ] Confirm no camera jump.

## Edit Stage / Space-pan

-   [ ] Enter Edit Stage.
-   [ ] Hold Space and drag empty space.
-   [ ] Confirm camera pans.
-   [ ] Hold Space and begin drag directly over a fixture.
-   [ ] Confirm camera pans and fixture remains stationary.
-   [ ] Release Space.
-   [ ] Drag fixture normally.
-   [ ] Confirm fixture moves instead of camera.

## Text entry regression

With Stage visible:

-   [ ] Click a fixture/project/group naming field.
-   [ ] Type `Front Wash Stage Left`.
-   [ ] Confirm all spaces appear.
-   [ ] Test a search field if one is available.
-   [ ] Confirm Space is not swallowed outside Stage navigation.

## Fixture movement

-   [ ] Drag one fixture slowly.
-   [ ] Confirm it remains visually attached to pointer.
-   [ ] Release and confirm no commit jump.
-   [ ] Undo once and confirm original position.
-   [ ] Redo once.

## Multi-fixture movement

-   [ ] Select several movable fixtures.
-   [ ] Drag one selected fixture.
-   [ ] Confirm the entire group follows live.
-   [ ] Confirm relative spacing remains constant.
-   [ ] Undo once and confirm entire group returns.

## Lock

-   [ ] Lock a fixture.
-   [ ] Attempt to drag it.
-   [ ] Confirm geometry remains unchanged.
-   [ ] Test mixed locked/unlocked multi-selection.

## Lower shelf

-   [ ] Resize lower shelf.
-   [ ] Collapse it.
-   [ ] Confirm Stage/Programmer reclaim the space.
-   [ ] Expand it.
-   [ ] Confirm previous height returns.
-   [ ] Confirm selected shelf tool remains selected.
-   [ ] Relaunch/reopen as appropriate and verify persistence.

------------------------------------------------------------------------

# 6. Prepare Interaction Layer for C4

C4 will make non-fixture Stage objects directly manipulable.

Examples:

-   truss,
-   stage areas,
-   shapes,
-   lines,
-   text,
-   performer silhouettes,
-   stage equipment images,
-   imported images.

Do **not** implement those C4 features during C3.1.

However, inspect the new transient drag architecture and avoid
unnecessary fixture-only assumptions where a small generic abstraction
would make it reusable.

Desired future model:

``` text
Stage document state
    ├── fixture placements
    └── layout objects

Stage camera state
    └── pan / zoom / fit

Stage interaction state
    └── active object drag / origins / delta / modifiers
```

The C3.1 closeout is acceptable if fixture dragging remains
fixture-specific internally, provided it does not force C4 to duplicate
the entire pan/drag coordinate system.

------------------------------------------------------------------------

# 7. Non-Goals

Do not implement during this closeout:

-   movable truss/shapes,
-   performer silhouettes,
-   image palette,
-   imported images,
-   z-order controls,
-   Stage visual redesign,
-   C4 rendering polish,
-   multi-monitor windowing,
-   splash-screen work.

Those are explicitly assigned to later phases.

------------------------------------------------------------------------

# 8. Completion Criteria

C3.1 is approved when:

-   Space-pan works in Edit Stage.
-   Space is never stolen from text entry or unrelated controls.
-   Fixture drag and camera pan cannot fire simultaneously.
-   Single fixture live drag behaves correctly.
-   Multi-fixture live drag behaves correctly.
-   One physical drag corresponds to one logical Undo.
-   Locked fixtures remain protected.
-   Zoom/pan coordinate conversion is correct.
-   Lower shelf collapse/restore/persistence works.
-   Strengthened drag tests exercise production-equivalent finalization
    logic.
-   Native macOS/Xcode build and test suite pass.
-   Manual production-app checklist is completed.
-   No C4 work has been started accidentally.

------------------------------------------------------------------------

# 9. STOP CONDITION

After these corrections:

> **STOP and report C3.1 final closeout results. Do not begin C4 until
> human approval.**

Once approved, C3.1 is considered architecturally complete and the
project may move into the expanded C4 Stage Designer and visual-polish
phase.
