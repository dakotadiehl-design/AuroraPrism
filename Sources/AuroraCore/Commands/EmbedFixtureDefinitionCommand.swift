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

    private var previous: FixtureDefinition?
    private var didReplace = false

    public func perform(context: CommandContext) throws {
        if let existing = context.project.definition(id: definition.id) {
            previous = existing
            didReplace = true
            didEmbed = false
            context.updateProject { project in
                if let idx = project.fixtureDefinitions.firstIndex(where: { $0.id == definition.id }) {
                    project.fixtureDefinitions[idx] = definition
                }
                project.metadata.modifiedAt = Date()
            }
            return
        }
        context.updateProject { project in
            project.fixtureDefinitions.append(definition)
            project.metadata.modifiedAt = Date()
        }
        didEmbed = true
        didReplace = false
        previous = nil
    }

    public func undo(context: CommandContext) throws {
        if didEmbed {
            context.updateProject { project in
                project.fixtureDefinitions.removeAll { $0.id == definition.id }
                project.metadata.modifiedAt = Date()
            }
            return
        }
        if didReplace, let previous {
            context.updateProject { project in
                if let idx = project.fixtureDefinitions.firstIndex(where: { $0.id == definition.id }) {
                    project.fixtureDefinitions[idx] = previous
                }
                project.metadata.modifiedAt = Date()
            }
        }
    }
}
