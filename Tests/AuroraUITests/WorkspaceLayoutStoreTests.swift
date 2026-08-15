import AuroraUI
import XCTest

final class WorkspaceLayoutStoreTests: XCTestCase {
    func testRoundTripAndClamp() {
        let defaults = UserDefaults(suiteName: "aurora.test.layout.\(UUID().uuidString)")!
        var layout = WorkspaceLayout(leadingFraction: 0.9, trailingFraction: 0.9, bottomFraction: 0.9)
        layout.clampToSafeGeometry()
        XCTAssertLessThanOrEqual(layout.leadingFraction + layout.trailingFraction, 0.86)
        WorkspaceLayoutStore.save(layout, to: defaults)
        let loaded = WorkspaceLayoutStore.load(from: defaults)
        XCTAssertEqual(loaded.schemaVersion, WorkspaceLayout.currentSchemaVersion)
        XCTAssertLessThanOrEqual(loaded.leadingFraction, 0.45)
    }

    func testNamedPresets() {
        let patch = WorkspaceLayout.namedBuildPreset("Patch")
        XCTAssertEqual(patch.namedPreset, "Patch")
        let prog = WorkspaceLayout.namedBuildPreset("Programming")
        XCTAssertEqual(prog.namedPreset, "Programming")
    }

    func testCorruptFallsBackToDefault() {
        let defaults = UserDefaults(suiteName: "aurora.test.layout.bad.\(UUID().uuidString)")!
        defaults.set(Data("not-json".utf8), forKey: WorkspaceLayoutStore.defaultsKey)
        let loaded = WorkspaceLayoutStore.load(from: defaults)
        XCTAssertEqual(loaded, .default)
    }
}
