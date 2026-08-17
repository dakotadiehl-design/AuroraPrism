# Checkpoint C6 — Splash & Brand Fidelity Closeout

**Phase:** C6  
**Status:** Implementation complete — **STOP for human visual acceptance**  
**Roadmap:** `UIDesignReferences/Aurora_C4_C5_C6_UX_Redesign_Roadmap.md` §18–23  
**Discrepancy checklist:** `C6A_DISCREPANCY_CHECKLIST.md` (same folder)

Do **not** begin Final UX Acceptance / smoke testing until this checkpoint is approved.

---

## Product goal

Bring production splash and high-visibility brand surfaces into fidelity with the approved Aurora identity — **not** a splash redesign.

---

## C6A — Source of truth

| Source | Role |
|--------|------|
| `App/DesignAssets/BrandMasters/` | Mark + wordmark masters |
| `App/Assets.xcassets/AuroraMark|AuroraWordmark` | Runtime catalog (transparent PNGs) |
| UI-02A brand rules | Toolbar `[Mark] AURORA`; full wordmark for welcome/About/splash contexts |
| Existing splash architecture | Phase sequencer + real AppModel bootstrap milestones |

Key pre-C6 defect: splash stacked **large mark + full wordmark image** → double star (wordmark imageset already includes the mark).

---

## C6B — Fidelity changes

| Area | Change |
|------|--------|
| Composition | Full-bleed charcoal + layered accent glow (less dialog-card) |
| Mark | Larger (104pt) with dual halo (violet + cool rim) |
| Wordmark | **Typographic** luminous `AURORA` under mark (no double star) |
| Tagline | Shared `LIGHTING CONTROL` (`AuroraBrandCopy`) |
| Ribbon | Retained cinematic aurora wash; reduce-motion safe |
| DMX bars | Quiet engine-activity meters after branding phase |
| Exit | Eased cubic exit progress (~0.28s), clean fade into workspace |
| Hold | Min **2.85s** (was 5.0s) — brief but intentional |

---

## C6C — Startup behavior

| Rule | Implementation |
|------|----------------|
| Prompt appear | Overlay on main `ContentView` as soon as visible |
| Real status | Bootstrap phases from `AppModel.init` (library → engine → output → MIDI → workspace) |
| Non-blocking | Workspace initializes underneath; splash is presentation only |
| Failure | Status + detail + **Continue** (no permanent trap) |
| Hang safety | Max hold **12s** then force-exit (except hard failure with Continue) |
| Single splash | Only main ContentView — **not** on float `WindowGroup`s |
| Once per process | `LaunchSplashController` process-lifetime; not on project open/mode switch |
| Reduced motion | Shorter fades; paused ribbon/bar motion |

---

## C6D — Brand consistency sweep

| Surface | Treatment |
|---------|-----------|
| Toolbar | `AuroraToolbarBrand` — shared `[Mark] AURORA` |
| Welcome | Mark + full wordmark image + tagline + soft accent wash |
| About | New `Window("About Aurora")` + Help/App menu **About Aurora** |
| Splash | Shared mark assets + typographic wordmark + product line |
| Settings | Unchanged (not a brand hero surface) |

Shared helpers: `AuroraBrandViews.swift`, `AuroraAboutView.swift`, `AuroraBrandCopy`.

---

## Files touched

- `Sources/Aurora/Splash/*` — view, visuals, controller  
- `Sources/Aurora/Branding/AuroraBrandViews.swift`  
- `Sources/Aurora/Branding/AuroraAboutView.swift` (new)  
- `Sources/Aurora/Shell/WelcomeEmptyView.swift`  
- `Sources/Aurora/Shell/AuroraBuildToolbar.swift`  
- `Sources/Aurora/ContentView.swift`  
- `Sources/Aurora/AuroraApp.swift`  
- `Tests/AuroraUITests/LaunchSplashC6Tests.swift`  
- `UX redesign/checkpoint-c6/*`

---

## Verification

| Check | Result |
|-------|--------|
| `swift build --target Aurora` | Pass |
| `xcodebuild -scheme Aurora` | Pass (after xcodegen) |
| `LaunchSplashC6Tests` | Pass |
| `WorkspaceFloatC5Tests` | Pass (regression) |

---

## Manual acceptance (human)

### Visual fidelity
- [ ] Launch splash: single mark (no double star), luminous AURORA, charcoal glow  
- [ ] Sequence feels brief and intentional (not a long commercial)  
- [ ] Retina: mark edges clean at 1x/2x  
- [ ] External display: splash only on main window; no stranded overlay  

### Startup
- [ ] Status text progresses with real init  
- [ ] Transition into Welcome/workspace is clean  
- [ ] Force-fail path (if inducible) shows Continue and recovers  

### Brand surfaces
- [ ] **Aurora → About Aurora**: mark, wordmark, version, Close  
- [ ] Welcome: mark + wordmark + LIGHTING CONTROL + actions  
- [ ] Toolbar: mark + AURORA matches UI-02A  

Capture production splash stills and compare mentally to brand masters before closing C6.

---

## STOP

> **C6 complete for implementation. STOP for human splash/brand acceptance.**

If accepted:

```text
C6 CLOSED
  → Final UX Acceptance (consolidated workflow)
  → Smoke Testing
```

Do **not** auto-start Final UX Acceptance or smoke testing from this agent turn.
