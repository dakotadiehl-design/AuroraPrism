import AuroraModel
import XCTest

final class AuroraLibraryPackageTests: XCTestCase {
    func testRoundTripLibrary() throws {
        var project = ShowProject.empty(name: "LibSrc")
        let def = FixtureDefinition(
            manufacturer: "User",
            model: "Wash",
            channels: [ChannelDef(offset: 1, name: "I", attribute: "intensity")]
        )
        project.fixtureDefinitions = [def]
        project.midiBehaviors = [
            MIDIBehaviorDefinition(name: "Kick", drumRole: .kick, attribute: "intensity"),
        ]
        project.drumProfiles = [.generalMIDIKit]
        project.midiFeedbackProfiles = [MIDIFeedbackProfile(name: "Board", masterIntensityCC: 7)]

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aurora-lib-\(UUID().uuidString).auroralib")
        defer { try? FileManager.default.removeItem(at: dir) }

        let contents = AuroraLibraryPackage.Contents.from(project: project, name: "TestLib")
        try AuroraLibraryPackage.save(contents, to: dir)
        let loaded = try AuroraLibraryPackage.load(from: dir)
        XCTAssertEqual(loaded.manifest.name, "TestLib")
        XCTAssertEqual(loaded.fixtureDefinitions.count, 1)
        XCTAssertEqual(loaded.midiBehaviors.count, 1)
        XCTAssertEqual(loaded.drumProfiles.count, 1)
        XCTAssertEqual(loaded.feedbackProfiles.first?.masterIntensityCC, 7)

        var target = ShowProject.empty(name: "Target")
        AuroraLibraryPackage.merge(loaded, into: &target)
        XCTAssertEqual(target.fixtureDefinitions.count, 1)
        XCTAssertEqual(target.midiBehaviors.count, 1)
    }

    func testMissingPalettesJSONFailsLoad() throws {
        var project = ShowProject.empty(name: "Lib")
        project.fixtureDefinitions = [
            FixtureDefinition(
                manufacturer: "U", model: "W",
                channels: [ChannelDef(offset: 1, name: "I", attribute: "intensity")]
            )
        ]
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aurora-lib-miss-\(UUID().uuidString).auroralib")
        defer { try? FileManager.default.removeItem(at: dir) }
        try AuroraLibraryPackage.save(
            .from(project: project, name: "Miss"),
            to: dir
        )
        try FileManager.default.removeItem(at: dir.appendingPathComponent("palettes.json"))
        XCTAssertThrowsError(try AuroraLibraryPackage.load(from: dir)) { error in
            guard case AuroraLibraryPackage.LibraryError.missingFile(let name) = error else {
                return XCTFail("Expected missingFile, got \(error)")
            }
            XCTAssertEqual(name, "palettes.json")
        }
    }

    func testPackagePersistsBehaviors() throws {
        var project = ShowProject.empty(name: "Pkg")
        project.midiBehaviors = [MIDIBehaviorDefinition(name: "Snare", drumRole: .snare)]
        project.drumProfiles = [.generalMIDIKit]
        project.midiFeedbackProfiles = [MIDIFeedbackProfile()]

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("aurora-beh-\(UUID().uuidString).aurora")
        defer { try? FileManager.default.removeItem(at: url) }
        try ProjectPackage.save(project, to: url)
        let loaded = try ProjectPackage.load(from: url)
        XCTAssertEqual(loaded.schemaVersion, ProjectPackage.currentSchemaVersion)
        XCTAssertEqual(loaded.midiBehaviors.count, 1)
        XCTAssertFalse(loaded.drumProfiles.isEmpty)
        XCTAssertEqual(loaded.midiFeedbackProfiles.count, 1)
    }
}
