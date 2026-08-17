import AuroraModel
import Foundation
import XCTest

final class PrismRebrandCompatibilityTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrismRebrand-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
    }

    func testProjectExtensionsPreferPrismAndRetainAuroraLegacySupport() {
        XCTAssertEqual(ProjectPackage.packageExtension, "prism")
        XCTAssertEqual(ProjectPackage.legacyPackageExtension, "aurora")
        XCTAssertTrue(ProjectPackage.isSupportedPackageExtension("prism"))
        XCTAssertTrue(ProjectPackage.isSupportedPackageExtension("AURORA"))
        XCTAssertFalse(ProjectPackage.isSupportedPackageExtension("show"))
    }

    func testLegacyProjectMigrationUsesSiblingPrismURL() {
        let legacy = URL(fileURLWithPath: "/tmp/Haywire.aurora")
        XCTAssertTrue(ProjectPackage.isLegacyPackageURL(legacy))
        XCTAssertEqual(
            ProjectPackage.preferredPackageURL(for: legacy).path,
            "/tmp/Haywire.prism"
        )
    }

    func testCurrentProjectURLIsNotRewritten() {
        let current = URL(fileURLWithPath: "/tmp/Haywire.prism")
        XCTAssertFalse(ProjectPackage.isLegacyPackageURL(current))
        XCTAssertEqual(ProjectPackage.preferredPackageURL(for: current), current)
    }

    func testLibraryExtensionsPreferPrismAndRetainAuroraLegacyName() {
        XCTAssertEqual(AuroraLibraryPackage.packageExtension, "prismlib")
        XCTAssertEqual(AuroraLibraryPackage.legacyPackageExtension, "auroralib")
    }

    func testPrismProjectPackageRoundTripUsesUnchangedSchema() throws {
        let url = temporaryRoot.appendingPathComponent("Current.prism", isDirectory: true)
        let project = ShowProject.empty(name: "Current")
        try ProjectPackage.save(project, to: url)

        let loaded = try ProjectPackage.load(from: url)
        XCTAssertEqual(loaded.metadata.name, "Current")
        XCTAssertEqual(loaded.schemaVersion, ProjectPackage.currentSchemaVersion)
    }

    func testLegacyAuroraPackageStillLoads() throws {
        let url = temporaryRoot.appendingPathComponent("Legacy.aurora", isDirectory: true)
        try ProjectPackage.save(.empty(name: "Legacy"), to: url)

        XCTAssertEqual(try ProjectPackage.load(from: url).metadata.name, "Legacy")
    }
}
