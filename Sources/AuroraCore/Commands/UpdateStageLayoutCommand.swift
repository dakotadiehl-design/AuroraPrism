import AuroraModel
import Foundation

/// Replace stage layout (visual only — does not alter patch).
@MainActor
public final class UpdateStageLayoutCommand: Command {
    public let name = "Update Stage Layout"
    private let layout: StageLayout
    private var previous: StageLayout?

    public init(layout: StageLayout) {
        self.layout = layout
    }

    public func perform(context: CommandContext) throws {
        previous = context.project.stageLayout
        context.updateProject { project in
            project.stageLayout = self.layout
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard let previous else { return }
        context.updateProject { project in
            project.stageLayout = previous
            project.metadata.modifiedAt = Date()
        }
    }
}
