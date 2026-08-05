import AuroraModel
import XCTest

final class PaletteRefHelpersTests: XCTestCase {
    func testRecordPaletteRefAddsAndUpdates() {
        let palette = Palette(name: "Warm", type: .color, values: ["colorR": 1])
        let fxA = UUID()
        let fxB = UUID()
        var cue = Cue(number: 1, name: "Q1")
        cue.recordPaletteRef(palette: palette, fixtureIDs: [fxA])
        XCTAssertEqual(cue.levels.fixtures.count, 1)
        XCTAssertEqual(cue.levels.fixtures[0].paletteRefs["color"], palette.id)

        cue.recordPaletteRef(palette: palette, fixtureIDs: [fxA, fxB])
        XCTAssertEqual(cue.levels.fixtures.count, 2)
        XCTAssertEqual(
            cue.levels.fixtures.first { $0.fixtureId == fxB }?.paletteRefs["color"],
            palette.id
        )
    }

    func testRecordPaletteRefPreservesLiterals() {
        let palette = Palette(name: "Warm", type: .color, values: ["colorR": 1])
        let fx = UUID()
        var cue = Cue(
            number: 1,
            name: "Q1",
            levels: CueLevelData(fixtures: [
                FixtureCueLevels(fixtureId: fx, attributes: ["colorR": 0.5], paletteRefs: [:]),
            ])
        )
        cue.recordPaletteRef(palette: palette, fixtureIDs: [fx])
        XCTAssertEqual(cue.levels.fixtures[0].attributes["colorR"], 0.5)
        XCTAssertEqual(cue.levels.fixtures[0].paletteRefs["color"], palette.id)
    }

    func testTargetCuesPrefersSelectionThenFallback() {
        let cue1 = Cue(number: 1, name: "One")
        let cue2 = Cue(number: 2, name: "Two")
        let list = CueList(name: "Main", cues: [cue1, cue2])
        var project = ShowProject.sample()
        project.cueLists = [list]
        project.palettes = []

        let selected = project.targetCuesForPaletteRecord(selectedCueIDs: [cue2.id])
        XCTAssertEqual(selected.count, 1)
        XCTAssertEqual(selected[0].cue.id, cue2.id)

        let fallback = project.targetCuesForPaletteRecord(selectedCueIDs: [])
        XCTAssertEqual(fallback.count, 1)
        XCTAssertEqual(fallback[0].cue.id, cue1.id)

        let missing = project.targetCuesForPaletteRecord(selectedCueIDs: [UUID()])
        XCTAssertEqual(missing.count, 1)
        XCTAssertEqual(missing[0].cue.id, cue1.id)
    }

    func testPaletteReferenceCountAndSummaries() {
        let palette = Palette(name: "Warm", type: .color, values: [:])
        let fx = UUID()
        var cue = Cue(number: 1, name: "Look A")
        cue.recordPaletteRef(palette: palette, fixtureIDs: [fx])
        let list = CueList(name: "Main", cues: [cue])
        var project = ShowProject.sample()
        project.cueLists = [list]
        project.palettes = [palette]
        project.presets = []

        XCTAssertTrue(project.isPaletteReferenced(palette.id))
        XCTAssertEqual(project.paletteReferenceCount(palette.id), 1)
        let summaries = project.paletteReferenceCueSummaries(palette.id)
        XCTAssertEqual(summaries.count, 1)
        XCTAssertTrue(summaries[0].contains("Main"))
        XCTAssertTrue(summaries[0].contains("Look A"))
        XCTAssertEqual(project.paletteReferenceCount(UUID()), 0)
    }
}
