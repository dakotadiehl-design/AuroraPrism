# Prism Comprehensive Logging and Human-Readable Error Plan

## 1. Objective

Implement one application-wide diagnostic system that:

- writes through Apple's Unified Logging system (`OSLog.Logger`), allowing macOS to manage persistence, rotation, storage pressure, and collection;
- lets an operator independently select the logging threshold for each major part of Prism in Settings;
- keeps logging safe and inexpensive on engine, MIDI, networking, and DMX real-time paths;
- retains the existing in-app Console and Diagnostics surfaces as useful live views without treating them as the durable log store;
- gives every user-facing error alert plain-language, actionable copy;
- records both the human-readable explanation and the machine-friendly error details for every presented error;
- prevents secrets, show content, MIDI payloads, network credentials, filesystem paths, and personal data from being exposed accidentally;
- is testable without depending on the live macOS log store.

This is an implementation plan, not an implementation. The proposed work should be delivered in small, reviewable waves so that high-frequency code is never migrated blindly.

## 2. Codebase audit summary

The repository currently contains 457 Swift source files across these targets:

| Target | Swift files | Relevant responsibility |
| --- | ---: | --- |
| `Aurora` | 47 | Prism app composition, controllers, Settings, AppKit alerts |
| `AuroraCore` | 50 | document session and commands |
| `AuroraDiagnostics` | 3 | bounded diagnostic event store only |
| `AuroraEngine` | 42 | show engine, programmer, effects, AME runtime |
| `AuroraFixtureLib` | 8 | fixture library/import, Lightkey import |
| `AuroraMIDI` | 18 | CoreMIDI, OSC, RTP-MIDI, MIDI output |
| `AuroraModel` | 40 | project/package/schema/model validation |
| `AuroraMusical` | 13 | musical clock, scheduling, transport |
| `AuroraOutput` | 15 | Art-Net, sACN, ENTTEC, output manager |
| `AuroraRemote` | 7 | TCP/web remote host and codec |
| `AuroraUI` | 78 | panels, stage, workspace, status/error text |

### 2.1 Existing diagnostic paths

- `AuroraDiagnostics/DiagnosticEvent.swift` defines four severities (`debug`, `info`, `warning`, `error`), seven broad subsystems, and a locked 500-event ring buffer.
- `DiagnosticsController` formats strings on `@MainActor`, keeps 200 console lines, and mirrors them into `DiagnosticsStore`. It does not write to Unified Logging.
- Only the app target and two tests currently import `AuroraDiagnostics`; the lower-level libraries cannot log through it directly.
- Controllers pass untyped `(String) -> Void` callbacks through project, MIDI, OSC, RTP-MIDI, output, and remote paths. These callbacks lose severity, category, event code, metadata, privacy, and source context.
- AME has a separate, rich `AMEDiagnosticEvent` ring in `AuroraEngine`; external control has another 500-entry `ExternalControlLog`; MIDI maintains its own visible lines. These are useful domain monitors but are not a durable log.
- The Console panel receives preformatted app strings. The `showConsoleTimestamps` preference exists, but timestamp formatting currently happens before presentation, so this setting cannot cleanly control the displayed result.
- There is one direct production `print` in `StageCanvasView` for a failed stage-layout commit.
- No production source currently uses `Logger`, `OSLog`, or `os_log`.

### 2.2 Existing error paths

- There are 149 `catch` sites. Many assign `error.localizedDescription` directly to status text; several surface it in SwiftUI alerts or `NSAlert`.
- Error alerts are created independently in `AuroraApp`, `AppModel`, `ProjectController`, Settings, fixture-library windows, fixture browser, and patch workspace.
- `ProjectController.presentError` puts raw `localizedDescription` directly in an alert.
- `CommandError`, `ProjectPackageError`, fixture import errors, and Lightkey errors have some human-oriented text. Several other error enums (`FixtureLibraryError`, `ENTTECError`, `MIDIError`, `OSCError`, `RemoteHostError`, musical validation errors, schema/library errors) do not consistently conform to `LocalizedError` or carry recovery guidance.
- Some domain errors embed an underlying `localizedDescription` into a new string. This destroys structured cause information and can leak technical details into the UI.
- Empty catches exist in stage/UI persistence code. Every such site needs an explicit determination: intentionally ignored at debug level, or an actual warning/error.

## 3. Design decisions

### 3.1 Unified Logging is the durable sink

