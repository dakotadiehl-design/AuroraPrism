# UI-03 — Fixture Browser + Programmer — Implementation Plan (Amended)

**Depends on:** UI-02 complete (`dbdd891` / tag `ui-02-complete`)  
**Disposition:** Approved with amendments from  
`Aurora_UI_03_Plan_Recommended_Amendments.md`

**Sources of truth:**  
- `UIDesignReferences/UIDevPlan.md` § UI-03  
- Post-UI-02 gate carry-in  
- UI-03 plan amendments (binding)  
- `docs/UI_BACKEND_CONTRACT.md`, `docs/UI_PANEL_CONTRACT.md`  
- Engine: `Programmer`, `ProgrammerGeometry`, `CompiledShow`

**Goal:** First complete high-value programming workflow — truthful multi-fixture Programmer (support + value), ordered selection for Fan, live sync from external mutations, responsive ~80 **mixed** fixtures.

**Non-goals:** Shell redesign, UI-04 palettes create/delete, UI-05 cues, stage-map, raw DMX primary UX, AppModel wholesale rewrite, remote Programmer.

**Key principle:**

> The Programmer must tell the truth about the **entire selected rig**, not the first selected fixture.

---

## 0. Current baseline

| Surface | Today | UI-03 gap |
|---------|--------|-----------|
| `ProgrammerPanel` | First-fixture `@State`; Locate/Home/Clear selection | Stale after MIDI; no mixed; no Fan/Align/Clear All; no real technical color |
| `FixtureBrowserPanel` | Search, select, inspect | Selection summary; optional quiet badges only |
| `GroupsPanel` | `selectFixtures(Set)` | Must use **ordered** selection |
| Engine | `clearAll`, `setMany`, fan/align geometry | Wire + **lock Fan/Align semantics** |
| Design system | `AuroraAttributeVisualState` | Drive controls from dual support/value model |
| Shell | Option A | **Unchanged** |

---

## 1. Locked product decisions

### 1.1 Restore table

| Function | Decision | Notes |
|----------|----------|--------|
| Clear selection | Keep | Clear programmer values for selected only |
| Clear All | Restore | Distinct control; `programmer.clearAll()` |
| Fan | Restore | **Center + spread + ordered selection** (see §1.2) |
| Align | Restore | **Align to First** — first capable in `orderedFixtureIDs` (see §1.3) |
| HSV wheel | Keep primary | High-level color |
| Technical color | Secondary | **Only real supported channels** (no fake W) |

### 1.2 Fan semantics (locked before coding)

**Model:**

```text
center + spread + orderedFixtureIDs
```

For N ordered fixtures, map each to a normalized phase in approximately `[-1…+1]` and distribute the active attribute around `center` by `spread`.

```text
fixture 1 … fixture N
  -1        0        +1   (phase across ordered selection)
value_i = clamp(center + phase_i * spread, 0…1)
```

**Rules:**

- Operates only on fixtures that **support** the active attribute  
- Never invents unsupported attributes  
- **Pan and Tilt fan independently** — no implicit 2D coupling  
- Deterministic; reverse selection order reverses fan result  
- If attribute is **untouched**, do **not** silently invent a 0…1 fan; UI must establish intentional center/spread when user invokes Fan  
- If values already exist and center/spread can be derived unambiguously, may seed controls from them  

**Engine:** extend or wrap `ProgrammerGeometry` with explicit `fan(fixtureIDs:center:spread:)` (or equivalent).

### 1.3 Align semantics (locked)

**UI label:** “Align to First” (or equivalent tooltip).

```text
reference = first fixture in orderedFixtureIDs that supports the active attribute
all capable selected fixtures → that reference value
```

- Not Set iteration / project order  
- If no capable reference → disable Align  
- Unsupported fixtures untouched  

### 1.4 Mixed-value ordinary edit (locked)

Display: **MIXED** — never first-fixture value as truth.

On **first intentional** fader/pad/wheel movement:

```text
all capable fixtures receive the explicit new value
state → common(newValue) / programmer-owned
```

Do **not** preserve relative offsets on ordinary drag. Fan is the geometry path for relative distribution.

### 1.5 Orthogonal support vs value (locked model)

**Do not** conflate support and value in one mega-enum.

