# Prism Log Event Catalog

Subsystem: `com.aurora.lighting`

Levels: `debug` < `info` < `notice` < `warning` < `error` < `fault`.  
`Off` in Settings still accepts `error` and `fault`.

Privacy: dynamic values default to `.private`. Public allowlist: `code`, `category`, `level`, `count`, `enabled`, `ok`, `protocol`, `universe`, `frameRateHz`, `port`, `schemaVersion`, `durationMs`, `sampled`, `suppressedCount`, `profile`.

Volume budgets:

| Scenario | Allowed |
| --- | --- |
| Idle, Production Defaults | lifecycle/state only; no recurring events |
| Playback, Production Defaults | cue/transport transitions only; 0 events/frame |
| Heavy MIDI, AME High-level | no per-event logs |
| AME Verbose | sampled + rate-limited; `ame.ingress.received` is not 1:1 with MIDI |
| 4-universe output @ 40–44 Hz | 0 per-frame logs at High-level; verbose summaries ≤ 1 Hz/driver |

Rate policy `1/s` means first event plus a `log.rate_limited` summary at the next window.


## Implementation status

Every catalog row is implemented in production sources as a structured event literal.

## App

| Code | Level | Category | Metadata | Rate | Owner |
| --- | --- | --- | --- | --- | --- |
| `app.lifecycle.launch` | notice | app.lifecycle | profile, count (enabled categories) public | none | Aurora |
| `app.lifecycle.terminate` | notice | app.lifecycle | — | none | Aurora |
| `app.settings.profile_changed` | notice | app.settings | profile public | none | Aurora |
| `app.settings.config_fallback` | warning | app.settings | — | none | Aurora |
| `app.windowing.surface_opened` | info | app.windowing | — | none | Aurora |

## Project

| Code | Level | Category | Metadata | Rate | Owner |
| --- | --- | --- | --- | --- | --- |
| `project.document.created` | notice | project.document | — | none | Aurora |
| `project.document.opened` | notice | project.document | schemaVersion public | none | Aurora |
| `project.document.saved` | notice | project.document | schemaVersion public | none | Aurora |
| `project.document.migrated` | notice | project.migration | schemaVersion public | none | Aurora |
| `project.document.open_failed` | error | project.document | — | none | Aurora |
| `project.document.save_failed` | error | project.document | — | none | Aurora |
| `project.document.import_failed` | error | project.document | — | none | Aurora |
| `project.autosave.succeeded` | info | project.autosave | — | none | Aurora |
| `project.autosave.failed` | error | project.autosave | count public | none | Aurora |
| `project.autosave.disabled` | notice | project.autosave | — | none | Aurora |
| `project.validation.summary` | info | project.validation | count public | none | Aurora |
| `project.command.failed` | error | project.document | — | none | AuroraCore / AuroraUI |
| `project.command.rolled_back` | debug | project.document | — | none | AuroraCore |

## Fixture

| Code | Level | Category | Metadata | Rate | Owner |
| --- | --- | --- | --- | --- | --- |
| `fixture.library.loaded` | notice | fixture.library | count public | none | Aurora |
| `fixture.library.load_failed` | error | fixture.library | — | none | Aurora |
| `fixture.library.directory_changed` | notice | fixture.library | — | none | Aurora |
| `fixture.library.failed` | error | fixture.library | — | none | Aurora |
| `fixture.library.export_failed` | error | fixture.library | — | none | Aurora |
| `fixture.library.import_failed` | error | fixture.library | — | none | Aurora |
| `fixture.library.save_failed` | error | fixture.library | — | none | AuroraUI |
| `fixture.import.completed` | notice | fixture.import | count public | none | AuroraFixtureLib |
| `fixture.import.failed` | error | fixture.import | — | none | AuroraFixtureLib |
| `fixture.lightkey.import_completed` | notice | fixture.lightkey | count public | none | AuroraFixtureLib |
| `fixture.lightkey.import_failed` | error | fixture.lightkey | — | none | AuroraFixtureLib |

## Engine

