# C6A — Splash Source-of-Truth Discrepancy Checklist

**Phase:** C6 Splash & Brand Fidelity  
**Sources of truth:**

- Approved brand masters: `App/DesignAssets/BrandMasters/`
- Catalog assets: `App/Assets.xcassets/AuroraMark|AuroraWordmark`
- UI-02A brand rules (toolbar mark + AURORA text; full wordmark for welcome/About/splash)
- Roadmap §18–23 (fidelity areas, startup correctness, limited brand sweep)
- Production implementation: `Sources/Aurora/Splash/*`, `Branding/*`

## Comparison findings (pre-C6)

| Area | Approved intent | Production pre-C6 | Severity | C6 action |
|------|-----------------|-------------------|----------|-----------|
| Mark geometry | Soft four-point star, violet→cyan gradient, transparent field | Catalog PNGs match; transparent | OK | Keep catalog assets |
| Wordmark | Mark + metallic AURORA | Full wordmark image used under large mark → **double star** | High | Mark alone + typographic AURORA (wordmark image reserved for Welcome/About) |
| Proportions | Large mark, airy brand stack, calm status | 88pt mark, tight card, 5s min hold feels long | Medium | Larger mark, refined spacing, shorter cinematic hold |
| Background | Charcoal power-on, soft accent glow | Card on dim overlay | Medium | Full-bleed charcoal + layered glow/vignette; lighter card chrome |
| Accent/glow | Luminous aurora ribbon behind mark | Present | Low | Tune opacity/easing; reduce motion path |
| Animation | Brief intentional sequence | Phases OK; min 5.0s | Medium | Tighten timings; max fail-safe; reduce-motion collapse |
| Status text | Real bootstrap milestones | Correctly wired from AppModel | OK | Keep; polish typography |
| Error path | Must not trap user | Failure holds forever | High | Continue affordance + optional force dismiss |
| Multi-monitor | Single splash | Overlay only on main ContentView | OK | Document; no float splash |
| About | Brand surface | Missing | High | About Aurora window + Help menu |
| Welcome | Wordmark + actions | Minimal wordmark only | Medium | Mark + wordmark + tagline hierarchy |
| Toolbar | `[Mark] AURORA` | Present | OK | Minor tracking/alignment polish |

## Constraints documented

- No separate “approved splash PSD” in-repo; fidelity is reconstructed from brand masters + UI-02A + existing splash architecture (do not redesign from scratch).
- Wordmark imageset includes the star; stacking full wordmark under a large mark is incorrect. Native equivalent: mark asset + system wordmark typography with brand tracking/weight.
- Heavy particle/metal shaders not required; SwiftUI gradients + blur ribbon remain the high-quality native equivalent.

## Out of scope

- New app icon artwork generation
- Broad UI chrome redesign
- Marketing website / remote companion branding
