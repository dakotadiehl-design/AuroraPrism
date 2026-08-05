# Aurora — Final Pre-UI Blockers and Cleanup

> **STATUS: HISTORICAL / COMPLETED (2026-08-05)**  
> BLOCKER-1 + PRE-UI-1/2/3 + UI-FOUNDATION-5 implemented on `main`.  
> UI-FOUNDATION-1/2/3/4 carried into first UI-foundation PR (not backend).  
> Active memory: `docs/PROJECT_HANDOFF.md` + `docs/UI_BACKEND_CONTRACT.md`.

**Review target:** `Aurora_uigate.zip`  
**Reviewed HEAD:** `a11c475` / implementation HEAD `904aebc`  
**Review purpose:** Final go/no-go review before beginning the full Aurora visual UI redesign.

## Executive verdict

Aurora is **very close to UI-ready**. The previous UI-gate remediation is genuinely present in the code and the backend architecture remains sound. I do **not** recommend another broad refactor and I do **not** recommend reopening the completed P0-P3 roadmap.

There is, however, **one real data-safety blocker** that should be fixed before UI development begins: package writes are not serialized, so background autosave can race a manual Save/Save As and overwrite a newer package with an older snapshot.

After `BLOCKER-1` is fixed and regression-tested, I consider the backend ready for the UI redesign. The remaining items in this document are small enough to complete in the same pass or carry directly into the first UI-foundation PR.

---

# BLOCKER-1 — Serialize all writes to an `.aurora` package

**Priority:** P0 / must fix before UI mode  
**Area:** project persistence, autosave, manual Save/Save As  
**Files:**

- `Sources/Aurora/AppModel.swift`
- `Sources/Aurora/Controllers/ProjectController.swift`
- `Sources/Aurora/Controllers/AutosaveController.swift`
- `Sources/AuroraModel/ProjectPackage.swift`

## Finding

`performBackgroundAutosave()` performs `ProjectPackage.save(...)` from a detached task while `ProjectController.save(to:)` can independently call `ProjectPackage.save(...)` synchronously for user-initiated Save/Save As.

There is no shared writer lock, actor, serial queue, save coordinator, generation lease, or in-flight-save cancellation mechanism.

The temp package names are unique, but the final replacement destination is not.

## Failure scenario

1. Document state **A** is dirty.
2. Autosave snapshots state A and begins writing in the background.
3. User makes additional edits, producing state **B**.
4. User presses Command-S. Manual save successfully writes state B to `Show.aurora`.
5. The older autosave finishes later.
6. Its `ProjectPackage.save` sees `Show.aurora`, moves it aside, and installs the stale state-A package.
7. MainActor state checking correctly notices that the autosave snapshot is stale and leaves the in-memory document dirty.
8. **But the filesystem has already been replaced with stale state A.**

A crash or quit before another successful save can therefore lose the newer state-B package that the user explicitly saved.

Two overlapping autosaves can also race each other if package I/O ever exceeds the autosave interval.

## Required fix

Create a **single save coordinator** for package writes.

Recommended design:

```text
ProjectController / AutosaveController
              |
              v
       ProjectSaveCoordinator
          (actor or serial queue)
              |
              v
       ProjectPackage.save(...)
```

The coordinator should serialize **all writes to the same destination**.

A Swift `actor` is a good fit, provided the macOS app integration remains straightforward.

### Required semantics

- Manual Save and Save As must never run concurrently with autosave for the same package.
- An autosave that becomes stale while waiting should be skipped rather than written.
- A user-initiated Save should take precedence over queued stale autosaves.
- Only the state actually written may become the saved generation.
- A stale autosave must not replace a newer manual save.
- Save As asset preservation must retain its current correct behavior.
- ProjectPackage's existing temp/backup rollback behavior should remain unchanged.

One possible API shape:

```swift
actor ProjectSaveCoordinator {
    func autosave(snapshot: SaveSnapshot) async throws -> SaveResult
    func save(snapshot: SaveSnapshot) async throws -> SaveResult
}
```

`SaveSnapshot` should include at least:

- project value snapshot
- document state ID
- destination URL
- source package URL for media/layout preservation
- save kind (`manual`, `saveAs`, `autosave`)

Do not solve this with unrelated sleeps or by merely checking generation after the write. The correctness boundary must exist **before filesystem replacement**.

## Regression tests

