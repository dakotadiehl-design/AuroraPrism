# Prism Debug Logging — First-Pass Deep-Dive Review

## Executive assessment

**Review status: Changes required before release sign-off.**

The first pass is now a credible, broad implementation rather than only a logging foundation. It provides configurable per-category thresholds, a native macOS Unified Logging sink, structured in-memory Console events, rate limiting, AME diagnostics bridging, instrumentation across all major package targets, human-oriented error reports, structured SwiftUI/AppKit alerts, privacy-tagged metadata, documentation, linting, and tests.

The implementation compiles and the complete Swift test suite passes. The review nevertheless found four high-priority issues:

1. a persisted “test-only” flag can suppress error and fault logging in production;
2. runtime Art-Net and sACN send failures update health state but do not emit their promised failure events;
3. the copyable support-summary privacy statement is stronger than the redaction actually provides;
4. verbose output instrumentation adds locking to every successful DMX send completion even when verbose logging is disabled.

There are also several diagnostic-accuracy, lock-scope, configuration-versioning, and test-quality issues detailed below.

## Scope and verification

Reviewed areas:

- `AuroraDiagnostics` event, configuration, sinks, privacy, rate limiting, signposts, and error reporting;
- Settings persistence and Logging tab behavior;
- Console projection and filtering;
- app bootstrap and controller integration;
- Project, Model, Fixture, Engine, AME, Music, MIDI/OSC, Output, Remote, and UI instrumentation;
- popup and inline error migration;
- event catalog, catch audit, lint scripts, and new tests;
- real-time and concurrency-sensitive paths.

Verification performed:

- `swift test`: **927 tests executed, 1 skipped, 0 failures**;
- `Scripts/lint-logging.sh`: passed;
- `Scripts/verify-catch-audit.sh`: passed with 151 catch sites inventoried;
- `git diff --check`: passed;
- production scan: no direct `print` or `debugPrint` calls;
- production scan: no remaining `onLog`, `log: (String) -> Void`, or `setDiagnosticsLogger` APIs;
- event-catalog/source literal comparison: no cataloged event code was wholly absent from production source;
- the regenerated Xcode project includes the new app source files and the Debug app target builds.

Passing tests are useful evidence, but several tests do not exercise the integration behavior their names imply; those gaps are called out below.

## Findings

### [P1] Persisted preferences can disable error and fault logging completely

`PrismLogConfiguration.allowFaultSuppression` is described as test-only, but it is public, encoded to UserDefaults, decoded from UserDefaults, and preserved whenever Settings changes a category or group. See [PrismLogConfiguration.swift](/Users/dakota/code/Aurora/Sources/AuroraDiagnostics/PrismLogConfiguration.swift:20), especially the Codable keys and decode path at line 103.

If the persisted JSON contains `"allowFaultSuppression": true`, selecting “Off” for a category suppresses errors and faults as well as routine messages. That contradicts the Settings label “Off (errors still logged)” and removes postmortem coverage from production. A corrupt preference, manual defaults edit, future migration bug, or accidentally encoded test configuration can therefore make Prism fail silent.

Required remediation:

- remove `allowFaultSuppression` from the production Codable representation;
- make full suppression an internal test-sink behavior rather than production configuration state;
- force decoded production configurations to preserve errors/faults regardless of unknown stored fields;
- add a test decoding JSON with `allowFaultSuppression: true` and assert that errors/faults remain enabled.

### [P1] Runtime Art-Net and sACN transmission failures are not logged

Both network drivers emit failure events for configuration/startup failures, but their asynchronous send-completion error branches only update `_lastError`, increment dropped packets, and mark the driver degraded:

- [ArtNetOutputDriver.swift](/Users/dakota/code/Aurora/Sources/AuroraOutput/ArtNetOutputDriver.swift:223)
- [SACNOutputDriver.swift](/Users/dakota/code/Aurora/Sources/AuroraOutput/SACNOutputDriver.swift:136)

