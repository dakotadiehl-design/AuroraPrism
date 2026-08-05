import Foundation

/// Composite command: one undo step for multiple inner commands (transaction group).
@MainActor
public final class CommandGroup: Command {
    public let name: String
    private let commands: [any Command]

    public init(name: String, commands: [any Command]) {
        self.name = name
        self.commands = commands
    }

    public func perform(context: CommandContext) throws {
        for command in commands {
            try command.perform(context: context)
        }
    }

    public func undo(context: CommandContext) throws {
        for command in commands.reversed() {
            try command.undo(context: context)
        }
    }
}
