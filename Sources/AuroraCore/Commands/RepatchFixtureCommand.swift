import AuroraModel
import Foundation

@MainActor
public final class RepatchFixtureCommand: Command {
    public let name: String
    private let fixtureID: UUID
    private let newUniverseID: UUID
    private let newAddress: UInt16
    private var previousUniverseID: UUID?
    private var previousAddress: UInt16?

    public init(
        fixtureID: UUID,
        universeID: UUID,
        address: UInt16,
        name: String = "Repatch Fixture"
    ) {
        self.fixtureID = fixtureID
        self.newUniverseID = universeID
        self.newAddress = address
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        guard let index = context.project.fixtures.firstIndex(where: { $0.id == fixtureID }) else {
            throw CommandError.fixtureNotFound(fixtureID)
        }
        var updated = context.project.fixtures[index]
        previousUniverseID = updated.universeId
        previousAddress = updated.address
        updated.universeId = newUniverseID
        updated.address = newAddress

        try PatchValidator.validatePlacement(
            fixture: updated,
            in: context.project,
            ignoringFixtureID: fixtureID
        )

        context.updateProject { project in
            project.fixtures[index] = updated
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard let previousUniverseID, let previousAddress,
              let index = context.project.fixtures.firstIndex(where: { $0.id == fixtureID })
        else { return }
        context.updateProject { project in
            project.fixtures[index].universeId = previousUniverseID
            project.fixtures[index].address = previousAddress
            project.metadata.modifiedAt = Date()
        }
    }
}