Neither branch emits `output.artnet.failed` or `output.sacn.failed`. ENTTEC correctly emits a rate-limited failure after a write error at [ENTTECUSBDMXProDriver.swift](/Users/dakota/code/Aurora/Sources/AuroraOutput/ENTTECUSBDMXProDriver.swift:536), so the network protocols behave inconsistently.

This is the failure mode most likely to occur during a show after output has started. The health panel may show an error, but macOS Unified Logging lacks the machine/human error record needed for postmortem diagnosis. The event catalog's presence check does not detect this because the same failure code exists in startup/configuration branches.

Required remediation:

- capture the error and transition state under the driver lock;
- unlock, then emit a rate-limited structured error containing human and private technical forms;
- emit recovery only after a previously reported degraded period;
- add simulated `NWConnection` completion-failure tests for both drivers.

### [P1] The copied support summary claims to remove names that it can still include

`supportSummary(for:)` says the copy does not include “show names,” but it copies `userTitle`, `userMessage`, and `recoverySuggestion` after regex-based free-text redaction. See [PrismLogSanitizer.swift](/Users/dakota/code/Aurora/Sources/AuroraDiagnostics/PrismLogSanitizer.swift:73).

The redactor covers Unix paths, IPv4 addresses, a small set of secret assignments, email addresses, and some bracketed payloads. It does not identify:

- show, cue, song, fixture, manufacturer, model, or mode names in ordinary prose;
- hostnames that are not IPv4 addresses;
- device serial numbers and endpoint names;
- Windows-style paths;
- IPv6 addresses;
- secrets expressed as `PIN 123456`, `token is ...`, quoted values, or separated by whitespace without `:`/`=`.

This matters because `CommandError.message(String)` returns arbitrary caller text as its user-facing message at [CommandError.swift](/Users/dakota/code/Aurora/Sources/AuroraCore/CommandError.swift:48). Existing callers construct some messages from fixture/manufacturer/model/mode names. Those values can flow into a report and then into the clipboard despite the assurance that names are excluded.

Required remediation:

- make the support summary code/reference/category-only by default; or
- include only fields explicitly classified safe when the report is built, not regex-sanitized arbitrary user copy;
- change the explanatory sentence so it makes only guarantees the code enforces;
- add tests with ordinary show/cue/song/fixture names, hostname, serial, endpoint, IPv6, Windows path, and varied secret syntax.

### [P1] Disabled verbose output still performs synchronization on every successful frame

Art-Net, sACN, and ENTTEC call `PrismIntervalCounter.note()` on every successful send or completion before calling the Debug logger:

- [ArtNetOutputDriver.swift](/Users/dakota/code/Aurora/Sources/AuroraOutput/ArtNetOutputDriver.swift:239)
- [SACNOutputDriver.swift](/Users/dakota/code/Aurora/Sources/AuroraOutput/SACNOutputDriver.swift:152)
- [ENTTECUSBDMXProDriver.swift](/Users/dakota/code/Aurora/Sources/AuroraOutput/ENTTECUSBDMXProDriver.swift:525)

`PrismIntervalCounter.note()` takes an `NSLock` and calls `Date()` every time. This happens even at Production Defaults, where Debug output is disabled. With several universes and multiple drivers at 40–44 Hz, the implementation adds hundreds of avoidable lock/date operations per second to user-interactive output queues and, for local DMX, the synchronous send path.

The original design specifically required threshold checks before hot-path diagnostic work. Autoclosure laziness does not help here because the counter work occurs before `PrismLog.debug` performs its threshold check.

Required remediation:

- check `PrismLog.shared.isEnabled(.debug, category: ...)` before calling the interval counter;
- preferably inject/cache a cheap configuration snapshot or use an atomic enabled bit for real-time paths rather than acquiring multiple global locks;
- benchmark disabled and Verbose logging with four or more universes at maximum frame rate;
- assert that disabled Debug instrumentation does not invoke the counter/clock.