| Code | Level | Category | Metadata | Rate | Owner |
| --- | --- | --- | --- | --- | --- |
| `engine.show.started` | notice | engine.show | frameRateHz public | none | AuroraEngine |
| `engine.show.start_failed` | error | engine.show | — | none | AuroraEngine |
| `engine.show.stopped` | notice | engine.show | — | none | AuroraEngine |
| `engine.cues.go` | notice | engine.cues | — | none | AuroraEngine |
| `engine.programmer.clear` | info | engine.programmer | — | none | AuroraEngine |
| `engine.effects.update_failed` | error | engine.effects | — | none | Aurora |
| `engine.performance.budget_exceeded` | warning | engine.performance | durationMs public | 1/s | AuroraEngine |

## AME

Correlation: `latencyID` → `correlationID`. Mapping/trigger UUIDs are private identifiers.

| Code | Level | Category | Rate |
| --- | --- | --- | --- |
| `ame.ingress.received` | debug | ame.ingress | 1/s |
| `ame.ingress.armed` | notice | ame.ingress | none |
| `ame.ingress.disarmed` | notice | ame.ingress | none |
| `ame.ingress.config_accepted` | notice | ame.ingress | none |
| `ame.ingress.config_rejected` | error | ame.ingress | none |
| `ame.ingress.invalid_config` | error | ame.ingress | none |
| `ame.ingress.timestamp_fallback` | info | ame.ingress | 1/s |
| `ame.ingress.learn_failed` | warning | ame.ingress | none |
| `ame.matching.matched` | debug | ame.matching | 1/s |
| `ame.matching.missed` | debug | ame.matching | 1/s |
| `ame.matching.candidate` | debug | ame.matching | 1/s |
| `ame.matching.suppressed` | debug | ame.matching | 1/s |
| `ame.matching.disabled` | info | ame.matching | none |
| `ame.matching.scope_inactive` | debug | ame.matching | 1/s |
| `ame.matching.timing_failed` | debug | ame.matching | 1/s |
| `ame.matching.rate_suppressed` | debug | ame.matching | 1/s |
| `ame.matching.edit_skipped` | debug | ame.matching | 1/s |
| `ame.transform.rejected` | debug | ame.transform | 1/s |
| `ame.emission.skipped` | debug | ame.emission | 1/s |
| `ame.emission.fired` | info | ame.emission | none |
| `ame.emission.dry_run` | debug | ame.emission | 1/s |
| `ame.emission.armed` | info | ame.emission | none |
| `ame.emission.unsupported` | warning | ame.emission | none |
| `ame.held.acquired` | debug | ame.heldState | 1/s |
| `ame.held.released` | debug | ame.heldState | 1/s |
| `ame.held.release_all` | debug | ame.heldState | none |
| `ame.held.release_emission` | debug | ame.heldState | 1/s |
| `ame.held.released_by_context` | debug | ame.heldState | none |
| `ame.held.released_by_document` | debug | ame.heldState | none |
| `ame.held.released_by_mode` | debug | ame.heldState | none |
| `ame.held.released_by_source` | debug | ame.heldState | none |
| `ame.held.sim_purged` | info | ame.heldState | none |
| `ame.quantization.immediate` | debug | ame.quantization | 1/s |
| `ame.quantization.deferred` | debug | ame.quantization | 1/s |
| `ame.quantization.cancelled` | debug | ame.quantization | 1/s |
| `ame.quantization.held` | debug | ame.quantization | 1/s |
| `ame.quantization.fallback` | info | ame.quantization | none |
| `ame.sequence.deferred` | debug | ame.sequence | 1/s |
| `ame.sequence.step_fired` | info | ame.sequence | none |
| `ame.sequence.advanced` | info | ame.sequence | none |
| `ame.sequence.reset` | info | ame.sequence | none |
| `ame.sequence.missing` | debug | ame.sequence | none |
| `ame.sequence.empty` | debug | ame.sequence | none |
| `ame.sequence.invalid_step` | debug | ame.sequence | none |
| `ame.sequence.control` | debug | ame.sequence | none |
| `ame.sequence.no_context` | debug | ame.sequence | none |

## Music