Add deterministic tests using an injectable/delayed writer or save coordinator:

### Test A — stale autosave cannot overwrite manual save

1. Begin autosave for state A and pause before replacement.
2. Save state B manually.
3. Resume autosave A.
4. Load package from disk.
5. Assert package contains B.

### Test B — autosave coalescing

Queue A, B, C autosaves while a writer is busy. The coordinator may skip obsolete A/B and write only the newest eligible state.

### Test C — Save As during autosave

Save As to a new package while an autosave of the old package is active. Both destinations must remain valid and media/layout assets preserved.

### Test D — manual Save establishes save point only for written state

Concurrent edits during a queued save must leave the document dirty unless the exact current state was written.

---

# PRE-UI-1 — Output health presentation can become stale

**Priority:** P1 / fix before the new status chrome is trusted  
**Area:** OutputController, Perform mode, diagnostics

## Finding

`OutputController.outputStatus` is refreshed on configuration changes and a few explicit app actions, but asynchronous driver health changes are not guaranteed to refresh the string.

For example, an Art-Net or sACN send can later change a driver's health to `.degraded` after a Network.framework completion error. `ShowControlController` polls `output.outputStatus`, but that property may still contain the older text because the poll does not call `refreshOutputStatus()`.

The planned Aurora UI has intentionally quiet but trustworthy status indicators. A green-looking output status that remains stale after a driver failure defeats that design.

## Recommended fix

Make driver health the source of truth rather than a manually cached string.

Good approaches:

- Have `OutputController` periodically poll `healthSnapshots()` at a modest presentation rate (for example 2–4 Hz), or
- Compute a small immutable `OutputPresentationSnapshot` from health on demand during the existing presentation poll.

Do not push 40 Hz output frames through SwiftUI observation.

The future UI should receive semantic states such as:

```text
healthy
warning / degraded
failed
disabled
```

plus concise detail text.

## Regression test

Inject a mock health-reporting driver, transition it from ready to degraded asynchronously, and verify the presentation snapshot/status reflects the change without a configuration action or GO press.

---

# PRE-UI-2 — Make OutputDriver running-state access truly thread-safe

**Priority:** P1/P2 concurrency hardening  
**Area:** `AuroraOutput`

## Finding

`OutputManager.flush()` runs on the engine scheduler thread and reads:

```swift
let activeDrivers = drivers.values.filter(\.isRunning)
```

while UI/configuration code may call `start()` / `stop()` on drivers concurrently.

Several drivers store `isRunning` as a plain `public private(set) var`, even though writes occur while holding the driver's internal lock. The getter itself is not lock-protected.

This creates a potential data race under Thread Sanitizer during live enable/disable operations.

Affected implementations include at least:

- `ArtNetOutputDriver`
- `SACNOutputDriver`
- `ENTTECUSBDMXProDriver`
- `NullOutputDriver`
- `MockOutputDriver`

## Recommended fix

Either:

1. make `isRunning` a lock-protected computed property in each concurrent driver, or
2. change the output-manager contract so `flush()` does not need an unsynchronized pre-read and lets each driver atomically decide whether to accept `send()`.

Keep start/stop/send/health state internally consistent under the same synchronization policy.

Run the output tests under Thread Sanitizer on macOS once the Xcode project is active.

---

# PRE-UI-3 — Call the existing shutdown path during normal app termination

**Priority:** P1/P2 live lifecycle  
**Area:** macOS app shell

## Finding

`AppModel.shutdown()` correctly stops autosave, status timers/engine, MIDI/OSC, output and remote services.

However, the AppKit delegate currently confirms unsaved changes in `applicationShouldTerminate` and then returns `.terminateNow`; it does not call the shutdown path. `AppModel.deinit` also intentionally contains no cleanup call.

The OS will eventually tear down sockets/process resources, but a professional live-control application should perform an explicit orderly shutdown.

## Required fix

Wire:

```swift
func applicationWillTerminate(_ notification: Notification) {
    appModel?.shutdown()
}
```

or equivalent guaranteed lifecycle handling.

### Important product note

Do **not** automatically add a blackout-on-quit policy without explicitly defining it. Some users may want hold-last-look / receiver timeout behavior and others may want blackout.

For now, orderly driver/engine shutdown is enough. A configurable exit-output policy can be designed later.

---

# UI-FOUNDATION-1 — Decide where controller-aware UI composition lives

