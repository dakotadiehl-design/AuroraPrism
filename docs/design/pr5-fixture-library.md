# PR5 — Fixture Library Seed Format

| Field | Value |
|-------|--------|
| **PR** | PR5 |
| **Status** | Implemented |
| **Depends on** | PR2 |
| **Unblocks** | PR6 patch, PR8 browser, PR28 import |

## Purpose

Bundled seed personalities as JSON resources, loaded by `FixtureLibrary` into `FixtureDefinition` (Model).

## Seed set

| Model | Mode | Channels |
|-------|------|----------|
| Generic Dimmer | 1-channel | intensity |
| Generic RGB Par | 3-channel | RGB |
| Generic RGBW Par | 4-channel | RGBW |
| Generic Moving Head | 16-channel | pan/tilt, intensity, color, gobo, zoom… |

Stable UUIDs under `20000000-…` for catalog/tests.

## API

- `FixtureLibrary.loadBundledSeed()`
- lookup / search / manufacturers
- `makeEmbeddableCopy` for project embed

## Non-goals

UI, GDTF import, Core dependency on FixtureLib.