### [P2] Saving a project emits a false “project opened” event

`ProjectPackage.save` verifies its staged package by calling `load(from: tmpURL)` at [ProjectPackage.swift](/Users/dakota/code/Aurora/Sources/AuroraModel/ProjectPackage.swift:205). The shared load path unconditionally emits `project.document.opened` at line 540.

As a result, every successful save produces an “opened the show” event for an internal temporary package before emitting `project.document.saved`. This is misleading in Console.app, inflates event counts, and makes open/save sequences unreliable for support diagnostics.

Required remediation: separate package decoding/validation from the user-operation event boundary. Add an `emitOperationalEvent` parameter only if necessary, but a private silent loader plus public open wrapper is cleaner. Add a test asserting save emits `saved` and not `opened`.

### [P2] Production Unified Logging retains an additional raw private event cache

`UnifiedPrismLogger` has a test capture hook with a default capacity of 64 records at [UnifiedPrismLogger.swift](/Users/dakota/code/Aurora/Sources/AuroraDiagnostics/UnifiedPrismLogger.swift:19). The production app constructs `UnifiedPrismLogger()` without overriding that default, so it keeps the last 64 human and technical messages in an ordinary in-process array in addition to macOS Unified Logging and the in-memory Console sink.

The captured record contains raw `humanMessage` and `technicalMessage`; OSLog privacy annotations do not apply to this array. The method `capturedRecords()` is public. This increases sensitive-data lifetime and memory duplication solely for a test hook.

Required remediation:

- default `captureLimit` to zero;
- make capture an explicitly injected test observer/sink rather than production behavior;
- make captured-record access internal/test-only if retained.

### [P2] Logging occurs while the remote-session lock is held

`RemoteSessionManager.handleHello` holds its `NSLock` for the full method via `defer` and emits authentication failure/success events inside that critical section at [RemoteSessionManager.swift](/Users/dakota/code/Aurora/Sources/AuroraRemote/RemoteSessionManager.swift:152).

Logging can acquire the global logger lock, configuration lock, rate-limiter lock, Unified logger lock, and memory-sink lock. Even without a current direct lock cycle, this lengthens the authentication critical section and creates avoidable lock-order coupling. A future sink callback or observer could turn it into a deadlock.

Required remediation: compute the result and event descriptor under the session lock, unlock, then emit the event. Add a concurrency test with parallel hello/auth and logging activity.

### [P2] Configuration version is stored but never validated or migrated

`PrismLogConfiguration.currentVersion` and the encoded `version` field exist, but decode accepts any version without branching, rejecting, or migrating. A future incompatible blob will be treated as current, while unknown/invalid thresholds silently fall back category by category.

Required remediation: explicitly accept version 1, migrate known older versions, and reject newer versions to the existing production-default fallback path. Add old/current/future-version tests.

### [P2] Event-code catalog verification proves presence, not correct behavior

All catalog literals are now present somewhere in source, which is a real improvement. However, literal presence did not catch:

- Art-Net/sACN runtime send failures lacking failure events;
- saves producing false open events;
- events emitted twice at multiple abstraction layers;
- unreachable or incorrectly leveled/category-mapped emissions.

Fixture library loading illustrates duplication risk: the library target emits `fixture.library.loaded`, and `ProjectController` also emits a successful library-load event. Similar lifecycle events can be produced at driver and controller layers.

Required remediation: define event ownership in executable tests. For each important operation, assert an exact ordered/multiset result rather than only checking that a code string exists in the repository.

### [P2] Several lifecycle events are emitted even when no state transition occurred

Some `stop()` implementations emit “stopped/off” notices unconditionally, including Art-Net, sACN, and OSC. Calling stop on an already stopped driver therefore records a state transition that did not happen. Reconfiguration may also produce repeated stop/start notices for internal restarts without distinguishing operator intent from implementation detail.