```swift
enum AttributeSupportState: Equatable {
    case none
    case partial
    case all
}

enum ProgrammerValueState: Equatable {
    case untouched
    case common(Double)
    case mixed
}

struct ProgrammerAttributeState: Equatable {
    var support: AttributeSupportState
    var value: ProgrammerValueState
}

struct ProgrammerAttributePresentation: Equatable {
    var orderedFixtureIDs: [UUID]
    var intensity, pan, tilt: ProgrammerAttributeState
    var colorR, colorG, colorB, colorW: ProgrammerAttributeState
}
```

| support | value | UI |
|---------|-------|-----|
| none | — | hide / unavailable |
| partial / all | untouched | control + untouched chrome |
| partial / all | common(v) | show v + owned chrome |
| partial / all | mixed | MIXED — no fake representative number |
| partial | * | apply only to capable |

**Inherited / palette-referenced:** do not fake in UI-03 unless data is real.

### 1.6 Technical color

Secondary faders only for attributes the selection actually supports. No decorative W.

---

## 2. Architecture

```text
Programmer  (source of truth)
    ↓
ProgrammerPresentationStore  (observable projection — preferred over magic epoch)
    ↓
ProgrammerPanel  (presentation + temporary drag drafts)
```

- Store derives from snapshot + ordered selection + definitions  
- Refresh after: local UI, MIDI, palette apply, Locate, Home, Clear, Clear All, Fan, Align  
- Epoch only as fallback if store is too invasive  

**Fan order inspectability:** summary strip or temporary order indicators while Fan is active.

Shell geometry and panel hosting contract unchanged.

---

## 3. Waves

### Wave A — Presentation + ordered selection

| ID | Work |
|----|------|
| A1 | Dual-axis presentation + pure resolve + support×value tests |
| A2 | Groups/Browser → `selectFixturesOrdered` |
| A3 | Geometry `fan(center:spread:)` + order/unsupported/pan-tilt tests |
| A4 | Align-to-first helper + tests |

### Wave B — Programmer panel

| ID | Work |
|----|------|
| B1 | `ProgrammerPresentationStore` + host wiring |
| B2 | Sections Intensity / Color / Position from support |
| B3 | Chrome + mixed edit → common |
| B4 | External sync (MIDI without reselect) — first-class acceptance |
| B5–B6 | Locate/Home/Clear / Clear All |
| B7–B8 | Fan (center/spread + order UI) / Align to First |
| B9–B10 | Technical color (real attrs) + numeric |

### Wave C — Fixture Browser

| ID | Work |
|----|------|
| C1–C2 | Ordered multi-select + selection summary |
| C3 | Capability badges **optional** only if quiet |
| C4–C6 | Group ordered select; cache capabilities; large mixed smoke |

### Wave D — Light integration

Inspector programmer attrs (light); palette apply refreshes store — no palette CRUD.

### Wave E — Closeout

Tests (§5), mixed-80 performance, **visual review gate** (single/common/mixed/partial/Fan/large), docs, `swift test` + Xcode Debug.

---

## 4. Performance

Stress **80 mixed** fixtures (multiple personalities, intensity-only + color + movers), search active, fader/Fan interaction. Goal: perceptually immediate; cache definition capabilities; no high-frequency whole-shell invalidation.

---

## 5. Acceptance (UI-03 complete)

```text
[ ] Ordered fixture/group selection
[ ] Selection order inspectable when using Fan
[ ] Support × value independent and truthful
[ ] Mixed never shows first fixture as truth
[ ] Mixed ordinary edit → common explicit value
[ ] Clear Selection + Clear All distinct
[ ] Fan center+spread; ordered; skip unsupported; pan/tilt independent
[ ] Align to First deterministic
[ ] Technical color = real channels only
[ ] MIDI/external + Locate/Home/Clear/Fan/Align/palette refresh UI
[ ] Browser scannable; badges optional
[ ] ~80 mixed fixtures responsive
[ ] Programmer ephemeral; shell unchanged
[ ] Visual review passes
[ ] Unit tests + Xcode Debug green
```

---

## 6. Explicit non-work

UI-04 palettes CRUD · UI-05 cues · full beam/gobo · stage map · AppModel rewrite · remote · UI-04/05 drift

---

## 7. Success

```text
Select ordered mixed rig → truthful mixed/owned/partial programming
→ Fan with inspectable order → Align to First → Clear All
→ external mutations refresh → ~80 mixed remains immediate → visual review
→ Close UI-03
```
