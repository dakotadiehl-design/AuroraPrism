import AuroraModel
import Foundation

/// Embeds a definition if needed and patches a fixture in one undoable command.
@MainActor
public final class PatchFixtureCommand: Command {
    public let name: String
    private let definition: FixtureDefinition
    private let fixture: PatchedFixture
    private var didEmbedDefinition = false
    private var didAddFixture = false

    public init(
        definition: FixtureDefinition,
        fixture: PatchedFixture,
        name: String = "Patch Fixture"
    ) {
        self.definition = definition
        self.fixture = fixture
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        precondition(fixture.definitionId == definition.id, "fixture.definitionId must match definition.id")
        try FixtureNameValidator.validate(fixture.name, in: context.project)

        if context.project.definition(id: definition.id) == nil {
            context.updateProject { project in
                project.fixtureDefinitions.append(definition)
            }
            didEmbedDefinition = true
        }

        // Re-read project after possible embed for validation.
        var trial = context.project
        if didEmbedDefinition, trial.definition(id: definition.id) == nil {
            trial.fixtureDefinitions.append(definition)
        }
        try PatchValidator.validatePlacement(fixture: fixture, in: trial)

        context.updateProject { project in
            project.fixtures.append(fixture)
            project.metadata.modifiedAt = Date()
        }
        didAddFixture = true
    }

    public func undo(context: CommandContext) throws {
        if didAddFixture {
            context.updateProject { project in
                project.fixtures.removeAll { $0.id == fixture.id }
            }
        }
        if didEmbedDefinition {
            context.updateProject { project in
                project.fixtureDefinitions.removeAll { $0.id == definition.id }
            }
        }
        if didAddFixture || didEmbedDefinition {
            context.updateProject { project in
                project.metadata.modifiedAt = Date()
            }
        }
    }
}
