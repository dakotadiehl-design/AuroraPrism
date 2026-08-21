import AuroraModel
@testable import AuroraUI
import XCTest

final class StageCanvasCameraTests: XCTestCase {
    func testPointerAnchoredZoomKeepsWorldPointStationary() {
        let viewport = CGSize(width: 900, height: 600)
        let anchor = CGPoint(x: 180, y: 125)
        let oldScale: CGFloat = 0.75
        let oldPan = CGSize(width: 42, height: -31)
        let result = StageCanvasCamera.zoom(
            scale: oldScale,
            pan: oldPan,
            factor: 1.4,
            anchor: anchor,
            viewportSize: viewport
        )
        let center = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        let worldX = (anchor.x - center.x - oldPan.width) / oldScale
        let worldY = (anchor.y - center.y - oldPan.height) / oldScale
        XCTAssertEqual(center.x + result.pan.width + worldX * result.scale, anchor.x, accuracy: 0.001)
        XCTAssertEqual(center.y + result.pan.height + worldY * result.scale, anchor.y, accuracy: 0.001)
    }

    func testZoomClampsAtCameraLimits() {
        let viewport = CGSize(width: 800, height: 500)
        XCTAssertEqual(
            StageCanvasCamera.zoom(scale: 1, pan: .zero, factor: 100, anchor: .zero, viewportSize: viewport).scale,
            StageCanvasCamera.maximumScale
        )
        XCTAssertEqual(
            StageCanvasCamera.zoom(scale: 1, pan: .zero, factor: 0.0001, anchor: .zero, viewportSize: viewport).scale,
            StageCanvasCamera.minimumScale
        )
    }

    func testInspectorFormatsHueAsDegreesAndLevelsAsPercentages() {
        XCTAssertEqual(InspectorProgrammerValueFormatter.string(key: "colorHue@element-2", value: 180), "180°")
        XCTAssertEqual(InspectorProgrammerValueFormatter.string(key: "colorR@element-2", value: 0.92), "92%")
    }

    func testFixtureClaimPreventsSamePointerUpFromClearingSelection() {
        XCTAssertFalse(StagePointerArbitration.shouldClearSelection(
            contentClaimed: true,
            performedPan: false,
            movement: 0,
            performedMarquee: false
        ))
        XCTAssertTrue(StagePointerArbitration.shouldClearSelection(
            contentClaimed: false,
            performedPan: false,
            movement: 0,
            performedMarquee: false
        ))
    }

    func testContentBoundsIncludesFixturesAndScenicObjects() {
        let fixtureID = UUID()
        let layout = StageLayout(
            fixtures: [StageFixturePlacement(fixtureID: fixtureID, x: 200, y: 300)],
            objects: [
                StageLayoutObject.shape(
                    .stageArea,
                    name: "Main Stage",
                    x: 600,
                    y: 400,
                    width: 500,
                    height: 260
                )
            ]
        )

        let bounds = StageCanvasCamera.contentBounds(layout: layout)

        XCTAssertLessThanOrEqual(bounds.minX, 177)
        XCTAssertGreaterThanOrEqual(bounds.maxX, 850)
        XCTAssertLessThanOrEqual(bounds.minY, 270)
        XCTAssertGreaterThanOrEqual(bounds.maxY, 530)
    }

    func testContentBoundsIgnoresHiddenElements() {
        let visibleID = UUID()
        let hiddenID = UUID()
        let layout = StageLayout(
            fixtures: [
                StageFixturePlacement(fixtureID: visibleID, x: 300, y: 250),
                StageFixturePlacement(fixtureID: hiddenID, x: 1100, y: 750, hidden: true)
            ],
            objects: [
                StageLayoutObject(
                    kind: .shape,
                    shapeKind: .region,
                    name: "Hidden",
                    x: 1000,
                    y: 700,
                    width: 300,
                    height: 200,
                    hidden: true
                )
            ]
        )

        let bounds = StageCanvasCamera.contentBounds(layout: layout)

        XCTAssertLessThan(bounds.maxX, 400)
        XCTAssertLessThan(bounds.maxY, 350)
    }

    func testEmptyLayoutFitsTheWholeCanvas() {
        let layout = StageLayout(canvasWidth: 1200, canvasHeight: 800)
        let bounds = StageCanvasCamera.contentBounds(layout: layout)
        XCTAssertEqual(bounds, CGRect(x: 0, y: 0, width: 1200, height: 800))

        let camera = StageCanvasCamera.fitStage(layout: layout, in: CGSize(width: 600, height: 400))
        XCTAssertEqual(camera.pan, .zero)
    }
}
