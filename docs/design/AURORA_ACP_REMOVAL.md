# AuroraACP removal boundary

Prism temporarily provides local lighting control only. No remote network adapter is
attached while the retired AuroraACP integration is removed and rACP remains future
work.

## Cleanup map

| Component | Disposition | Reason |
| --- | --- | --- |
| `Sources/PrismACP` | Remove | AuroraACP listener, session, discovery, enrollment, trust, state projection, and diagnostics adapter |
| `PrismACPController` | Remove | App lifecycle and presentation bridge for the retired protocol |
| ACP settings, menus, diagnostics, and persisted preferences | Remove | They would expose controls and status for an unavailable service |
| AuroraACP Swift package and `PrismACP` products/targets | Remove | No remaining consumer after adapter removal |
| `_acp._tcp` Bonjour declaration and ACP usage copy | Remove | Prism must not advertise the retired service |
| `ControlActionRouter` | Keep | Protocol-neutral semantic action boundary used by local controls and future adapters |
| Cue, song, grand-master, blackout, stop, and state semantics | Keep | Authoritative application behavior independent of transport |
| Art-Net, sACN, OSC, RTP-MIDI, and local DMX configuration | Keep | Active local/output functionality unrelated to AuroraACP |
| Historical ACP design records under `docs/design` and `FutureReference` | Keep as history | Non-production records; they are not compiled or shipped as runtime integration |

## Future rACP attachment point

A future adapter should validate rACP input and dispatch through the existing
`ControlActionRouter` and controller-level semantic methods. It must not mutate the
lighting engine, programmer, output drivers, or DMX buffers directly.
