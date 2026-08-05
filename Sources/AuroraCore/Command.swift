import Foundation

/// A reversible user mutation. All show edits go through commands.
///
/// Commands are reference types so they can capture inverse state during `perform`
/// (e.g. a removed fixture) for later `undo`.
@MainActor
public protocol Command: AnyObject {
    /// Human-readable action name (menus, undo labels).
    var name: String { get }

    func perform(context: CommandContext) throws
    func undo(context: CommandContext) throws

    /// If non-`nil`, replace the prior undo entry instead of pushing a new one.
    func merging(withPrior prior: any Command) -> (any Command)?
}

public extension Command {
    func merging(withPrior prior: any Command) -> (any Command)? {
        nil
    }
}
