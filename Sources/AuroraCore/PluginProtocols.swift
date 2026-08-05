import Foundation

/// Stable internal plugin surfaces before dynamic dylib loading (P3-4).
/// Implementations register in-process via `PluginHost` until the SDK freezes.

// MARK: - Action / control

/// Provides show-control actions (maps to `ShowAction` storage keys in the app).
public protocol PluginActionProvider: AnyObject {
    var actionStorageKeys: [String] { get }
}

// MARK: - Data source

/// External data feed (timecode, sensor, score, etc.).
public protocol PluginDataSource: AnyObject {
    var dataSourceID: String { get }
    func start() throws
    func stop()
}

// MARK: - Effect generator

/// Additional effect kinds beyond built-in pulse/chase/wave/rainbow.
public protocol PluginEffectGenerator: AnyObject {
    var effectKindID: String { get }
    var displayName: String { get }
}

// MARK: - Fixture importer

public protocol PluginFixtureImporter: AnyObject {
    var supportedExtensions: [String] { get }
}

// MARK: - Settings descriptor

public struct PluginSettingDescriptor: Equatable, Sendable {
    public var key: String
    public var title: String
    public var valueType: String

    public init(key: String, title: String, valueType: String = "string") {
        self.key = key
        self.title = title
        self.valueType = valueType
    }
}

public protocol PluginSettingsProviding: AnyObject {
    var settingDescriptors: [PluginSettingDescriptor] { get }
}

// MARK: - Diagnostics

public protocol PluginDiagnosticsSink: AnyObject {
    func pluginLog(code: String?, message: String)
}