**Priority:** UI architecture decision, not a backend rewrite  
**Area:** `AuroraUI` vs app target

## Finding

The new backend contract correctly says views should prefer focused controllers such as `ProjectController`, `ShowControlController`, `InputController`, etc.

Those controller types currently live in the `Aurora` executable/app target, while the reusable `AuroraUI` package sits *below* the app in the dependency graph.

Therefore `AuroraUI` cannot directly import or bind those controller concrete types without creating a dependency inversion/cycle.

The current application bridges this with `PanelRegistry`, closures, `WorkspacePanelContext`, and direct engine/session values. That was a sensible scaffolding strategy, but the upcoming redesign should make the ownership boundary explicit rather than accidentally evolving a forest of closure adapters.

## Recommended direction

**Do not move the lighting engine/model into the UI and do not make AuroraUI depend on the executable target.**

Choose one of these before implementing dozens of new screens:

### Option A — Recommended for now

Treat `AuroraUI` as the **design-system and reusable pure-view library**:

```text
AuroraUI
  AuroraPanel
  AuroraButton
  AuroraFader
  AuroraPaletteTile
  AuroraStatusIndicator
  pure view models / presentation structs
  reusable panel content that needs no app-controller type

Aurora app target
  controller-aware screen composition
  BuildWorkspaceView
  PerformWorkspaceView
  Settings views/adapters
  PanelRegistry / controller bindings
```

This requires no backend module reshuffle and fits the current dependency graph.

### Option B — Later if desirable

Create an `AuroraApplication` / `AuroraPresentation` library containing controller-facing presentation contracts and controller types that do not require AppKit. The app shell and AuroraUI can then depend on that lower module.

Do not perform this refactor merely for aesthetic architecture if Option A remains clean.

## UI rule

The redesign must not fall back to making every new view depend on the entire `AppModel` just because it is convenient.

---

# UI-FOUNDATION-2 — Add test coverage for the app/controller integration layer

**Priority:** P2 / strongly recommended during first UI PR  
**Area:** testing architecture

## Finding

The repository reports 255 package tests and the library-level test coverage is substantial.

However, several of the latest UI-gate fixes live in the executable/app layer:

- multi-observer controller wiring
- OSC/remote live-dispatch ordering
- background autosave orchestration
- app frame-rate application
- output presentation state
- controller composition

These are difficult or impossible for the current package tests to import directly because they live in the executable target.

The latest remediation added excellent lower-level tests for MIDI stream parsing, routing, validation and performance totals, but not integration tests for all of the app-level wiring described above.

## Recommendation

During the first UI-foundation work, establish one importable/testable presentation/application layer or an Xcode app test target capable of exercising controller composition.

At minimum, make it possible to test:

- multiple ControlActionRouter observers remain registered through AppModel/controller wiring;
- OSC/remote actions dispatch before UI notification;
- output health presentation refreshes;
- autosave/manual-save coordination;
- app frame-rate setting reaches the actual engine config.

Also add package/app tests to the normal Xcode test workflow so Command-U is meaningful during UI development.

---

# UI-FOUNDATION-3 — App sandbox bookmark documentation is ahead of implementation

**Priority:** P2 / document lifecycle hardening before distribution  
**Area:** Xcode packaging, sandbox, recent documents

## Finding

The Xcode project enables:

```text
com.apple.security.files.bookmarks.app-scope
```

and `docs/xcode-project.md` says this provides security-scoped bookmarks for autosave of user-selected packages.

I found no code that creates, stores, resolves, starts, or stops access to security-scoped bookmarks.

The user-selected read/write entitlement and Launch Services/open-panel sandbox extensions may be sufficient for the current session and normal user-opened documents, but the repository should not claim persistent bookmark behavior that it does not implement.

## Recommendation

For now either:

- correct the documentation to say bookmark persistence is reserved/not yet implemented, or
- implement a small bookmark store if Aurora intends to reopen/autosave documents across relaunch without the user selecting them again.

This does **not** block the visual redesign, but it should be settled before distribution and before a polished Recent Shows workflow is advertised.

---

# UI-FOUNDATION-4 — Replace/fix placeholder AppIcon asset set during visual-design work

**Priority:** P2 / UI asset cleanup  
**Area:** Xcode asset catalog

## Finding

The new Xcode project correctly contains an AppIcon asset catalog, but it is placeholder artwork and the asset filenames include generated-looking names such as:

