# Aurora Post-C6 Whole-Codebase Audit & Pre-Programmer/MIDI Remediation Plan

**Project:** Aurora Lighting Control\
**Reviewed repository:** `Aurora_C6.zip`\
**Review point:** Completed C6 UX/brand implementation\
**Purpose:** Perform a whole-tree code audit before beginning the new
Programmer Color Engine and Advanced MIDI Engine work.\
**Required outcome:** Correct high-confidence correctness,
data-integrity, real-time, hardware-I/O, and regression-test weaknesses
before adding another major layer of high-frequency Programmer/MIDI
behavior.

------------------------------------------------------------------------

# 1. Executive Verdict

Aurora is in **substantially better shape than its size and development
pace might suggest**.

The C1-C6 UX work has not produced an obviously rotten foundation. The
major subsystems are sensibly separated into Swift packages/modules,
project persistence is mostly defensive, the Stage architecture is now
coherent, C5 floating windows have been reconciled onto shared
production surfaces, and the C6 splash/brand implementation does not
reveal a reason to reopen the design.

However, this audit found several issues that should be corrected
**before the Programmer Color Engine and Advanced MIDI Engine
significantly increase live mutation frequency and before real hardware
smoke testing begins**.

The most important findings are:

1.  **LightingEngine frame execution is not serialized.** Scheduler
    frames and synchronous "force a frame now" paths can execute
    concurrently.
2.  **Current-schema `.aurora` packages can silently treat missing
    Stage/MIDI files as empty**, creating a data-loss risk after package
    corruption.
3.  **Several user/project-data paths use
    `Dictionary(uniqueKeysWithValues:)` and can crash on duplicate
    IDs/paths even though the validator merely reports those
    duplicates.**
4.  **ENTTEC serial I/O has real concurrency and partial-write
    weaknesses**, and generic serial devices can still be classified as
    ENTTEC USB DMX Pro.
5.  **Art-Net startup can report `.ready` after a timeout without
    actually reaching `.ready`, and later connection-state failures are
    not continuously reflected.**
6.  **Aurora Library loading silently converts corrupted/missing content
    files into empty collections, and save replacement is less safe than
    project-package saving.**
7.  **Stage imported-media migration can trap on duplicate paths and can
    collide when two legacy files share the same basename.**
8.  **C6 splash tests mostly test copied constants/booleans rather than
    production splash code.**
9.  **There is still a complete legacy `StagePanel` production
    implementation that is effectively dead but can diverge from the
    canonical DESIGN/Edit Stage workflow.**
10. **App-wide invalidation is broader and more redundant than it should
    be before adding a 60--120 Hz color-wheel interaction path.**

None of this requires a rewrite.

The recommended remediation is a focused **Post-C6 / Pre-Programmer
hardening pass**.

------------------------------------------------------------------------

# 2. Audit Scope

The repository contains approximately:

``` text
Production Swift:
267 files
42,553 lines

Tests:
97 files
9,803 lines

Total Swift in archive:
~53,000 lines
```

Production module breakdown:

``` text
Sources/AuroraUI          72 files   15,025 lines
Sources/Aurora            42 files   10,808 lines
Sources/AuroraModel       33 files    4,386 lines
Sources/AuroraEngine      29 files    3,829 lines
Sources/AuroraCore        46 files    3,216 lines
Sources/AuroraMIDI        14 files    1,638 lines
Sources/AuroraOutput      15 files    1,601 lines
Sources/AuroraRemote       7 files    1,592 lines
Sources/AuroraFixtureLib   6 files      352 lines
Sources/AuroraDiagnostics  3 files      106 lines
```

The audit used:

-   whole-tree Swift source enumeration,
-   line-count and largest-file analysis,
-   whole-tree scans for:
    -   unchecked Sendable usage,
    -   silent catches,
    -   `try?`,
    -   trapping dictionary initializers,
    -   force unwraps,
    -   mutable static state,
    -   TODO/FIXME markers,
    -   placeholder/dead/stub indicators,
-   line-level manual review of high-risk paths:
    -   engine scheduler and frame loop,
    -   playback/effects/programmer merge boundary,
    -   output routing,
    -   Art-Net,
    -   sACN,
    -   ENTTEC serial transport,
    -   project package load/save/recovery,
    -   library package load/save,
    -   Stage media,
    -   Stage direct manipulation,
    -   C5 floating-window lifecycle,
    -   C6 splash,
    -   UI invalidation,
    -   Programmer presentation,
    -   project validation,
    -   remote listener/session paths,
    -   relevant tests.

This is intended to be an **engineering audit**, not a formatting/style
critique. Low-value cosmetic refactoring is deliberately omitted.

------------------------------------------------------------------------

# 3. Severity Definitions

## P0 --- Correct before Programmer/MIDI work continues

High-confidence correctness/data-loss/crash/real-time defects that can
make later debugging much harder.

## P1 --- Correct before hardware smoke testing / final acceptance

Important reliability, hardware-I/O, state-reporting, or
regression-protection issues.

## P2 --- Strong cleanup before the codebase grows again

Maintainability/performance problems that are not currently
show-stoppers but will become increasingly expensive.

------------------------------------------------------------------------

# 4. P0 --- Serialize the Entire LightingEngine Frame Pipeline

**File:**\
`Sources/AuroraEngine/LightingEngine.swift`

