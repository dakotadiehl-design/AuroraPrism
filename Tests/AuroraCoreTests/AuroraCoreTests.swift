import AuroraCore
import AuroraModel
import XCTest

final class AuroraCoreTests: XCTestCase {
    func testModuleIdentity() {
        XCTAssertEqual(AuroraCoreModule.name, "AuroraCore")
        XCTAssertFalse(AuroraCoreModule.version.isEmpty)
        XCTAssertTrue(AuroraCoreModule.version.contains("pr12"))
    }

    func testDependsOnModel() {
        XCTAssertEqual(AuroraCoreModule.modelModuleName, AuroraModelModule.name)
    }
}