```text
ivan.p@example.net
wendy.h@example.net
walt.e@example.net
```

More importantly, `Contents.json` uses the same 512×512 image for both the 128pt@2x and 256pt@2x slots. The 128pt@2x slot conventionally expects a 256×256 source.

## Recommendation

Do not spend backend time polishing this placeholder.

As part of the Aurora visual-design system PR:

- install the approved Aurora icon artwork;
- generate correct 16/32/64/128/256/512/1024 pixel assets;
- use sane deterministic filenames;
- validate the asset catalog in Xcode/CI.

This is naturally part of UI mode.

---

# UI-FOUNDATION-5 — Preserve full 16-bit home/highlight defaults

**Priority:** P2 correctness/polish  
**Area:** fixture personality compilation

## Finding

`CompiledShow.compileAttributeWrites` correctly pairs coarse/fine channels for output.

However, `compileHomeAndHighlight` skips fine channels and derives normalized home/highlight only from the coarse byte:

```swift
homeNorm = Double(channel.defaultValue) / 255.0
```

For a true 16-bit personality whose fine default/highlight byte is non-zero, Home/Highlight loses that fine precision.

## Recommended fix

When an attribute has a compiled 16-bit coarse/fine pair, combine both bytes:

```text
value16 = (coarse << 8) | fine
normalized = value16 / 65535
```

Do the same for highlight.

Add a fixture personality test where the fine home/highlight byte is non-zero.

This is not a reason to delay the overall UI redesign after the save blocker is fixed, but it is a good small backend cleanup before the new Position/Programmer UI begins relying heavily on Home/Locate.

---

# Xcode / macOS verification gate

I could statically inspect the XcodeGen project, entitlements, Info.plist, asset catalog, schemes and CI workflow, but this review environment is Linux and cannot compile the CoreMIDI/Network/AppKit graph.

Before declaring the backend gate closed, run on the Mac:

```bash
swift test

xcodebuild \
  -project Aurora.xcodeproj \
  -scheme Aurora \
  -destination 'platform=macOS' \
  -configuration Debug \
  CODE_SIGN_IDENTITY="-" \
  build

xcodebuild \
  -project Aurora.xcodeproj \
  -scheme Aurora-Release \
  -destination 'platform=macOS' \
  -configuration Release \
  CODE_SIGN_IDENTITY="-" \
  build
```

Recommended once output/controller concurrency changes land:

- Run output/integration tests with **Thread Sanitizer** in a Debug configuration.
- Confirm App Sandbox local-network prompt and file open/save behavior.
- Confirm Finder double-click of `.aurora` opens the package.

---

# What I verified from the previous final gate

The latest code genuinely contains the intended fixes for:

- multi-observer MIDI/control notifications;
- OSC and remote transport dispatch before MainActor presentation work;
- `none` as safe no-physical-output routing and explicit `mirror` routing;
- multi-universe active-channel totals;
- incomplete MIDI messages across packet boundaries with realtime-byte interleaving;
- truthful manual-only Song progression;
- autosave I/O off MainActor and state-ID verification;
- duplicate universe-number rejection and expanded validation;
- app-global frame rate driving the actual engine configuration;
- ENTTEC USB Pro vs Open DMX distinction;
- typed diagnostics on key paths;
- command-group provisional dirty state;
- safer `Int` patch-address arithmetic;
- backup recovery ordered by filesystem timestamps;
- refreshed UI/backend contract and handoff documentation;
- an Xcode project that **composes the existing SPM library modules rather than flattening them**.

The underlying architecture is still healthy. There is no justification for a rewrite.

---

# Final go/no-go rule

## Before UI mode

**Must complete:**

1. `BLOCKER-1` — serialized package writes / stale autosave race.
2. Run the macOS Swift test suite and Debug/Release Xcode builds after that fix.

**Very desirable in the same small cleanup pass:**

3. `PRE-UI-1` — truthful output-health presentation.
4. `PRE-UI-2` — thread-safe OutputDriver running-state contract.
5. `PRE-UI-3` — explicit app shutdown lifecycle.
6. `UI-FOUNDATION-5` — full 16-bit home/highlight normalization.

## Then proceed

Once those are green, **stop backend feature work and begin the Aurora UI redesign.**

Carry `UI-FOUNDATION-1/2/3/4` directly into the first UI-foundation/design-system PR rather than treating them as reasons for another backend phase.

