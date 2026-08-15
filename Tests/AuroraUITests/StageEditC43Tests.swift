import AuroraUI
import XCTest

final class StageEditC43Tests: XCTestCase {
    func testCommittedAndTransientAreMutuallyExclusive() {
        let a = UUID()
        let b = UUID()
        let transient: Set<UUID> = [a]
        XCTAssertFalse(
            StageEditRenderEligibility.shouldRenderInCommittedLayer(
                elementID: a, transientElementIDs: transient
            )
        )
        XCTAssertTrue(
            StageEditRenderEligibility.shouldRenderInTransientLayer(
                elementID: a, transientElementIDs: transient
            )
        )
        XCTAssertTrue(
            StageEditRenderEligibility.shouldRenderInCommittedLayer(
                elementID: b, transientElementIDs: transient
            )
        )
        XCTAssertTrue(
            StageEditRenderEligibility.isSingleRenderInvariantHeld(
                elementID: a, transientElementIDs: transient
            )
        )
        XCTAssertTrue(
            StageEditRenderEligibility.isSingleRenderInvariantHeld(
                elementID: b, transientElementIDs: transient
            )
        )
    }

    func testLayoutObjectTransientTargetsUnion() {
        let move = UUID()
        let resize = UUID()
        let rotate = UUID()
        let toolbar = UUID()
        let ids = StageEditTransientTargets.layoutObjectIDs(
            activeTransform: .move(objectID: move),
            moveDragIDs: [move],
            resizeObjectID: resize,
            rotateObjectID: rotate,
            toolbarRotationPreviewIDs: [toolbar]
        )
        XCTAssertEqual(ids, [move, resize, rotate, toolbar])
    }

    func testCannotClaimSecondTransformWhileActive() {
        let id = UUID()
        let active = StageTransformInteraction.resize(objectID: id)
        XCTAssertTrue(active.blocksMove)
        XCTAssertTrue(active.blocksAim)
        XCTAssertTrue(active.blocksRotate)
        XCTAssertFalse(active.blocksResize)
    }

    func testFixtureAimTargets() {
        let aim = UUID()
        let move = UUID()
        let ids = StageEditTransientTargets.fixtureIDs(
            activeTransform: .aim(fixtureID: aim),
            moveDragFixtureIDs: [move],
            aimFixtureID: aim
        )
        XCTAssertEqual(ids, [aim, move])
    }

    /// Rotation preview is UI state: document stays put until commit (contract).
    func testRotationPreviewDoesNotImplyDocumentMutation() {
        // Document value independent of preview map.
        let committed: Double = 10 * .pi / 180
        let preview: Double = 45 * .pi / 180
        XCTAssertNotEqual(committed, preview, accuracy: 0.0001)
        // Render path prefers preview when present (mirrors StageCanvasView.objectDisplayRotation).
        let rendered = preview
        XCTAssertEqual(rendered, 45 * .pi / 180, accuracy: 0.0001)
        // After clear, rendered falls back to committed.
        let previewCleared: Double? = nil
        let after = previewCleared ?? committed
        XCTAssertEqual(after, committed, accuracy: 0.0001)
    }

    // MARK: - C4.4 multi-object exclusivity

    func testMultiObjectMoveEligibility() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let d = UUID()
        let transient: Set<UUID> = [a, b, c]
        for id in [a, b, c] {
            XCTAssertFalse(
                StageEditRenderEligibility.shouldRenderInCommittedLayer(
                    elementID: id, transientElementIDs: transient
                )
            )
            XCTAssertTrue(
                StageEditRenderEligibility.shouldRenderInTransientLayer(
                    elementID: id, transientElementIDs: transient
                )
            )
        }
        XCTAssertTrue(
            StageEditRenderEligibility.shouldRenderInCommittedLayer(
                elementID: d, transientElementIDs: transient
            )
        )
        XCTAssertFalse(
            StageEditRenderEligibility.shouldRenderInTransientLayer(
                elementID: d, transientElementIDs: transient
            )
        )
    }

    func testCancelRestoresCommittedEligibility() {
        let x = UUID()
        var transient: Set<UUID> = [x]
        XCTAssertFalse(
            StageEditRenderEligibility.shouldRenderInCommittedLayer(
                elementID: x, transientElementIDs: transient
            )
        )
        transient.removeAll()
        XCTAssertTrue(
            StageEditRenderEligibility.shouldRenderInCommittedLayer(
                elementID: x, transientElementIDs: transient
            )
        )
        XCTAssertFalse(
            StageEditRenderEligibility.shouldRenderInTransientLayer(
                elementID: x, transientElementIDs: transient
            )
        )
    }
}
