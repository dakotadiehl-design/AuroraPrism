# Aurora — Project Handoff / Compressed-Session Memory

**Purpose:** Survive chat-memory compression. **Read this file first** in any new session before changing code.

| Field | Value |
|-------|--------|
| **Last updated** | 2026-08-05 (Pre-UI blockers complete — UI redesign unblocked) |
| **Workspace** | `/Users/dakota/code/Aurora` |
| **Branch** | `main` (local only; no remote assumed) |
| **HEAD** | *(see `git log -1`)* — Pre-UI blockers cleanup |
| **Tests** | **264** passing (`swift test`) |
| **Xcode app** | `Aurora.xcodeproj` — Debug build verified green |

**Open first after compression:**

1. **`docs/PROJECT_HANDOFF.md`** (this file)  
2. **`docs/UI_BACKEND_CONTRACT.md`** — **authoritative UI API / domain contract**  
3. **`docs/STAGE_C_UI_STATE_HANDOFF.md`** — controller ownership  
4. **`docs/xcode-project.md`** — Xcode app, entitlements, schemes  
5. **`Package.swift`** + **`Sources/Aurora/AppModel.swift`**  

**Historical only (not active backlog):**

- `Aurora_Final_Pre_UI_Blockers.md` — **implemented 2026-08-05**  
- `Aurora_Final_Backend_UI_Gate_Review.md` — implemented  
- `Aurora_Post_Remediation_Deep_Review_UI_Readiness.md`  
- `Aurora_Deep_Code_Review_Fixes.md`  

**Do not invent new PR work without an explicit user request.**  
**Backend is UI-ready. Next major deliverable: visual UI redesign when the user asks.**

---

## 1. What Aurora is

**Aurora** is a **macOS-native professional lighting control** app for live performance (patch, cues, MIDI/OSC, Art-Net/sACN, ENTTEC USB Pro framing mock, web remote). Swift SPM monorepo + Xcode app, macOS 14+.

---

## 2. Architecture (must not break)

```
UI / MIDI / OSC / remote
  → ControlActionRouter (multi-observer; live off MainActor)
  → DocumentSession and/or LightingEngine
  → OutputManager → drivers

Save / Save As / autosave
  → ProjectSaveCoordinator (actor, per-destination serial)
  → ProjectPackage.save
```

- **`updateProject`** preserves playback; **`load`** is destructive  
- Package writes are **serialized**; stale autosave cannot overwrite a newer manual save on disk  
- Output status from live `presentationSnapshot()` / health, not a config-only cache  
- Quit: `prepareToTerminate()` → await save → idempotent `shutdown()`  

---

## 3. Pre-UI blockers completed (this pass)

| ID | Fix |
|----|-----|
| **BLOCKER-1** | `ProjectSaveCoordinator` + async ProjectController save/autosave; quit awaits save |
| **PRE-UI-1** | `OutputPresentationSnapshot` from live health; presentation poll refreshes |
| **PRE-UI-2** | Lock-protected `isRunning` on all output drivers |
| **PRE-UI-3** | `applicationShouldTerminate` / `applicationWillTerminate` → shutdown |
| **UI-FOUNDATION-5** | 16-bit home/highlight uses coarse\|fine / 65535 |
| Doc | Bookmarks entitlement documented as reserved/not implemented |

**Carry into first UI PR (not done here):** UI-FOUNDATION-1 Option A composition, app integration tests, bookmark store, AppIcon artwork.

---

## 4. Key domain rules (summary)

| Topic | Behavior |
|-------|----------|
| Dirty | Unique state IDs; group dirty on first mutation |
| Save | Coordinator serializes; mark clean only for written state ID if still current |
| Route `none` | No physical output; `mirror` = all protocols |
| Active channels | Sum across all universes |
| Song | Manual only |
| Frame rate | App setting drives engine 20–44 Hz |
| ENTTEC | USB Pro framing only — not Open DMX |
| Home/Highlight | Full 16-bit when coarse+fine present |

---

## 5. Intentionally next (user-driven)

1. **Visual UI redesign** — `UI_BACKEND_CONTRACT.md` Option A (AuroraUI = design system; app = controller screens)  
2. Hardware soak Art-Net/sACN/ENTTEC  
3. App integration test target / bookmarks / AppIcon during UI foundation  

**Stop backend feature work** until user requests otherwise.

---

## 6. Smoke

```bash
swift test
xcodebuild -project Aurora.xcodeproj -scheme Aurora -destination 'platform=macOS' \
  -configuration Debug CODE_SIGN_IDENTITY="-" build
open Aurora.xcodeproj   # Run Aurora
```

---

## 7. Agent instructions post-compact

```
Read docs/PROJECT_HANDOFF.md and docs/UI_BACKEND_CONTRACT.md first.
Do not invent PR work without explicit user request.
Backend pre-UI blockers are DONE — do not re-implement from review MDs.
UI redesign only when user asks (Option A composition).
Preserve control path, save coordinator, module deps.
```

---

*End of handoff.*