Required remediation: snapshot `wasRunning` under lock and emit only on a real transition. If internal restart visibility is useful, use a distinct configuration/restart event.

### [P2] Error wrapping still flattens underlying causes into localized strings

Project package, library package, fixture library/import, and network health paths still interpolate `error.localizedDescription` into wrapper strings. These are no longer placed raw into popups, which is good, but the underlying NSError chain and typed cause are lost before `PrismErrorReporting` can inspect them.

Examples include [ProjectPackage.swift](/Users/dakota/code/Aurora/Sources/AuroraModel/ProjectPackage.swift:222) and [FixtureLibrary.swift](/Users/dakota/code/Aurora/Sources/AuroraFixtureLib/FixtureLibrary.swift:36).

Required remediation: preserve typed underlying errors in wrapper types or attach them through `NSUnderlyingErrorKey`. Generate the machine-friendly technical representation at the outer reporting boundary.

### [P3] The rate-limit summary test does not test summary emission

`testRateLimitSummaryUsesOriginalLevel` sends two events inside the same real-time window, then separately tests a standalone limiter with injected dates. It never advances the composite logger's limiter into a new window and never asserts that `CompositePrismLogger` emitted a `log.rate_limited` summary at the original level.

Required remediation: inject a clock or rate limiter into the composite, drive it across a window deterministically, and assert the summary code, original level, suppressed count, category, and correlation behavior.

### [P3] The mixed AME/Music “Settings” test bypasses the Settings model

`testCustomProfilePreservesMixedAMEAndMusic` mutates `PrismLogConfiguration` directly. It does not instantiate `LoggingSettingsModel`, invoke `applyProfile(.custom)`, or verify the apply/persistence closure. The previous Custom-profile defect could therefore recur without this test failing.

Required remediation: move the Settings model into a testable module or add an app-target test that exercises the actual model and `AppSettingsStore` round trip.

### [P3] The public metadata sanitizer contains redundant/unreachable logic

`PrismLogSanitizer.sanitize(key:value:)` has two consecutive conditions that reduce to the same allowlist check. The `looksSensitive` portion cannot change the result because allowlisted keys are accepted regardless and non-allowlisted keys are rejected by both conditions.

This is not currently a privacy bypass because the allowlist is narrow, but the code communicates a stronger sensitive-key override than it actually implements.

Required remediation: simplify to one clear rule, or explicitly make sensitive hints override the allowlist if that is the intended policy.

## Human-readable error review

The error work is substantially improved:

- major AppKit errors use `ErrorPresenter`;
- the main SwiftUI popup sites store `PrismErrorReport?` and use `prismErrorAlert`;
- reports carry stable code, human title/message, recovery guidance, technical description, underlying chain, category, severity, and correlation ID;
- popup copy displays human fields and a short reference ID;
- popup presentation does not log a second time;
- raw `localizedDescription` is no longer interpolated directly into error alerts.

Remaining limitations:

- not every inline status operation has specific wording; many use generic “That change couldn't be applied” context;
- `CommandError.message` trusts arbitrary caller text as human-safe;
- wrapper errors frequently lose typed underlying causes;
- the support-summary privacy issue above must be fixed before encouraging users to copy it.

The popup requirement is broadly met for the first pass, subject to the privacy issue.

## Architecture and concurrency review

Positive observations:

- `AuroraDiagnostics` remains Foundation/OSLog-only and package dependencies are acyclic;
- logger/configuration primitives are not main-actor-bound;
- structured logger helpers evaluate message/technical/metadata autoclosures only after threshold checks;
- Logger instances are cached per category;
- Unified Logging receives one OSLog call per accepted structured event with a public short reference;
- the in-memory projection is bounded by count and approximate bytes;
- AME mirrors diagnostics after releasing the AME lock;
- output and network callbacks generally unlock driver state before emitting recovery/summary events;
- error reporting is UI-neutral, with AppKit/SwiftUI presentation layered above it.

