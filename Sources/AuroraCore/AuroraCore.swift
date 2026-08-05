import AuroraModel

/// Application core: project session, commands, undo, selection, events.
///
/// PR3 adds command/undo; PR4 adds event bus and selection.
public enum AuroraCoreModule {
    public static let name = "AuroraCore"
    public static let version = "0.3.0-pr3"

    /// Confirms the Core → Model dependency is linked (used by tests).
    public static var modelModuleName: String {
        AuroraModelModule.name
    }
}
