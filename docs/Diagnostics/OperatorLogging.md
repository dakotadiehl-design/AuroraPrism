# Operator logging guide

Prism writes diagnostics through Apple Unified Logging. Prism does not keep its own rotating log files. macOS decides how long records stay on disk.

## Settings

Open **Settings → Logging**.

- **Off (errors still logged)** hides routine messages. Errors and faults are still written.
- **Errors only** is the same acceptance as Off, labeled for categories you want quiet except failures.
- **High-level** is the production default for engines, I/O, and project work.
- **Information** adds normal operational decisions.
- **Verbose** adds sampled diagnostic detail. Verbose and informational records may not persist as long as errors.

AME and Music Engine are separate groups. You can set AME to Verbose while Music stays High-level.

Changing a level applies immediately. It does not recreate older detail.

**Clear Console View** in the Console panel only clears the in-app list. It does not erase macOS logs.

## Collecting logs for support

Copy the support command from Settings → Logging, or run:

```
log show --predicate 'subsystem == "com.aurora.lighting"' --last 15m
```

Live stream:

```
log stream --predicate 'subsystem == "com.aurora.lighting"'
```

Send the command output plus the **Reference ID** from any error alert. Do not attach show files, PINs, or fixture library folders unless support asks and you have redacted them.

## Signed Debug / Release smoke list

1. Launch Prism. `log stream` should show `app.lifecycle.launch` under subsystem `com.aurora.lighting`.
2. Set AME to Verbose and Music to High-level. Confirm AME debug codes appear and music tick codes do not.
3. Force a save failure (locked folder). The alert is plain language and includes a Reference ID. The log event has the same ID plus a technical field.
4. Quit. Confirm `app.lifecycle.terminate`.
