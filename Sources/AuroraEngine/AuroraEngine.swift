import AuroraModel
import AuroraOutput

/// Lighting engine: cue, effect, playback, programmer, and scheduler.
///
/// PR10 provides scheduler, merge stub, snapshots, and output flush.
/// Cue timing (PR11) and programmer (PR13) build on this skeleton.
public enum AuroraEngineModule {
    public static let name = "AuroraEngine"
    public static let version = "0.10.0-pr10"

    public static var modelModuleName: String { AuroraModelModule.name }
    public static var outputModuleName: String { AuroraOutputModule.name }
}
