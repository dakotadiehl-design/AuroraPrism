import AuroraModel
import AuroraOutput

/// Lighting engine: cue, effect, playback, programmer, and scheduler.
///
/// PR10: scheduler + merge stub. PR11: cue timing/tracking playback.
/// PR13: programmer layer.
public enum AuroraEngineModule {
    public static let name = "AuroraEngine"
    public static let version = "0.11.0-pr11"

    public static var modelModuleName: String { AuroraModelModule.name }
    public static var outputModuleName: String { AuroraOutputModule.name }
}