Use `import OSLog` and `Logger`, with a stable subsystem based on the shipping bundle identifier (fallback to a compile-time constant for package tests). Do not create or rotate Prism-owned text log files. macOS owns storage policy and retention.

Unified Logging should be the authoritative operational log. Prism's ring buffers remain optional live projections for the in-app Console, Diagnostics workspace, AME monitor, and external-control monitor. Clearing an in-app monitor must not claim to erase the system log.

Important expectation to document in Settings: verbose/debug and informational records are intended primarily for live troubleshooting and may not have the same persistence as notice/error/fault records under macOS policy. Prism must not promise a retention duration or file size.

### 3.2 Per-category threshold, not a single global switch

Expose these operator-facing levels:

| Prism setting | Meaning | Unified Logging level |
| --- | --- | --- |
| Off | No routine output; faults still remain available unless an explicit test override disables the sink | none for routine events |
| Errors only | Failures requiring attention | `.error` and `.fault` |
| High-level | Start/stop, major state transitions, warnings, and failures | `.notice` and above |
| Information | Normal operations and significant decisions | `.info` and above |
| Verbose | Diagnostic decisions and sampled low-level detail | `.debug` and above |

Default production profile:

- App lifecycle: High-level
- Project/document: High-level
- Show engine: High-level
- AME: High-level
- Music engine: High-level
- Programmer/cue execution: High-level
- Output routing: High-level
- Local DMX/ENTTEC: High-level
- Art-Net: High-level
- sACN: High-level
- MIDI: High-level
- OSC/RTP-MIDI: High-level
- Remote control: High-level
- Fixture library/import: High-level
- Stage/UI/workspace: Errors only
- Performance: Errors only

Errors and faults should never depend on a user enabling verbose logging. “Off” should suppress errors only if product explicitly decides that category silence is more important than postmortem diagnosis; the recommended implementation interprets Off as “no debug/info/notice” and continues error/fault emission. Label that behavior in the UI as “Off (errors still logged)” to avoid ambiguity.

### 3.3 Category taxonomy

Create a stable `PrismLogCategory: String, CaseIterable, Codable, Sendable` in `AuroraDiagnostics`. Category raw values become Unified Logging category names and persisted preference keys, so they must not be renamed casually.

Recommended cases:

- `app.lifecycle`, `app.settings`, `app.windowing`
- `project.document`, `project.autosave`, `project.migration`, `project.validation`
- `fixture.library`, `fixture.import`, `fixture.lightkey`
- `engine.show`, `engine.programmer`, `engine.cues`, `engine.effects`, `engine.performance`
- `ame.ingress`, `ame.matching`, `ame.transform`, `ame.sequence`, `ame.quantization`, `ame.emission`, `ame.heldState`
- `music.clock`, `music.transport`, `music.scheduler`, `music.song`
- `output.routing`, `output.localDMX`, `output.artnet`, `output.sacn`
- `control.midi`, `control.osc`, `control.rtpMIDI`, `control.keyboard`
- `remote.host`, `remote.web`, `remote.session`, `remote.codec`
- `ui.stage`, `ui.patch`, `ui.workspace`, `ui.presentation`

Settings may group these into friendly sections while still storing a threshold for each leaf. Provide “Set all,” “Reset defaults,” and group-level controls; expanding a group reveals leaf categories. AME and Music Engine must be independent top-level groups, satisfying the motivating use case.

### 3.4 Event shape

Replace string-only diagnostic calls with a structured value:

```swift
struct PrismLogEvent: Sendable {
    let level: PrismLogLevel
    let category: PrismLogCategory
    let code: String
    let humanMessage: String
    let technicalMessage: String?
    let metadata: [String: PrismLogValue]
    let correlationID: UUID?
}
```

Rules:

- `code` is stable, lowercase dot notation such as `project.open.decode_failed` or `ame.mapping.suppressed`.
- `humanMessage` explains the event in understandable terms and is safe to show to an operator.
- `technicalMessage` contains the machine-oriented failure/cause when applicable. It must not be used in popups.
- Metadata uses a closed `PrismLogValue` enum rather than `[String: Any]`, carries an explicit privacy policy, and sorts keys for deterministic tests.
- Correlation IDs connect ingress to AME match/emission/action and connect a user operation to its error. Reuse AME latency IDs where appropriate.
- Do not add source filename/function/line to every production event; Unified Logging already adds process context, and indiscriminate source metadata creates noise. Allow it in debug-only helpers where useful.

