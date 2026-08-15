import AuroraCore
import AuroraModel
import XCTest

@MainActor
final class StageLayoutC4Tests: XCTestCase {
    func testLegacyScenicMigratesToObjects() throws {
        let scenicID = UUID()
        let json = """
        {
          "schemaVersion": 1,
          "canvasWidth": 1200,
          "canvasHeight": 800,
          "gridSize": 20,
          "snapToGrid": true,
          "fixtures": [],
          "scenic": [{
            "id": "\(scenicID.uuidString)",
            "kind": "stageArea",
            "name": "Deck",
            "x": 100, "y": 200, "width": 400, "height": 100,
            "rotation": 0, "zIndex": 2
          }]
        }
        """.data(using: .utf8)!
        let layout = try JSONDecoder().decode(StageLayout.self, from: json)
        XCTAssertEqual(layout.objects.count, 1)
        XCTAssertEqual(layout.objects[0].kind, .shape)
        XCTAssertEqual(layout.objects[0].shapeKind, .stageArea)
        XCTAssertEqual(layout.objects[0].name, "Deck")
        XCTAssertEqual(layout.schemaVersion, 2)
    }

    func testStockObjectRoundTripPreservesAssetKey() throws {
        var layout = StageLayout.empty
        let obj = StageLayoutObject.stock(
            assetKey: "stage.performers.drummer_full",
            name: "Drummer Full",
            x: 300, y: 400,
            width: 140, height: 110,
            opacity: 0.9
        )
        layout.appendObject(obj)
        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(StageLayout.self, from: data)
        XCTAssertEqual(decoded.objects.count, 1)
        XCTAssertEqual(decoded.objects[0].assetKey, "stage.performers.drummer_full")
        XCTAssertEqual(decoded.objects[0].kind, .stockImage)
    }

    func testPlaceStockCommandViaLayoutUpdateUndo() throws {
        let session = DocumentSession(project: ShowProject.empty(name: "C4"))
        var layout = session.project.stageLayout
        let obj = StageLayoutObject.stock(
            assetKey: "stage.performers.keyboardist_standing",
            name: "Keys", x: 400, y: 300, width: 150, height: 110
        )
        layout.appendObject(obj)
        try session.perform(UpdateStageLayoutCommand(layout: layout))
        XCTAssertEqual(session.project.stageLayout.objects.count, 1)
        try session.undo()
        XCTAssertTrue(session.project.stageLayout.objects.isEmpty)
    }
}
