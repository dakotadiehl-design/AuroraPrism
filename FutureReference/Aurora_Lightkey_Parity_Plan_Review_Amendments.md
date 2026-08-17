# Aurora Lightkey-Parity Implementation Plan --- Review Amendments

**Status:** Recommended amendments before approval of Grok Plan Mode
implementation plan\
**Date:** 2026-08-13\
**Applies to:** `Aurora Lightkey-Parity Pre-Smoke Implementation Plan`

## Overall Assessment

**Verdict: APPROVE WITH AMENDMENTS.**

The proposed architecture, dependency ordering, and PR decomposition are
strong. The plan correctly treats Aurora's existing implementation as a
baseline to extend rather than replace and correctly identifies the
major remaining gaps: Stage Preview, Fixture Profile Editor, Advanced
MIDI, Global Show Controls, portable libraries, and patch/reporting
functionality.

The following amendments should be incorporated before implementation
begins.

------------------------------------------------------------------------

## Amendment 1 --- Pixel / Matrix Fixtures Must Be Pre-Smoke

Do not postpone full multi-cell/pixel fixture support until after smoke
testing.

If Aurora's goal is practical Lightkey-class functional completeness
before smoke testing, multi-cell fixtures are part of that baseline. LED
bars, strips, battens, matrices, and multi-cell fixtures are common
enough that the fixture architecture should understand them before it is
considered mature.

Add a PR between the fixture-model work and Fixture Profile Editor UI:

### PR-P2B --- Multi-Cell / Parameterized Fixture Model

Required capabilities:

-   Fixture → cells/subfixtures
-   Repeating parameter blocks
-   Variable cell count
-   Calculated DMX footprint
-   Whole-fixture selection
-   Individual cell selection
-   Per-cell semantic state
-   Stage Preview representation
-   Programmer support
-   Effect targeting
-   Fixture Profile Editor support

A full pixel-mapping/media-server subsystem is **not** required before
smoke testing.

The requirement is that Aurora can correctly model, patch, program,
preview, and target ordinary multi-cell fixtures without requiring a
unique hard-coded personality for every possible cell count.

------------------------------------------------------------------------

## Amendment 2 --- Fixture Profiles Need a Generic / Raw-DMX Escape Hatch

Aurora's semantic fixture architecture should remain the preferred
model, but the Fixture Profile Editor must support fixture functions
that do not yet map cleanly to Aurora semantics.

A channel/function should be able to represent either:

``` text
Known Aurora semantic parameter
```

or:

``` text
Generic / raw fixture parameter
```

Example:

``` text
Channel 17
Name: Prism Macro
Semantic Type: Generic

DMX Functions:
0–31      Open
32–63     Prism A
64–95     Prism B
96–127    Prism C
...
```

Required behavior:

-   Generic parameters remain named and controllable.
-   DMX ranges/functions remain inspectable.
-   Generic parameters can be exposed in the Programmer/Inspector where
    appropriate.
-   Unsupported fixture capabilities must not require source-code
    changes merely to become operable.
-   Future Aurora semantic types may later replace generic mappings
    without breaking existing profiles.

This is essential for supporting unusual or poorly standardized fixtures
while preserving Aurora's semantic-first architecture.

------------------------------------------------------------------------

## Amendment 3 --- Add a First-Class DMX Output Monitor

Promote DMX/output inspection into an explicit P0-L requirement.

Aurora must be able to answer:

> **What does Aurora believe it is transmitting right now?**

Provide a universe/channel monitor.

Baseline example:

``` text
Universe 1

Channel    Value
001        255
002        128
003        000
004        043
005        255
```

Where mapping information is available, provide semantic attribution:

``` text
001   255   Front Wash L   Intensity
002   128   Front Wash L   Red
003    64   Front Wash L   Green
004    12   Front Wash L   Blue
```

Required capabilities:

-   Select universe
-   Inspect current channel values
-   Update from actual resolved/transmitted Aurora output
-   Identify patched fixture/channel ownership where known
-   Distinguish unused channels
-   Remain diagnostic/read-only
-   Avoid interfering with output timing

A compact grid/hex representation may be added later, but
straightforward channel/value inspection is required before smoke
testing.

This gives smoke testing a critical diagnostic boundary between:

``` text
Aurora engine state
        ↓
Aurora generated DMX
        ↓
Output driver/protocol
        ↓
Physical fixture
```

------------------------------------------------------------------------

## Amendment 4 --- Add Fixture / Profile Health Diagnostics

Connect fixture validation and output routing to an operator-facing
health workflow.

For a patched fixture, Aurora should be able to communicate conditions
such as:

``` text
✓ Fixture profile valid
✓ Patch valid
✓ Universe routed
✓ Output enabled
⚠ Physical device status unknown
```

