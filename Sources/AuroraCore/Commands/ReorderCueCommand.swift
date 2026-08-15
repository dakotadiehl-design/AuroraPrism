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
@MainActor
public final class DuplicateCueCommand: Command {
    public let name: String
    private let listID: UUID
    private let sourceCueID: UUID
    private var createdID: UUID?

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
        var copy = source
        copy.id = UUID()
        copy.name = source.name.isEmpty ? "Copy" : "\(source.name) Copy"
        // Bump display number slightly for readability.
        copy.number = source.number + Decimal(string: "0.1")!
        createdID = copy.id
        context.updateProject { project in
            project.cueLists[listIndex].cues.insert(copy, at: sourceIndex + 1)
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
