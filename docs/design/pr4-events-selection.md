# PR4 — Event Bus & Selection

| Field | Value |
|-------|--------|
| **PR** | PR4 |
| **Title** | Event bus & selection |
| **Status** | Implemented |
| **Depends on** | PR3 |
| **Unblocks** | PR7 UI binding, PR14 programmer, PR31 remote |
| **Parent design** | [`aurora-system-design.md`](./aurora-system-design.md) §6.2–6.3 |

---

## 1. Purpose

1. Typed **`AppEvent`** publication via **`EventBus`**.  
2. **`SelectionManager`** multi-select for fixtures, cues, lists, songs, groups.  
3. **`DocumentSession`** publishes `projectModified` after command lifecycle and prunes selection.  

---

## 2. Non-goals

- Engine/MIDI event producers  
- Combine / `ObservableObject`  
- Undo restoring selection (explicitly **not** restored)  
- Remote bridge (PR31)  

---

## 3. Types

| Type | Role |
|------|------|
| `AppEvent` | `.projectModified`, `.selectionChanged(SelectionSnapshot)` |
| `EventBus` | Subscribe / unsubscribe / publish (MainActor, sync) |
| `SelectionSnapshot` | Sets of selected IDs |
| `SelectionManager` | Mutate + prune against `ShowProject` |
| `DocumentSession` | Owns bus + selection; selection helpers |

---

## 4. Acceptance

- [x] Event bus subscribe/unsubscribe/publish  
- [x] Multi-select selection manager  
- [x] Session publishes on command mutate  
- [x] Fixture remove prunes selection  
- [x] Tests green  

---

## 5. Next

PR5 fixture library seed, PR6 more patch commands, PR7 wire UI to session undo/selection.
