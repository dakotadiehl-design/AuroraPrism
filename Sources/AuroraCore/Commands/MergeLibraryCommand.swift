import AuroraModel
import Foundation

/// Merges a portable Aurora Library into the current show.
@MainActor
public final class MergeLibraryCommand: Command {
    public let name: String
    private let contents: AuroraLibraryPackage.Contents
    private let replaceExisting: Bool
    private var previous: ShowProject?

    public init(
        contents: AuroraLibraryPackage.Contents,
        replaceExisting: Bool = false,
        name: String = "Import Library"
    ) {
        self.contents = contents
        self.replaceExisting = replaceExisting
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        previous = context.project
        context.updateProject { project in
            AuroraLibraryPackage.merge(contents, into: &project, replaceExisting: replaceExisting)
        }
    }

    public func undo(context: CommandContext) throws {
        guard let previous else { return }
        context.updateProject { project in
            project = previous
        }
    }
}