For errors, emit one structured record containing both forms, for example:

```text
code=project.open.decode_failed
human="Prism couldn't open ‘Tour Show’ because part of the show file is damaged."
technical="ProjectPackageError.decodingFailed(...); underlying=DecodingError.dataCorrupted(...); path=cues[3].duration"
```

### 3.5 Logger facade and dependency boundaries

Build the core in `AuroraDiagnostics`:

- `PrismLogging` protocol for injectable logging;
- production `UnifiedPrismLogger` sink backed by cached `Logger` instances, one per category;
- `PrismLogConfiguration` immutable snapshot and a thread-safe `PrismLogConfigurationStore`;
- `InMemoryPrismLogSink` for tests and the existing UI projection;
- a fan-out/composite sink so one accepted event reaches Unified Logging and, when enabled, the bounded in-app monitor;
- `PrismNoOpLogger` for focused unit tests;
- `PrismSignposts` for performance intervals where signposts add value.

Do not make logging `@MainActor`. Configuration reads and threshold checks must be lock-safe and fast. Use an atomic/locked immutable snapshot that can be swapped when Settings changes. Never dispatch synchronously to the main queue from a logging call.

Update `Package.swift` so targets that produce operational events depend on `AuroraDiagnostics`. Keep `AuroraDiagnostics` Foundation/OSLog-only so this does not introduce cycles. At minimum add it to Model, FixtureLib, Output, Musical, MIDI, Engine, Core, Remote, and UI. If coupling all domain targets in one change is too risky, first inject `any PrismLogging` at target boundaries; do not continue proliferating string callbacks.

Logger APIs should check the configured threshold before constructing expensive messages or metadata. Offer autoclosure/builder APIs, but keep the final OSLog interpolation at the call site/facade with explicit privacy annotations; never reduce all records to an eagerly built string.

### 3.6 Privacy and security policy

Default dynamic values to `.private`. Explicitly allow `.public` only for reviewed low-risk fields such as stable event code, category, counts, booleans, protocol name, universe number, frame rate, and non-secret enum state.

Always private or redacted:

- remote PINs, auth tokens, passwords, keychain results;
- complete file paths and usernames (log only a private path or public last path component when needed);
- show names, fixture custom names, song names, cue labels, imported profile contents;
- IP addresses, hostnames, device serial numbers, MIDI endpoint names/IDs;
- raw OSC/MIDI packets, DMX frame buffers, project JSON, media URLs;
- error strings from external frameworks until reviewed.

Add a metadata-key allowlist and a sanitizer test suite. Do not rely on developers remembering to redact interpolated strings. Never log payload buffers at any setting; verbose output should summarize length, type, sequence/correlation ID, and outcome.

### 3.7 Real-time and volume constraints

Logging must not destabilize lighting output or musical timing.

- No per-frame DMX logging, per-tick engine logging, per-packet network logging, or per-MIDI-event logging at Information/High-level.
- Verbose event streams require sampling/rate limiting and aggregation (for example, first event plus count per interval).
- Log state transitions, not repeated state snapshots.
- AME can mirror existing diagnostic decisions into Unified Logging only after its current lock-sensitive work is complete. `recordDiagnosticsOutsideLock` is the natural integration point.
- Never call date formatters, JSON encoders, disk APIs, or main-actor code on render/output callbacks.
- Add counters for suppressed/rate-limited records and emit periodic summaries at verbose level.
- Use `os_signpost` intervals for engine-frame phases, AME ingress-to-emission latency, project open/save, and output start/stop only. Signpost names must be static and cardinality bounded.

## 4. Human-readable error architecture

### 4.1 Separate presentation from diagnostic identity

Add a UI-neutral `PrismErrorReport` in `AuroraDiagnostics`:

```swift
struct PrismErrorReport: Sendable {
    let code: String
    let userTitle: String
    let userMessage: String
    let recoverySuggestion: String?
    let technicalDescription: String
    let underlyingChain: [String]
    let category: PrismLogCategory
    let severity: PrismLogLevel
    let metadata: [String: PrismLogValue]
    let correlationID: UUID
}
```

Create `PrismErrorReporting.report(error:context:)` to build the report and log it exactly once. Create an app/UI `ErrorPresenter` that displays only `userTitle`, `userMessage`, and `recoverySuggestion`. The presenter must not log again.

