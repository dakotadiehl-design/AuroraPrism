import AuroraDiagnostics
@testable import AuroraModel
import XCTest

final class ProjectPackageLoggingTests: XCTestCase {
    override func tearDown() {
        PrismLog.resetForTests()
        super.tearDown()
    }

    func testSaveEmitsSavedButNotOpened() throws {
        let sink = InMemoryPrismLogSink()
        PrismLog.shared = sink
        PrismLogConfigurationStore.shared.replace(.verboseAll)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("Logging.prism")

        try ProjectPackage.save(.empty(name: "Logging"), to: url)

        XCTAssertEqual(sink.snapshot().filter { $0.code == "project.document.saved" }.count, 1)
        XCTAssertFalse(sink.snapshot().contains(where: { $0.code == "project.document.opened" }))
    }
}