## 4.1 Current architecture

The background scheduler calls:

``` swift
processFrame(publishSnapshotAlways: false)
```

at the engine frame rate.

Several synchronous public operations also call the same private
function directly:

``` swift
setFreeze(false)
panic()
clearOverrides()
stepForTesting()
start() // after starting scheduler
```

For example:

``` swift
if !on {
    processFrame(publishSnapshotAlways: true)
}
```

and:

``` swift
public func panic() {
    ...
    processFrame(publishSnapshotAlways: true)
}
```

## 4.2 Problem

`processFrame` itself is **not serialized**.

The existing `lock` protects snapshots and small pieces of state, but it
is repeatedly acquired/released inside the frame.

It does not prevent:

``` text
scheduler frame N
+
main/control thread forced frame N+1
```

from executing concurrently.

Possible consequences:

-   out-of-order snapshot publication,
-   interleaved playback/effect/programmer evaluation,
-   two frames writing OutputManager buffers concurrently,
-   one frame flushing some universes after another frame has already
    written newer values,
-   universe-to-universe "tearing" of a supposedly coherent lighting
    frame,
-   non-monotonic semantic snapshot observation if a slower earlier
    frame publishes after a later one,
-   difficult MIDI/Programmer race bugs once interaction frequency
    increases.

The individual downstream classes use locks, but that does not make a
whole frame atomic.

## 4.3 Required fix

Create one dedicated execution serializer for the complete frame
pipeline.

Acceptable approaches:

### Preferred: dedicated serial engine execution queue

Conceptually:

``` swift
private let frameQueue = DispatchQueue(
    label: "com.aurora.engine.frames",
    qos: .userInteractive
)
```

All frame requests go through it.

Or:

### Dedicated `NSLock` / mutex around the entire frame

``` swift
private let frameExecutionLock = NSLock()

private func processFrame(...) {
    frameExecutionLock.lock()
    defer { frameExecutionLock.unlock() }

    ...
}
```

A serial queue is generally cleaner if later engine actions need
ordering.

## 4.4 Rules

-   Scheduler ticks use the serializer.
-   Panic/clear/unfreeze "immediate" frames use the same serializer.
-   Do not hold the small state lock for the entire expensive frame.
-   Avoid recursive entry/deadlock.
-   Decide whether an immediate frame should:
    -   synchronously wait for execution, or
    -   enqueue and return.
-   For panic/unfreeze, synchronous completion may be preferable if
    callers expect physical output to be updated immediately.

## 4.5 Engine lifecycle

Also serialize or protect:

``` swift
startedOutput
start()
stop()
updateConfiguration()
```

`startedOutput` is currently not guarded by the engine state lock.

`EngineScheduler.stop()` cancels the timer but does not create a strong
"no frame is still executing" barrier.

Required shutdown invariant:

> After `LightingEngine.stop()` returns, no old engine frame may later
> flush output.

## 4.6 Tests

Add concurrency tests that run the scheduler while concurrently calling:

``` text
panic
clearOverrides
freeze/unfreeze
forced frame
```

Verify:

-   published `frameIndex` is monotonically increasing,
-   no overlapping frame body executes,
-   output frame snapshots are internally coherent,
-   no post-stop output frame appears.

A small debug-only atomic "frames currently executing" counter can make
this easy to test:

``` text
maxConcurrentFrames must equal 1
```

------------------------------------------------------------------------

# 5. P0 --- Current-Schema Project Files Must Not Silently Disappear

**File:**\
`Sources/AuroraModel/ProjectPackage.swift`

## 5.1 Current behavior

Schema version is:

``` swift
currentSchemaVersion = 3
```

The loader correctly requires the original v1 collections.

But it still loads these as optional:

``` text
midi-rules.json
midi-behaviors.json
drum-profiles.json
midi-feedback.json
effects.json
```

and if `stage-layout.json` is missing:

``` swift
stageLayout = .empty
```

regardless of the package's declared schema version.

## 5.2 Why this is dangerous

Optional-on-load is correct for an **older schema that predates a
file**.

It is not correct for a current v3 package that claims those files
should exist.

Example:

``` text
valid current show:
stage-layout.json contains entire stage design

file gets corrupted/deleted

Aurora loads package
→ silently stageLayout = .empty

operator presses Save
→ empty Stage is now written back
```

The same applies to v3 MIDI behavior/profile data.

This converts package damage into silent data loss.

## 5.3 Required fix

Make requiredness schema-aware.

Conceptually:

``` text
Schema v1:
require v1 files
allow later files to be absent

Schema v2:
require all v1 files
require stage-layout.json
require files introduced by v2

Schema v3:
require all v1/v2 files
require MIDI behavior/rule/profile files introduced by v3
```

For packages written at `currentSchemaVersion`, every collection Aurora
itself always writes should be required unless deliberately documented
as optional.

## 5.4 Effects

Determine the schema version in which `effects.json` became durable.

Then apply the same version-aware rule.

If its introduction predates explicit schema tracking, at minimum:

``` text
schema == currentSchemaVersion
→ effects.json required
```

## 5.5 Tests

For a freshly saved current package, individually remove:

``` text
stage-layout.json
midi-rules.json
midi-behaviors.json
drum-profiles.json
midi-feedback.json
effects.json
```

and assert load fails with a meaningful package-damage error.

Also verify a genuine older-schema fixture can still migrate with
missing later files.

