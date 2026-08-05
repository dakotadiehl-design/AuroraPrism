import Foundation

/// Declared capability of a plugin (PR29).
public enum PluginCapability: String, Codable, Sendable, Hashable, CaseIterable {
    case outputDriver
    case effectGenerator
    case fixtureImporter
    case controlInput
    case diagnostics
}

/// Static identity for a plugin package.
public struct PluginManifest: Equatable, Sendable, Hashable, Codable {
    public var id: String
    public var name: String
    public var version: String
    public var capabilities: Set<PluginCapability>

    public init(
        id: String,
        name: String,
        version: String,
        capabilities: Set<PluginCapability> = []
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.capabilities = capabilities
    }
}

/// In-process plugin entry point. Hosts may query capabilities; implementations stay optional.
public protocol AuroraPlugin: AnyObject {
    var manifest: PluginManifest { get }
    /// Called once after successful registration.
    func pluginDidLoad(host: PluginHost)
    func pluginWillUnload()
}

public extension AuroraPlugin {
    func pluginDidLoad(host: PluginHost) {}
    func pluginWillUnload() {}
}

/// Registry for in-process plugins (no dynamic library loading in v1).
public final class PluginHost: @unchecked Sendable {
    private let lock = NSLock()
    private var plugins: [String: AuroraPlugin] = [:]

    public init() {}

    public var manifests: [PluginManifest] {
        lock.lock()
        defer { lock.unlock() }
        return plugins.values.map(\.manifest).sorted { $0.id < $1.id }
    }

    public func plugin(id: String) -> AuroraPlugin? {
        lock.lock()
        defer { lock.unlock() }
        return plugins[id]
    }

    public func plugins(with capability: PluginCapability) -> [AuroraPlugin] {
        lock.lock()
        defer { lock.unlock() }
        return plugins.values.filter { $0.manifest.capabilities.contains(capability) }
    }

    @discardableResult
    public func register(_ plugin: AuroraPlugin) -> Bool {
        let id = plugin.manifest.id
        lock.lock()
        if plugins[id] != nil {
            lock.unlock()
            return false
        }
        plugins[id] = plugin
        lock.unlock()
        plugin.pluginDidLoad(host: self)
        return true
    }

    public func unregister(id: String) {
        lock.lock()
        let plugin = plugins.removeValue(forKey: id)
        lock.unlock()
        plugin?.pluginWillUnload()
    }

    public func unregisterAll() {
        lock.lock()
        let all = Array(plugins.values)
        plugins.removeAll()
        lock.unlock()
        for plugin in all {
            plugin.pluginWillUnload()
        }
    }
}
