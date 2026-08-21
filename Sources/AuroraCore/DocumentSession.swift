import AuroraDiagnostics
import AuroraModel
import Foundation

/// Owns the live `ShowProject`, undo stack, event bus, and selection.
///
/// All show mutations should go through `perform(_:)`.
///
/// Dirty state uses **unique document state IDs** (P0-1 / post-remediation review):
/// - Every new committed content state mints a monotonic ID that is never reused for different content.
/// - Undo/redo restore the ID recorded for that history entry (so returning to a saved state is clean).
/// - Branching after undo mints new IDs (so depth collision cannot false-clean).
/// - Commands never coalesce across a save-point boundary.
@MainActor
public final class DocumentSession {
    public private(set) var project: ShowProject

    /// Unique ID of the current document content state.
    public private(set) var documentGeneration: UInt64 = 0
    /// State ID last successfully saved (or at open/new).
    public private(set) var savedGeneration: UInt64 = 0

    /// Dirty if state IDs differ **or** an open command group has mutated content (PRE-UI-5).
    public var isDirty: Bool {
        documentGeneration != savedGeneration || groupProvisionalStateID != nil
    }

    public let eventBus = EventBus()
    public let selection = SelectionManager()

    private let undoStack = UndoStack()
    /// State ID after each undo-stack entry was applied (parallel to undo stack).
    private var undoStateIDs: [UInt64] = []
    /// State ID after each redo-stack entry when re-applied (parallel to redo stack).
    private var redoStateIDs: [UInt64] = []
    /// Monotonic allocator; only increases when minting a brand-new content state.
    private var nextStateID: UInt64 = 0
    private var groupingName: String?
    private var groupBuffer: [any Command]?
    /// Provisional dirty flag while a command group is open (PRE-UI-5).
    private var groupProvisionalStateID: UInt64?

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

