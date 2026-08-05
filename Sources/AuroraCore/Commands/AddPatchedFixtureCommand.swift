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
        try PatchValidator.validatePlacement(fixture: fixture, in: context.project)

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
