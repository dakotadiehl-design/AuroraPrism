# PR30 — Performance Hardening

| Field | Value |
|-------|--------|
| **PR** | PR30 |
| **Status** | Implemented |
| **Depends on** | PR10–11 |

## Delivered

- `PerformanceBudget` targets (frame period, snapshot throttle)
- `EngineFrameMetrics` rolling stats on `LightingEngine` (optional sampling)
- Scale test: merge + step for N fixtures stays under budget in unit test
- Diagnostics module exports budget constants

## Non-goals

- Continuous CI microbenchmarks on every commit
- Instruments templates
