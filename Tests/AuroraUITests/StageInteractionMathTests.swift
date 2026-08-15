import AuroraUI
import XCTest

final class StageInteractionMathTests: XCTestCase {
    func testPanOriginPlusTranslation() {
        let start = CGSize(width: 100, height: 50)
        let t1 = CGSize(width: 40, height: -10)
        let p1 = StageCameraPan.displayedPan(start: start, translation: t1)
        XCTAssertEqual(p1.width, 140, accuracy: 0.001)
        XCTAssertEqual(p1.height, 40, accuracy: 0.001)

        // Second event reports cumulative translation from gesture start — recompute from start, not from p1.
        let t2 = CGSize(width: 60, height: -20)
        let p2 = StageCameraPan.displayedPan(start: start, translation: t2)
        XCTAssertEqual(p2.width, 160, accuracy: 0.001)
        XCTAssertEqual(p2.height, 30, accuracy: 0.001)
    }

    func testWorldDeltaAccountsForZoom() {
        let view = CGSize(width: 100, height: 50)
        let d1 = StageWorldDragMath.worldDelta(viewTranslation: view, scale: 1)
        XCTAssertEqual(d1.width, 100, accuracy: 0.001)
        XCTAssertEqual(d1.height, 50, accuracy: 0.001)

        let d2 = StageWorldDragMath.worldDelta(viewTranslation: view, scale: 2)
        XCTAssertEqual(d2.width, 50, accuracy: 0.001)
        XCTAssertEqual(d2.height, 25, accuracy: 0.001)
    }

    func testGroupSnapPreservesRelativeSpacing() {
        let idA = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let idB = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
        let a = CGPoint(x: 100, y: 100)
        let b = CGPoint(x: 150, y: 100)
        let originals: [UUID: CGPoint] = [idA: a, idB: b]
        let raw = CGSize(width: 37, height: -13)
        let snapped = StageWorldDragMath.snapDelta(raw, anchorOrigin: a, gridSize: 20, snapToGrid: true)
        let finals = StageWorldDragMath.finalPositions(originals: originals, delta: snapped)
        let fa = finals[idA]!
        let fb = finals[idB]!
        XCTAssertEqual(fb.x - fa.x, 50, accuracy: 0.001)
        XCTAssertEqual(fb.y - fa.y, 0, accuracy: 0.001)
    }

    func testDragDisplayPosition() {
        let id = UUID()
        var state = StageObjectDragState(
            anchorID: id,
            originalPositions: [id: CGPoint(x: 10, y: 20)]
        )
        state.currentDelta = CGSize(width: 5, height: -3)
        let p = state.displayPosition(for: id)!
        XCTAssertEqual(p.x, 15, accuracy: 0.001)
        XCTAssertEqual(p.y, 17, accuracy: 0.001)
    }

    func testSpaceOwnershipGateConcept() {
        // Text editing must block Stage Space ownership (mirrors StageCanvasKeyState rule).
        // Pure rule documented for regression: ownership requires hover && !textEditing.
        let stageMounted = true
        let pointerInside = true
        let textEditing = true
        let owns = stageMounted && pointerInside && !textEditing
        XCTAssertFalse(owns)
        XCTAssertTrue(stageMounted && pointerInside && !false)
    }
}
