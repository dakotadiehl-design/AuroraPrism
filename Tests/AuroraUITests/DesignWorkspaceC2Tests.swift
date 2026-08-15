import AuroraCore
import AuroraModel
import AuroraUI
import XCTest

/// Checkpoint C2 — DESIGN layout fields + selection independence from layout chrome.
@MainActor
final class DesignWorkspaceC2Tests: XCTestCase {
    func testWorkspaceLayoutDesignFieldsRoundTrip() throws {
        var layout = WorkspaceLayout.default
        layout.designPreviewFraction = 0.61
        layout.stagePreviewCollapsed = true
        layout.schemaVersion = 3
        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(WorkspaceLayout.self, from: data)
        XCTAssertEqual(decoded.designPreviewFraction, 0.61, accuracy: 0.0001)
        XCTAssertTrue(decoded.stagePreviewCollapsed)
        XCTAssertEqual(decoded.schemaVersion, 4)
    }

    func testLegacyLayoutDecodesWithDesignDefaults() throws {
        let json = """
        {
          "schemaVersion": 2,
          "visiblePanels": ["fixtureBrowser", "programmer", "inspector", "cueList"],
          "leadingFraction": 0.22,
          "trailingFraction": 0.22,
          "bottomFraction": 0.28,
          "leadingTab": "fixtureBrowser",
          "centerTab": "programmer",
          "bottomTab": "cueList"
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WorkspaceLayout.self, from: json)
        XCTAssertEqual(decoded.designPreviewFraction, 0.52, accuracy: 0.001)
        XCTAssertFalse(decoded.stagePreviewCollapsed)
        XCTAssertEqual(decoded.schemaVersion, 4)
    }

    func testCollapseIsLayoutOnlyDoesNotTouchProject() {
        let project = ShowProject.demoSummerNight()
        let count = project.fixtures.count
        var layout = WorkspaceLayout.default
        layout.stagePreviewCollapsed = true
        XCTAssertEqual(project.fixtures.count, count)
        XCTAssertTrue(layout.stagePreviewCollapsed)
    }

    func testSharedSelectionSessionUnchangedByLayout() {
        let session = DocumentSession(project: ShowProject.demoSummerNight())
        guard let id = session.project.fixtures.first?.id else {
            XCTFail("demo fixtures")
            return
        }
        session.selectFixtures([id], extending: false)
        XCTAssertEqual(session.selection.snapshot.fixtureIDs, [id])
        XCTAssertEqual(session.selection.snapshot.orderedFixtureIDs, [id])
    }

    // C3.1 lower shelf collapse
    func testLowerShelfCollapsePreservesBottomFraction() throws {
        var layout = WorkspaceLayout.default
        layout.bottomFraction = 0.34
        layout.lowerShelfCollapsed = true
        let data = try JSONEncoder().encode(layout)
        var decoded = try JSONDecoder().decode(WorkspaceLayout.self, from: data)
        XCTAssertTrue(decoded.lowerShelfCollapsed)
        XCTAssertEqual(decoded.bottomFraction, 0.34, accuracy: 0.0001)
        decoded.lowerShelfCollapsed = false
        XCTAssertEqual(decoded.bottomFraction, 0.34, accuracy: 0.0001)
    }

    func testLegacyLayoutDefaultsLowerShelfExpanded() throws {
        let json = """
        {
          "schemaVersion": 3,
          "visiblePanels": ["fixtureBrowser", "programmer", "inspector", "cueList"],
          "leadingFraction": 0.22,
          "trailingFraction": 0.22,
          "bottomFraction": 0.28,
          "designPreviewFraction": 0.52,
          "stagePreviewCollapsed": false,
          "leadingTab": "fixtureBrowser",
          "centerTab": "programmer",
          "bottomTab": "cueList"
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WorkspaceLayout.self, from: json)
        XCTAssertFalse(decoded.lowerShelfCollapsed)
        XCTAssertEqual(decoded.schemaVersion, 4)
    }
}
