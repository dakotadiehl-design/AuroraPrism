import AuroraCore
import AuroraEngine
import AuroraModel
import XCTest

final class ProgrammerCueBridgeTests: XCTestCase {

    func testLevelsAreEmpty() {
        XCTAssertTrue(ProgrammerCueBridge.levelsAreEmpty(.empty))
        XCTAssertTrue(ProgrammerCueBridge.levelsAreEmpty(
            CueLevelData(fixtures: [FixtureCueLevels(fixtureId: UUID(), attributes: [:])])
        ))
        XCTAssertFalse(ProgrammerCueBridge.levelsAreEmpty(
            CueLevelData(fixtures: [
                FixtureCueLevels(fixtureId: UUID(), attributes: ["intensity": 0.5])
            ])
        ))
    }

    func testResolveUpdateTargetPrefersCueID() {
        let listID = UUID()
        let cueA = Cue(number: 1, name: "A")
        let cueB = Cue(number: 2, name: "B")
        var project = ShowProject.empty(name: "T")
        project.cueLists = [CueList(id: listID, name: "Main", cues: [cueA, cueB])]

        let target = ProgrammerCueBridge.resolveUpdateTarget(
            project: project,
            preferredListID: listID,
            preferredCueID: cueB.id
        )
        XCTAssertEqual(target?.cue.id, cueB.id)
        XCTAssertEqual(target?.listID, listID)
    }

    func testResolveUpdateTargetFallsBackToFirstCue() {
        let cue = Cue(number: 1, name: "Only")
        var project = ShowProject.empty(name: "T")
        project.cueLists = [CueList(name: "Main", cues: [cue])]

        let target = ProgrammerCueBridge.resolveUpdateTarget(
            project: project,
            preferredListID: nil,
            preferredCueID: nil
        )
        XCTAssertEqual(target?.cue.id, cue.id)
    }

    func testMakeRecordedCueUsesNextNumberAndLevels() {
        let list = CueList(name: "Main", cues: [Cue(number: 3, name: "Existing")])
        let levels = CueLevelData(fixtures: [
            FixtureCueLevels(fixtureId: UUID(), attributes: ["colorR": 1, "intensity": 0.8])
        ])
        let cue = ProgrammerCueBridge.makeRecordedCue(
            levels: levels,
            list: list,
            preferences: .default
        )
        XCTAssertEqual(cue.number, 4)
        XCTAssertEqual(cue.levels.fixtures.count, 1)
        XCTAssertEqual(cue.levels.fixtures[0].attributes["intensity"], 0.8)
    }

    func testCueByApplyingLevelsPreservesMetadata() {
        var original = Cue(number: 1, name: "Test Cue", fadeIn: 2, fadeOut: 1)
        original.tracking = .track
        let levels = CueLevelData(fixtures: [
            FixtureCueLevels(fixtureId: UUID(), attributes: ["colorB": 0.4])
        ])
        let updated = ProgrammerCueBridge.cueByApplyingLevels(original, levels: levels)
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.name, "Test Cue")
        XCTAssertEqual(updated.fadeIn, 2)
        XCTAssertEqual(updated.levels.fixtures.first?.attributes["colorB"], 0.4)
    }

    func testProgrammerCaptureThenUpdateRoundTripThroughPackage() throws {
        let fxID = UUID()
        let listID = UUID()
        let cueID = UUID()
        var project = ShowProject.empty(name: "RoundTrip")
        project.cueLists = [
            CueList(
                id: listID,
                name: "List 1",
                cues: [Cue(id: cueID, number: 1, name: "Test Cue")]
            )
        ]

        let programmer = Programmer()
        programmer.setMany([
            fxID: ["intensity": 0.75, "colorR": 0.2, "colorG": 0.4, "colorB": 0.9]
        ])
        let levels = programmer.captureLevels()
        XCTAssertFalse(ProgrammerCueBridge.levelsAreEmpty(levels))

        guard let target = ProgrammerCueBridge.resolveUpdateTarget(
            project: project,
            preferredListID: listID,
            preferredCueID: cueID
        ) else {
            return XCTFail("expected update target")
        }
        let updatedCue = ProgrammerCueBridge.cueByApplyingLevels(target.cue, levels: levels)
        project.cueLists[0].cues[0] = updatedCue

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProgCue-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Show.prism", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try ProjectPackage.save(project, to: url)

        let loaded = try ProjectPackage.load(from: url)
        let loadedLevels = loaded.cueLists[0].cues[0].levels
        XCTAssertEqual(loadedLevels.fixtures.count, 1)
        XCTAssertEqual(loadedLevels.fixtures[0].fixtureId, fxID)
        XCTAssertEqual(loadedLevels.fixtures[0].attributes["intensity"], 0.75)
        XCTAssertEqual(loadedLevels.fixtures[0].attributes["colorB"], 0.9)
    }
}