------------------------------------------------------------------------

# 6. P0 --- Remove Trapping `Dictionary(uniqueKeysWithValues:)` From User/Project Data

Current production occurrences include:

``` text
Sources/AuroraEngine/EffectRunner.swift
Sources/AuroraUI/Panels/ProgrammerPanel.swift
Sources/AuroraModel/StageMediaSupport.swift
```

(`ShowProject+DemoSummerNight.swift` is controlled demo data and is not
the concern.)

## 6.1 EffectRunner crash path

`EffectRunner.load(definitions:)` does:

``` swift
effects = Dictionary(uniqueKeysWithValues: definitions.map { ... })
```

`ProjectValidator` already knows duplicate effect IDs are invalid.

But `LightingEngine.load(project:)` computes validation issues and
**continues loading**.

Therefore a corrupted/imported project with duplicate effect IDs can:

``` text
validator reports issue
→ EffectRunner.load()
→ Dictionary(uniqueKeysWithValues:)
→ runtime trap
```

The validator cannot protect against a trap that occurs after
validation.

## 6.2 ProgrammerPanel crash path

``` swift
Dictionary(uniqueKeysWithValues: project.fixtures.map { ($0.id, $0.name) })
```

A duplicate fixture ID in malformed project data can crash the UI while
trying to show Programmer.

## 6.3 StageMediaSupport crash path

``` swift
Dictionary(uniqueKeysWithValues:
    project.mediaAssets.map { ($0.relativePath, $0) }
)
```

Duplicate relative paths can trap during save/materialization.

## 6.4 Required policy

Never use a trapping unique-key initializer on:

-   project data,
-   imported library data,
-   legacy/migrated data,
-   user-authored content.

Use explicit deterministic reduction.

Example:

``` swift
var result: [UUID: EffectInstance] = [:]
for def in definitions {
    if result[def.id] == nil {
        result[def.id] = EffectInstance(definition: def)
    } else {
        // report validation / choose deterministic first-wins
    }
}
```

## 6.5 Structural validation

Preferably define a distinction between:

``` text
fatal structural project errors
```

and:

``` text
nonfatal show resolution warnings
```

Duplicate primary IDs are a strong candidate for fatal load rejection
rather than "engine will try its best."

At minimum, runtime code must tolerate them without trapping.

## 6.6 Extend validator

Add duplicate validation for:

``` text
MediaAssetRef.relativePath
```

and any other dictionary-key fields that assume uniqueness.

------------------------------------------------------------------------

# 7. P0 --- Stage Media Migration Can Collide and Can Trap

**File:**\
`Sources/AuroraModel/StageMediaSupport.swift`

## 7.1 Duplicate-path trap

Covered above:

``` swift
Dictionary(uniqueKeysWithValues: project.mediaAssets...)
```

must be removed.

## 7.2 Legacy basename collision

For legacy absolute references:

``` swift
let abs = URL(fileURLWithPath: ref)
fileName = abs.lastPathComponent
```

Aurora then copies to:

``` text
media/stage/<fileName>
```

Two legacy files:

``` text
/Users/A/BandA/logo.png
/Users/A/BandB/logo.png
```

both become:

``` text
media/stage/logo.png
```

The second can overwrite the first and both Stage objects can end up
referring to one image.

## 7.3 Required fix

When migrating legacy absolute assets, generate a unique package
filename:

``` text
media/stage/<UUID>.png
```

Preserve the original display name separately in `MediaAssetRef.name`.

Do not use basename as storage identity.

## 7.4 Relative-path safety

Current path rejection of `..` is useful.

Harden package containment using URL/path-component containment rather
than:

``` swift
resolvedPath.hasPrefix(packagePath)
```

String prefix tests can be subtly wrong for similarly prefixed
directories.

Use standardized/resolved URLs and explicit package-relative components.

## 7.5 Tests

-   two different legacy `logo.png` files migrate independently,
-   duplicate existing `MediaAssetRef.relativePath` does not trap,
-   unsafe `../` path rejected,
-   similarly prefixed outside directory cannot pass containment.

------------------------------------------------------------------------

# 8. P1 --- ENTTEC Serial Transport Needs Real I/O Serialization

**File:**\
`Sources/AuroraOutput/ENTTECUSBDMXProDriver.swift`

## 8.1 Current transport

`MacENTTECSerialTransport` is:

``` swift
@unchecked Sendable
```

with mutable:

``` text
fd
handle
isOpen
```

and no lock.

The driver protects some state with its own lock, but releases that lock
before:

``` swift
transport.write(packet)
```

`stop()` can close the transport concurrently.

Possible race:

``` text
engine thread:
guard running
unlock
write(fd)

UI/config thread:
stop
close(fd)

engine:
write using closed/reused fd
```

## 8.2 Required fix

Serialize:

``` text
open
write
close
```

for a physical transport.

Recommended:

-   dedicated serial I/O queue owned by the driver, or
-   internal transport lock.

Do not close while a write is in progress.

If transport confinement is guaranteed by driver design, make that
invariant explicit and remove unnecessary unchecked Sendable exposure
where possible.

## 8.3 Partial POSIX writes

Current write performs one:

``` swift
Darwin.write(fd, base, buf.count)
```

and treats any partial result as failure.

POSIX writes can legally be partial.

Implement a loop:

``` text
offset = 0
while offset < count:
    write remaining bytes
    if EINTR → retry
    if result <= 0 → error
    offset += result
```

## 8.4 Tests

A mock transport that simulates partial writes would be useful if the
loop is extracted into a testable helper.

Also stress:

``` text
send
stop
send
start
```

across concurrent queues.

------------------------------------------------------------------------

# 9. P1 --- Do Not Label Generic Serial Devices as ENTTEC USB DMX Pro

**File:**\
`Sources/AuroraOutput/ENTTECUSBDMXProDriver.swift`

## 9.1 Current enumerator

Candidates include device names containing:

``` text
usbserial
usbmodem
SLAB
DMX
FTDI
```

But every candidate is returned as:

``` swift
deviceType: .enttecUSBDMXPro
connectionState: .available
```

even when `looksDMX == false`.

The display string may say:

``` text
Serial <name>
```

but the semantic type still says ENTTEC USB Pro.

## 9.2 Risk

Aurora can present an unrelated serial device as a supported DMX Pro and
then write ENTTEC binary label-6 frames to it.

That is not safe device identification.

## 9.3 Required minimum fix

Unknown candidates:

``` swift
deviceType = .other
```

Only devices positively identified or strongly opted-in by the user as
ENTTEC Pro should instantiate `ENTTECUSBDMXProDriver`.

## 9.4 Better production fix

Use IOKit/CoreFoundation device properties to identify:

-   vendor ID,
-   product ID,
-   USB serial number,
-   stable device identity.

At minimum, persist selected hardware by something more stable than
`/dev/cu.*` path.

This can be a hardware-smoke-test closeout if IOKit work is larger, but
**do not mark arbitrary FTDI/usbmodem devices as ENTTEC Pro in the
meantime**.

------------------------------------------------------------------------

# 10. P1 --- `universeFilter` Must Not Be Public Mutable Shared State

**File:**\
`Sources/AuroraOutput/ENTTECUSBDMXProDriver.swift`

The driver reads `universeFilter` under its lock, but if the property
itself is publicly mutable, external callers can mutate the `Set`
without that lock.

Convert to:

``` text
private storage
+
locked snapshot/setter/update method
```

or immutable initialization if runtime change is unnecessary.

All state accessed by a class declared `@unchecked Sendable` must obey
one synchronization policy.

------------------------------------------------------------------------

# 11. P1 --- Art-Net Startup Can Falsely Report Ready

**File:**\
`Sources/AuroraOutput/ArtNetOutputDriver.swift`

## 11.1 Current startup

The driver waits:

``` swift
sem.wait(timeout: .now() + 0.5)
```

but ignores whether the semaphore timed out.

Then:

``` swift
if let startError {
    state = degraded
} else {
    state = ready
}
```

If the NWConnection remains `.preparing` for 500 ms:

``` text
wait times out
startError == nil
→ state = ready
```

even though `.ready` was never reached.

## 11.2 Later state changes

`stateUpdateHandler` only signals the semaphore.

It does not continuously update:

``` text
ready
failed
cancelled
```

after startup.

So a connection can later fail without health reflecting it until a send
completion reports an error.

## 11.3 Required fix

Track startup result explicitly:

``` text
ready
failed(error)
cancelled
timedOut
```

Timeout should remain:

``` text
starting / degraded
```

not ready.

The `stateUpdateHandler` should continue updating health state
throughout the connection lifecycle.

## 11.4 Swift concurrency

Avoid an unsynchronized captured mutable `startError` if enabling
stricter concurrency checking.

A small locked state holder or queue-confined startup state is cleaner.

------------------------------------------------------------------------

# 12. P1 --- sACN Connection Creation Has a Race

**File:**\
`Sources/AuroraOutput/SACNOutputDriver.swift`

Current `connection(forHost:)` does:

``` text
lock
check existing
unlock

create connection
start connection

lock
store
unlock
```

Two concurrent first sends to the same host can both see "no
connection," create two NWConnections, and one becomes untracked.

This is unlikely in today's single engine path, but the class advertises
thread safety through `@unchecked Sendable`, and the engine frame
serializer should not be the driver's only safety assumption.

Fix by:

-   creating/storing atomically under one synchronization policy, or
-   using the driver's serial network queue for connection creation.

Also consider keying by:

``` text
host + port
```

rather than host only if destination port can change without a full
connection reset.

------------------------------------------------------------------------

# 13. P1 --- Aurora Library Package Can Silently Lose Data

**File:**\
`Sources/AuroraModel/AuroraLibraryPackage.swift`

## 13.1 Load

Manifest is required.

Every actual library content file is loaded as:

``` swift
(try? readJSON(...)) ?? []
```

Therefore:

``` text
palettes.json corrupt
→ []
```

without telling the operator the library is damaged.

This is especially dangerous because library import/merge can then
appear to succeed with missing content.

## 13.2 Save

Current save:

``` text
write temp
remove existing destination
move temp to destination
```

If the move fails after destination removal, the previous valid library
is gone.

`ProjectPackage.save` already contains a safer backup/restore
replacement design.

## 13.3 Required fix

For schema v1:

-   define required files,
-   throw on missing/malformed required files,
-   add a JSON file size limit similar to `.aurora`,
-   use backup/replace recovery equivalent to `ProjectPackage`,
-   recover orphan temp/backup packages if worthwhile.

