import AuroraModel
import XCTest

final class AuroraModelTests: XCTestCase {
    func testModuleIdentity() {
        XCTAssertEqual(AuroraModelModule.name, "AuroraModel")
        XCTAssertFalse(AuroraModelModule.version.isEmpty)
        XCTAssertTrue(AuroraModelModule.version.contains("pr1"))
    }
}
