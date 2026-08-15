import AuroraCore
import AuroraModel
import AuroraUI
import XCTest

/// C3.1 final closeout — exercises the **same finalization path** as `StageCanvasView.commitFixtureDrag`.
@MainActor
final class StageLayoutDragFinalizerTests: XCTestCase {
    private let idA = UUID(uuidString: "00000000-0000-4000-8000-0000000000A1")!
    private let idB = UUID(uuidString: "00000000-0000-4000-8000-0000000000B2")!
    private let idLocked = UUID(uuidString: "00000000-0000-4000-8000-0000000000C3")!

    private func baseLayout(snap: Bool = false) -> StageLayout {
        StageLayout(
            gridSize: 20,
            snapToGrid: snap,
            fixtures: [
                StageFixturePlacement(fixtureID: idA, x: 100, y: 100),
                StageFixturePlacement(fixtureID: idB, x: 150, y: 100),
                StageFixturePlacement(fixtureID: idLocked, x: 200, y: 100, locked: true),
            ]
        )
    }

    func testSingleFixtureFinalizationAndUndo() throws {
        let layout = baseLayout()
        let origins = StageLayoutDragFinalizer.fixtureOrigins(
            layout: layout,
            selection: [idA],
            anchorID: idA
        )
        XCTAssertEqual(origins[idA]?.x, 100)
        XCTAssertNil(origins[idLocked])

        let drag = StageObjectDragState(anchorID: idA, originalPositions: origins)
        // view translation at scale 1: (+40, -20) world
        let final = StageLayoutDragFinalizer.finalizedLayout(
            layout: layout,
            drag: drag,
            viewTranslation: CGSize(width: 40, height: -20),
            scale: 1
        )
        XCTAssertEqual(final?.fixtures.first { $0.fixtureID == idA }?.x, 140)
        XCTAssertEqual(final?.fixtures.first { $0.fixtureID == idA }?.y, 80)
        // Others unchanged
        XCTAssertEqual(final?.fixtures.first { $0.fixtureID == idB }?.x, 150)
        XCTAssertEqual(final?.fixtures.first { $0.fixtureID == idLocked }?.x, 200)

        // Production commit: one command + undo
        let session = DocumentSession(project: {
            var p = ShowProject.empty(name: "Drag")
            p.stageLayout = layout
            return p
        }())
        try session.perform(UpdateStageLayoutCommand(layout: final!))
        XCTAssertEqual(session.project.stageLayout.fixtures.first { $0.fixtureID == idA }?.x, 140)
        try session.undo()
        XCTAssertEqual(session.project.stageLayout.fixtures.first { $0.fixtureID == idA }?.x, 100)
        try session.redo()
        XCTAssertEqual(session.project.stageLayout.fixtures.first { $0.fixtureID == idA }?.x, 140)
    }

    func testMultiFixtureSameDeltaPreservesSpacing() {
        let layout = baseLayout()
        let origins = StageLayoutDragFinalizer.fixtureOrigins(
            layout: layout,
            selection: [idA, idB],
            anchorID: idA
        )
        XCTAssertEqual(origins.count, 2)

        let drag = StageObjectDragState(anchorID: idA, originalPositions: origins)
        let final = StageLayoutDragFinalizer.finalizedLayout(
            layout: layout,
            drag: drag,
            viewTranslation: CGSize(width: 40, height: -20),
            scale: 1
        )!
        let a = final.fixtures.first { $0.fixtureID == idA }!
        let b = final.fixtures.first { $0.fixtureID == idB }!
        XCTAssertEqual(a.x, 140, accuracy: 0.001)
        XCTAssertEqual(a.y, 80, accuracy: 0.001)
        XCTAssertEqual(b.x - a.x, 50, accuracy: 0.001)
        XCTAssertEqual(b.y - a.y, 0, accuracy: 0.001)
        // Locked omitted
        XCTAssertEqual(final.fixtures.first { $0.fixtureID == idLocked }?.x, 200)
    }

    func testLockedOmittedFromOriginsAndFinalLayout() {
        let layout = baseLayout()
        let origins = StageLayoutDragFinalizer.fixtureOrigins(
            layout: layout,
            selection: [idA, idLocked],
            anchorID: idLocked
        )
        // Locked anchor → no origins (or empty for locked-only)
        XCTAssertTrue(origins.isEmpty || origins[idLocked] == nil)

        let unlockedOnly = StageLayoutDragFinalizer.fixtureOrigins(
            layout: layout,
            selection: [idA, idLocked],
            anchorID: idA
        )
        XCTAssertEqual(Set(unlockedOnly.keys), [idA])
        XCTAssertNil(unlockedOnly[idLocked])
    }

    func testGroupSnapDoesNotDistortSpacing() {
        let layout = baseLayout(snap: true)
        let origins = StageLayoutDragFinalizer.fixtureOrigins(
            layout: layout,
            selection: [idA, idB],
            anchorID: idA
        )
        let drag = StageObjectDragState(anchorID: idA, originalPositions: origins)
        // Non-grid raw delta; snap anchor only
        let final = StageLayoutDragFinalizer.finalizedLayout(
            layout: layout,
            drag: drag,
            viewTranslation: CGSize(width: 37, height: -13),
            scale: 1
        )!
        let a = final.fixtures.first { $0.fixtureID == idA }!
        let b = final.fixtures.first { $0.fixtureID == idB }!
        XCTAssertEqual(b.x - a.x, 50, accuracy: 0.001)
        XCTAssertEqual(b.y - a.y, 0, accuracy: 0.001)
    }

    func testZoomAwareFinalization() {
        let layout = baseLayout()
        let origins = StageLayoutDragFinalizer.fixtureOrigins(
            layout: layout,
            selection: [idA],
            anchorID: idA
        )
        let drag = StageObjectDragState(anchorID: idA, originalPositions: origins)
        // 100 view pixels at 2x zoom → 50 world units
        let final = StageLayoutDragFinalizer.finalizedLayout(
            layout: layout,
            drag: drag,
            viewTranslation: CGSize(width: 100, height: 0),
            scale: 2
        )!
        XCTAssertEqual(final.fixtures.first { $0.fixtureID == idA }!.x, 150, accuracy: 0.001)
    }

    func testLiveDeltaMatchesCommitDelta() {
        let layout = baseLayout(snap: true)
        let origins = StageLayoutDragFinalizer.fixtureOrigins(
            layout: layout,
            selection: [idA, idB],
            anchorID: idA
        )
        let drag = StageObjectDragState(anchorID: idA, originalPositions: origins)
        let view = CGSize(width: 37, height: -13)
        let live = StageLayoutDragFinalizer.liveDelta(
            layout: layout, drag: drag, viewTranslation: view, scale: 1
        )
        let final = StageLayoutDragFinalizer.finalizedLayout(
            layout: layout, drag: drag, viewTranslation: view, scale: 1
        )!
        let a = final.fixtures.first { $0.fixtureID == idA }!
        XCTAssertEqual(a.x, 100 + live.width, accuracy: 0.001)
        XCTAssertEqual(a.y, 100 + live.height, accuracy: 0.001)
    }

    func testNoOpDeltaReturnsNil() {
        let layout = baseLayout()
        let origins = StageLayoutDragFinalizer.fixtureOrigins(
            layout: layout,
            selection: [idA],
            anchorID: idA
        )
        let drag = StageObjectDragState(anchorID: idA, originalPositions: origins)
        let final = StageLayoutDragFinalizer.finalizedLayout(
            layout: layout,
            drag: drag,
            viewTranslation: .zero,
            scale: 1
        )
        XCTAssertNil(final)
    }
}