    /// Apply a package-derived show title without minting a new document generation (Save As basename).
    public func applyPackageDisplayName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        project.metadata.name = trimmed
    }

    /// Apply canonical package metadata after save so memory matches disk (P2-21).
    /// When `name` is provided (e.g. Save As basename), the in-memory title updates without minting a dirty state.
    public func applySavedMetadata(modifiedAt: Date, name: String? = nil) {
        if let name {
            applyPackageDisplayName(name)
        }
        project.metadata.modifiedAt = modifiedAt
        markSaved()
    }

    /// Reset session to a loaded/new project as clean.
    public func reset(to project: ShowProject) {
        self.project = project
        undoStack.clear()
        undoStateIDs.removeAll()
        redoStateIDs.removeAll()
        groupBuffer = nil
        groupingName = nil
        groupProvisionalStateID = nil
        documentGeneration = 0
        savedGeneration = 0
        nextStateID = 0
        selection.clear()
    }

    // MARK: - Selection

    public func selectFixtures(_ ids: Set<UUID>, extending: Bool = false) {
        selection.selectFixtures(ids, extending: extending)
        publishSelectionChanged()
    }

    /// Select fixtures preserving explicit order (chase/fan/wave phase order).
    public func selectFixturesOrdered(_ ids: [UUID], extending: Bool = false) {
        selection.selectFixturesOrdered(ids, extending: extending)
        publishSelectionChanged()
    }

    public func selectFixtureTargetsOrdered(_ targets: [FixtureTarget], extending: Bool = false) {
        selection.selectFixtureTargetsOrdered(targets, extending: extending)
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
            PrismLog.debug(.projectDocument, "project.command.rolled_back", "A command was rolled back.")
            throw error
        }

        project = context.project

        if var buffer = groupBuffer {
            if buffer.isEmpty {
                undoStack.clearRedo()
                redoStateIDs.removeAll()
                // First mutation inside a group: mint provisional dirty state immediately.
                let provisional = mintStateID()
                groupProvisionalStateID = provisional
                documentGeneration = provisional
            }
            buffer.append(command)
            groupBuffer = buffer
            didMutateProject()
            return
        }

        let newID = mintStateID()
        documentGeneration = newID

        // Never coalesce across a save-point: the stack top is exactly the saved state.
        let topIsSavedState = undoStateIDs.last == savedGeneration && !undoStateIDs.isEmpty
        if !topIsSavedState, let prior = undoStack.top, let merged = command.merging(withPrior: prior) {
            try undoStack.replaceTop(with: merged)
            redoStateIDs.removeAll()
            if !undoStateIDs.isEmpty {
                undoStateIDs[undoStateIDs.count - 1] = newID
            } else {
                undoStateIDs.append(newID)
            }
        } else {
            undoStack.push(command)
            redoStateIDs.removeAll()
            undoStateIDs.append(newID)
        }

        didMutateProject()
    }

    public func undo() throws {
        let command = try undoStack.popUndo()
        let undoneStateID = undoStateIDs.isEmpty ? documentGeneration : undoStateIDs.removeLast()
        let context = CommandContext(project: project)
        let snapshot = project

        do {
            try command.undo(context: context)
        } catch {
            project = snapshot
            undoStack.push(command)
            undoStateIDs.append(undoneStateID)
            PrismLog.debug(.projectDocument, "project.command.rolled_back", "Undo was rolled back.")
            throw error
        }

        project = context.project
        // Restore the state ID of the document after the previous entry (or baseline 0).
        documentGeneration = undoStateIDs.last ?? 0
        undoStack.pushRedo(command)
        redoStateIDs.append(undoneStateID)
        didMutateProject()
    }

    public func redo() throws {
        let command = try undoStack.popRedo()
        guard !redoStateIDs.isEmpty else {
            // Should not happen if stacks stay aligned; fall back to minting.
            undoStack.pushRedo(command)
            throw CommandError.nothingToRedo
        }
        let restoredID = redoStateIDs.removeLast()
        let context = CommandContext(project: project)
        let snapshot = project

        do {
            try command.perform(context: context)
        } catch {
            project = snapshot
            undoStack.pushRedo(command)
            redoStateIDs.append(restoredID)
            PrismLog.debug(.projectDocument, "project.command.rolled_back", "Redo was rolled back.")
            throw error
        }

        project = context.project
        // Restore the original state ID so returning to a saved checkpoint stays clean.
        documentGeneration = restoredID
        undoStack.pushUndoPreservingRedo(command)
        undoStateIDs.append(restoredID)
        didMutateProject()
    }

    public func beginGroup(named name: String) throws {
        guard groupBuffer == nil else { throw CommandError.alreadyGrouping }
        groupingName = name
        groupBuffer = []
        groupProvisionalStateID = nil
    }

    public func endGroup() throws {
        guard let buffer = groupBuffer, let name = groupingName else {
            throw CommandError.notGrouping
        }
        groupBuffer = nil
        groupingName = nil
        groupProvisionalStateID = nil

        guard !buffer.isEmpty else {
            throw CommandError.emptyGroup
        }

        // Reuse provisional ID if already minted on first group mutation; else mint now.
        let newID: UInt64
        if documentGeneration != savedGeneration, undoStateIDs.last != documentGeneration {
            // Provisional ID already set on first mutation — keep it as the committed ID.
            newID = documentGeneration
        } else {
            newID = mintStateID()
            documentGeneration = newID
        }
        let group = CommandGroup(name: name, commands: buffer)
        undoStack.push(group)
        redoStateIDs.removeAll()
        undoStateIDs.append(newID)
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
            // Restore generation to pre-group state (last undo ID or baseline).
            documentGeneration = undoStateIDs.last ?? 0
            groupProvisionalStateID = nil
            didMutateProject()
        }
        groupBuffer = nil
        groupingName = nil
        groupProvisionalStateID = nil
    }

    public func didMutateProject() {
        eventBus.publish(.projectModified)
        if selection.prune(against: project) {
            publishSelectionChanged()
        }
    }

    private func mintStateID() -> UInt64 {
        nextStateID &+= 1
        return nextStateID
    }

    private func publishSelectionChanged() {
        eventBus.publish(.selectionChanged(selection.snapshot))
    }
}
