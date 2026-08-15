import AuroraCore
import AuroraModel
import AuroraUI
import XCTest

final class StageInteractionC42Tests: XCTestCase {
    // MARK: - Aim math

    func testAimFromPointerQuadrants() {
        let c = CGPoint(x: 0, y: 0)
        let east = StageAimMath.aimFromPointer(fixtureCenter: c, pointer: CGPoint(x: 100, y: 0))
        XCTAssertEqual(east.direction, 0, accuracy: 0.0001)
        XCTAssertEqual(east.length, 100, accuracy: 0.001)

        let south = StageAimMath.aimFromPointer(fixtureCenter: c, pointer: CGPoint(x: 0, y: 100))
        XCTAssertEqual(south.direction, .pi / 2, accuracy: 0.0001)
        XCTAssertEqual(south.length, 100, accuracy: 0.001)

        let west = StageAimMath.aimFromPointer(fixtureCenter: c, pointer: CGPoint(x: -50, y: 0))
        XCTAssertEqual(west.direction, .pi, accuracy: 0.0001)
        XCTAssertEqual(west.length, 50, accuracy: 0.001)

        let north = StageAimMath.aimFromPointer(fixtureCenter: c, pointer: CGPoint(x: 0, y: -80))
        XCTAssertEqual(north.direction, -.pi / 2, accuracy: 0.0001)
        XCTAssertEqual(north.length, 80, accuracy: 0.001)
    }

    func testAimHandleRoundTrip() {
        let c = CGPoint(x: 40, y: 60)
        let dir = -0.7
        let len = 150.0
        let tip = StageAimMath.handlePoint(fixtureCenter: c, direction: dir, length: len)
        let back = StageAimMath.aimFromPointer(fixtureCenter: c, pointer: tip)
        XCTAssertEqual(back.direction, dir, accuracy: 0.001)
        XCTAssertEqual(back.length, len, accuracy: 0.5)
    }

    // MARK: - Resize ownership semantics

    func testTransformStateBlocksMoveDuringResize() {
        let r = StageTransformInteraction.resize(objectID: UUID())
        XCTAssertTrue(r.blocksMove)
        XCTAssertFalse(r.blocksResize)
        let m = StageTransformInteraction.move(objectID: UUID())
        XCTAssertFalse(m.blocksMove)
        XCTAssertTrue(m.blocksResize)
    }

    func testNWResizeDoesNotTranslateAsWholeOnly() {
        // NW drag grows left/up: center moves, size changes — both expected.
        let resize = StageObjectResizeState(
            objectID: UUID(),
            corner: .northWest,
            originalX: 200, originalY: 200,
            originalWidth: 100, originalHeight: 80,
            aspectPolicy: .freeByDefault
        )
        // Drag left/up in view: translation negative
        let g = StageLayoutResizeFinalizer.geometry(
            resize: resize,
            viewTranslation: CGSize(width: -40, height: -20),
            scale: 1,
            shiftHeld: false
        )
        XCTAssertGreaterThan(g.width, 100)
        XCTAssertGreaterThan(g.height, 80)
        // Opposite corner (SE) stays fixed: SE = center + (w/2, h/2)
        let origSEX = 200 + 50.0
        let origSEY = 200 + 40.0
        let newSEX = g.x + g.width / 2
        let newSEY = g.y + g.height / 2
        XCTAssertEqual(newSEX, origSEX, accuracy: 0.5)
        XCTAssertEqual(newSEY, origSEY, accuracy: 0.5)
    }

    func testZoomAwareResizeDelta() {
        let resize = StageObjectResizeState(
            objectID: UUID(),
            corner: .southEast,
            originalX: 0, originalY: 0,
            originalWidth: 100, originalHeight: 100
        )
        let at1 = StageLayoutResizeFinalizer.geometry(
            resize: resize,
            viewTranslation: CGSize(width: 40, height: 0),
            scale: 1,
            shiftHeld: false
        )
        let at2 = StageLayoutResizeFinalizer.geometry(
            resize: resize,
            viewTranslation: CGSize(width: 80, height: 0),
            scale: 2,
            shiftHeld: false
        )
        // Same world delta → same size
        XCTAssertEqual(at1.width, at2.width, accuracy: 0.01)
    }

    func testRotatedObjectResizeLocalAxes() {
        // Object rotated 90°: view +X should map to local -Y or +Y depending on convention
        let resize = StageObjectResizeState(
            objectID: UUID(),
            corner: .southEast,
            originalX: 100, originalY: 100,
            originalWidth: 80, originalHeight: 40,
            originalRotation: .pi / 2,
            aspectPolicy: .freeByDefault
        )
        let g = StageLayoutResizeFinalizer.geometry(
            resize: resize,
            viewTranslation: CGSize(width: 0, height: 40),
            scale: 1,
            shiftHeld: false
        )
        // At 90°, view +Y maps into local -X or similar — size must change and stay >= min
        XCTAssertGreaterThanOrEqual(g.width, StageLayoutResizeFinalizer.minSize)
        XCTAssertGreaterThanOrEqual(g.height, StageLayoutResizeFinalizer.minSize)
        XCTAssertTrue(abs(g.width - 80) > 0.5 || abs(g.height - 40) > 0.5)
    }

    // MARK: - Rotation

    func testRotationFromPointer() {
        let c = CGPoint(x: 0, y: 0)
        let r = StageRotateMath.rotationFromPointer(center: c, pointer: CGPoint(x: 0, y: -1), orientationOffset: 0)
        XCTAssertEqual(r, -.pi / 2, accuracy: 0.001)
    }

    // MARK: - Aim finalization / model separation

    @MainActor
    func testStaticAimCommitUndoRestoresDirectionAndLength() throws {
        let session = DocumentSession(project: ShowProject.empty(name: "C42"))
        var layout = session.project.stageLayout
        let place = StageFixturePlacement.placed(fixtureID: UUID(), x: 100, y: 100, category: "par")
        layout.fixtures = [place]
        try session.perform(UpdateStageLayoutCommand(layout: layout))

        var next = session.project.stageLayout
        next.fixtures[0].aimDirection = 0.5
        next.fixtures[0].beamLength = 200
        try session.perform(UpdateStageLayoutCommand(layout: next))
        XCTAssertEqual(session.project.stageLayout.fixtures[0].aimDirection, 0.5, accuracy: 0.001)
        XCTAssertEqual(session.project.stageLayout.fixtures[0].beamLength, 200, accuracy: 0.001)
        try session.undo()
        XCTAssertEqual(session.project.stageLayout.fixtures[0].aimDirection, place.aimDirection, accuracy: 0.001)
        XCTAssertEqual(session.project.stageLayout.fixtures[0].beamLength, place.beamLength, accuracy: 0.001)
    }

    func testMoverComposeDoesNotMutatePhysicalAim() {
        var place = StageFixturePlacement.placed(fixtureID: UUID(), x: 0, y: 0, category: "moving head")
        place.aimDirection = -1.0
        let rendered = StageBeamDirectionResolver.renderedAimRadians(
            placement: place,
            livePan: 1.0,
            panRangeRadians: .pi,
            hasPanTilt: true
        )
        // Physical aim unchanged
        XCTAssertEqual(place.aimDirection, -1.0, accuracy: 0.0001)
        // Rendered differs when pan not at home
        XCTAssertNotEqual(rendered, place.aimDirection, accuracy: 0.001)
    }
}