## 13.4 Tests

-   malformed `palettes.json` must fail load,
-   missing definitions file must fail load,
-   simulated replacement failure preserves original library.

------------------------------------------------------------------------

# 14. P1 --- C6 Splash Tests Do Not Test the Production Splash

**File:**\
`Tests/AuroraUITests/LaunchSplashC6Tests.swift`

## 14.1 Current tests

Examples:

``` swift
let minimum: TimeInterval = 2.85
let maximum: TimeInterval = 12.0
```

and:

``` swift
let splashUsesTypographicWordmark = true
```

The tests then assert those locally declared constants.

This tests the **test author's copy of the requirement**, not production
code.

The comment acknowledges:

``` text
Full LaunchSplashController lives in the Aurora app target
```

but the practical result is that the named C6 tests offer almost no
protection against production regression.

For example, production could change to:

``` text
minimum = 20 seconds
```

and `LaunchSplashC6Tests` would still pass.

## 14.2 Required fix

Move the testable policy/state machine into a library target.

Conceptually:

``` swift
LaunchSplashPolicy
LaunchSplashStateMachine
```

Production `LaunchSplashController` consumes it.

Tests import and exercise the real type.

## 14.3 Required cases

Test real behavior for:

-   timing constants come from production,
-   `beginIfNeeded` is idempotent,
-   ready-before-minimum waits correctly,
-   minimum-before-ready waits for readiness,
-   failure prevents normal auto-dismiss,
-   Continue after failure dismisses,
-   watchdog path after maximum,
-   force hide/cancellation,
-   only intended process/main-window entry point constructs splash
    state where testable.

UI snapshot tests are optional.

Behavioral state-machine tests are not.

------------------------------------------------------------------------

# 15. P1 --- C5 Window Tests Still Stop Short of Real Lifecycle Coverage

**File:**\
`Tests/AuroraUITests/WorkspaceFloatC5Tests.swift`

These tests are much better than the splash tests and validate the pure
`WorkspaceFloatState`.

However, some named contracts remain conceptual.

Example:

``` swift
testQuitPreservesFloatingConceptually
```

does not exercise:

``` text
FloatingSurfaceWindowCoordinator
NSWindow close
termination guard
exact window registration
```

Because the coordinator lives in the executable target.

## Required improvement

Extract the close-policy/lifecycle decision into a small testable
library type or add an app-target macOS test target.

Test:

``` text
user close → redock
app quit → preserve floating
Dock command → close exact registered surface
```

This is not a reason to redo C5; it is regression coverage.

------------------------------------------------------------------------

# 16. P1 --- Remove Dead Legacy Stage UI From Production

**Files:**

``` text
Sources/Aurora/Shell/BuildWorkspaceHost.swift
Sources/AuroraUI/Panels/StagePanel.swift
```

## 16.1 Current product flow

`BuildWorkspaceMode.stage` now aliases to:

``` text
DESIGN + enter Edit Stage
```

and the production Stage surface is:

``` text
DesignStageSurface
+
StageCanvasView
```

This is the correct architecture.

## 16.2 Dead legacy code

`BuildWorkspaceHost` still contains a private `stageMainRow(totalW:)`
that constructs:

``` swift
StagePanel(...)
```

but the current mode switch no longer uses it.

`StagePanel.swift` remains approximately **461 lines** of a second Stage
shell with separate state and older behavior.

This is exactly the divergence risk C5 was intended to eliminate.

## 16.3 Required fix

Keep one Stage workflow.

Preferred:

-   remove dead `stageMainRow`,
-   remove `StagePanel` from production if no runtime caller remains,
-   update old checkpoint tooling to use production `DesignStageSurface`
    or move legacy Stage-only code behind DEBUG/tooling if absolutely
    required.

Do not retain a second complete Stage implementation "just in case."

------------------------------------------------------------------------

# 17. P1 --- Do Not Silently Swallow Stage Document Command Failures

**Files:**

``` text
Sources/AuroraUI/Stage/StageCanvasView.swift
Sources/AuroraUI/Panels/StagePanel.swift
```

Current code includes:

``` swift
catch {}
```

during Stage layout commit.

A failed document command can therefore make a user drag/resize
something and simply see it fail or revert with no explanation and no
diagnostic.

Replace empty catch with:

-   status note,
-   diagnostics event,
-   optional error callback,
-   user-visible nonmodal error when appropriate.

If legacy `StagePanel` is removed, one of the two empty catches
disappears automatically.

No production mutation path should silently discard an error unless
there is a documented reason.

------------------------------------------------------------------------

# 18. P2 / Pre-Programmer --- Reduce Redundant Global UI Invalidations

**Files include:**

``` text
Sources/Aurora/AppModel.swift
Sources/Aurora/ProgrammerPresentationStore.swift
workspace/project/controller call sites
```

## 18.1 Current pattern

`AppModel` subscribes to child `ObservableObject.objectWillChange` and
forwards those changes.

At the same time many call sites:

1.  mutate a child controller that already publishes,
2.  then explicitly call:

``` swift
appModel.notifyUI()
```

This can produce redundant app-wide invalidation.

## 18.2 Why it matters now

The next feature is a large LightKey-style color Programmer.

A color wheel can emit pointer changes at display rate:

``` text
60–120 updates/sec
```

If every sample causes:

