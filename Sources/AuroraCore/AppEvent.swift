import Foundation

/// Typed application events. Only cases that have real publishers today are included.
public enum AppEvent: Equatable, Sendable {
    /// Show document data changed (command perform / undo / redo).
    case projectModified
    /// Selection snapshot changed.
    case selectionChanged(SelectionSnapshot)
}
