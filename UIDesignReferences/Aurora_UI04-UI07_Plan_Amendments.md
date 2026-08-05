# Aurora UI-04 through UI-07 Plan Amendments

## Status

**Implementation plan verdict:** Approved for execution with the amendments below.

These amendments refine the existing `Aurora UI-04 through UI-07 Implementation Plan`. They do **not** replace that plan and should be applied alongside it.

The intended execution sequence remains:

```text
UI-04
  ↓
UI-05
  ↓
UI-06
  ↓
UI-07
  ↓
INTEGRATION GATE
  ↓
STOP
```

Do not begin UI-08.

The existing architectural constraints remain in force:

- Preserve UI-03 Programmer semantics.
- Keep one authoritative owner per state kind.
- SwiftUI presents and issues actions; it does not own playback.
- Reuse existing engine/domain abstractions.
- Preserve select ≠ execute.
- Preserve Programmer ephemeral state vs document state.
- Preserve PaletteResolver/CueResolver semantics.
- Preserve SongDirector as orchestration, not playback.
- Preserve Perform Mode as a thin presentation/control layer.
- Stop if a major architectural conflict is discovered.

---

# Amendment 1 — Constrain UI-04 “Record Ref” to Existing Cue-Reference Infrastructure

## Applies to

- UI-04 — Palettes + Presets
- Record Ref workflow
- Palette/cue reference integration

The UI-04 plan includes the existing Record Ref workflow:

```text
Palette
  → Record Ref
  → Cue.recordPaletteRef
  → UpdateCueCommand
```

This is acceptable because Aurora already has cue-reference infrastructure.

However, UI-04 must **not** use Record Ref as an excuse to begin implementing UI-05 cue-editing architecture.

## Requirement

UI-04 Record Ref may:

- use existing cue selection;
- use existing cue-reference domain APIs;
- write palette references through existing commands;
- surface truthful errors if no valid cue target exists.

UI-04 Record Ref must **not** introduce:

- new cue-list editing workflows;
- new cue creation UX;
- cue Record/Update-from-Programmer workflows;
- new cue selection architecture solely for Record Ref;
- cue timing editors;
- cue CRUD beyond what already exists and is strictly required by the existing reference path.

If the existing cue-target pathway is insufficient:

```text
do not expand UI-04
        ↓
document the missing UX
        ↓
defer it to UI-05
```

## Acceptance addition

```text
[ ] UI-04 Record Ref reuses existing cue-reference infrastructure
[ ] No new general cue editor is introduced in UI-04
[ ] Missing cue-target UX is deferred to UI-05 rather than expanding scope
```

---

# Amendment 2 — Mixed Palette Attributes Must Never Be Silently Omitted

## Applies to

- UI-04 palette creation
- Multi-fixture Programmer capture
- Color / Position / Intensity palette creation

The proposed “common values only” creation rule is acceptable.

Example:

```text
Fixture A:
  R = 1.00
  G = 0.20
  B = 0.00

Fixture B:
  R = 1.00
  G = 0.70
  B = 0.00
```

A common-only Color palette may legitimately capture:

```text
R = 1.00
B = 0.00
```

and omit mixed `G`.

However, Aurora must **never make that omission invisible to the operator**.

## Requirement

If palette creation skips attributes because their selected Programmer state is mixed:

- create only the values that are genuinely common;
- do not fabricate a value;
- do not average values;
- do not choose the first fixture's value;
- clearly communicate which attributes were omitted.

The existing planned status line for mixed/skipped attributes should therefore be treated as required behavior rather than optional polish.

Possible UX:

```text
Created Color palette
Skipped mixed attributes: Green
```

Exact wording/design may follow the Aurora design system.

## Empty result

If all candidate attributes are mixed/untouched such that no valid values remain:

```text
refuse palette creation
```

Do not create an empty or misleading palette.

## Acceptance additions

```text
[ ] Mixed attributes are never fabricated
[ ] Mixed attributes are never silently dropped
[ ] Operator receives clear indication of skipped mixed attributes
[ ] Palette creation is refused if no valid common values remain
```

---

# Amendment 3 — Cue Update Should Be Immediate and Undoable, Not Routinely Modal

## Applies to

- UI-05 — Cue Workflow
- Cue Record / Update behavior

The existing distinction is correct:

```text
Record
  → create a new cue

Update
  → replace/update the currently selected cue's programmed levels
```

