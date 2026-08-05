# PR3 — Command System & Undo

| Field | Value |
|-------|--------|
| **PR** | PR3 |
| **Title** | Command system & undo |
| **Status** | Implemented |
| **Depends on** | PR1–PR2 |
| **Unblocks** | PR4, PR6, PR7 menus, PR31 remote commands |
| **Parent design** | [`aurora-system-design.md`](./aurora-system-design.md) §6.1 |

---

## 1. Purpose

1. All show mutations go through a **`Command`** protocol.  
2. **`DocumentSession`** owns the live `ShowProject` and an unlimited **undo/redo** stack.  
3. Support **transaction groups** and **coalescing** (rename).  
4. Ship sample commands: add/remove fixture, rename project.  

---

## 2. Non-goals

- AppKit `UndoManager` menu bridge (PR7)  
- Engine notification  
- Full command catalog  
- Event bus / selection (PR4)  

---

## 3. Types

| Type | Role |
|------|------|
| `Command` | `perform` / `undo` / optional `merging` |
| `CommandContext` | Mutable `ShowProject` during apply |
| `CommandError` | Validation failures |
| `UndoStack` | Undo/redo stacks |
| `CommandGroup` | Composite undo step |
| `DocumentSession` | `perform` / `undo` / `redo` / groups / `isDirty` |
| `AddPatchedFixtureCommand` | Add + overlap check |
| `RemovePatchedFixtureCommand` | Remove + group membership restore |
| `RenameProjectCommand` | Coalescing rename |

Concurrency: `@MainActor` for session and commands.

---

## 4. Acceptance

- [x] Command + session + undo/redo + groups  
- [x] Sample add/remove fixture + rename  
- [x] Tests for perform/undo/redo, group, coalesce, atomic errors  
- [x] No Engine/MIDI product logic  

---

## 5. Next

**PR4** — event bus + selection manager, wire `projectModified` from session.
