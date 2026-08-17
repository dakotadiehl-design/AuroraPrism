# Aurora UI-08 through UI-11 — Grok Development Prompt

## Mission

Continue Aurora development only after the UI-04→07 review fixes are complete and that baseline has been explicitly accepted.

Your assignment is to **plan first, then implement sequentially**:

- **UI-08 — Full Settings Content**
- **UI-09 — Patch / Output / Diagnostics**
- **UI-10 — Web / iPad Remote**
- **UI-11 — Advanced Docking / Layouts**

Do **not** begin UI-12 Product Polish.

Treat these as four independently testable and reviewable phases, not one monolithic change.

---

## 1. Inspect Before Designing

Before changing code, inspect the accepted repository and all relevant roadmap, design, handoff, and code-review documentation.

The current repository is authoritative. Do not assume old planning documents still match current APIs.

Inspect at minimum:

- UI-01→07 implementation and final UI-04→07 review fixes
- `AppModel` and controller ownership
- document/session command and undo architecture
- Programmer and presentation-store architecture
- palettes, presets, cues, songs, playback and Perform Mode
- Settings
- fixture library and patch model
- universes and protocol hints
- `OutputController`, `OutputManager`, Art-Net and sACN
- accepted local-DMX/ENTTEC implementation, if present
- output health/diagnostics
- MIDI
- remote/web server and embedded web UI
- persistence
- workspace/window/layout state
- existing tests

Inventory existing reusable architecture, missing architecture, and architecture that should not change.

If a major architectural conflict appears during planning, stop and document it before implementation.

---

## 2. Plan Before Implementation

First produce a detailed UI-08→11 implementation plan containing:

1. Existing architecture assessment
2. Cross-phase dependency map
3. State ownership map
4. UI-08 plan
5. UI-09 plan
6. UI-10 plan
7. UI-11 plan
8. Testing strategy
9. Performance/observation strategy
10. Persistence/migration strategy
11. Remote security strategy
12. Manual verification strategy
13. Phase checkpoints
14. Final integration gate

After the plan is internally coherent, execute it sequentially. Normal implementation details do not require a human pause.

---

## 3. Architectural Rules

Preserve the accepted Aurora architecture:

```text
One authoritative owner per state kind.

SwiftUI presents state and issues actions.
SwiftUI does not become engine authority.

Document mutations use the established command/session path.

Playback remains owned by the playback engine/controller.

Song orchestration remains separate from cue playback.

Programmer remains authoritative for ephemeral Programmer values.

Output drivers remain behind output abstractions.

High-frequency engine/output data must not invalidate the whole SwiftUI tree.

Select != execute.

Health status != transport capability.

GO remains usable during nonfatal output/health failures.

Fixture capability filtering remains truthful.

Unsupported != untouched.

Undo restores the real prior document state, including ordering.

One logical user gesture should normally equal one logical Undo.
```

Do not create UI-specific copies of authoritative domain state.

---

## 4. Required Sequence

```text
Accepted UI-07 baseline
        ↓
UI-08
        ↓
tests + manual verification + handoff + clean Git checkpoint
        ↓
UI-09
        ↓
tests + manual verification + handoff + clean Git checkpoint
        ↓
UI-10
        ↓
tests + manual verification + handoff + clean Git checkpoint
        ↓
UI-11
        ↓
tests + manual verification + handoff + clean Git checkpoint
        ↓
UI-08→11 integration package
        ↓
STOP
```

Do not leave UI-08→11 as one giant working-tree delta.

---

# UI-08 — Full Settings Content

Turn Settings into a complete production-useful configuration surface.

## First classify every setting

For each setting identify whether it is:

```text
application preference
project/document setting
device-specific configuration
runtime-only state
derived/read-only status
```

Do not persist runtime status as configuration. Do not move project-owned settings into global preferences merely because the UI is under Settings.

## Cover, where supported by the accepted domain/roadmap

### General
- startup/application behavior
- default workspace/project behavior
- autosave/recovery preferences if supported
- meaningful operator defaults

### Appearance
- approved Aurora appearance behavior
- only roadmap-supported density/scale options
- reduced-motion/animation behavior where appropriate
- no gratuitous theme-customization system

### MIDI
- input sources
- enable/disable
- mappings
- learn workflow if in scope
- connection state
- duplicate/conflict handling
- persistence
- truthful disconnected/unavailable state