The plan currently leaves confirmation before overwriting non-empty cue levels as an optional soft confirm.

For normal lighting-console operation, routine Update should **not** require a modal confirmation.

## Requirement

Treat pressing **Update** as explicit operator intent.

Preferred behavior:

```text
Programmer state
      ↓
UPDATE
      ↓
selected cue
      ↓
UpdateCueCommand
      ↓
undo available
```

Use Undo as the recovery mechanism.

Routine Update should:

- be immediate;
- preserve non-level fields unless the user explicitly edits them;
- be undoable;
- not display a modal confirmation every time.

Confirmation is more appropriate for structurally destructive operations such as Delete.

## Scope guard

Do not introduce complicated update modes or merge strategies in UI-05.

The intended UI-05 semantic remains:

```text
Update cue levels from current Programmer capture
```

using the existing sparse/owned Programmer semantics.

## Acceptance additions

```text
[ ] Update selected cue is immediate
[ ] Update does not routinely show modal confirmation
[ ] Update is undoable
[ ] Update preserves cue metadata/timing unless explicitly edited
```

---

# Amendment 4 — Lock Down Cue Ordering Authority Before Implementing UI-05 Reorder/Create Behavior

## Applies to

- UI-05 cue creation
- cue numbering
- cue reordering
- playback sequence semantics

Before implementing cue creation/reordering UI, inspect and document the existing engine/model rule for cue order.

The implementation must answer:

```text
Does Cue.number determine playback sequence?

OR

Does CueList collection order determine playback sequence,
with Cue.number serving as display metadata?

OR

Does the existing model define another rule?
```

Do **not** allow SwiftUI to accidentally create a second ordering rule.

## Requirement

Preserve the existing authoritative engine/domain behavior.

Add focused tests proving the rule.

Examples worth covering where supported:

```text
Cue 1
Cue 2
Cue 2.5
Cue 3
```

and/or:

```text
array order differs from numeric labels
```

The tests should establish exactly what playback will do.

## Creation policy

The current proposal to create a new cue using `last + 1` or an appropriate decimal step is fine only if it is consistent with existing ordering semantics.

Do not invent a new numbering model solely for UI convenience.

## Reorder

If drag reorder is implemented in UI-05:

- it must mutate the authoritative ordering representation;
- it must not merely reorder rows visually;
- it must remain undoable.

If ordering semantics are ambiguous or require a model redesign:

```text
stop
document conflict
do not invent a new rule in UI-05
```

## Acceptance additions

```text
[ ] Existing cue-ordering authority is explicitly documented
[ ] Playback order has focused test coverage
[ ] Cue numbering UI does not create a competing ordering rule
[ ] Any reorder operation mutates authoritative domain state
```

---

# Amendment 5 — Song Entry Navigation Must Be Visually Secondary to GO

## Applies to

- UI-06 — Song Mode
- UI-07 — Perform Mode
- SongDirector entry navigation
- live transport UX

The architectural distinction in the plan is correct:

```text
Song Next/Previous Entry
  → advances SongDirector entry

GO
  → advances cue playback within the loaded cue list
```

However, these actions can be semantically close from an operator's perspective.

Aurora must make their hierarchy unmistakable.

## Requirement

**GO remains the primary live-show transport control.**

Song entry navigation must:

- be visually subordinate to GO;
- be clearly labeled as song/section navigation;
- not use the same prominence, shape, or visual hierarchy as GO;
- not imply that it is a replacement for cue progression.

If the existing domain term is `Entry`, it may remain in implementation-facing text. Operator-facing language may use a more musical term such as `Section` only if that is consistent with the approved UX and model semantics.

Do not rename domain concepts casually during this pass.

## UI-06

In Build/Song Mode, make the distinction obvious:

```text
Song / Section navigation
        vs
Cue transport
```

## UI-07

In Perform Mode:

```text
GO = dominant action

Song previous/next entry = secondary navigation
```

Song entry buttons must not visually compete with GO.

## Acceptance additions

```text
[ ] GO is the dominant transport affordance
[ ] Song entry navigation is visibly secondary
[ ] Operator can distinguish “advance cue” from “advance song entry” at a glance
[ ] Song entry controls do not reuse GO styling/prominence
```

---

# Amendment 6 — Perform Transport Must Remain Available During Nonfatal Health/Output Failures

## Applies to

