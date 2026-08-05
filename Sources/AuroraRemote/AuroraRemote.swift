import AuroraCore
import AuroraModel

/// Stage remote companion protocol host library (PR31).
public enum AuroraRemoteModule {
    public static let name = "AuroraRemote"
    public static let version = "0.31.0-pr31"
    public static let protocolVersion = 1

    public static var coreModuleName: String { AuroraCoreModule.name }
    public static var modelModuleName: String { AuroraModelModule.name }
}
