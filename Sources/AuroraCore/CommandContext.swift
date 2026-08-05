import AuroraModel
import Foundation

/// Mutable view of session state available to commands during perform/undo.
@MainActor
public final class CommandContext {
    public private(set) var project: ShowProject

    public init(project: ShowProject) {
        self.project = project
    }

    public func replaceProject(_ project: ShowProject) {
        self.project = project
    }

    public func updateProject(_ body: (inout ShowProject) -> Void) {
        body(&project)
    }
}
