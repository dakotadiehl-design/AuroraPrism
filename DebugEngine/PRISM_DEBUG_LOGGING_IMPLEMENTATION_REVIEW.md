# Prism Debug Logging Implementation Review

## Review outcome

**Status: Changes required — not ready to describe as a full implementation.**

The implementation establishes a useful foundation: typed categories and levels, application-persisted per-category configuration, a macOS Unified Logging sink, a bounded in-memory Console projection, an AME bridge, diagnosable error types, centralized AppKit error presentation, rate limiting, documentation, and focused foundation tests. The complete Swift test suite builds and passes.

However, the implementation is incomplete relative to the approved plan and contains privacy and diagnostic-correlation problems that should block release. Most lower-level systems do not emit structured events at all, the checked-in event catalog lists many nonexistent events, copied “technical details” are not sanitized, and `UnifiedPrismLogger` splits one structured error into several independent log entries without a usable join key.

## Findings

### [P1] The event catalog and catch audit claim migrations that were not implemented

The catalog documents operational coverage across Project, Music, Output, MIDI, Remote, Fixture, Engine, and UI, but the corresponding targets contain essentially no direct structured logging calls.

Observed structured emission/reporting call sites by target:

| Target | Direct calls |
| --- | ---: |
| `Aurora` | 49 |
| `AuroraUI` | 6 |
| `AuroraEngine` | 1 (the AME bridge) |
| `AuroraCore` | 0 |
| `AuroraFixtureLib` | 0 |
| `AuroraMIDI` | 0 |
| `AuroraModel` | 0 |
| `AuroraMusical` | 0 |
| `AuroraOutput` | 0 |
| `AuroraRemote` | 0 |

A literal comparison between `docs/Diagnostics/PrismLogEventCatalog.md` and production sources found 73 cataloged event codes with no matching implementation. Important missing families include:

- all `music.transport.*`, `music.clock.*`, `music.scheduler.*`, and `music.song.*` events;
- all Art-Net, sACN, and Local DMX lifecycle/failure/recovery/frame-summary events;
- `control.midi.started`, source changes, and failures;
- remote authentication, codec, and web listener events;
- project open/save/migrate/autosave/validation events;
- cue, programmer, effects, and performance events;
- several fixture import/library events;
- several Stage/Patch/UI events.

For example, the catalog promises Music transport logging at [PrismLogEventCatalog.md](/Users/dakota/code/Aurora/docs/Diagnostics/PrismLogEventCatalog.md:114), yet `AuroraMusical` has no structured logging call. Similarly, the catalog promises output driver lifecycle and failure events at [PrismLogEventCatalog.md](/Users/dakota/code/Aurora/docs/Diagnostics/PrismLogEventCatalog.md:131), while `AuroraOutput` still only stores raw `localizedDescription` in driver health state, such as [ArtNetOutputDriver.swift](/Users/dakota/code/Aurora/Sources/AuroraOutput/ArtNetOutputDriver.swift:64) and [SACNOutputDriver.swift](/Users/dakota/code/Aurora/Sources/AuroraOutput/SACNOutputDriver.swift:70).

The catch audit compounds the problem. Every row is marked `migrated`, but most rows have category and code recorded as `—` and the same generic note. The verification script checks only that its generated count matches the table count; it does not verify classification, a structured log call, a human-message mapping, or an intentional-ignore rationale. The audit therefore cannot support its own “migrated” claim.

Impact:

- Setting AME to Verbose works for the existing AME diagnostics, but setting Music, Art-Net, sACN, Local DMX, Fixture Import, or several other categories to Verbose yields little or no additional diagnostic output.
- Common hardware, transport, project, and networking failures remain absent from Unified Logging.
- The event catalog and catch audit give reviewers and support staff a false view of production coverage.

Required remediation:

1. Implement each cataloged event or mark it explicitly `planned/not implemented`.
2. Instrument the lower-level targets, particularly `AuroraMusical`, `AuroraOutput`, `AuroraMIDI`, `AuroraRemote`, `AuroraModel`, and `AuroraFixtureLib`.
3. Replace the remaining raw diagnostics callbacks (`setDiagnosticsLogger`, controller `log:` closures, and `DiagnosticsController.log`) with typed logger injection.
4. Give every catch-audit row an actual classification, category, code, and disposition. Make CI validate more than row count.

### [P1] “Copy Technical Details” can copy sensitive information without redaction

`PrismLogSanitizer.supportSummary(for:)` appends `technicalDescription` and the complete underlying-error chain verbatim at [PrismLogSanitizer.swift](/Users/dakota/code/Aurora/Sources/AuroraDiagnostics/PrismLogSanitizer.swift:48). `ErrorPresenter` then copies this raw value directly to the pasteboard at [ErrorPresenter.swift](/Users/dakota/code/Aurora/Sources/Aurora/ErrorPresenter.swift:21).

