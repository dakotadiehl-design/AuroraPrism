import AuroraModel
import Foundation

/// Replaces the project's durable effect list (P1-4). Undo restores prior list.
@MainActor
public final class SetEffectsCommand: Command {
    public let name: String = "Update Effects"
    private let effects: [EffectDefinition]
    private var previous: [EffectDefinition]?

    public init(effects: [EffectDefinition]) {
        self.effects = effects
    }

    public func perform(context: CommandContext) throws {
        if previous == nil {
            previous = context.project.effects
        }
        context.updateProject { project in
            project.effects = effects
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard let previous else { return }
        context.updateProject { project in
            project.effects = previous
            project.metadata.modifiedAt = Date()
        }
    }
}