``` text
Programmer engine mutation
+ ProgrammerPresentationStore full refresh
+ AppModel-wide objectWillChange
+ child objectWillChange
```

then Browser, Inspector, Stage, floating windows, shelves, etc. may all
be asked to recompute unnecessarily.

The UI may still "work," but performance debt will appear exactly when
the new Programmer is added.

## 18.3 Required targeted cleanup

Before or as the Programmer implementation begins:

-   inventory explicit `notifyUI()` calls,
-   remove calls that merely duplicate child ObservableObject
    publication,
-   reserve `notifyUI()` for state that is not independently observable,
-   localize high-frequency Programmer state observation,
-   keep Stage Preview live,
-   avoid invalidating every shell surface per color-wheel pixel.

## 18.4 Instrument first

Add debug instrumentation around:

``` text
ProgrammerPanel body evaluations
BuildWorkspaceHost body evaluations
StageCanvasView body evaluations
AppModel.objectWillChange rate
```

Then drag an existing intensity control continuously.

Use measurement, not guesswork.

## 18.5 Desired high-frequency architecture

Conceptually:

``` text
pointer sample
→ Programmer engine/state update immediately
→ Programmer presentation updates locally
→ Stage preview sees resolved/output update
```

without forcing unrelated UI panels to redraw at the same rate.

Do not perform a giant ObservableObject rewrite before measurement.

------------------------------------------------------------------------

# 19. P2 --- `ProgrammerPresentationStore.refresh()` Always Increments Revision

Before the new Color Engine lands, inspect whether:

``` swift
ProgrammerPresentationStore.refresh(...)
```

increments its revision even when the resolved presentation is equal.

If so, avoid publishing a revision/change when there is no semantic
presentation change.

This matters particularly for:

-   live output changes that do not alter capability presentation,
-   selection-stable color-wheel updates,
-   repeated engine snapshot callbacks.

Separate:

``` text
capability/selection presentation
```

from:

``` text
high-frequency value state
```

where practical.

The Programmer should not rebuild its entire capability model every time
RGB changes by 1%.

------------------------------------------------------------------------

# 20. P2 --- Remove Unused Floating Window Lifecycle Proxy

**File:**\
`Sources/Aurora/Shell/FloatingSurfaceWindowCoordinator.swift`

The repository contains `WindowCloseProxy`, documented as:

``` text
placeholder for future NSWindowDelegate use
```

while actual lifecycle is NotificationCenter-based.

If it is not registered/used, remove it.

This is small, but C5 is now closed enough that dead lifecycle objects
should not remain to confuse the next engineer.

------------------------------------------------------------------------

# 21. P2 --- Review Debounced Workspace Store Static Mutable State

**Files:**

``` text
Sources/AuroraUI/Workspace/FloatSurfaceID.swift
Sources/AuroraUI/Workspace/WorkspaceLayoutStore.swift
```

Both contain static mutable pending state / DispatchWorkItems.

Ensure these are confined to one actor/queue.

Given all workspace mutations are UI-driven, simplest is often:

``` text
@MainActor store state
```

with delayed persistence dispatched safely.

Do not leave static mutable state whose safety exists only by
convention.

This is a reliability cleanup, not a design rewrite.

------------------------------------------------------------------------

# 22. P2 --- Incrementally Enable Strict Concurrency Checking

The repository has more than twenty `@unchecked Sendable` classes,
including:

``` text
LightingEngine
EngineScheduler
Programmer
PlaybackController
EffectRunner
OutputManager
ArtNetOutputDriver
SACNOutputDriver
ENTTEC transport/driver
Remote host/server/session
MIDI input/output/runtime classes
FixtureLibrary
DiagnosticsStore
```

This is not inherently wrong.

Many use explicit locks.

But `@unchecked Sendable` means the compiler is trusting the
implementation.

The concrete races found in Engine/ENTTEC/sACN demonstrate why an
incremental strict-concurrency pass would be valuable.

Recommended:

-   enable complete strict concurrency warnings in CI/build
    configuration where feasible,
-   fix warnings module-by-module,
-   do not migrate the entire app to actors in one pass,
-   remove `@unchecked Sendable` where real isolation can be expressed.

Prioritize:

``` text
AuroraEngine
AuroraOutput
AuroraMIDI
AuroraRemote
```

------------------------------------------------------------------------

# 23. P2 --- Use One Error-Reporting Policy for `try?` UI Mutations

There are a number of commands invoked with:

``` swift
try? session.perform(...)
```

for operations such as:

-   group add/remove,
-   MIDI mapping removal,
-   palette group cancellation,
-   fixture definition embedding.

Some best-effort `try?` use is reasonable.

But command failures that represent user edits should generally reach:

``` text
status note
DiagnosticsStore
nonmodal error
```

rather than disappearing.

Do not mechanically remove every `try?`.

Classify them:

``` text
expected benign cleanup/cancel
→ try? acceptable

user-requested durable mutation
→ report failure
```

------------------------------------------------------------------------

# 24. P2 --- Remove Duplicate Documentation/Dead Comments Around Engine

`LightingEngine.swift` contains duplicate comments:

``` text
/// Non-destructive model update...
/// Non-destructive model update...
```

Minor, but this file is central real-time code.

During the engine concurrency fix, clean stale/duplicate comments and
document the new threading contract at the class level.

Add a short section such as:

