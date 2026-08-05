import AuroraModel
import Foundation

@MainActor
public final class AddUniverseCommand: Command {
    public let name: String
    private let universe: Universe

    public init(universe: Universe, name: String = "Add Universe") {
        self.universe = universe
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        if context.project.universes.contains(where: { $0.id == universe.id }) {
            throw CommandError.message("Universe already exists: \(universe.id)")
        }
        context.updateProject { project in
            project.universes.append(universe)
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        context.updateProject { project in
            project.universes.removeAll { $0.id == universe.id }
            project.metadata.modifiedAt = Date()
        }
    }
}
