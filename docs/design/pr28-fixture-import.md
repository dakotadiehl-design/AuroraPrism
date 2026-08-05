# PR28 — Fixture Import Formats

| Field | Value |
|-------|--------|
| **PR** | PR28 |
| **Status** | Implemented (subset) |
| **Depends on** | PR5 |

## Delivered

- `FixtureImporter` for:
  1. **Native** Aurora `FixtureDefinition` JSON (same as seed files)
  2. **OFL-lite** JSON (manufacturer/name + modes[] with channel name arrays)
- Attribute heuristics (Red→colorR, Dimmer→intensity, Pan/Tilt, etc.)
- File menu: **Import Fixture Definition…** embeds into show via `EmbedFixtureDefinitionCommand`
- Unit tests for OFL-lite → definition

## Not in this PR (honest)

- Full GDTF (zip + XML) — non-trivial; would need a dedicated parser PR
- Full Open Fixture Library online fetch

GDTF remains future work; do not claim support until implemented.
