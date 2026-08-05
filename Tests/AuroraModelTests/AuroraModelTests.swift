import AuroraModel
import Foundation
import XCTest

final class AuroraModelTests: XCTestCase {
    func testModuleIdentity() {
        XCTAssertEqual(AuroraModelModule.name, "AuroraModel")
        XCTAssertFalse(AuroraModelModule.version.isEmpty)
        XCTAssertTrue(AuroraModelModule.version.contains("pr2"))
        XCTAssertEqual(AuroraModelModule.schemaVersion, ProjectPackage.currentSchemaVersion)
    }

    func testEmptyProjectDefaults() {
        let project = ShowProject.empty(name: "Demo")
        XCTAssertEqual(project.metadata.name, "Demo")
        XCTAssertEqual(project.schemaVersion, ProjectPackage.currentSchemaVersion)
        XCTAssertTrue(project.fixtures.isEmpty)
        XCTAssertTrue(project.universes.isEmpty)
        XCTAssertEqual(project.preferences.preferredFrameRateHz, 40)
    }

    func testSampleProjectStructure() {
        let sample = ShowProject.sample()
        XCTAssertEqual(sample.metadata.name, "Sample Show")
        XCTAssertEqual(sample.universes.count, 1)
        XCTAssertEqual(sample.fixtures.count, 1)
        XCTAssertEqual(sample.fixtureDefinitions.count, 1)
        XCTAssertEqual(sample.cueLists.count, 1)
        XCTAssertEqual(sample.cueLists[0].cues.count, 1)
        XCTAssertEqual(sample.cueLists[0].cues[0].number, Decimal(string: "1.0"))
        XCTAssertEqual(sample.songs.count, 1)
        XCTAssertTrue(sample.overlappingPatchRanges().isEmpty)
    }

    func testPatchOverlapDetection() {
        let universeID = UUID()
        let defID = UUID()
        let definition = FixtureDefinition(
            id: defID,
            manufacturer: "Generic",
            model: "Dimmer",
            channelCount: 1,
            channels: [
                ChannelDef(offset: 1, name: "Int", attribute: "intensity")
            ]
        )
        let a = PatchedFixture(name: "A", definitionId: defID, universeId: universeID, address: 1)
        let b = PatchedFixture(name: "B", definitionId: defID, universeId: universeID, address: 1)
        let project = ShowProject(
            metadata: ProjectMetadata(name: "Overlap"),
            fixtureDefinitions: [definition],
            universes: [Universe(id: universeID, number: 1)],
            fixtures: [a, b]
        )
        let overlaps = project.overlappingPatchRanges()
        XCTAssertEqual(overlaps.count, 1)
        XCTAssertEqual(overlaps[0].universeId, universeID)
    }

    func testPackageRoundTripGoldenSample() throws {
        let original = ShowProject.sample()
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuroraModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let packageURL = tempRoot.appendingPathComponent("Sample.aurora", isDirectory: true)
        try ProjectPackage.save(original, to: packageURL)

        // Package is a directory with expected files.
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.path, isDirectory: &isDir) && isDir.boolValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("project.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("universes.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("cues").path))

        let loaded = try ProjectPackage.load(from: packageURL)

        XCTAssertEqual(loaded.schemaVersion, ProjectPackage.currentSchemaVersion)
        XCTAssertEqual(loaded.metadata.name, original.metadata.name)
        XCTAssertEqual(loaded.metadata.author, original.metadata.author)
        XCTAssertEqual(loaded.metadata.notes, original.metadata.notes)
        // ISO-8601 date coding is second-precision; compare via timeInterval.
        XCTAssertEqual(
            loaded.metadata.createdAt.timeIntervalSince1970,
            original.metadata.createdAt.timeIntervalSince1970,
            accuracy: 1
        )
        XCTAssertEqual(loaded.preferences, original.preferences)
        XCTAssertEqual(loaded.fixtureDefinitions, original.fixtureDefinitions)
        XCTAssertEqual(loaded.universes, original.universes)
        XCTAssertEqual(loaded.fixtures, original.fixtures)
        XCTAssertEqual(loaded.groups, original.groups)
        XCTAssertEqual(loaded.palettes, original.palettes)
        XCTAssertEqual(loaded.presets, original.presets)
        XCTAssertEqual(loaded.cueLists, original.cueLists)
        XCTAssertEqual(loaded.songs, original.songs)
        XCTAssertEqual(loaded.mediaAssets, original.mediaAssets)
        XCTAssertEqual(loaded.midiMappings, original.midiMappings)
        XCTAssertEqual(loaded.workspaceLayoutId, original.workspaceLayoutId)
    }

    func testPackageRoundTripEmptyProject() throws {
        let original = ShowProject.empty(name: "Blank")
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuroraModelTests-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let packageURL = tempRoot.appendingPathComponent("Blank.aurora", isDirectory: true)
        try ProjectPackage.save(original, to: packageURL)
        let loaded = try ProjectPackage.load(from: packageURL)

        XCTAssertEqual(loaded.metadata.name, "Blank")
        XCTAssertTrue(loaded.fixtures.isEmpty)
        XCTAssertTrue(loaded.cueLists.isEmpty)
        XCTAssertEqual(loaded.schemaVersion, 1)
    }

    func testUnsupportedSchemaVersion() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuroraModelTests-schema-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let packageURL = tempRoot.appendingPathComponent("Future.aurora", isDirectory: true)
        try ProjectPackage.save(ShowProject.empty(), to: packageURL)

        // Bump schemaVersion in project.json beyond what we support.
        let projectJSON = packageURL.appendingPathComponent("project.json")
        let data = try Data(contentsOf: projectJSON)
        var root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        root["schemaVersion"] = 999
        let updated = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try updated.write(to: projectJSON)

        XCTAssertThrowsError(try ProjectPackage.load(from: packageURL)) { error in
            guard case ProjectPackageError.unsupportedSchemaVersion(let found, let max) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(found, 999)
            XCTAssertEqual(max, ProjectPackage.currentSchemaVersion)
        }
    }

    func testLoadMissingPackageThrows() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).aurora")
        XCTAssertThrowsError(try ProjectPackage.load(from: missing)) { error in
            guard case ProjectPackageError.notADirectory = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testCueNumberDecimalRoundTripInJSON() throws {
        let cue = Cue(number: Decimal(string: "12.5")!, name: "Break")
        let list = CueList(name: "A", cues: [cue])
        let data = try ProjectPackage.makeEncoder().encode(list)
        let decoded = try ProjectPackage.makeDecoder().decode(CueList.self, from: data)
        XCTAssertEqual(decoded.cues[0].number, Decimal(string: "12.5"))
    }
}
