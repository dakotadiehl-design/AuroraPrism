/// Pure data types for shows, fixtures, cues, and related entities.
///
/// Domain model and package document format arrive in PR2.
/// No I/O side effects live outside `ProjectPackage`.
public enum AuroraModelModule {
    public static let name = "AuroraModel"
    public static let version = "0.2.0-pr2"

    /// Current on-disk schema version written by `ProjectPackage`.
    public static let schemaVersion = ProjectPackage.currentSchemaVersion
}