### Output
- Art-Net
- sACN
- local DMX / ENTTEC if implemented
- output enable/disable
- appropriate network/destination configuration
- device selection
- configuration separated from runtime health

### Remote
- server enable
- bind/listen behavior
- port
- authentication/pairing
- permission/read-only options if supported
- connection state as read-only presentation

### Diagnostics / Advanced
Expose operator-useful settings only. Do not turn Settings into a developer debug dump.

## Settings behavior

Controls mutate the authoritative configuration owner. Local draft state is acceptable for validated text fields.

Validate ports, addresses, universe ranges, device selection, MIDI mappings, and network configuration. Do not silently coerce invalid values unless behavior is deliberate and obvious.

## UI-08 tests

Cover:

```text
settings persistence
invalid input
MIDI mapping persistence
output configuration persistence
remote configuration persistence
project-vs-global ownership
device disappearance/reappearance
undo where a setting is document-owned
```

---

# UI-09 — Patch / Output / Diagnostics

This phase must let the operator answer:

```text
What is patched?
Where is it patched?
Where is each universe going?
Is output healthy?
Why is something not working?
```

## Patch

Provide a professional patch workflow using existing fixture/personality models:

- fixture instance
- personality/mode
- universe
- start address
- footprint/end address
- fixture name/number
- add/edit/delete
- duplicate where appropriate
- safe bulk operations
- search/filter/sort

Validate and visibly report:

```text
address overlap
footprint beyond universe boundary
invalid universe/address
missing personality/mode
fixture-number conflicts if uniqueness is required
unsupported output route
```

Never silently move fixtures to make a patch valid.

Provide useful universe/address occupancy visualization if consistent with the roadmap.

Patch changes are document commands. Bulk operations must be atomic.

## Output Routing

Provide a clear per-universe view of:

```text
Aurora universe
protocol hint
destination driver
local device if applicable
network destination/mode
enabled state
health
```

Only present protocols Aurora actually implements.

Keep project routing separate from application/device availability.

If local DMX exists, make the universe→physical-device relationship explicit.

## Diagnostics

Provide semantic, throttled operator diagnostics such as:

```text
engine state
output enable state
per-driver health
per-universe route
last meaningful output error
local DMX state
Art-Net/sACN state
MIDI state
remote server state
```

Optional useful metrics may include frame/update rate, last-send time, error counters, and connected clients, but do not bind raw high-frequency engine/network/DMX data into broad SwiftUI observation.

Diagnostics are a projection over engine state, never a second engine.

**Output failure must not automatically disable GO.**

## Test/Identify

If roadmap-supported, add safe identify/flash/test tools. They must not become a second Programmer and must not leave output latched accidentally.

## UI-09 tests

Cover at minimum:

```text
patch overlap
universe boundary
footprint
patch undo/redo
bulk patch atomicity
route resolution
.local → local driver
.artNet → Art-Net
.sACN → sACN
.mirror behavior
.none behavior
driver failure health
device disconnect health
diagnostic throttling
```

Add an integration test:

```text
patched fixture
→ attribute
→ DMX translation
→ universe routing
→ intended output driver
```

---

# UI-10 — Web / iPad Remote

Turn the existing remote foundation into a deliberate touch-oriented live-show surface.

Do not simply reproduce the Mac UI in a browser.

## Inspect existing remote infrastructure

Inventory and reuse:

```text
HTTP server
WebSocket/SSE/event transport
embedded assets
remote API
command routing
snapshot APIs
authentication
connection lifecycle
tests
```

Do not create a parallel backend.

## Priority remote functions

Where roadmap-supported:

### Performance
- current song
- current cue
- next cue
- GO
- BACK
- STOP if deliberately exposed
- song/section navigation
- transition progress
- output health
- connection status

### Programmer subset
Only if explicitly in scope. Use the same capability-aware Programmer APIs as macOS. No remote-only Programmer state.

### Cue/song browsing
Touch-oriented navigation without accidental structural editing during performance.

Remote presentation consumes semantic snapshots, never raw DMX frames.

## Command authority

All remote commands route into existing local/domain actions:

```text
Remote GO
  → remote command endpoint
  → existing transport action
  → PlaybackController
```

No web-only playback/song/Programmer engine.

## Security