| Code | Level | Category | Rate |
| --- | --- | --- | --- |
| `music.transport.start` | notice | music.transport | none |
| `music.transport.stop` | notice | music.transport | none |
| `music.transport.continue` | notice | music.transport | none |
| `music.clock.provider_changed` | notice | music.clock | none |
| `music.clock.provider_lost` | warning | music.clock | none |
| `music.clock.tempo_source_changed` | notice | music.clock | none |
| `music.song.section_changed` | info | music.song | none |
| `music.scheduler.rescheduled` | info | music.scheduler | none |
| `music.scheduler.deadline_missed` | warning | music.scheduler | 1/s |
| `music.scheduler.tick_summary` | debug | music.scheduler | 1 Hz summary only |

## Output

| Code | Level | Category | Rate |
| --- | --- | --- | --- |
| `output.routing.changed` | notice | output.routing | none |
| `output.localDMX.started` | notice | output.localDMX | none |
| `output.localDMX.stopped` | notice | output.localDMX | none |
| `output.localDMX.failed` | error | output.localDMX | 1/s |
| `output.localDMX.recovered` | info | output.localDMX | none |
| `output.artnet.started` | notice | output.artnet | none |
| `output.artnet.stopped` | notice | output.artnet | none |
| `output.artnet.failed` | error | output.artnet | 1/s |
| `output.artnet.recovered` | info | output.artnet | none |
| `output.artnet.frame_summary` | debug | output.artnet | ≤ 1 Hz |
| `output.sacn.started` | notice | output.sacn | none |
| `output.sacn.stopped` | notice | output.sacn | none |
| `output.sacn.failed` | error | output.sacn | 1/s |
| `output.sacn.recovered` | info | output.sacn | none |
| `output.sacn.frame_summary` | debug | output.sacn | ≤ 1 Hz |
| `output.localDMX.frame_summary` | debug | output.localDMX | ≤ 1 Hz |

## Control

| Code | Level | Category | Rate |
| --- | --- | --- | --- |
| `control.midi.started` | notice | control.midi | none |
| `control.midi.failed` | error | control.midi | none |
| `control.midi.source_changed` | notice | control.midi | none |
| `control.midi.learned` | info | control.midi | none |
| `control.osc.started` | notice | control.osc | none |
| `control.osc.stopped` | notice | control.osc | none |
| `control.osc.failed` | error | control.osc | none |
| `control.rtpMIDI.started` | notice | control.rtpMIDI | none |
| `control.rtpMIDI.stopped` | notice | control.rtpMIDI | none |

## Remote

Never log PIN, tokens, or client display names as public.

| Code | Level | Category | Rate |
| --- | --- | --- | --- |
| `remote.host.starting` | notice | remote.host | none |
| `remote.host.started` | notice | remote.host | none |
| `remote.host.stopped` | notice | remote.host | none |
| `remote.host.failed` | error | remote.host | none |
| `remote.web.started` | notice | remote.web | none |
| `remote.web.stopped` | notice | remote.web | none |
| `remote.web.failed` | error | remote.web | none |
| `remote.session.authenticated` | info | remote.session | none |
| `remote.session.kicked` | notice | remote.session | none |
| `remote.session.auth_failed` | warning | remote.session | 1/s |
| `remote.codec.invalid` | warning | remote.codec | 1/s |

## UI

| Code | Level | Category | Rate |
| --- | --- | --- | --- |
| `ui.workspace.layout_load_failed` | warning | ui.workspace | none |
| `ui.workspace.layout_save_failed` | error | ui.workspace | none |
| `ui.workspace.layout_reset` | notice | ui.workspace | none |
| `ui.workspace.float_persist_failed` | warning | ui.workspace | none |
| `ui.stage.layout_commit_failed` | error | ui.stage | none |
| `ui.stage.media_failed` | error | ui.stage | none |
| `ui.patch.command_failed` | error | ui.patch | none |
| `patch.rename.failed` | error | ui.patch | none |
| `ui.presentation.export_failed` | debug | ui.presentation | none |

## Logging internals

| Code | Level | Category | Rate |
| --- | --- | --- | --- |
| `log.rate_limited` | debug | same as suppressed category | none |
