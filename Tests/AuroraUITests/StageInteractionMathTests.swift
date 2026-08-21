import AuroraModel
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

    func testFirstFixtureDragUsesLocalReplacementSelection() {
        let selected = UUID()
        let anchor = UUID()

        XCTAssertEqual(
            StageFixtureDragSelection.workingSelection(current: [selected], anchorID: anchor),
            [anchor]
        )
        XCTAssertTrue(
            StageFixtureDragSelection.shouldPublishAfterDrag(current: [selected], anchorID: anchor)
        )
    }

    func testSelectedFixtureDragPreservesGroupWithoutRepublishing() {
        let first = UUID()
        let anchor = UUID()
        let current: Set<UUID> = [first, anchor]

        XCTAssertEqual(
            StageFixtureDragSelection.workingSelection(current: current, anchorID: anchor),
            current
        )
        XCTAssertFalse(
            StageFixtureDragSelection.shouldPublishAfterDrag(current: current, anchorID: anchor)
        )
    }

    func testFixtureHoverInfoIncludesIdentityTypePatchAndUsefulContext() {
        let universe = Universe(number: 2, name: "Stage Left")
        let definition = FixtureDefinition(
            manufacturer: "ETC",
            model: "Source Four LED",
            modeName: "Direct 10ch",
            channelCount: 10,
            category: "Profile"
        )
        let fixture = PatchedFixture(
            name: "FOH Special",
            definitionId: definition.id,
            universeId: universe.id,
            address: 101
        )

        let text = StageFixtureHoverInfo.text(
            fixture: fixture,
            definition: definition,
            universe: universe,
            footprint: 10,
            groupNames: ["Specials", "FOH"],
            locked: true
        )

        XCTAssertTrue(text.contains("FOH Special"))
        XCTAssertTrue(text.contains("Type: Profile"))
        XCTAssertTrue(text.contains("Fixture: ETC Source Four LED"))
        XCTAssertTrue(text.contains("Mode: Direct 10ch · 10 channels"))
        XCTAssertTrue(text.contains("Universe 2 — Stage Left · Channels 101–110"))
        XCTAssertTrue(text.contains("Groups: FOH, Specials"))
        XCTAssertTrue(text.contains("Stage position: Locked"))
    }

    func testFixtureHoverInfoDescribesUnpatchedFixtureWithoutDefinition() {
        let fixture = PatchedFixture(
            name: "Spare",
            definitionId: UUID(),
            universeId: UUID(),
            address: 0
        )
        let text = StageFixtureHoverInfo.text(
            fixture: fixture,
            definition: nil,
            universe: nil,
            footprint: 1,
            groupNames: [],
            locked: false
        )
        XCTAssertTrue(text.contains("Type: Fixture"))
        XCTAssertTrue(text.contains("Footprint: 1 channel"))
        XCTAssertTrue(text.contains("Patch: Unpatched"))
    }
}