Remote control can fire a real rig. Treat security as a product requirement.

At minimum:

- deliberate default bind behavior
- do not accidentally expose control to every reachable network
- authentication/pairing where supported
- validate all commands and ranges
- protect file/path access
- do not leak filesystem details
- handle abusive command floods reasonably
- define multiple-client behavior
- do not imply TLS/encryption if it does not exist

## iPad/touch UX

Use:

```text
large touch targets
clear CURRENT/NEXT
dominant GO
secondary song navigation
no hover dependency
safe destructive-control spacing
high legibility
portrait/landscape where practical
```

Warnings must not obscure GO.

## Resilience

Handle:

```text
server restart
Wi-Fi interruption
client sleep/wake
reconnect
stale state
multiple clients
command during reconnect
```

After reconnect, **server truth wins** and the client resynchronizes.

## Performance

Do not push full application state every DMX frame.

Prefer:

```text
CURRENT/NEXT change → immediate
GO acknowledgement → immediate
transition progress → throttled
health → on change/throttled
raw DMX → not normal remote state
```

## UI-10 tests

Cover:

```text
GO/BACK routing
song navigation
invalid command rejection
out-of-range values
auth/pairing
reconnect snapshot
multiple clients
stale-client resync
server disabled
read-only permissions if present
```

Use browser automation selectively; do not make the phase dependent on fragile end-to-end tests.

---

# UI-11 — Advanced Docking / Layouts

Make Aurora flexible without turning it into a window-manager project.

Preserve the approved professional dark macOS workstation design and its operator hierarchy.

## Layout capabilities

Implement roadmap-defined functionality such as:

- resizable panels
- collapsible panels
- split positions
- panel visibility
- saved workspace layouts
- reset layout
- Build/Perform layouts where appropriate
- multi-display only if already supported/planned

Do not invent floating-window complexity unless required.

## Ownership

Layout state is presentation/application-preference state unless the roadmap explicitly says otherwise.

Do not contaminate:

```text
ShowProject
cue/song data
playback
Programmer
```

with ephemeral SwiftUI geometry.

Explicitly decide whether layout persistence is global, per-workspace, or per-project before implementation.

## Stable identity

Persist semantic panel IDs, not view-instance IDs.

Layout restore must tolerate:

```text
new panel
removed panel
corrupt/old layout
screen-size change
monitor disconnect
```

Fall back safely.

## Minimum usable geometry

Prevent impossible layouts:

```text
GO offscreen
Programmer effectively zero width
split outside valid bounds
optional panel swallowing whole workspace
```

## Perform safety

Custom layouts must not make essential live controls unreachable.

At minimum preserve access to:

```text
CURRENT
NEXT
GO
```

## Persistence/migration

Use version-tolerant layout persistence with validation and reset-to-default.

## UI-11 tests

Cover:

```text
encode/decode
restore
invalid-layout fallback
missing-panel fallback
new-panel default insertion
split bounds
reset
Build/Perform separation if supported
screen-size adaptation logic where testable
```

Manually verify real macOS resizing.

---

# Cross-Phase Ownership Review

Before implementation, document for each domain:

```text
Settings
Patch
Output configuration
Output runtime
Diagnostics
Remote
Workspace layout
```

the:

```text
authoritative owner
persistence owner
mutation API
presentation projection
high-frequency data
main observers
```

Pay special attention to:

```text
project output route vs physical device availability
configuration vs runtime health
remote presentation vs remote authority
workspace layout vs show document
```

---

# Performance / Observation Rules

Never broadly observe raw:

```text
DMX frames
Art-Net packets
sACN packets
serial writes
MIDI event streams
socket traffic
```

Use:

```text
high-frequency engine data
        ↓
semantic/throttled projection
        ↓
focused observable state
        ↓
UI
```

Human-semantic health/metrics may be throttled. GO/CURRENT/NEXT changes propagate immediately.

Avoid state mutation from SwiftUI body/read functions.

Remove redundant manual `objectWillChange` where `@Published` already supplies correct notification.

---

# Error Handling

Do not silently `try?` user-requested mutations when failure matters.

Use explicit error handling and surface meaningful failures.

Avoid modal-dialog storms in Perform Mode. Prefer inline/status warnings when appropriate.

---

# Undo / Transactions

Document mutations remain undoable.

Examples:

```text
patch fixture
move address
bulk patch
project universe route
```

One user gesture normally equals one Undo.

Bulk operations are atomic.

Application layout/preferences do not automatically belong in document Undo. Document the distinction.

---

# Accessibility / macOS Behavior

Preserve:

- keyboard navigation
- VoiceOver labels
- meaningful control names
- sane focus behavior
- menu consistency
- no shortcut collisions
- existing Perform shortcuts

Remote UI must have touch equivalents and cannot depend on hover.

---

# Phase Checkpoint Requirements

At the end of every phase:

```text
1. Run focused tests.
2. Run full swift test on macOS.
3. Build Xcode Debug.
4. Run manual phase smoke checklist.
5. Review for later-phase scope leakage.
6. Review for duplicate state authority.
7. Review observation/performance.
8. Review Undo grouping.
9. Review persistence/migration.
10. Produce Markdown handoff.
11. Create clean Git checkpoint.
12. Continue unless a major architectural conflict exists.
```

Each handoff must state:

```text
implemented
deliberately not implemented
files changed
architecture decisions
state ownership changes
persistence changes
commands added
tests added/results
manual verification
known limitations
risks
Git checkpoint
```

---

# Final UI-08→11 Integration Gate

After UI-11, stop feature development.

Prepare the repository for independent deep review.

The integrated chain should now cover:

```text
Fixture Library
→ Patch
→ Fixture Selection
→ Programmer
→ Palette/Preset
→ Cue
→ Song
→ Perform
→ Output Routing
→ Art-Net / sACN / Local DMX
```

with parallel surfaces:

```text
Settings
Diagnostics
Web/iPad Remote
Workspace Layout
```

## Required integration scenarios

### A — Patch to Output
```text
add fixture
→ personality/mode
→ universe/address
→ select
→ program attributes
→ DMX translation
→ route
→ intended driver
```

### B — Full Show
```text
program
→ palette
→ cue
→ song
→ Perform
→ GO
→ CURRENT/NEXT
→ output
```

### C — Output Failure
```text
run show
→ fail/disconnect output
→ health degrades
→ GO remains usable
→ recover output
→ health recovers truthfully
```

### D — Remote
```text
connect iPad/browser
→ state sync
→ remote GO
→ Mac/remote agree
→ Wi-Fi interruption
→ reconnect
→ server truth resyncs client
```

### E — Layout
```text
customize Build layout
→ save
→ restart/restore
→ enter Perform
→ transport remains usable
→ reset layout
```

---

# Hardware Readiness

If accepted local DMX/ENTTEC support exists, preserve and test it throughout UI-08/09.

Mocks prove logic. They do not prove hardware integration.

Clearly distinguish mock test success from real-device verification.

The UI-11 repository should be suitable for broader real-rig testing.

---

# Explicit Non-Goals

Do not:

- implement UI-12
- add unrelated future features
- redesign Programmer without a demonstrated blocker
- redesign playback without a demonstrated blocker
- create remote-specific state authority
- expose raw engine internals merely because Diagnostics exists
- turn docking into an unconstrained window manager
- replace Aurora's approved visual language
- silently change document schema without migration/default handling
- skip tests because a feature is "just UI"

---

# Stop Conditions

Stop autonomous implementation and produce a blocker report if:

```text
a phase contradicts accepted engine semantics
a destructive document migration lacks a safe path
output ownership cannot be preserved
remote control cannot be made acceptably safe
layout requirements demand a fundamental shell rewrite
tests expose a critical baseline regression that invalidates later work
```

Do not improvise a major rewrite merely to keep moving.

---

# Final Deliverables

After UI-11 provide:

```text
UI-08 handoff
UI-09 handoff
UI-10 handoff
UI-11 handoff
full test results
manual verification results
known limitations
migration notes
security notes
performance notes
Git checkpoint history
UI-08→11 integration summary
```

Then **STOP**.

The repository will undergo an independent deep code review before UI-12.

---

# Final Instruction

**Do not begin this campaign until the current UI-04→07 code-review fixes have been completed and that baseline has been explicitly accepted.**

Once accepted:

1. inspect the repository;
2. create the detailed plan;
3. implement UI-08→11 sequentially;
4. test and checkpoint every phase;
5. preserve existing state ownership and performance architecture;
6. stop on major architectural conflict;
7. hard-stop after UI-11.
