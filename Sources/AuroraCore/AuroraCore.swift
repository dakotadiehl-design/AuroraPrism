import AuroraModel

/// Application core: project management, commands, undo, selection, preferences, events.
///
/// Implementations land in PR3–PR4. PR1 only exposes module identity and a Model dependency touchpoint.
public enum AuroraCoreModule {
    public static let name = "AuroraCore"
    public static let version = "0.1.0-pr1"

    /// Confirms the Core → Model dependency is linked (used by tests).
    public static var modelModuleName: String {
        AuroraModelModule.name
    }
}
