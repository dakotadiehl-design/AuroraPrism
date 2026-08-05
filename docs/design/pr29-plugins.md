# PR29 — Plugin Architecture Skeleton

| Field | Value |
|-------|--------|
| **PR** | PR29 |
| **Status** | Implemented (skeleton) |
| **Depends on** | Mature module APIs |

## Delivered

- `AuroraPlugin` protocol + `PluginManifest` (id, name, version, capabilities)
- `PluginHost` registry (in-process registration only)
- Capability tags: `.outputDriver`, `.effectGenerator`, `.fixtureImporter`, `.controlInput`
- Smoke tests for register/list

## Explicit non-goals (v1)

- Dynamic `.bundle` / dylib loading at runtime
- Sandboxed third-party marketplace
- ABI stability guarantees

In-process registration keeps architecture safe while reserving extension points.