The error context supplies the failed operation, safe user-visible object label, category, fallback message, and optional recovery action. Typed domain errors supply stable codes and details. Unknown errors receive a safe contextual fallback, while `String(reflecting: error)`, NSError domain/code, failure reason, and underlying-error chain go only to the technical log fields.

### 4.2 Domain error protocol

Introduce a small protocol, implemented by Prism-owned error enums:

```swift
protocol PrismDiagnosableError: Error {
    var prismErrorCode: String { get }
    var userMessage: String { get }
    var recoverySuggestion: String? { get }
    var technicalDetails: String { get }
}
```

Continue conforming to `LocalizedError` for platform interoperability, but make `errorDescription` human-readable. Preserve typed associated values rather than concatenating underlying `localizedDescription` into wrapper strings. Where wrapping is needed, add an underlying-error representation that can be traversed or store safe structured details before type erasure.

Audit and update at least:

- `CommandError` (retain current good messages; add stable codes and recovery suggestions);
- `ProjectPackageError`, schema migration, project/library package errors;
- `FixtureLibraryError`, `FixtureImportError`, Lightkey plist/import errors;
- `ENTTECError`, Art-Net/sACN/network and output-manager failures;
- `MIDIError`, `OSCError`, RTP-MIDI/session failures;
- `RemoteHostError`, `RemoteCodecError`, listener/server failures;
- AME sequence/configuration and musical meter/duration/scheduler errors;
- workspace layout and stage-media persistence failures.

### 4.3 Popup copy standard

Every error popup should answer:

1. What failed, in the title: “Prism Couldn't Save the Show.”
2. What that means, without implementation jargon.
3. What the operator can do next: retry, choose another location/device, repair a conflicting patch, reconnect hardware, or contact support with a short correlation/reference ID.

Use sentence case, contractions where natural, and product vocabulary already visible in the UI. Do not expose Swift type names, JSON keys, POSIX codes, raw UUIDs, framework domains, stack information, or phrases such as “decoding failed” unless the target audience truly needs them.

Use alert style and actions consistently:

- `.critical` for data-loss risk or an operation that cannot continue;
- `.warning` for recoverable failures requiring a decision;
- informational status/banner rather than a popup for transient, non-blocking issues;
- default action is the safe recovery action; destructive actions are clearly labeled;
- “Copy Technical Details” is optional and should copy a sanitized support summary, never display it as the main message.

Non-error confirmation alerts (dirty-document save, programmer-look recording, migration choices, rename/create prompts, destination entry) should remain task dialogs and are outside the error rewrite except for consistency/accessibility review.

### 4.4 Alert and status migration inventory

Migrate the known error popup surfaces first:

- `ProjectController.presentError`;
- app open/import/save/save-as/quit failure paths in `AppModel` and `AuroraApp`;
- Fixture Library Settings and `UserFixtureLibraryWindow`;
- `FixtureBrowserPanel` and `PatchWorkspaceView` rename failures;
- Lightkey importer failure UI;
- any Settings operation that currently drops an error only into the console.

Then audit every one of the 149 catch sites and classify it in a checked-in inventory:

- user-blocking: present a human error and log the paired technical report;
- user-visible non-blocking: show concise inline status and log once;
- operational only: log at an appropriate level;
- expected control flow: no error log, optionally debug with a stable code;
- intentionally ignored: document why and add a debug event if it aids diagnosis.

Status strings in Stage, Patch, Cue List, Cue Blocks, Palettes, Song, Inspector, fixture profile editor, and output health must use the same human-message mapper. “Human-readable popup” is the minimum requirement, but using the mapper for all visible error text prevents inconsistent regressions.

## 5. Settings design

Add a dedicated “Logging” tab in `AuroraSettingsRoot` rather than burying a large matrix in Advanced. Keep the existing operator health summary in Advanced/Diagnostics.

The Logging tab should contain:

- a short explanation that macOS manages the logs and that sensitive values are redacted;
- a profile picker: Production Defaults, Troubleshooting, Verbose All, Custom;
- grouped category rows with per-category level pickers;
- group-level “Set all in group” controls;
- “Reset Defaults” with confirmation;
- “Open Console.app” filtered to Prism's subsystem, if a reliable public URL/API is available; otherwise provide a copyable `log stream` command rather than shelling out silently;
- “Copy Support Command” for a bounded `log show --predicate 'subsystem == ...' --last ...` query;
- an optional “Include recent logs in support bundle” action planned separately, with preview/redaction and explicit consent;
- a read-only note explaining that changing a level takes effect immediately and does not retroactively create detail.