and failures such as:

``` text
✕ Fixture profile missing
✕ Patch overlaps Fixture 17
⚠ Universe 3 has no output route
```

Potential health dimensions:

-   Fixture profile present
-   Fixture profile valid
-   Fixture mode valid
-   Patch valid
-   No address collision
-   Universe configured
-   Universe routed
-   Output protocol enabled
-   Output driver healthy
-   External endpoint/device state where technically knowable

Do not imply physical fixture reachability when the underlying protocol
cannot establish it.

Integrate this with Aurora's restrained status/diagnostics design rather
than creating noisy warning chrome throughout the UI.

The operational objective is simple:

> When a fixture is not behaving, Aurora should help the operator
> identify which layer of the control chain is unhealthy.

------------------------------------------------------------------------

## Amendment 5 --- Strengthen Stage Preview Parity Testing

Keep the existing requirement that Stage Preview derives from resolved
semantic engine state.

Add an explicit regression/acceptance test proving that Stage Preview
and protocol output originate from the same authoritative resolved
frame/state.

Conceptually:

``` text
                Resolved Engine State
                       /     \
                      /       \
                     v         v
          StagePreviewSnapshot  DMX Frame
```

For known fixture state, verify that:

-   Preview intensity corresponds to resolved fixture intensity.
-   Preview color corresponds to resolved fixture color.
-   Generated protocol output corresponds to that same state.
-   Programmer changes appear in both.
-   Cue transitions appear in both.
-   Effects appear in both.
-   MIDI behaviors appear in both.
-   Master changes appear in both.
-   Blackout/Freeze semantics affect both according to documented rules.

The test should become a long-term architectural tripwire against future
divergence between visualization and physical output.

------------------------------------------------------------------------

## Amendment 6 --- Add Wave 9: Formal Lightkey-Parity Verification

Do not move directly from Wave 8 hardening into general smoke testing.

Add:

# Wave 9 --- Lightkey-Parity Verification

**Purpose:** Verify product completeness against the approved parity
matrix.

No new feature development should occur during this wave except fixes
required to satisfy an already-approved parity requirement.

Take the final Lightkey parity matrix line-by-line and classify every
item:

``` text
PASS
FAIL
DEFERRED / ACCEPTED
NOT APPLICABLE
```

Example:

``` text
Fixture workflow          PASS
Patch workflow            PASS
Programmer                PASS
Palettes / presets        PASS
Cue playback              PASS
Effects                   PASS
Blind                     PASS
Freeze                    PASS
Master                    PASS
2D Stage Preview          PASS
MIDI input                PASS
Advanced MIDI behavior    PASS
MIDI feedback             PASS
External control          PASS
Output diagnostics        PASS
Persistence               PASS
```

Any intentionally omitted Lightkey capability must remain visible as
**DEFERRED / ACCEPTED** rather than disappearing from the checklist.

### Wave 9 Exit

Produce a final artifact:

``` text
AURORA LIGHTKEY-PARITY GATE: PASSED
```

Only then begin broad smoke testing.

This creates three distinct quality stages:

1.  **Implementation testing:** Does each feature work?
2.  **Parity verification:** Did we build the complete product baseline
    we committed to?
3.  **Smoke testing:** What breaks when Aurora is exercised as a
    complete real-world lighting application?

------------------------------------------------------------------------

# Freeze Semantics --- Approved Direction

Approve Grok's proposed default Freeze behavior:

> **Freeze holds physical/resolved stage presentation while Aurora's
> internal playback timeline may continue.**

Conceptually:

``` text
Cue 14 active
      |
    FREEZE
      |
Physical/preview output holds Cue 14 appearance
      |
     GO
     GO
     GO
      |
Internal playback reaches Cue 17
Physical output remains held
      |
   UNFREEZE
      |
Output resolves to current Cue 17 state
```

The implementation plan must explicitly define release behavior.

Grok should evaluate whether unfreezing:

-   Immediately resolves/snaps to current state, or
-   Uses a controlled release transition.

Whichever behavior is chosen must be deterministic, documented, and
tested.

Freeze remains distinct from Blackout and Blind.

------------------------------------------------------------------------

# UI Development Policy --- Approved

Retain Grok's proposed rule:

> **No UI-12 polish campaign until the parity smoke gate.**

The existing Aurora UI is sufficiently mature for functional completion
work.

Do not begin another broad visual-polish campaign while known
professional workflow gaps remain.

UI work during the parity program should be limited to:

-   UI required by newly implemented functionality
-   Usability blockers
-   Broken/inconsistent states
-   Accessibility requirements
-   Operational clarity
-   Safety/status indication

A broader visual refinement pass should occur after Aurora has been
exercised as a complete product during smoke testing.

