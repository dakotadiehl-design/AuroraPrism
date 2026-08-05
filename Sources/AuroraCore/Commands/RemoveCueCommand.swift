import AuroraModel
import Foundation

@MainActor
public final class RemoveCueCommand: Command {
    public let name: String
    private let listID: UUID
    private let cueID: UUID
    private var removed: Cue?
    private var removedIndex: Int?

    public init(listID: UUID, cueID: UUID, name: String = "Remove Cue") {
        self.listID = listID
        self.cueID = cueID
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        guard let li = context.project.cueLists.firstIndex(where: { $0.id == listID }) else {
            throw CommandError.message("Cue list not found")
        }
        guard let ci = context.project.cueLists[li].cues.firstIndex(where: { $0.id == cueID }) else {
            throw CommandError.message("Cue not found")
        }
        removed = context.project.cueLists[li].cues[ci]
        removedIndex = ci
        context.updateProject { project in
            project.cueLists[li].cues.remove(at: ci)
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard let removed, let removedIndex,
              let li = context.project.cueLists.firstIndex(where: { $0.id == listID })
        else { return }
        context.updateProject { project in
            let idx = min(removedIndex, project.cueLists[li].cues.count)
            project.cueLists[li].cues.insert(removed, at: idx)
            project.metadata.modifiedAt = Date()
        }
    }
}