Persist settings as an application-global, versioned Codable blob in `AppSettingsStore`, e.g. `prism.logging.configuration.v1`. Continue reading existing `aurora.*` keys for compatibility, but all new keys should use `prism.*`. Unknown future categories fall back to their compiled default. Corrupt preference data falls back safely and emits one settings warning.

Do not save logging settings inside `.prism` show packages: diagnostic verbosity belongs to the Mac/application, not the show file.

Settings changes should atomically replace the logger configuration snapshot. They should not restart the engine, reconnect devices, rebuild Logger instances, or trigger high-frequency SwiftUI redraws. Give the Logging tab a narrow observable view model rather than observing all of `AppModel`.

## 6. In-app Console and Diagnostics behavior

Preserve the existing live panels but change them to consume structured events.

- Format timestamps at presentation time so `showConsoleTimestamps` works.
- Add category, level, and text filters.
- Show the friendly message by default, with a disclosure row for code and sanitized technical details.
- Bound memory by event count and approximate byte budget, not only count.
- Batch/throttle published updates to avoid rebuilding UI for every event.
- Make “Clear” clear only the in-memory view and say so.
- Keep AME and external-control domain monitors for specialized columns and filtering; bridge selected events to the unified logger rather than replacing those monitors with flat text.
- Remove the separate unstructured MIDI/console streams after their structured equivalents are proven.

## 7. Detailed implementation waves

### Wave 0 — Baseline and event catalog

1. Record current test and performance baselines (`swift test`, engine scale tests, AME latency tests).
2. Create `Docs/Diagnostics/PrismLogEventCatalog.md` listing category, code, level, metadata, privacy, rate policy, and owner for every planned event.
3. Create `Docs/Diagnostics/ErrorCatchAudit.md` containing all 149 catch sites and the classifications described above.
4. Confirm the shipping bundle identifier and use it as the Unified Logging subsystem constant.
5. Define measurable log-volume budgets for idle, playback, heavy MIDI, AME verbose, and four-universe output scenarios.

Acceptance: every existing diagnostic source and catch site has an owner/category and no production behavior has changed.

### Wave 1 — Logging foundation

1. Add levels, categories, values/privacy, structured events, configuration, protocol, unified sink, memory sink, composite sink, rate limiter, and test sink to `AuroraDiagnostics`.
2. Cache `Logger` per category; map Prism levels to `OSLogType` deliberately.
3. Add error-report formatting, NSError/underlying-chain capture, correlation IDs, and sanitization.
4. Add package dependencies without introducing cycles.
5. Unit-test threshold ordering, category override/default resolution, thread safety, fan-out, deterministic metadata, privacy redaction, rate limiting, and disabled-message laziness.

Acceptance: a library target can emit a structured event without AppKit/SwiftUI/main actor, settings updates are immediately observed, and disabled verbose message builders are not evaluated.

### Wave 2 — Application composition and Settings

1. Construct the production composite logger before controllers in `AppModel` composition.
2. Load versioned configuration from `AppSettingsStore`; atomically apply it before startup events.
3. Implement the narrow Logging Settings view model and tab.
4. Adapt `DiagnosticsController` to consume accepted structured events in batches; stop it from being the logging gateway.
5. Update Console formatting and honor `showConsoleTimestamps`.
6. Add one launch summary event (version/build, safe configuration summary, environment) and one termination event; do not dump all preferences.

Acceptance: AME can be Verbose while Music is High-level during the same run; relaunch restores the configuration; UI remains responsive under a synthetic event burst.

### Wave 3 — Human error foundation and popup migration

1. Implement `PrismDiagnosableError`, `PrismErrorReport`, contextual mapping, and a centralized SwiftUI/AppKit `ErrorPresenter`.
2. Convert Prism-owned error enums, starting with project/save/import and command errors.
3. Replace every known error popup with the presenter.
4. Log the report once at the catch/presentation boundary with human and technical fields.
5. Add snapshot/copy tests for titles, messages, recovery suggestions, fallback behavior, and absence of technical tokens.

Acceptance: no error popup interpolates raw `localizedDescription`; every presented error produces exactly one structured record containing code, human message, technical cause, category, and correlation ID.