- UI-07 — Perform Mode
- health indicators
- output/MIDI warnings
- validation warnings
- GO/BACK/STOP availability

The existing plan correctly states that warnings must not cover GO.

Strengthen this into a transport-availability rule.

## Principle

**GO is sacred during performance.**

Health and output status are not the same thing as playback capability.

Example:

```text
OUTPUT NODE OFFLINE   🔴

CURRENT  Chorus
NEXT     Guitar Solo

        [ GO ]
```

If the engine can still accept GO, Aurora should not disable GO merely because output delivery is degraded.

## Requirement

Nonfatal conditions such as:

- Art-Net/sACN node unavailable;
- MIDI disconnected;
- output warning;
- validation warning;
- missing noncritical reference warning;
- degraded health state;

must not disable transport unless the underlying playback operation is genuinely impossible or unsafe.

Transport availability should be derived from actual playback capability, not general health color.

## Separate concerns

Present:

```text
playback capability
```

separately from:

```text
output health
MIDI health
validation status
```

A red health indicator may coexist with an enabled GO button.

## Fatal conditions

If a condition genuinely makes the requested transport action impossible, Aurora may disable/block it, but the UI must communicate the specific reason.

Avoid generic:

```text
System unhealthy → disable everything
```

logic.

## Alerts

Warnings/errors in Perform Mode should prefer:

- inline/nonmodal status;
- persistent health chrome;
- banners that do not obscure transport.

Avoid incidental modal dialogs that steal focus from transport.

## Acceptance additions

```text
[ ] Nonfatal output failure does not disable GO
[ ] MIDI disconnect does not disable UI transport
[ ] Validation warnings do not disable transport by default
[ ] Playback capability and health status are modeled separately
[ ] Fatal transport blocks explain the specific reason
[ ] No incidental modal warning obscures or steals focus from GO
```

---

# Cross-Phase Scope Guards

These amendments do not change the broader implementation strategy.

For every phase:

```text
1. Re-read the approved phase plan.
2. Re-read prior phase handoff.
3. Implement domain/foundation work first.
4. Implement UI on top of authoritative state.
5. Add focused tests.
6. Run full test suite.
7. Run Xcode Debug verification.
8. Complete manual smoke checklist.
9. Produce phase handoff.
10. Preserve a clean checkpoint.
11. Continue unless a major architecture conflict appears.
```

Do not pause for normal human approval between UI-04, UI-05, UI-06, and UI-07 if autonomous execution has been authorized.

Do stop if implementation uncovers a major architecture conflict that would require redesign.

---

# Updated Autonomous Execution Instruction

After incorporating these amendments, proceed according to the approved UI-04 through UI-07 implementation plan.

The required sequence is:

```text
UI-04
  → checkpoint / tests / handoff

UI-05
  → checkpoint / tests / handoff

UI-06
  → checkpoint / tests / handoff

UI-07
  → checkpoint / tests / handoff

INTEGRATION REVIEW PACKAGE
  → STOP
```

Do **not** begin UI-08.

Do not collapse the phases into one undifferentiated implementation.

---

# Final Acceptance Additions Summary

Add the following to the relevant phase checklists:

```text
UI-04
[ ] Record Ref does not expand into UI-05 cue-editor scope
[ ] Mixed palette attrs are never silently omitted
[ ] Empty/common-less palette creation is refused

UI-05
[ ] Update is immediate, deliberate, and undoable
[ ] Routine Update has no modal confirmation
[ ] Cue ordering authority is documented and tested
[ ] UI does not invent a competing cue-order rule

UI-06
[ ] Song entry navigation is clearly distinct from GO
[ ] Entry navigation remains secondary to cue transport

UI-07
[ ] GO remains the dominant live action
[ ] Nonfatal health/output/MIDI warnings do not disable transport
[ ] Playback capability is separate from health status
[ ] Warnings do not obscure or steal focus from transport
```

---

# Final Gate

The original UI-04 through UI-07 plan remains:

**APPROVED FOR AUTONOMOUS IMPLEMENTATION WITH THESE AMENDMENTS.**

The target remains a clean, testable operator chain:

```text
Fixture Selection
  → Programmer
  → Palette / Preset
  → Cue
  → Song
  → Perform Mode
  → Playback / Output
```

After UI-07, stop feature development and prepare the repository for the full UI-03 through UI-07 integration review and subsequent physical-light smoke test.
