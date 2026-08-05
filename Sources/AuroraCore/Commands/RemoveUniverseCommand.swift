import AuroraModel
import Foundation

@MainActor
public final class RemoveUniverseCommand: Command {
    public let name: String
    private let universeID: UUID
    private var removed: Universe?

    public init(universeID: UUID, name: String = "Remove Universe") {
        self.universeID = universeID
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        guard let universe = context.project.universe(id: universeID) else {
            throw CommandError.universeNotFound(universeID)
        }
        if context.project.fixtures.contains(where: { $0.universeId == universeID }) {
            throw CommandError.universeHasFixtures(universeID)
        }
        removed = universe
        context.updateProject { project in
            project.universes.removeAll { $0.id == universeID }
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard let universe = removed else { return }
        context.updateProject { project in
            project.universes.append(universe)
            project.metadata.modifiedAt = Date()
        }
    }
}
