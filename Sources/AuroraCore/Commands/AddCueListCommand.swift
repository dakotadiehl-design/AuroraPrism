import AuroraModel
import Foundation

@MainActor
public final class AddCueListCommand: Command {
    public let name: String
    private let list: CueList

    public init(list: CueList, name: String = "Add Cue List") {
        self.list = list
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        context.updateProject { project in
            project.cueLists.append(list)
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        context.updateProject { project in
            project.cueLists.removeAll { $0.id == list.id }
            project.metadata.modifiedAt = Date()
        }
    }
}
