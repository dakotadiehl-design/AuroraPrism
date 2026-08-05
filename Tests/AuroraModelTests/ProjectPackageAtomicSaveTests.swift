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

    /// Ordinary Save As: destination does not exist; assets come from the open source package.
    func testTrueSaveAsPreservesSourceMediaAndLayouts() throws {
        let src = tempRoot.appendingPathComponent("Src.aurora", isDirectory: true)
        let dst = tempRoot.appendingPathComponent("Dst.aurora", isDirectory: true)
        let project = ShowProject.empty(name: "Copy")
        try ProjectPackage.save(project, to: src)

        let mediaPayload = Data("aurora-media".utf8)
        let nestedMedia = src
            .appendingPathComponent("media", isDirectory: true)
            .appendingPathComponent("audio", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedMedia, withIntermediateDirectories: true)
        try mediaPayload.write(to: nestedMedia.appendingPathComponent("intro.wav"))

        let layoutPayload = Data(#"{"panel":"programming"}"#.utf8)
        let layoutsDir = src.appendingPathComponent("layouts", isDirectory: true)
        try FileManager.default.createDirectory(at: layoutsDir, withIntermediateDirectories: true)
        try layoutPayload.write(to: layoutsDir.appendingPathComponent("programming.json"))

        XCTAssertFalse(FileManager.default.fileExists(atPath: dst.path))

        var p2 = project
        p2.metadata.notes = "after-save-as"
        try ProjectPackage.save(p2, to: dst, preservingAssetsFrom: src)

        let copiedMedia = try Data(contentsOf: dst
            .appendingPathComponent("media/audio/intro.wav"))
        XCTAssertEqual(copiedMedia, mediaPayload)

        let copiedLayout = try Data(contentsOf: dst
            .appendingPathComponent("layouts/programming.json"))
        XCTAssertEqual(copiedLayout, layoutPayload)

        // Source and destination remain independent after Save As.
        try Data("mutated".utf8).write(to: dst.appendingPathComponent("media/audio/intro.wav"))
        let sourceStillOriginal = try Data(contentsOf: nestedMedia.appendingPathComponent("intro.wav"))
        XCTAssertEqual(sourceStillOriginal, mediaPayload)
    }

    /// Without an explicit asset source, Save As to a new path cannot invent media.
    func testSaveAsWithoutAssetSourceOmitsSourceMedia() throws {
        let src = tempRoot.appendingPathComponent("SrcOnly.aurora", isDirectory: true)
        let dst = tempRoot.appendingPathComponent("DstEmpty.aurora", isDirectory: true)
        let project = ShowProject.empty(name: "NoSource")
        try ProjectPackage.save(project, to: src)
        try Data("secret".utf8).write(to: src.appendingPathComponent("media/clip.bin"))

        try ProjectPackage.save(project, to: dst) // no preservingAssetsFrom
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: dst.appendingPathComponent("media/clip.bin").path)
        )
    }

    func testEffectsRoundTripOnSaveLoad() throws {
        let packageURL = tempRoot.appendingPathComponent("Fx.aurora", isDirectory: true)
        var project = ShowProject.empty(name: "Fx")
        let fxID = UUID()
        let fixID = UUID()
        project.effects = [
            EffectDefinition(
                id: fxID,
                name: "Pulse 1",
                kind: "pulse",
                rateHz: 2,
                size: 0.4,
                fixtureIDs: [fixID],
                order: 3,
                enabled: true
            )
        ]
        try ProjectPackage.save(project, to: packageURL)
        let loaded = try ProjectPackage.load(from: packageURL)
        XCTAssertEqual(loaded.effects.count, 1)
        XCTAssertEqual(loaded.effects[0].id, fxID)
        XCTAssertEqual(loaded.effects[0].order, 3)
        XCTAssertEqual(loaded.effects[0].fixtureIDs, [fixID])
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("effects.json").path))
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