------------------------------------------------------------------------

# Revised Implementation Program

Use the following high-level sequence, subject to repo-aware dependency
validation:

## Wave 0 --- Repository Audit + Final Parity Matrix

-   Current implementation inventory
-   Complete / Partial / Missing / Deferred classification
-   Exact repository ownership
-   Dependency graph
-   Risk register
-   Final PR sequence

**STOP for approval.**

## Wave 1 --- Global Show Control + Foundational Engine/Model Work

-   Master
-   Blackout
-   Freeze
-   Blind
-   Panic/reset
-   MIDI performance enable
-   Precedence/blending rules
-   Foundational persisted-model changes

## Wave 2 --- Fixture Architecture + Rig Management

-   Fixture definition completeness
-   Generic/raw parameter support
-   Multi-cell/parameterized fixture architecture
-   Fixture Profile Editor
-   Fixture/profile validation
-   Patch workflow completion
-   Patch import/export/reporting
-   Portable Aurora Library foundations

## Wave 3 --- Programming / Playback Completion

-   Programmer completion
-   Locate/Highlight
-   Palettes/presets
-   Cue-list gaps
-   Effects gaps
-   Song Mode completion
-   Global-control UI integration

## Wave 4 --- 2D Stage Designer / Live Preview

-   Stage persistence
-   Semantic preview snapshot
-   Canvas
-   Edit/Live modes
-   Fixture visualization
-   Beams/movers
-   Dominant background
-   Selection synchronization
-   Multi-cell representation
-   Preview/output parity tests

## Wave 5 --- Advanced MIDI Engine

-   Rich MIDI events
-   Rules
-   Context
-   Behaviors
-   Envelopes
-   Velocity scaling
-   Continuous controllers
-   Drum profiles
-   Semantic drum roles
-   Safety
-   Monitor

## Wave 6 --- MIDI Feedback + Unified External Control

-   Outbound MIDI feedback
-   Controller/device profiles
-   Encoders/14-bit considerations
-   Mapping import/export
-   Feedback-loop prevention
-   Unified external-control monitor
-   Mapping/action diagnostics

## Wave 7 --- Output / Remote / OSC / Fixture Diagnostics

-   DMX hardware hardening
-   Art-Net
-   sACN
-   Routing
-   DMX Output Monitor
-   Fixture/Profile Health
-   Reconnection behavior
-   Remote completion
-   OSC completion
-   Diagnostic integration

## Wave 8 --- Pre-Smoke Hardening

No planned major feature development.

Focus on:

-   Persistence round trips
-   Schema migrations
-   Undo/redo
-   Broken references
-   Device disconnect/reconnect
-   Error handling
-   Large-show performance
-   Frame-loop protection
-   UI restoration
-   Canonical test projects
-   Scenario 1--10 completion

## Wave 9 --- Formal Lightkey-Parity Verification

-   Re-run final parity matrix
-   PASS / FAIL / DEFERRED / N/A every requirement
-   Resolve all unaccepted failures
-   Produce final parity-gate result

### Gate

``` text
AURORA LIGHTKEY-PARITY GATE: PASSED
```

## Then --- Broad Smoke Testing

At this point Aurora should be tested as a complete lighting-control
product rather than as a collection of partially implemented subsystems.

------------------------------------------------------------------------

# Final Directive to Grok

Incorporate these amendments into the existing **Aurora Lightkey-Parity
Pre-Smoke Implementation Plan**.

Before coding:

1.  Reconcile these amendments against the live repository.
2.  Update the Wave 0 parity matrix requirements.
3.  Add multi-cell/parameterized fixtures to the pre-smoke baseline.
4.  Add generic/raw fixture parameters to the Fixture Profile Editor
    architecture.
5.  Add the DMX Output Monitor to P0 output diagnostics.
6.  Add Fixture/Profile Health diagnostics.
7.  Add explicit Stage Preview ↔ resolved-output parity regression
    tests.
8.  Add Wave 9 formal Lightkey-Parity Verification.
9.  Preserve the approved no-UI-polish-until-parity policy.
10. Preserve the proposed Freeze direction, but explicitly define and
    test release semantics.
11. Update PR ordering/dependencies accordingly.
12. Identify any existing Aurora implementation that already satisfies
    these requirements and avoid unnecessary rewrites.
13. **Stop after producing the revised repo-aware implementation plan.
    Do not begin coding until explicitly authorized.**

## Guiding Principle

> **Lightkey is Aurora's functional floor, not its design ceiling.**

Aurora should enter smoke testing only after it can perform the
practical professional lighting workflows expected from a mature
Lightkey-class controller, while retaining Aurora's stronger Song Mode,
performance MIDI, semantic architecture, spatial preview, reusable
behaviors, and future-facing design.
