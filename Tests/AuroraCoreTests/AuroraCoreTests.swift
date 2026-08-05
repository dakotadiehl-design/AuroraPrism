import AuroraCore
import AuroraModel
import XCTest

final class AuroraCoreTests: XCTestCase {
    func testModuleIdentity() {
        XCTAssertEqual(AuroraCoreModule.name, "AuroraCore")
        XCTAssertFalse(AuroraCoreModule.version.isEmpty)
    }

    func testDependsOnModel() {
        XCTAssertEqual(AuroraCoreModule.modelModuleName, AuroraModelModule.name)
    }
}
