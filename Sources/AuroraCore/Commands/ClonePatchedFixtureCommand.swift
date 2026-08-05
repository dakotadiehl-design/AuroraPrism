import AuroraModel
import Foundation

@MainActor
public final class ClonePatchedFixtureCommand: Command {
    public let name: String
    private let sourceFixtureID: UUID
    private let targetUniverseID: UUID?
    private var created: PatchedFixture?

    public init(
        sourceFixtureID: UUID,
        targetUniverseID: UUID? = nil,
        name: String = "Clone Fixture"
    ) {
        self.sourceFixtureID = sourceFixtureID
        self.targetUniverseID = targetUniverseID
        self.name = name
    }

    public var createdFixtureID: UUID? { created?.id }

    public func perform(context: CommandContext) throws {
        guard let source = context.project.fixtures.first(where: { $0.id == sourceFixtureID }) else {
            throw CommandError.fixtureNotFound(sourceFixtureID)
        }
        let universeID = targetUniverseID ?? source.universeId
        let channelCount = context.project.channelCount(for: source)
        guard let address = context.project.nextFreeAddress(in: universeID, channelCount: channelCount) else {
            throw CommandError.noFreeAddress(universeID: universeID, channelCount: channelCount)
        }

        let clone = PatchedFixture(
            id: UUID(),
            name: source.name.hasSuffix(" copy") ? source.name : "\(source.name) copy",
            definitionId: source.definitionId,
            universeId: universeID,
            address: address,
            groupIds: source.groupIds,
            notes: source.notes
        )
        try PatchValidator.validatePlacement(fixture: clone, in: context.project)

        context.updateProject { project in
            project.fixtures.append(clone)
            project.metadata.modifiedAt = Date()
        }
        created = clone
    }

    public func undo(context: CommandContext) throws {
        guard let created else { return }
        context.updateProject { project in
            project.fixtures.removeAll { $0.id == created.id }
            project.metadata.modifiedAt = Date()
        }
    }
}
