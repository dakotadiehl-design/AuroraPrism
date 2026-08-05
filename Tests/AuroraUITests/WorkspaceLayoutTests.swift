import AuroraUI
import XCTest

final class WorkspaceLayoutTests: XCTestCase {
    func testLayoutRoundTrip() throws {
        var layout = WorkspaceLayout.default
        layout.toggle(.console)
        layout.leadingFraction = 0.3
        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(WorkspaceLayout.self, from: data)
        XCTAssertEqual(decoded.leadingFraction, 0.3)
        // Default layout shows console; one toggle hides it.
        XCTAssertFalse(decoded.isVisible(.console))
        XCTAssertEqual(decoded, layout)
    }

    func testPanelIDsHaveTitles() {
        for id in WorkspacePanelID.allCases {
            XCTAssertFalse(id.title.isEmpty)
        }
        XCTAssertTrue(WorkspacePanelID.allCases.contains(.effects))
        XCTAssertEqual(WorkspacePanelID.effects.title, "Effects")
    }

    func testDefaultLayoutIncludesEffectsPanel() {
        XCTAssertTrue(WorkspaceLayout.defaultVisible.contains(.effects))
    }

    func testLayoutStoreSaveLoad() {
        let defaults = UserDefaults(suiteName: "aurora.tests.layout.\(UUID().uuidString)")!
        var layout = WorkspaceLayout.default
        layout.bottomFraction = 0.4
        WorkspaceLayoutStore.save(layout, to: defaults)
        let loaded = WorkspaceLayoutStore.load(from: defaults)
        XCTAssertEqual(loaded.bottomFraction, 0.4, accuracy: 0.0001)
    }
}
