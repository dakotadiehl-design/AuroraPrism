import AuroraModel
import Foundation
import XCTest

/// P0-5: missing known schema v1 package files must fail load (not become empty).
final class ProjectPackageRequiredFilesTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuroraRequiredFiles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testMissingEachRequiredCollectionFileFailsLoad() throws {
        for fileName in ProjectPackage.schemaV1RequiredCollectionFiles {
            let packageURL = tempRoot.appendingPathComponent("Show-\(fileName).aurora", isDirectory: true)
            try ProjectPackage.save(ShowProject.empty(name: "Req"), to: packageURL)
            let target = packageURL.appendingPathComponent(fileName)
            try FileManager.default.removeItem(at: target)

            XCTAssertThrowsError(
                try ProjectPackage.load(from: packageURL),
                "Expected load failure when \(fileName) is missing"
            ) { error in
                guard case ProjectPackageError.missingFile(let name) = error else {
                    return XCTFail("Expected missingFile for \(fileName), got \(error)")
                }
                XCTAssertEqual(name, fileName)
            }
        }
    }

    func testMissingProjectJSONFailsLoad() throws {
        let packageURL = tempRoot.appendingPathComponent("NoRoot.aurora", isDirectory: true)
        try ProjectPackage.save(ShowProject.empty(name: "Req"), to: packageURL)
        try FileManager.default.removeItem(at: packageURL.appendingPathComponent("project.json"))

        XCTAssertThrowsError(try ProjectPackage.load(from: packageURL)) { error in
            guard case ProjectPackageError.missingFile(let name) = error else {
                return XCTFail("Expected missingFile, got \(error)")
            }
            XCTAssertEqual(name, "project.json")
        }
    }

    func testMissingCueListFileFailsLoad() throws {
        var project = ShowProject.empty(name: "Cues")
        let list = CueList(name: "Main", cues: [Cue(number: 1, name: "Q1")])
        project.cueLists = [list]
        let packageURL = tempRoot.appendingPathComponent("CueMissing.aurora", isDirectory: true)
        try ProjectPackage.save(project, to: packageURL)

        let cueFile = packageURL
            .appendingPathComponent("cues", isDirectory: true)
            .appendingPathComponent("\(list.id.uuidString).json")
        try FileManager.default.removeItem(at: cueFile)

        XCTAssertThrowsError(try ProjectPackage.load(from: packageURL)) { error in
            guard case ProjectPackageError.missingFile(let name) = error else {
                return XCTFail("Expected missingFile, got \(error)")
            }
            XCTAssertTrue(name.contains(list.id.uuidString))
        }
    }

    func testEmptyCollectionsStillLoadWhenFilesPresent() throws {
        let packageURL = tempRoot.appendingPathComponent("EmptyOK.aurora", isDirectory: true)
        try ProjectPackage.save(ShowProject.empty(name: "Empty"), to: packageURL)
        let loaded = try ProjectPackage.load(from: packageURL)
        XCTAssertTrue(loaded.fixtures.isEmpty)
        XCTAssertTrue(loaded.universes.isEmpty)
    }

    /// Post-C6 / v5: current-schema missing Stage/MIDI/effects/AME/cue-blocks files are package damage.
    func testMissingCurrentSchemaExtensionFilesFailLoad() throws {
        for fileName in [
            "stage-layout.json",
            "midi-rules.json",
            "midi-behaviors.json",
            "drum-profiles.json",
            "midi-feedback.json",
            "effects.json",
            "ame.json",
            "cue-blocks.json",
        ] {
            let packageURL = tempRoot.appendingPathComponent("Cur-\(fileName).aurora", isDirectory: true)
            try ProjectPackage.save(ShowProject.empty(name: "Cur"), to: packageURL)
            let target = packageURL.appendingPathComponent(fileName)
            try FileManager.default.removeItem(at: target)

            XCTAssertThrowsError(
                try ProjectPackage.load(from: packageURL),
                "Expected load failure when current-schema \(fileName) is missing"
            ) { error in
                guard case ProjectPackageError.missingFile(let name) = error else {
                    return XCTFail("Expected missingFile for \(fileName), got \(error)")
                }
                XCTAssertEqual(name, fileName)
            }
        }
    }

    func testLegacySchemaOneStillLoadsWithoutStageFile() throws {
        // Hand-build a minimal v1-shaped package: save current then rewrite schema + drop stage.
        let packageURL = tempRoot.appendingPathComponent("LegacyV1.aurora", isDirectory: true)
        var project = ShowProject.empty(name: "V1")
        project.schemaVersion = 1
        try ProjectPackage.save(project, to: packageURL)
        // After save, package is stamped currentSchemaVersion; rewrite project.json to v1
        // and remove stage-layout to simulate an old package.
        let projectJSON = packageURL.appendingPathComponent("project.json")
        var data = try Data(contentsOf: projectJSON)
        if var text = String(data: data, encoding: .utf8) {
            if let range = text.range(of: #"\"schemaVersion\"\s*:\s*\d+"#, options: .regularExpression) {
                text.replaceSubrange(range, with: "\"schemaVersion\" : 1")
            }
            data = Data(text.utf8)
            try data.write(to: projectJSON)
        }
        try? FileManager.default.removeItem(at: packageURL.appendingPathComponent("stage-layout.json"))
        try? FileManager.default.removeItem(at: packageURL.appendingPathComponent("effects.json"))
        try? FileManager.default.removeItem(at: packageURL.appendingPathComponent("midi-rules.json"))
        try? FileManager.default.removeItem(at: packageURL.appendingPathComponent("midi-behaviors.json"))
        try? FileManager.default.removeItem(at: packageURL.appendingPathComponent("drum-profiles.json"))
        try? FileManager.default.removeItem(at: packageURL.appendingPathComponent("midi-feedback.json"))
        try? FileManager.default.removeItem(at: packageURL.appendingPathComponent("ame.json"))
        try? FileManager.default.removeItem(at: packageURL.appendingPathComponent("cue-blocks.json"))

        let loaded = try ProjectPackage.load(from: packageURL)
        XCTAssertEqual(loaded.schemaVersion, ProjectPackage.currentSchemaVersion) // migrated up
        XCTAssertTrue(loaded.stageLayout.objects.isEmpty)
        XCTAssertTrue(loaded.cueBlocks.isEmpty)
    }
}
