import AuroraModel
import Foundation
import XCTest

final class ProjectPackageAtomicSaveTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuroraAtomicSave-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testSuccessfulSaveReplacesPackage() throws {
        let packageURL = tempRoot.appendingPathComponent("Show.aurora", isDirectory: true)
        var project = ShowProject.empty(name: "V1")
        try ProjectPackage.save(project, to: packageURL)
        project.metadata.name = "V2"
        try ProjectPackage.save(project, to: packageURL)
        let loaded = try ProjectPackage.load(from: packageURL)
        XCTAssertEqual(loaded.metadata.name, "V2")
    }

    func testMediaPreservedOnResave() throws {
        let packageURL = tempRoot.appendingPathComponent("Media.aurora", isDirectory: true)
        let project = ShowProject.empty(name: "MediaShow")
        try ProjectPackage.save(project, to: packageURL)

        let mediaFile = packageURL
            .appendingPathComponent("media", isDirectory: true)
            .appendingPathComponent("clip.bin")
        let payload = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02])
        try payload.write(to: mediaFile)

        var renamed = project
        renamed.metadata.name = "MediaShow2"
        try ProjectPackage.save(renamed, to: packageURL)

        let preserved = try Data(contentsOf: mediaFile)
        XCTAssertEqual(preserved, payload)
    }

    func testSaveAsCopiesMediaFromExistingPackage() throws {
        let src = tempRoot.appendingPathComponent("Src.aurora", isDirectory: true)
        let dst = tempRoot.appendingPathComponent("Dst.aurora", isDirectory: true)
        let project = ShowProject.empty(name: "Copy")
        try ProjectPackage.save(project, to: src)
        let payload = Data("aurora-media".utf8)
        try payload.write(to: src.appendingPathComponent("media/clip.bin"))

        try FileManager.default.copyItem(at: src, to: dst)
        var p2 = project
        p2.metadata.notes = "after"
        try ProjectPackage.save(p2, to: dst)
        let copied = try Data(contentsOf: dst.appendingPathComponent("media/clip.bin"))
        XCTAssertEqual(copied, payload)
    }

    func testNoTempLeftoversAfterSave() throws {
        let packageURL = tempRoot.appendingPathComponent("Safe.aurora", isDirectory: true)
        var project = ShowProject.empty(name: "Original")
        try ProjectPackage.save(project, to: packageURL)
        project.metadata.name = "Updated"
        try ProjectPackage.save(project, to: packageURL)
        let leftovers = try FileManager.default.contentsOfDirectory(at: tempRoot, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains(".tmp-") || $0.lastPathComponent.contains(".bak-") }
        XCTAssertTrue(leftovers.isEmpty)
    }
}