``` text
Threading:
- stateLock protects snapshots/config
- frameQueue serializes complete frame execution
- playback/programmer/effects own internal synchronization
```

This is far more useful than scattered PR-history comments.

------------------------------------------------------------------------

# 25. P2 --- Art-Net / sACN Health Should Represent Real Connection State

Beyond the concrete Art-Net startup bug:

-   review whether `.ready`, `.degraded`, `.failed`, `.disabled`,
    `.starting` have consistent semantics across all drivers,
-   ensure Settings/status UI does not interpret `_isRunning == true` as
    healthy,
-   health should mean "driver is operational," not merely "start() was
    called."

This will matter during hardware smoke testing and network-node
troubleshooting.

------------------------------------------------------------------------

# 26. P2 --- Remote Server: Add/Confirm Request Body Enforcement at Socket Layer

`RemoteWebServer` defines:

``` text
maxBodyBytes = 64 KB
maxHeaderBytes = 16 KB
```

The testable route handlers are reasonable.

Confirm the socket-level HTTP parser enforces:

-   header cap before delimiter,
-   declared Content-Length cap,
-   actual body cap,
-   malformed/negative/huge length rejection,
-   connection close on abuse.

This audit did not identify an immediate authorization bypass in the
reviewed route flow, but these constants should correspond to actual
parser enforcement, not merely documentation.

Keep remote binding default conservative for show safety.

------------------------------------------------------------------------

# 27. P2 --- C6 Splash Implementation Itself Can Be Accepted

The production C6 splash code was reviewed.

No architectural C6 blocker was found that warrants reopening the splash
design.

Good properties include:

-   main-window-only mounting,
-   MainActor controller,
-   weak task captures,
-   cancellation in deinit,
-   minimum and maximum timing policy,
-   failure hold with Continue,
-   bootstrap phase reporting,
-   non-permanent failure state.

The key C6 issue is **regression coverage**, not the production design.

Once the real tests in Finding #14 are added, C6 can remain closed.

------------------------------------------------------------------------

# 28. P2 --- C5 Implementation Can Remain Closed Subject to Regression Tests

The current C5 code now uses:

-   exact surface/window registration,
-   reusable production workspace surfaces,
-   production `DesignStageSurface`,
-   frame persistence hooks,
-   monitor visible-frame recovery,
-   compact restore behavior.

No reason was found to redo C5.

Cleanups:

-   remove dead `WindowCloseProxy`,
-   strengthen lifecycle tests,
-   keep one Stage implementation.

------------------------------------------------------------------------

# 29. Test/Build Caveat for This Audit

The supplied repository includes C6 checkpoint evidence stating that
macOS builds/tests passed.

This review environment is Linux and cannot truthfully execute the
complete native Aurora target because Aurora depends on macOS-only
frameworks such as:

``` text
AppKit
CoreMIDI
Network/macOS UI APIs
```

Therefore this document does **not** claim a new independent macOS
`xcodebuild` run.

Grok must run all required builds/tests natively on macOS after
remediation.

------------------------------------------------------------------------

# 30. Required New Test Suites

Create focused regression tests rather than only adding broad
integration tests.

Recommended additions:

``` text
LightingEngineFrameSerializationTests
ProjectPackageCurrentSchemaIntegrityTests
DuplicateProjectIdentityRobustnessTests
StageMediaMigrationCollisionTests
ENTTECSerialLifecycleTests
ArtNetDriverStateTests
SACNConnectionConcurrencyTests
AuroraLibraryPackageIntegrityTests
LaunchSplashProductionPolicyTests
FloatingWindowLifecyclePolicyTests
```

Use existing module test targets where possible.

------------------------------------------------------------------------

# 31. Recommended Implementation Order

## Pass 1 --- P0 real-time/data safety

1.  Serialize `LightingEngine.processFrame`.
2.  Make engine start/stop lifecycle race-safe.
3.  Make current-schema ProjectPackage files version-required.
4.  Remove trapping project-data dictionary construction.
5.  Fix Stage media duplicate/collision behavior.

Run Model/Engine tests.

------------------------------------------------------------------------

## Pass 2 --- P1 hardware/output reliability

6.  Serialize ENTTEC open/write/close.
7.  Implement partial-write loop.
8.  Stop classifying generic serial devices as ENTTEC Pro.
9.  Lock/private `universeFilter`.
10. Fix Art-Net startup/state transitions.
11. Fix sACN connection creation race.

Run Output tests.

------------------------------------------------------------------------

## Pass 3 --- package/library/test integrity

12. Harden `.auroralib` load/save.
13. Replace fake C6 splash tests with production-policy tests.
14. Strengthen C5 lifecycle coverage.
15. Remove empty Stage catches / report errors.

------------------------------------------------------------------------

## Pass 4 --- production-code cleanup before new UI

16. Remove dead legacy `StagePanel` path.
17. Remove unused window lifecycle proxy.
18. Review workspace persistence static state confinement.
19. Clean duplicate central-engine threading comments.

------------------------------------------------------------------------

## Pass 5 --- Programmer performance readiness

20. Instrument AppModel invalidation.
21. Remove redundant global `notifyUI()` calls.
22. Separate capability presentation refresh from high-frequency value
    updates.
23. Establish a performance baseline before implementing the new
    RGB/White/Amber/UV color UI.

Then STOP for review.

------------------------------------------------------------------------

