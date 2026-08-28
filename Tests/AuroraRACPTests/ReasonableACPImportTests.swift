import ReasonableACP
import XCTest

final class ReasonableACPImportTests: XCTestCase {
    func testPublicModuleIsVisible() throws {
        let hello = try RACPHello(peerType: "prism", peerID: "dependency-spike")

        XCTAssertEqual(hello.peerType, "prism")
        XCTAssertEqual(hello.peerID, "dependency-spike")
        XCTAssertEqual(hello.capabilities, [])
    }
}