### Wave 4 — Project, model, fixture, and UI migration

1. Replace `ProjectController.onLog` and project/autosave/import callback strings with `PrismLogging`.
2. Instrument document create/open/migrate/save/autosave/validation as start/result transitions and signpost intervals.
3. Migrate fixture library, Prism fixture import, and Lightkey import events/errors.
4. Replace direct status assignments in Patch, Stage, Cue List, Cue Blocks, Palettes, Song, Inspector, and fixture editor with mapped human messages.
5. Replace the direct StageCanvas `print` with a structured error report.
6. Resolve empty catches in UI/workspace persistence explicitly.

Acceptance: project and editing workflows contain no direct production `print`, no raw error popup, and no unclassified catch in the migrated targets.

### Wave 5 — Engine, AME, and Music migration

1. Add high-level show-engine lifecycle, compile/validation, cue execution, programmer, blackout/freeze/blind, and performance budget events.
2. Map each `AMEDiagnosticKind` to a stable code and sensible default level. Mirror at `recordDiagnosticsOutsideLock`, preserving AME's specialized ring.
3. Add AME correlation from ingress/latency ID through match, suppression, quantization, emission, and executor result.
4. Add Music clock/transport/scheduler state transitions; aggregate tick/scheduling detail rather than logging every tick.
5. Add signposts and performance regression tests around disabled and verbose logging.

Acceptance: AME Verbose explains why a mapping fired or did not fire; Music High-level emits transport/state changes without tick spam; engine frame and AME latency budgets remain within the agreed tolerance.

### Wave 6 — MIDI, OSC, remote, and output migration

1. Replace MIDI input/output diagnostics callbacks, MIDI text arrays, OSC/RTP callbacks, and remote `onLog` closures with structured logger injection.
2. Log connection/device/listener state transitions, decoding failures, mapping outcomes, and reconnect decisions with private identifiers.
3. Instrument output routing and driver lifecycle for ENTTEC, Art-Net, and sACN.
4. Never emit raw MIDI/OSC/DMX/network payloads; add sampled summaries only at Verbose.
5. Rate-limit repeated driver/network failures and emit recovery transitions.
6. Convert driver health errors to human-safe text while retaining technical details in structured records.

Acceptance: no untyped diagnostics callbacks remain; output at 40–44 Hz does not generate per-frame logs; PINs, hosts, serials, paths, and payloads are absent from captured public text.

### Wave 7 — Cleanup, documentation, and release hardening

1. Complete the 149-site catch audit and fail CI if the checked-in inventory is stale.
2. Remove obsolete string logging APIs after all call sites migrate.
3. Add a lint/CI script that rejects production `print`, `debugPrint`, direct `NSAlert.informativeText = error.localizedDescription`, and raw error interpolation in SwiftUI alert messages.
4. Add operator documentation for Console.app filtering and support-log collection.
5. Run privacy review, accessibility review, localization readiness review, stress tests, and clean-install/settings-migration tests.
6. Release behind an internal feature flag for one cycle if needed, but never dual-write duplicate errors in production.

Acceptance: event catalog and code agree; no forbidden patterns remain; all tests and performance budgets pass; support can identify failures by code/correlation ID without asking users to expose sensitive show data.

## 8. Category-specific event guidance

### App and Settings

- Notice: launch complete, requested termination, configuration profile changed.
- Info: window/settings surface opened, non-sensitive preference changed.
- Error/fault: unrecoverable composition/startup failure, corrupted preference fallback.

### Project and autosave

- Notice: document created/opened/saved/migrated, autosave disabled after repeated failure.
- Info: validation summary, autosave success after recovery.
- Debug: package component timings and counts.
- Error: open/save/replace/decode/encode failures, including human and technical forms.

### AME

- Notice: armed/disarmed, runtime configuration accepted/rejected.
- Info: mapping fired, sequence reset/advanced, quantization fallback.
- Debug: candidates, misses, suppressions, scope decisions, transforms, held-state lifecycle.
- Warning/error: invalid configuration, unsupported action, schedule failure.

### Music engine

- Notice: transport start/stop/continue, provider changed/lost, tempo source changed.
- Info: song/section transitions and material rescheduling.
- Debug: sampled scheduling decisions, clock drift summaries, quantization calculations.
- Warning/error: invalid meter/duration, provider instability, deadline misses over threshold.

