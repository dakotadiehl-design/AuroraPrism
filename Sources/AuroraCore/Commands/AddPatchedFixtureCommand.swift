import AuroraModel
import Foundation

/// Adds a patched fixture to the project.
@MainActor
public final class AddPatchedFixtureCommand: Command {
    public let name: String
    private let fixture: PatchedFixture
    private var didPerform = false

    public init(fixture: PatchedFixture, name: String = "Add Fixture") {
        self.fixture = fixture
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        guard context.project.universes.contains(where: { $0.id == fixture.universeId }) else {
            throw CommandError.universeNotFound(fixture.universeId)
        }
        if !context.project.fixtureDefinitions.isEmpty {
            guard context.project.fixtureDefinitions.contains(where: { $0.id == fixture.definitionId }) else {
                throw CommandError.definitionNotFound(fixture.definitionId)
            }
        }
        if fixture.address == 0 {
            throw CommandError.invalidAddress(fixture.address)
        }

        // Build a temporary project view to reuse overlap detection.
        var trial = context.project
        trial.fixtures.append(fixture)
        let overlaps = trial.overlappingPatchRanges()
        if let hit = overlaps.first(where: { $0.first == fixture.id || $0.second == fixture.id }) {
            let other = hit.first == fixture.id ? hit.second : hit.first
            throw CommandError.patchOverlap(fixtureID: fixture.id, otherFixtureID: other)
        }

        context.updateProject { project in
            project.fixtures.append(fixture)
            project.metadata.modifiedAt = Date()
        }
        didPerform = true
    }

    public func undo(context: CommandContext) throws {
        guard didPerform else { return }
        context.updateProject { project in
            project.fixtures.removeAll { $0.id == fixture.id }
            project.metadata.modifiedAt = Date()
        }
    }
}