Technical descriptions are built from `String(reflecting:)`, NSError failure reasons, and wrapped error strings. Existing project and fixture code embeds file names, last path components, decoder details, network reasons, and framework messages into errors. Nothing in `supportSummary` redacts paths, usernames, IP addresses, endpoint names, show/cue/song/fixture names, auth values, or payload-like content.

The sanitizer tests do not exercise this path with sensitive data. `testSupportSummaryContainsCodeAndReferenceNotPIN` passes only because the constructed report never contains a PIN.

Impact: a support summary that is labeled and treated as sanitized may place private show/operator/system data on the clipboard, ready to be pasted into chat, email, or a ticket.

Required remediation:

- Build the support summary from structured, privacy-tagged fields rather than arbitrary technical strings.
- Add a conservative redactor for unknown NSError/reflection text, or omit raw technical/underlying text from the copyable summary.
- Add tests containing real path, username, host/IP, serial, endpoint, PIN/token, project name, cue/song/fixture name, and JSON/payload patterns.
- Make the UI state clearly what will be copied and require explicit consent for sensitive diagnostics.

### [P1] One structured error becomes several independent Unified Log records

`UnifiedPrismLogger.log` writes the primary message, technical message, correlation ID, and every metadata pair as separate calls to `Logger.log` at [UnifiedPrismLogger.swift](/Users/dakota/code/Aurora/Sources/AuroraDiagnostics/UnifiedPrismLogger.swift:19).

Those records have no common public identifier:

- the main record does not contain the event ID or correlation ID;
- the technical record does not contain the event code;
- the correlation UUID is emitted in a separate record and marked private;
- metadata records contain neither event code nor correlation ID.

Concurrent events in the same category can interleave, so Console.app or `log show` cannot reliably tell which technical detail and metadata belong to which human message. This directly weakens the requirement that a logged error include both the human-readable and machine-friendly forms.

Required remediation:

- Emit one Unified Log record per `PrismLogEvent` containing the stable public event code and a stable public short correlation/reference ID, plus human and technical fields with their appropriate privacy annotations.
- If metadata must be serialized, serialize bounded structured metadata into that same record. Avoid a follow-up record per field.
- Add a concurrency test that sends multiple errors simultaneously and verifies each captured representation is independently understandable and joinable.

### [P2] Selecting the “Custom” profile destroys the current category configuration

`LoggingSettingsModel.applyProfile(.custom)` replaces every category threshold with the current App Lifecycle threshold at [LoggingSettingsModel.swift](/Users/dakota/code/Aurora/Sources/Aurora/Settings/LoggingSettingsModel.swift:23).

Example: if AME is Verbose, Music is High-level, and App Lifecycle is High-level, choosing Custom changes every category to High-level. That is surprising and destroys the exact per-system configuration Custom is meant to represent.

Required remediation: make Custom a derived/nonselectable state, or make selecting it preserve the existing thresholds unchanged. Add a Settings-model test covering a mixed AME/Music configuration.

### [P2] A corrupt saved logging configuration warning is silently lost during startup

`AppSettingsStore` attempts to emit `app.settings.config_fallback` while decoding settings at [AppSettingsStore.swift](/Users/dakota/code/Aurora/Sources/Aurora/Controllers/AppSettingsStore.swift:97). At that point `PrismLog.shared` is still the no-op logger. The production composite logger is installed only after `AppSettingsStore()` returns at [AppModel.swift](/Users/dakota/code/Aurora/Sources/Aurora/AppModel.swift:95).

Impact: the exact configuration-corruption event documented in the catalog is never recorded.

Required remediation: return a load warning/result from `AppSettingsStore`, bootstrap the logger, then emit the warning; or bootstrap a minimal production logger before reading settings and swap its configuration afterward. Add an application-composition test with corrupt stored JSON.

### [P2] Error popups are only partially migrated to the structured presenter

The new `ErrorPresenter` and `PrismErrorAlertModifier` are good primitives, but existing SwiftUI error alerts still store only `String` messages. Examples include Fixture Library Settings, `UserFixtureLibraryWindow`, `FixtureBrowserPanel`, and `PatchWorkspaceView`. Their catch sites may create/log a report, then discard its title, recovery suggestion, correlation ID, and technical-copy capability before the popup is shown.

This yields human-readable text in many cases, but not the consistent popup contract proposed by the plan. It also means the SwiftUI `PrismErrorAlertModifier` is not used by the actual migrated popup sites.

Required remediation: store `PrismErrorReport?` and apply `prismErrorAlert(item:)` at every error-popup site. Add UI/model tests for title, message, recovery suggestion, reference ID, and exactly-once logging.

### [P2] The implementation still contains untyped legacy diagnostic paths

The proposed migration explicitly removed untyped callback logging, but these remain:

