import AuroraCore
import AuroraEngine
import AuroraModel

/// UI panels, workspace layout, and views (SwiftUI + AppKit bridges as needed).
public enum AuroraUIModule {
    public static let name = "AuroraUI"
    public static let version = "0.7.0-pr7"
}

/// One row in the scaffold module list (kept for smoke tests).
public struct ScaffoldModuleInfo: Equatable, Sendable {
    public let name: String
    public let version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }

    public var displayLine: String {
        "\(name) \(version)"
    }
}

public enum ScaffoldModuleCatalog {
    public static var modules: [ScaffoldModuleInfo] {
        [
            ScaffoldModuleInfo(name: AuroraModelModule.name, version: AuroraModelModule.version),
            ScaffoldModuleInfo(name: AuroraCoreModule.name, version: AuroraCoreModule.version),
            ScaffoldModuleInfo(name: AuroraEngineModule.name, version: AuroraEngineModule.version),
            ScaffoldModuleInfo(name: AuroraUIModule.name, version: AuroraUIModule.version),
        ]
    }
}
