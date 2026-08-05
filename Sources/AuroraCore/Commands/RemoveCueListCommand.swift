import AuroraModel
import Foundation

@MainActor
public final class RemoveCueListCommand: Command {
    public let name: String
    private let listID: UUID
    private var removed: CueList?
    private var removedIndex: Int?

    public init(listID: UUID, name: String = "Remove Cue List") {
        self.listID = listID
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        guard let index = context.project.cueLists.firstIndex(where: { $0.id == listID }) else {
            throw CommandError.message("Cue list not found")
        }
        removed = context.project.cueLists[index]
        removedIndex = index
        context.updateProject { project in
            project.cueLists.remove(at: index)
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard let removed, let removedIndex else { return }
        context.updateProject { project in
            let idx = min(removedIndex, project.cueLists.count)
            project.cueLists.insert(removed, at: idx)
            project.metadata.modifiedAt = Date()
        }
    }
}
