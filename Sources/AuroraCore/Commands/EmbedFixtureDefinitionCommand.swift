import AuroraModel
import Foundation

/// Embeds a fixture definition into the project if not already present (no-op if same id exists).
@MainActor
public final class EmbedFixtureDefinitionCommand: Command {
    public let name: String
    private let definition: FixtureDefinition
    private var didEmbed = false

    public init(definition: FixtureDefinition, name: String = "Embed Fixture Definition") {
        self.definition = definition
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        if context.project.definition(id: definition.id) != nil {
            didEmbed = false
            return
        }
        context.updateProject { project in
            project.fixtureDefinitions.append(definition)
            project.metadata.modifiedAt = Date()
        }
        didEmbed = true
    }

    public func undo(context: CommandContext) throws {
        guard didEmbed else { return }
        context.updateProject { project in
            project.fixtureDefinitions.removeAll { $0.id == definition.id }
            project.metadata.modifiedAt = Date()
        }
    }
}
