import AuroraModel
import Foundation

@MainActor
public final class AddCueCommand: Command {
    public let name: String
    private let listID: UUID
    private let cue: Cue

    public init(listID: UUID, cue: Cue, name: String = "Add Cue") {
        self.listID = listID
        self.cue = cue
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        guard let index = context.project.cueLists.firstIndex(where: { $0.id == listID }) else {
            throw CommandError.message("Cue list not found")
        }
        context.updateProject { project in
            project.cueLists[index].cues.append(cue)
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard let index = context.project.cueLists.firstIndex(where: { $0.id == listID }) else { return }
        context.updateProject { project in
            project.cueLists[index].cues.removeAll { $0.id == cue.id }
            project.metadata.modifiedAt = Date()
        }
    }
}
