import AuroraModel
import Foundation

/// Owns the live `ShowProject`, undo stack, and (PR4) events/selection wiring points.
///
/// All show mutations should go through `perform(_:)`.
@MainActor
public final class DocumentSession {
    public private(set) var project: ShowProject
    public private(set) var isDirty: Bool = false

    private let undoStack = UndoStack()
    private var groupingName: String?
    private var groupBuffer: [any Command]?

    public init(project: ShowProject) {
        self.project = project
    }

    // MARK: - Undo state

    public var canUndo: Bool { undoStack.canUndo }
    public var canRedo: Bool { undoStack.canRedo }
    public var undoActionName: String? { undoStack.undoActionName }
    public var redoActionName: String? { undoStack.redoActionName }

    // MARK: - Commands

    /// Performs a command, pushing it onto the undo stack (or merging / grouping).
    public func perform(_ command: any Command) throws {
        let context = CommandContext(project: project)
        let snapshot = project

        do {
            try command.perform(context: context)
        } catch {
            project = snapshot
            throw error
        }

        project = context.project
        isDirty = true

        if var buffer = groupBuffer {
            // New user action invalidates redo even while grouping.
            if buffer.isEmpty {
                undoStack.clearRedo()
            }
            buffer.append(command)
            groupBuffer = buffer
            didMutateProject()
            return
        }

        if let prior = undoStack.top, let merged = command.merging(withPrior: prior) {
            try undoStack.replaceTop(with: merged)
        } else {
            undoStack.push(command)
        }

        didMutateProject()
    }

    public func undo() throws {
        let command = try undoStack.popUndo()
        let context = CommandContext(project: project)
        let snapshot = project

        do {
            try command.undo(context: context)
        } catch {
            project = snapshot
            undoStack.push(command)
            throw error
        }

        project = context.project
        isDirty = true
        undoStack.pushRedo(command)
        didMutateProject()
    }

    public func redo() throws {
        let command = try undoStack.popRedo()
        let context = CommandContext(project: project)
        let snapshot = project

        do {
            try command.perform(context: context)
        } catch {
            project = snapshot
            undoStack.pushRedo(command)
            throw error
        }

        project = context.project
        isDirty = true
        undoStack.pushUndoPreservingRedo(command)
        didMutateProject()
    }

    public func beginGroup(named name: String) throws {
        guard groupBuffer == nil else { throw CommandError.alreadyGrouping }
        groupingName = name
        groupBuffer = []
    }

    public func endGroup() throws {
        guard let buffer = groupBuffer, let name = groupingName else {
            throw CommandError.notGrouping
        }
        groupBuffer = nil
        groupingName = nil

        guard !buffer.isEmpty else {
            throw CommandError.emptyGroup
        }

        let group = CommandGroup(name: name, commands: buffer)
        // Commands already applied during perform; only push the composite for undo.
        undoStack.push(group)
        didMutateProject()
    }

    public func cancelGroup() throws {
        guard groupBuffer != nil else { throw CommandError.notGrouping }
        // Cannot easily roll back already-applied group members without reverse order undo.
        // Policy: cancel is only valid before any perform in the group, or we undo buffer.
        if let buffer = groupBuffer, !buffer.isEmpty {
            let context = CommandContext(project: project)
            for command in buffer.reversed() {
                try command.undo(context: context)
            }
            project = context.project
        }
        groupBuffer = nil
        groupingName = nil
    }

    /// Hook for PR4 event publication / selection prune. PR3 default is a no-op override point.
    public func didMutateProject() {
        // Overridden behavior layered in PR4 via same method body update.
    }
}
