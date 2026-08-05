import AuroraModel

/// Fixture definition library: manufacturers, personalities, channel layouts.
///
/// Seed format arrives in PR5. PR1 only exposes module identity.
public enum AuroraFixtureLibModule {
    public static let name = "AuroraFixtureLib"
    public static let version = "0.1.0-pr1"

    public static var modelModuleName: String { AuroraModelModule.name }
}
