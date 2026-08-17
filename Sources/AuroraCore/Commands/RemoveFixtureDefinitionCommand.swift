import AuroraModel
import Foundation

/// Removes an unused project-embedded fixture personality. Library/built-in protection
/// is a UI concern because AuroraCore does not know which catalog supplied a definition.
@MainActor
public final class RemoveFixtureDefinitionCommand: Command {
    public let name = "Remove Fixture Library Mode"
    private let definitionID: UUID
    private var removed: FixtureDefinition?
    private var removedIndex: Int?

    public init(definitionID: UUID) {
        self.definitionID = definitionID
    }

    public func perform(context: CommandContext) throws {
        guard !context.project.fixtures.contains(where: { $0.definitionId == definitionID }) else {
            throw CommandError.message("This fixture mode is currently used by fixtures in the show")
        }
        guard let index = context.project.fixtureDefinitions.firstIndex(where: { $0.id == definitionID }) else {
            throw CommandError.message("Fixture mode not found")
        }
        removed = context.project.fixtureDefinitions[index]
        removedIndex = index
        context.updateProject {
            $0.fixtureDefinitions.remove(at: index)
            $0.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard let removed, let removedIndex else { return }
        context.updateProject {
            $0.fixtureDefinitions.insert(removed, at: min(removedIndex, $0.fixtureDefinitions.count))
            $0.metadata.modifiedAt = Date()
        }
    }
}
