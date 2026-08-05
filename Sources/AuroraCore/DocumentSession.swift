import AuroraModel
import Foundation

/// Owns the live `ShowProject`, undo stack, event bus, and selection.
///
/// All show mutations should go through `perform(_:)`.
/// Dirty state uses generation counters so undo can return to a saved point (P0-3).
@MainActor
public final class DocumentSession {
    public private(set) var project: ShowProject

    /// Logical document generation; bumps on mutate / undo / redo.
    public private(set) var documentGeneration: UInt64 = 0
    /// Generation last successfully saved (or at open/new).
    public private(set) var savedGeneration: UInt64 = 0

    public var isDirty: Bool { documentGeneration != savedGeneration }

    public let eventBus = EventBus()
    public let selection = SelectionManager()

    private let undoStack = UndoStack()
    /// Generation after each undo stack entry was applied.
    private var undoGenerations: [UInt64] = []
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

    /// Call after a successful package save.
    public func markSaved() {
        savedGeneration = documentGeneration
    }

    /// Reset session to a loaded/new project as clean.
    public func reset(to project: ShowProject) {
        self.project = project
        undoStack.clear()
        undoGenerations.removeAll()
        groupBuffer = nil
        groupingName = nil
        documentGeneration = 0
        savedGeneration = 0
        selection.clear()
    }

    // MARK: - Selection

    public func selectFixtures(_ ids: Set<UUID>, extending: Bool = false) {
        selection.selectFixtures(ids, extending: extending)
        publishSelectionChanged()
    }

    public func clearSelection() {
        guard !selection.snapshot.isEmpty else { return }
        selection.clear()
        publishSelectionChanged()
    }

    public func toggleFixtureSelection(_ id: UUID) {
        selection.toggleFixture(id)
        publishSelectionChanged()
    }

    // MARK: - Commands

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

        if var buffer = groupBuffer {
            if buffer.isEmpty {
                undoStack.clearRedo()
            }
            buffer.append(command)
            groupBuffer = buffer
            didMutateProject()
            return
        }

        documentGeneration &+= 1
        if let prior = undoStack.top, let merged = command.merging(withPrior: prior) {
            try undoStack.replaceTop(with: merged)
            if !undoGenerations.isEmpty {
                undoGenerations[undoGenerations.count - 1] = documentGeneration
            } else {
                undoGenerations.append(documentGeneration)
            }
        } else {
            undoStack.push(command)
            undoGenerations.append(documentGeneration)
        }

        didMutateProject()
    }

    public func undo() throws {
        let command = try undoStack.popUndo()
        if !undoGenerations.isEmpty {
            undoGenerations.removeLast()
        }
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
        documentGeneration = undoGenerations.last ?? 0
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
        documentGeneration &+= 1
        undoStack.pushUndoPreservingRedo(command)
        undoGenerations.append(documentGeneration)
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

        documentGeneration &+= 1
        let group = CommandGroup(name: name, commands: buffer)
        undoStack.push(group)
        undoGenerations.append(documentGeneration)
        didMutateProject()
    }

    public func cancelGroup() throws {
        guard groupBuffer != nil else { throw CommandError.notGrouping }
        if let buffer = groupBuffer, !buffer.isEmpty {
            let context = CommandContext(project: project)
            for command in buffer.reversed() {
                try command.undo(context: context)
            }
            project = context.project
            didMutateProject()
        }
        groupBuffer = nil
        groupingName = nil
    }

    public func didMutateProject() {
        eventBus.publish(.projectModified)
        if selection.prune(against: project) {
            publishSelectionChanged()
        }
    }

    private func publishSelectionChanged() {
        eventBus.publish(.selectionChanged(selection.snapshot))
    }
}
