import AuroraModel
import Foundation

@MainActor
public final class UpdateCueCommand: Command {
    public let name: String
    private let listID: UUID
    private let cue: Cue
    private var previous: Cue?

    public init(listID: UUID, cue: Cue, name: String = "Update Cue") {
        self.listID = listID
        self.cue = cue
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        guard let li = context.project.cueLists.firstIndex(where: { $0.id == listID }) else {
            throw CommandError.message("Cue list not found")
        }
        guard let ci = context.project.cueLists[li].cues.firstIndex(where: { $0.id == cue.id }) else {
            throw CommandError.message("Cue not found")
        }
        previous = context.project.cueLists[li].cues[ci]
        context.updateProject { project in
            project.cueLists[li].cues[ci] = cue
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard let previous,
              let li = context.project.cueLists.firstIndex(where: { $0.id == listID }),
              let ci = context.project.cueLists[li].cues.firstIndex(where: { $0.id == previous.id })
        else { return }
        context.updateProject { project in
            project.cueLists[li].cues[ci] = previous
            project.metadata.modifiedAt = Date()
        }
    }
}
