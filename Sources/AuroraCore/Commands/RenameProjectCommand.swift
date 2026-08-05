import Foundation

/// Renames the show (`metadata.name`). Coalesces consecutive renames into one undo step.
@MainActor
public final class RenameProjectCommand: Command {
    public let name: String = "Rename Project"
    private let newName: String
    private var previousName: String?

    public init(newName: String) {
        self.newName = newName
    }

    public func perform(context: CommandContext) throws {
        if previousName == nil {
            previousName = context.project.metadata.name
        }
        context.updateProject { project in
            project.metadata.name = newName
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard let previousName else { return }
        context.updateProject { project in
            project.metadata.name = previousName
            project.metadata.modifiedAt = Date()
        }
    }

    public func merging(withPrior prior: any Command) -> (any Command)? {
        guard let priorRename = prior as? RenameProjectCommand else { return nil }
        // Keep the earliest previousName; apply latest newName.
        let merged = RenameProjectCommand(newName: newName)
        merged.previousName = priorRename.previousName ?? previousName
        return merged
    }
}
