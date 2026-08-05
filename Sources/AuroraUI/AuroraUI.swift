import AuroraCore
import AuroraEngine
import AuroraModel

/// UI panels, workspace layout, and views (SwiftUI + AppKit bridges later).
///
/// Docking and panels arrive in PR7+. PR1 provides scaffold helpers for the app shell.
public enum AuroraUIModule {
    public static let name = "AuroraUI"
    public static let version = "0.1.0-pr1"
}

/// One row in the PR1 scaffold module list.
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

/// Modules the scaffold window should list (linked libraries + UI itself).
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