# 32. P0 Acceptance Checklist

-   [ ] Engine can never execute two frames concurrently.
-   [ ] Stop waits/guarantees no old frame will later flush.
-   [ ] Panic/unfreeze cannot race scheduler frame.
-   [ ] Current v3 missing Stage file is treated as package damage.
-   [ ] Current v3 missing MIDI behavior files are treated as package
    damage.
-   [ ] Old-schema packages still migrate.
-   [ ] Duplicate effect IDs cannot trap.
-   [ ] Duplicate fixture IDs cannot crash Programmer rendering.
-   [ ] Duplicate media paths cannot trap save.
-   [ ] Two legacy images named `logo.png` migrate independently.

------------------------------------------------------------------------

# 33. Hardware/Output Acceptance Checklist

-   [ ] ENTTEC close cannot race a write.
-   [ ] Partial POSIX writes complete correctly.
-   [ ] Generic USB serial device is not labeled as ENTTEC Pro.
-   [ ] Art-Net timeout cannot report ready.
-   [ ] Art-Net later failure updates health.
-   [ ] sACN only creates one tracked connection per destination.
-   [ ] Output driver health remains truthful during network loss.
-   [ ] Engine stop results in no subsequent DMX/network flush.

------------------------------------------------------------------------

# 34. Persistence Acceptance Checklist

-   [ ] Damaged current `.aurora` fails clearly rather than silently
    deleting data.
-   [ ] Damaged `.auroralib` fails clearly.
-   [ ] Failed library replace preserves previous valid library.
-   [ ] Project Save/Save As Stage media remains portable.
-   [ ] Duplicate media metadata cannot crash package save.
-   [ ] Legacy asset migration is collision-safe.

------------------------------------------------------------------------

# 35. UI/Regression Acceptance Checklist

-   [ ] C4 Stage ghosting remains fixed.
-   [ ] Stage move/resize/rotate/aim still work.
-   [ ] C5 floating surfaces still share production state.
-   [ ] C5 frame restoration still works.
-   [ ] C6 splash looks unchanged.
-   [ ] C6 real behavior tests exercise production policy.
-   [ ] Exactly one production Stage shell remains.
-   [ ] Stage command failures are visible/logged.
-   [ ] Existing Programmer controls still work.
-   [ ] Continuous Programmer drag does not trigger pathological
    full-app redraws.

------------------------------------------------------------------------

# 36. Native Build Gate

After all remediation, Grok must run on macOS:

``` text
swift test
swift build --target Aurora
xcodebuild -scheme Aurora -configuration Debug build
```

or the repo's canonical equivalent.

Also run any Xcode-only/app-target tests added for:

-   floating windows,
-   splash,
-   AppKit hardware/device integration.

Do not consider this audit closed on Linux-only/package-only test
results.

------------------------------------------------------------------------

# 37. What Does NOT Need to Be Rewritten

Do **not** use this audit as an excuse to redo:

-   C4 Stage Designer architecture,
-   C4.4 ghosting solution,
-   C5 undockable-window concept,
-   C6 splash visual design,
-   ProjectPackage's existing atomic backup design,
-   AppModel composition root wholesale,
-   engine merge model wholesale,
-   Remote protocol wholesale,
-   MIDI engine before its planned redesign.

The goal is hardening, not churn.

------------------------------------------------------------------------

# 38. Programmer Color Engine Handoff Gate

Do not begin the large LightKey-style Programmer Color Engine
implementation until at least the P0 items are complete.

Before starting Color Programmer implementation, specifically confirm:

``` text
engine frame serialization complete
duplicate-project crash paths removed
global UI invalidation baseline measured
Programmer presentation refresh behavior understood
```

The new Programmer will create much higher-frequency UI and engine
activity than the current controls.

Fixing these foundations first will make color-wheel bugs substantially
easier to reason about.

------------------------------------------------------------------------

# 39. Advanced MIDI Engine Handoff Gate

The Advanced MIDI Engine should remain parked until this hardening pass
is reviewed.

Before MIDI redesign begins, confirm:

-   engine frame serializer is in place,
-   MIDI-triggered forced actions cannot overlap engine frames unsafely,
-   project v3 MIDI files have strict current-schema integrity,
-   duplicate MIDI IDs do not trap runtime structures,
-   output/lifecycle reliability is improved,
-   strict concurrency warnings have at least been assessed for
    AuroraMIDI/AuroraEngine.

This prevents the MIDI redesign from inheriting hidden concurrency
ambiguity.

------------------------------------------------------------------------

# 40. Final Verdict

C6 itself is acceptable.

Aurora is **not in need of another UX redesign before the
Programmer/MIDI work**.

What it needs now is a compact engineering-hardening pass.

The primary theme of this audit is:

> The visible application has matured faster than a few of the invisible
> contracts underneath it.

The fixes above close those contracts:

-   one engine frame at a time,
-   damaged files fail loudly instead of becoming empty,
-   malformed project data cannot trigger Swift traps,
-   hardware I/O has explicit serialization,
-   network health tells the truth,
-   tests exercise production behavior rather than duplicated
    expectations,
-   one canonical Stage UI remains,
-   and the upcoming high-frequency Programmer does not redraw the
    entire workstation unnecessarily.

Once those are complete, Aurora will be in a much safer position to
begin the new Programmer Color Engine and Advanced MIDI Engine phases.
