import AuroraUI
import XCTest

@MainActor
final class StageStockCatalogTests: XCTestCase {
    func testCatalogLoadsBundledAssets() {
        let catalog = StageStockCatalog.shared
        catalog.reload()
        XCTAssertTrue(catalog.didLoad)
        XCTAssertNil(catalog.loadError, catalog.loadError ?? "")
        // Corrected kit + C4.5 lighting stand / riser
        XCTAssertEqual(catalog.assets.count, 35, catalog.loadError ?? "no error")
        XCTAssertNotNil(catalog.asset(key: "stage.performers.drummer_full"))
        XCTAssertFalse(catalog.assets(in: .performers).isEmpty)
        XCTAssertFalse(catalog.assets(in: .truss).isEmpty)
        XCTAssertTrue(catalog.kitName?.contains("Corrected") == true)
    }
}