- `MIDIInputManager.setDiagnosticsLogger` and `MIDIOutputManager.setDiagnosticsLogger`;
- controller `log: (String) -> Void` callbacks for output setup;
- numerous `appModel.diagnostics.log(...)` calls;
- compatibility mapping in `DiagnosticsController.log` that assigns broad categories after detail has already been lost.

These paths cannot carry stable event code, exact category, structured metadata, privacy, correlation, or rate policy. They also explain why lower-level target instrumentation is absent despite those targets now depending on `AuroraDiagnostics`.

Required remediation: inject `any PrismLogging` or emit through the typed facade at the source of the event. Remove the compatibility APIs after call-site migration.

### [P2] Logging an error can generate excessive records and disk pressure

Because `UnifiedPrismLogger` emits a primary record, optional technical record, optional correlation record, and one record per metadata key, a single logical event may become many Unified Log entries. The composite also mirrors all accepted events into the in-memory sink.

This undermines the stated volume budget and makes high-rate troubleshooting noisier than necessary. It is particularly undesirable for AME Verbose, where many domain diagnostic events are generated.

Required remediation: one Unified Log emission per logical event, bounded metadata, and measured volume tests using representative AME/MIDI/output scenarios.

### [P3] Rate-limit summaries disappear unless Debug is enabled

`CompositePrismLogger` always creates `log.rate_limited` at `.debug`. If an Info/Notice/Warning/Error event uses a rate policy while the category threshold is not Verbose, repeated records are silently suppressed and the summary is also filtered out.

Required remediation: emit the summary at the original event level or at the lowest enabled level that preserves the operator's expectation. Include the original code and suppressed count in the same summary record.

### [P3] Test coverage validates the foundation but not the advertised product behavior

The new tests cover level ordering, configuration decoding, basic laziness, fan-out, metadata privacy downgrading, rate-limiter mechanics, ring eviction, concurrent configuration swaps, and basic error mapping. Missing tests include:

- Settings persistence through `AppSettingsStore` and a fresh `AppModel`;
- mixed AME/Music interaction through the actual Settings model;
- corrupt configuration startup logging;
- Unified Logging record cohesion;
- sensitive support-summary redaction;
- real domain error popup mappings;
- actual Music/Output/MIDI/Remote event emission;
- burst batching/publication behavior in `DiagnosticsController`;
- performance/volume budgets for disabled and verbose logging.

These are the areas where the review found failures, so foundation unit tests alone are not sufficient acceptance evidence.

## Positive implementation notes

- The logger and configuration store are not main-actor-bound, making them callable from engine/network/output paths.
- Threshold checking occurs before autoclosure evaluation in the typed `PrismLog` helpers.
- Per-category configuration supports the requested independent AME and Music settings at the model level.
- “Off (errors still logged)” semantics are explicit and tested.
- The in-memory sink is bounded by count and an approximate byte budget.
- Console timestamps are formatted at presentation time, so the existing timestamp preference can work.
- The Console has text, severity, and group filters and correctly states that clearing it does not erase macOS logs.
- AME events are bridged outside the AME lock and reuse latency IDs as correlations.
- Direct production `print`/`debugPrint` calls were removed.
- Prism-owned error enums received substantially better human-readable conformance and stable codes.
- The package dependency direction remains acyclic and the entire project compiles.

## Verification performed

- `swift test` completed successfully using isolated compiler/build caches.
- Result: **912 tests executed, 1 skipped, 0 failures**.
- `Scripts/lint-logging.sh`: passed.
- `Scripts/verify-catch-audit.sh`: passed, but its current row-count-only validation is insufficient as noted above.
- Production source scan: no `print` or `debugPrint` calls.
- Production source scan: remaining `localizedDescription` uses are in domain wrapping/runtime health rather than direct popup interpolation, but several still flatten underlying errors and need structured-cause migration.
- Event-catalog/source comparison: 73 documented event literals were not found in production source.

## Recommended remediation order

1. Fix support-summary privacy and single-record Unified Log correlation.
2. Correct the event catalog and catch audit so documentation reflects reality.
3. Instrument Project, Music, Output, MIDI/OSC/RTP-MIDI, Remote, Fixture, and core Engine paths with typed events.
4. Remove legacy string callbacks and compatibility logging.
5. Finish structured error-report adoption at every popup.
6. Fix Custom-profile and corrupt-settings startup behavior.
7. Add integration, privacy, concurrency, and volume/performance tests.
8. Rerun the full suite, lint, a real Console.app/log-stream smoke test, and high-rate AME/MIDI/output stress tests before sign-off.

## Final assessment

This is a solid first foundation and partial application migration, not a completed codebase-wide debug engine. The Settings taxonomy and AME bridge demonstrate the intended architecture, but most selectable categories do not yet produce the promised logs. Release should wait until the P1 findings are fixed and the documentation/audit accurately represents implemented coverage.
