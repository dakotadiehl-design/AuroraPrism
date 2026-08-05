import Foundation

/// Unlimited-session undo/redo stacks of performed commands.
@MainActor
public final class UndoStack {
    private var undoItems: [any Command] = []
    private var redoItems: [any Command] = []

    public init() {}

    public var canUndo: Bool { !undoItems.isEmpty }
    public var canRedo: Bool { !redoItems.isEmpty }

    public var undoActionName: String? { undoItems.last?.name }
    public var redoActionName: String? { redoItems.last?.name }

    public var undoCount: Int { undoItems.count }
    public var redoCount: Int { redoItems.count }

    /// Top of the undo stack (most recently performed), if any.
    public var top: (any Command)? { undoItems.last }

    /// Push a newly performed command. Clears the redo stack.
    public func push(_ command: any Command) {
        undoItems.append(command)
        redoItems.removeAll()
    }

    /// Move a command onto the undo stack without clearing redo (used by redo()).
    public func pushUndoPreservingRedo(_ command: any Command) {
        undoItems.append(command)
    }

    /// Replace the current top undo entry (coalescing). Clears redo.
    public func replaceTop(with command: any Command) throws {
        guard !undoItems.isEmpty else {
            throw CommandError.nothingToUndo
        }
        undoItems[undoItems.count - 1] = command
        redoItems.removeAll()
    }

    public func popUndo() throws -> any Command {
        guard let command = undoItems.popLast() else {
            throw CommandError.nothingToUndo
        }
        return command
    }

    public func pushRedo(_ command: any Command) {
        redoItems.append(command)
    }

    public func popRedo() throws -> any Command {
        guard let command = redoItems.popLast() else {
            throw CommandError.nothingToRedo
        }
        return command
    }

    public func clear() {
        undoItems.removeAll()
        redoItems.removeAll()
    }

    public func clearRedo() {
        redoItems.removeAll()
    }
}
