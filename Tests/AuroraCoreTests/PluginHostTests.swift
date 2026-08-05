import AuroraCore
import XCTest

private final class StubPlugin: AuroraPlugin {
    let manifest: PluginManifest
    var loaded = false
    var unloaded = false

    init(id: String, capabilities: Set<PluginCapability> = [.diagnostics]) {
        self.manifest = PluginManifest(
            id: id,
            name: "Stub \(id)",
            version: "1.0.0",
            capabilities: capabilities
        )
    }

    func pluginDidLoad(host: PluginHost) { loaded = true }
    func pluginWillUnload() { unloaded = true }
}

final class PluginHostTests: XCTestCase {
    func testRegisterAndList() {
        let host = PluginHost()
        let a = StubPlugin(id: "a.aurora.test", capabilities: [.outputDriver])
        let b = StubPlugin(id: "b.aurora.test", capabilities: [.controlInput, .diagnostics])
        XCTAssertTrue(host.register(a))
        XCTAssertTrue(host.register(b))
        XCTAssertFalse(host.register(a)) // duplicate
        XCTAssertEqual(host.manifests.count, 2)
        XCTAssertTrue(a.loaded)
        XCTAssertEqual(host.plugins(with: .controlInput).count, 1)
        host.unregister(id: "a.aurora.test")
        XCTAssertTrue(a.unloaded)
        XCTAssertEqual(host.manifests.count, 1)
    }
}
