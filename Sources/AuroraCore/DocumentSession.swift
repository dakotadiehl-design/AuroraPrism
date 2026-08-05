import AuroraModel
import Foundation

/// Owns the live `ShowProject`, undo stack, event bus, and selection.
///
/// All show mutations should go through `perform(_:)`.
@MainActor
public final class DocumentSession {
    public private(set) var project: ShowProject
    public private(set) var isDirty: Bool = false

    public let eventBus = EventBus()
    public let selection = SelectionManager()

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

    // MARK: - Selection (publishes events)

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
        undoStack.push(group)
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

    /// Publishes project events and prunes selection after a successful mutation.
    /// Selection is not restored on undo/redo (by design).
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
