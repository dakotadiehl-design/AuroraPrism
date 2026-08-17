import AuroraModel
import Foundation

/// Reorders a cue within its list (playback order = array order).
@MainActor
public final class ReorderCueCommand: Command {
    public let name: String
    private let listID: UUID
    private let cueID: UUID
    private let toIndex: Int
    private var fromIndex: Int?

    public init(listID: UUID, cueID: UUID, toIndex: Int, name: String = "Reorder Cue") {
        self.listID = listID
        self.cueID = cueID
        self.toIndex = toIndex
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        guard let listIndex = context.project.cueLists.firstIndex(where: { $0.id == listID }) else {
            throw CommandError.message("Cue list not found")
        }
        let cues = context.project.cueLists[listIndex].cues
        guard let from = cues.firstIndex(where: { $0.id == cueID }) else {
            throw CommandError.message("Cue not found")
        }
        fromIndex = from
        // `toIndex` is the desired final index in the list after the move.
        let dest = min(max(0, toIndex), cues.count - 1)
        guard dest != from else { return }
        context.updateProject { project in
            var list = project.cueLists[listIndex]
            let cue = list.cues.remove(at: from)
            list.cues.insert(cue, at: dest)
            project.cueLists[listIndex] = list
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard let fromIndex,
              let listIndex = context.project.cueLists.firstIndex(where: { $0.id == listID }),
              let current = context.project.cueLists[listIndex].cues.firstIndex(where: { $0.id == cueID })
        else { return }
        context.updateProject { project in
            var list = project.cueLists[listIndex]
            let cue = list.cues.remove(at: current)
            let insertAt = min(fromIndex, list.cues.count)
            list.cues.insert(cue, at: insertAt)
            project.cueLists[listIndex] = list
            project.metadata.modifiedAt = Date()
        }
    }
}

/// Duplicates a cue immediately after the source (new identity, same levels/timing).
/// Cue Block references keep the same `cueBlockID` and order but receive new reference UUIDs.
/// New cue id and reference ids are fixed on first perform so undo/redo preserves identity.
@MainActor
public final class DuplicateCueCommand: Command {
    public let name: String
    private let listID: UUID
    private let sourceCueID: UUID
    private var createdID: UUID?
    private var remappedRefs: [CueBlockReference]?
    private var createdName: String?
    private var createdNumber: Decimal?
    private var insertIndex: Int?

    public init(listID: UUID, sourceCueID: UUID, name: String = "Duplicate Cue") {
        self.listID = listID
        self.sourceCueID = sourceCueID
        self.name = name
    }

    public var duplicatedCueID: UUID? { createdID }

    public func perform(context: CommandContext) throws {
        guard let listIndex = context.project.cueLists.firstIndex(where: { $0.id == listID }) else {
            throw CommandError.message("Cue list not found")
        }
        let cues = context.project.cueLists[listIndex].cues
        guard let sourceIndex = cues.firstIndex(where: { $0.id == sourceCueID }) else {
            throw CommandError.message("Cue not found")
        }
        let source = cues[sourceIndex]

        if createdID == nil {
            createdID = UUID()
            createdName = source.name.isEmpty ? "Copy" : "\(source.name) Copy"
            createdNumber = source.number + Decimal(string: "0.1")!
            remappedRefs = source.cueBlockRefs.map { ref in
                CueBlockReference(id: UUID(), cueBlockID: ref.cueBlockID, enabled: ref.enabled)
            }
            insertIndex = sourceIndex + 1
        }

        guard let createdID, let createdName, let createdNumber, let remappedRefs, let insertIndex else {
            throw CommandError.message("Duplicate Cue internal state missing")
        }

        var copy = source
        copy.id = createdID
        copy.name = createdName
        copy.number = createdNumber
        copy.cueBlockRefs = remappedRefs

        context.updateProject { project in
            let idx = min(insertIndex, project.cueLists[listIndex].cues.count)
            project.cueLists[listIndex].cues.insert(copy, at: idx)
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard let createdID,
              let listIndex = context.project.cueLists.firstIndex(where: { $0.id == listID })
        else { return }
        context.updateProject { project in
            project.cueLists[listIndex].cues.removeAll { $0.id == createdID }
            project.metadata.modifiedAt = Date()
        }
    }
}
