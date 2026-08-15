import AuroraModel
import XCTest

final class PackageRecoveryTests: XCTestCase {
    func testRecoverOrphanBackupWhenDestinationMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuroraRecover-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let dest = root.appendingPathComponent("Show.aurora", isDirectory: true)
        try ProjectPackage.save(ShowProject.empty(name: "Live"), to: dest)
        let bak = root.appendingPathComponent(".Show.aurora.bak-test", isDirectory: true)
        try FileManager.default.moveItem(at: dest, to: bak)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))

        let recovered = try ProjectPackage.recoverOrphanedPackages(around: dest)
        XCTAssertEqual(recovered?.path, dest.path)
        let loaded = try ProjectPackage.load(from: dest)
        XCTAssertEqual(loaded.metadata.name, "Live")
    }

    func testSchemaMigrationV1ToCurrent() throws {
        var p = ShowProject.empty(name: "M")
        p.schemaVersion = 1
        let migrated = try SchemaMigration.migrate(p)
        XCTAssertEqual(migrated.schemaVersion, ProjectPackage.currentSchemaVersion)
        XCTAssertEqual(migrated.stageLayout, .empty)
    }
}