Risks:

- the global singleton logger/configuration design makes test isolation and multi-instance previews fragile;
- direct `PrismLog.shared.log(event)` calls bypass autoclosure laziness, although the composite still filters before sink work;
- hot-path code still pays counter work before checking whether Debug is enabled;
- some domain locks still enclose logging calls;
- the production Unified sink carries an unnecessary test capture buffer.

## Settings and Console review

Positive observations:

- AME and Music categories are independently configurable;
- group and per-leaf controls are present;
- Production, Troubleshooting, Verbose All, and Custom profiles behave sensibly after the Custom preservation fix;
- changes apply immediately and persist as app-global settings;
- corrupt stored configuration produces a warning after logger bootstrap;
- Settings accurately explains macOS retention and non-retroactive detail;
- Console filters by text, level, and category group;
- timestamps are formatted at presentation time;
- clearing the view is explicitly distinguished from erasing macOS logs.

Remaining issues:

- the test-only suppression flag is persisted;
- configuration version is ignored;
- actual Settings model/persistence integration is lightly tested;
- support commands use the correct shipping subsystem but no automated test ensures they stay synchronized with `UnifiedPrismLogger.subsystem`.

## Test and tooling assessment

The expanded test suite is healthy and all 927 tests pass. The dedicated diagnostics tests cover:

- threshold ordering and Off semantics;
- per-category configuration and Codable defaults;
- message laziness;
- composite fan-out and metadata privacy downgrade;
- ring eviction;
- rate-limiter mechanics;
- configuration-store concurrency;
- error mapping and exactly-once reporting;
- support-summary omission of raw technical dumps;
- one-record Unified Logging composition and concurrent record capture;
- representative Engine, Music, and Remote domain events.

Recommended additions:

- production decode cannot enable full error/fault suppression;
- Project save does not emit Project open;
- Art-Net/sACN async send failures and recovery;
- disabled Debug output performs no interval-counter work;
- exact lifecycle event multiplicity/ordering;
- actual `LoggingSettingsModel` and `AppSettingsStore` round trip;
- future configuration-version fallback;
- support-copy tests for names, hostname, serial, endpoint, IPv6, Windows path, and varied secret syntax;
- lock/concurrency stress around Remote hello and output completions;
- measured high-rate AME/MIDI/DMX performance.

The lint script is useful but pattern-based. The catch-audit verifier now rejects obvious placeholders and requires every catch-site line to appear. It still cannot verify that a note is accurate or that the claimed event is emitted on the relevant branch; targeted integration tests are needed for that.

## Recommended remediation order

1. Remove production persistence/decoding of full fault suppression.
2. Add runtime Art-Net/sACN failure logging outside driver locks.
3. Make support summaries code/reference/category-only or explicitly safe-field-only.
4. Eliminate disabled-verbose counter work from output hot paths and benchmark it.
5. Stop Project save verification from emitting Project open.
6. Disable the Unified logger capture buffer in production.
7. Move Remote session logging outside its lock.
8. Enforce configuration version handling.
9. Remove duplicate/no-op lifecycle events and formalize event ownership.
10. Preserve structured underlying error causes and strengthen integration/privacy/performance tests.

## Final conclusion

The first pass is technically substantial and much closer to the requested system: Settings can independently tune AME, Music, output protocols, controls, Remote, Project, UI, and other categories; native Unified Logging is used; Console remains bounded; and popup errors are generally human-readable with paired technical records.

It should not receive final release approval yet. The P1 items affect the core promises of the feature—errors must never silently disappear, runtime output failures must be available after the fact, copied diagnostics must honor their privacy guarantee, and disabled verbose logging must remain cheap on lighting output paths. Once those issues and their tests are addressed, the remaining P2/P3 items can be closed in a focused hardening pass.
