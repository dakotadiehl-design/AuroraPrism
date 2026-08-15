import AuroraModel
import AuroraUI
import XCTest

final class StageObjectDragC4Tests: XCTestCase {
    func testObjectDragFinalizerMovesStockNotLocked() {
        var layout = StageLayout.empty
        let a = StageLayoutObject.stock(
            assetKey: "stage.performers.vocalist_mic",
            name: "Vox", x: 100, y: 100, width: 70, height: 130
        )
        var b = StageLayoutObject.stock(
            assetKey: "stage.performers.guitarist_neutral",
            name: "Gtr", x: 200, y: 100, width: 70, height: 130
        )
        b.locked = true
        layout.objects = [a, b]
        let origins = StageLayoutDragFinalizer.objectOrigins(
            layout: layout,
            selection: [a.id, b.id],
            anchorID: a.id
        )
        XCTAssertEqual(origins.count, 1)
        XCTAssertNotNil(origins[a.id])
        XCTAssertNil(origins[b.id])

        let drag = StageObjectDragState(anchorID: a.id, originalPositions: origins)
        let final = StageLayoutDragFinalizer.finalizedLayout(
            layout: layout,
            drag: drag,
            viewTranslation: CGSize(width: 40, height: -20),
            scale: 1
        )!
        XCTAssertEqual(final.objects.first { $0.id == a.id }!.x, 140, accuracy: 0.001)
        XCTAssertEqual(final.objects.first { $0.id == b.id }!.x, 200, accuracy: 0.001)
    }

    func testObjectResizeFinalizerSE() {
        var layout = StageLayout.empty
        let obj = StageLayoutObject.stock(
            assetKey: "stage.performers.drummer_full",
            name: "Drummer", x: 300, y: 200, width: 140, height: 110
        )
        layout.objects = [obj]
        let resize = StageObjectResizeState(
            objectID: obj.id,
            corner: .southEast,
            originalX: 300,
            originalY: 200,
            originalWidth: 140,
            originalHeight: 110
        )
        let final = StageLayoutResizeFinalizer.finalizedLayout(
            layout: layout,
            resize: resize,
            viewTranslation: CGSize(width: 40, height: 20),
            scale: 1,
            shiftHeld: false
        )!
        let out = final.objects[0]
        XCTAssertEqual(out.width, 180, accuracy: 0.001)
        XCTAssertEqual(out.height, 130, accuracy: 0.001)
        // SE grows right/down → center shifts
        XCTAssertEqual(out.x, 320, accuracy: 0.001)
        XCTAssertEqual(out.y, 210, accuracy: 0.001)
    }

    func testObjectResizeAllCornersAndMinSize() {
        var layout = StageLayout.empty
        let obj = StageLayoutObject.shape(.rectangle, name: "R", x: 100, y: 100, width: 80, height: 60)
        layout.objects = [obj]

        for corner in StageResizeCorner.allCases {
            let resize = StageObjectResizeState(
                objectID: obj.id,
                corner: corner,
                originalX: 100, originalY: 100,
                originalWidth: 80, originalHeight: 60,
                aspectPolicy: .freeByDefault
            )
            let g = StageLayoutResizeFinalizer.geometry(
                resize: resize,
                viewTranslation: CGSize(width: 30, height: 20),
                scale: 1,
                shiftHeld: false
            )
            XCTAssertGreaterThanOrEqual(g.width, StageLayoutResizeFinalizer.minSize)
            XCTAssertGreaterThanOrEqual(g.height, StageLayoutResizeFinalizer.minSize)
        }

        // Min size clamp
        let shrink = StageObjectResizeState(
            objectID: obj.id,
            corner: .southEast,
            originalX: 100, originalY: 100,
            originalWidth: 20, originalHeight: 20
        )
        let shrunk = StageLayoutResizeFinalizer.geometry(
            resize: shrink,
            viewTranslation: CGSize(width: -100, height: -100),
            scale: 1,
            shiftHeld: false
        )
        XCTAssertEqual(shrunk.width, StageLayoutResizeFinalizer.minSize, accuracy: 0.001)
        XCTAssertEqual(shrunk.height, StageLayoutResizeFinalizer.minSize, accuracy: 0.001)
    }

    func testObjectResizeRespectsLockAndAspect() {
        var layout = StageLayout.empty
        var obj = StageLayoutObject.stock(
            assetKey: "stage.performers.vocalist_standing",
            name: "Vox", x: 50, y: 50, width: 70, height: 130
        )
        obj.locked = true
        layout.objects = [obj]
        let lockedResize = StageObjectResizeState(
            objectID: obj.id,
            corner: .southEast,
            originalX: 50, originalY: 50,
            originalWidth: 70, originalHeight: 130,
            aspectPolicy: .preserveByDefault
        )
        XCTAssertNil(
            StageLayoutResizeFinalizer.finalizedLayout(
                layout: layout,
                resize: lockedResize,
                viewTranslation: CGSize(width: 50, height: 50),
                scale: 1
            )
        )

        obj.locked = false
        layout.objects = [obj]
        let free = StageObjectResizeState(
            objectID: obj.id,
            corner: .southEast,
            originalX: 50, originalY: 50,
            originalWidth: 70, originalHeight: 130,
            aspectPolicy: .preserveByDefault
        )
        // Width-dominant drag with aspect lock
        let g = StageLayoutResizeFinalizer.geometry(
            resize: free,
            viewTranslation: CGSize(width: 70, height: 5),
            scale: 1,
            shiftHeld: false
        )
        let aspect = 70.0 / 130.0
        XCTAssertEqual(g.width / g.height, aspect, accuracy: 0.02)
    }
}
