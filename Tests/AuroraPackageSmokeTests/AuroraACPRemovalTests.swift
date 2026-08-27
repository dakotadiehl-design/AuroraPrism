import Foundation
import XCTest

final class AuroraACPRemovalTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testProductionSourcesDoNotImportRetiredAuroraACP() throws {
        let sources = repositoryRoot.appendingPathComponent("Sources")
        let enumerator = FileManager.default.enumerator(
            at: sources,
            includingPropertiesForKeys: nil
        )
        let swiftFiles = (enumerator?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "swift" }

        for file in swiftFiles {
            let contents = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(contents.contains("import AuroraACP"), file.path)
            XCTAssertFalse(contents.contains("import PrismACP"), file.path)
        }
    }

    func testRetiredServiceIsAbsentFromBuildAndDiscoveryConfiguration() throws {
        let manifest = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let info = try String(
            contentsOf: repositoryRoot.appendingPathComponent("App/Info.plist"),
            encoding: .utf8
        )

        XCTAssertFalse(manifest.contains("AuroraCommunicationsProtocol"))
        XCTAssertFalse(manifest.contains("PrismACP"))
        XCTAssertFalse(info.contains("_acp._tcp"))
        let retiredSources = repositoryRoot.appendingPathComponent("Sources/PrismACP")
        let files = try? FileManager.default.contentsOfDirectory(
            at: retiredSources,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(files?.isEmpty ?? true)
    }

    func testProtocolNeutralControlBoundaryRemainsAvailable() throws {
        let router = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/Aurora/ControlActionRouter.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(router.contains("final class ControlActionRouter"))
        XCTAssertTrue(router.contains(".go"))
        XCTAssertTrue(router.contains(".back"))
        XCTAssertTrue(router.contains(".blackout"))
    }
}
