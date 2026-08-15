import AuroraUI
import XCTest

@MainActor
final class StageStockCatalogC41Tests: XCTestCase {
    func testCorrectedCatalogLoadsBoundsAndDefaults() {
        let catalog = StageStockCatalog.shared
        catalog.reload()
        XCTAssertTrue(catalog.didLoad)
        XCTAssertNil(catalog.loadError, catalog.loadError ?? "")
        XCTAssertFalse(catalog.assets.isEmpty)
        XCTAssertEqual(catalog.assets.count, 35)
        XCTAssertTrue(
            catalog.kitName?.contains("Corrected") == true,
            "Expected corrected kit name, got \(catalog.kitName ?? "nil")"
        )

        // Stable keys still resolve
        let drummer = catalog.asset(key: "stage.performers.drummer_full")
        XCTAssertNotNil(drummer)
        XCTAssertGreaterThan(drummer!.defaultStageWidth, 0)
        XCTAssertGreaterThan(drummer!.defaultStageHeight, 0)
        // Corrected kit: full visual bounds (pre-isolated art)
        XCTAssertTrue(drummer!.visualBounds.isFull)
        XCTAssertEqual(drummer!.sourceStatus, "corrected-isolated-vector")

        // Standing performer is taller than wide (meters 0.85×1.8 → world)
        XCTAssertLessThan(drummer!.defaultStageWidth, drummer!.defaultStageHeight)

        let curved = catalog.asset(key: "stage.truss.curved_left")
        XCTAssertNotNil(curved)
        XCTAssertTrue(curved!.visualBounds.isFull)
        // Near-square curved truss
        let curvedAR = curved!.defaultStageWidth / curved!.defaultStageHeight
        XCTAssertEqual(curvedAR, 1.0, accuracy: 0.15)

        // Straight long truss is wide and shallow — not a square box
        let straight = catalog.asset(key: "stage.truss.straight_long")
        XCTAssertNotNil(straight)
        XCTAssertGreaterThan(straight!.defaultStageWidth, straight!.defaultStageHeight * 3)

        // PNG resources resolve for a sample of categories
        XCTAssertNotNil(catalog.image(for: "stage.performers.vocalist_standing"))
        XCTAssertNotNil(catalog.image(for: "stage.equipment.mic_stand"))
        XCTAssertNotNil(catalog.image(for: "stage.truss.straight_short"))
        XCTAssertNotNil(catalog.image(for: "stage.audience.crowd_wide"))
    }

    func testLegacyMissingBoundsDefaultsToFull() {
        let size = StageStockCatalog.heuristicDefaultSize(
            key: "stage.truss.curved_left",
            category: .truss
        )
        let m = StageStockCatalog.catalogMetersToStageWorld
        XCTAssertEqual(size.width, 1.8 * m, accuracy: 0.1)
        XCTAssertEqual(size.height, 1.8 * m, accuracy: 0.1)
    }

    func testPaletteSectionsStable() {
        XCTAssertEqual(StageObjectPaletteView.PaletteSection.allCases.count, 6)
        XCTAssertEqual(
            StageObjectPaletteView.PaletteSection.allCases.map(\.rawValue),
            ["Performers", "Audience", "Equipment", "Truss", "Special", "Shapes"]
        )
    }

    func testStableKeysUnchangedFromPriorKit() {
        let catalog = StageStockCatalog.shared
        catalog.reload()
        let expected: [String] = [
            "stage.performers.vocalist_standing",
            "stage.performers.drummer_full",
            "stage.performers.guitarist_neutral",
            "stage.equipment.mic_stand",
            "stage.equipment.speaker_on_pole",
            "stage.equipment.lighting_stand",
            "stage.equipment.riser_platform",
            "stage.truss.straight_short",
            "stage.truss.curved_left",
            "stage.audience.crowd_wide",
            "stage.special.disco_ball",
        ]
        for key in expected {
            XCTAssertNotNil(catalog.asset(key: key), "Missing stable key \(key)")
        }
        XCTAssertNotNil(catalog.image(for: "stage.equipment.lighting_stand"))
        XCTAssertNotNil(catalog.image(for: "stage.equipment.riser_platform"))
        let riser = catalog.asset(key: "stage.equipment.riser_platform")!
        XCTAssertGreaterThan(riser.defaultStageWidth, riser.defaultStageHeight)
    }
}
