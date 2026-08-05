import AuroraModel
import AuroraOutput

/// Lighting engine: cue, effect, playback, programmer, and scheduler.
///
/// Real-time logic arrives in later PRs. PR1 only exposes module identity.
public enum AuroraEngineModule {
    public static let name = "AuroraEngine"
    public static let version = "0.1.0-pr1"

    /// Touchpoints so Model/Output stay in the link graph.
    public static var modelModuleName: String { AuroraModelModule.name }
    public static var outputModuleName: String { AuroraOutputModule.name }
}
