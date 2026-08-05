import AuroraModel

/// Application core: project session, commands, undo, selection, events.
public enum AuroraCoreModule {
    public static let name = "AuroraCore"
    public static let version = "0.12.0-pr12"

    /// Confirms the Core → Model dependency is linked (used by tests).
    public static var modelModuleName: String {
        AuroraModelModule.name
    }
}
