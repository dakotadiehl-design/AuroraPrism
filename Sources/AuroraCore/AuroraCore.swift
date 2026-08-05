import AuroraModel

/// Application core: project session, commands, undo, selection, events.
public enum AuroraCoreModule {
    public static let name = "AuroraCore"
    public static let version = "0.4.0-pr4"

    /// Confirms the Core → Model dependency is linked (used by tests).
    public static var modelModuleName: String {
        AuroraModelModule.name
    }
}