### Output

- Notice: driver enabled/disabled, route changed, device connected/disconnected.
- Info: universe route summary and recovery.
- Debug: sampled frame counts, packet/sequence summaries, queue/backpressure summaries.
- Error/fault: device open/write failure, socket failure, persistent deadline failure, invalid configuration.

### MIDI/OSC/Remote

- Notice: service/listener/session start/stop and device/session connect/disconnect.
- Info: mapping learned, client authenticated/kicked, configuration applied.
- Debug: redacted/sampled event-type and dispatch decisions.
- Warning/error: malformed message, authentication failure summary, listener bind/codec failure.

### UI/Stage/Workspace

- Notice: workspace reset or layout recovery.
- Info: major operator workflow completion only where diagnostically valuable.
- Debug: difficult state transitions, never mouse movement/drag-frame spam.
- Error: command failure, layout persistence failure, stage media failure.

## 9. Testing strategy

### Unit tests

- Level ordering and category overrides, including Off/errors-only semantics.
- Versioned preference encode/decode, corrupt data fallback, new-category defaults.
- Concurrent configuration updates and logging from multiple queues.
- Autoclosure laziness and absence of expensive metadata work below threshold.
- Ring byte/count eviction and published-update batching.
- Rate-limit boundaries and suppression summary events.
- Error code stability, known-error mappings, unknown-error fallback, underlying chain extraction.
- Privacy sanitizer for tokens, PIN-like values, paths, IPs, endpoint names, payload bytes, and project content.
- Exactly-once logging for presented errors.

### Integration tests

- Configure AME Verbose and Music High-level; verify accepted events differ appropriately.
- Open/save corrupted or unwritable projects; assert readable popup copy and paired technical test-sink event.
- Fixture import, Lightkey import, MIDI/OSC bind, remote bind, ENTTEC open/write, Art-Net/sACN socket failure cases.
- Console filtering, timestamps on/off, clear semantics, and burst batching.
- Settings persistence across a fresh `AppModel` and safe migration from old UserDefaults.

### Performance and stress tests

- Engine/output baseline with logging thresholds below all hot-path events.
- AME Verbose under a high-rate MIDI stream.
- Four or more output universes at the maximum supported frame rate.
- Repeating network/device failure to confirm rate limiting and recovery event behavior.
- Memory stability for long sessions with Console and Diagnostics open and closed.

Because Unified Logging is not a deterministic unit-test database, tests should assert against the injectable memory sink. Add a small manual/macOS integration checklist using `log stream` and `log show` to confirm subsystem/category/type/privacy behavior in signed debug and release builds.

## 10. Definition of done

- Settings independently control logging level for AME, Music Engine, and every agreed Prism category.
- Configuration applies live, persists across launch, and stays application-global.
- All accepted production events go to Apple's Unified Logging; Prism owns no rotating log files.
- No direct `print`/`debugPrint` or unstructured diagnostic callback remains in production code.
- No high-frequency path emits unbounded per-frame/per-tick/per-packet logs.
- Existing Console, Diagnostics, AME, and external-control monitors remain useful and memory-bounded.
- Every error popup is plain-language and actionable, with no raw technical error text.
- Every presented error has one logged event containing stable code, human message, machine-friendly description, category, and correlation ID.
- Secrets and sensitive show/operator data are private or absent at every level.
- All 149 original catch sites are explicitly classified and migrated or documented.
- Unit, integration, privacy, accessibility, and performance tests pass in debug and release configurations.
- Event catalog, operator support instructions, and CI enforcement are checked in with the implementation.

## 11. Recommended pull-request breakdown

1. Diagnostics types, Unified Logging sink, configuration, privacy, and tests.
2. Settings Logging tab and structured in-app Console adapter.
3. Error-report model, presenter, domain error codes, and project/save/open popup migration.
4. Project/model/fixture/UI catch-site migration and direct-print cleanup.
5. Engine/AME/Music instrumentation and performance validation.
6. MIDI/OSC/Remote/Output instrumentation and rate limiting.
7. Final catch audit, obsolete API removal, CI lint, docs, privacy/accessibility hardening.

Each PR should update the event catalog and catch audit, include before/after captured events from the test sink, and state its measured hot-path overhead. Avoid a single codebase-wide mechanical replacement: severity, privacy, rate, human wording, and ownership require domain-specific review.
