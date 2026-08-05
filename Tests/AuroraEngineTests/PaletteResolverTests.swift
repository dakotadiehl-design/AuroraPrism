import AuroraEngine
import AuroraModel
import XCTest

final class PaletteResolverTests: XCTestCase {
    func testPaletteRefResolvesAndUpdates() {
        let paletteID = UUID()
        let fixtureID = UUID()
        var project = ShowProject.empty()
        project.palettes = [
            Palette(id: paletteID, name: "Warm Amber", type: .color, values: [
                "colorR": 1, "colorG": 0.5, "colorB": 0.1,
            ])
        ]
        let levels = CueLevelData(fixtures: [
            FixtureCueLevels(fixtureId: fixtureID, paletteRefs: ["color": paletteID])
        ])
        let r1 = PaletteResolver.resolve(levels: levels, project: project)
        XCTAssertEqual(r1.levels.fixtures[0].attributes["colorR"], 1)
        XCTAssertTrue(r1.issues.isEmpty)

        project.palettes[0].values["colorR"] = 0.2
        let r2 = PaletteResolver.resolve(levels: levels, project: project)
        XCTAssertEqual(r2.levels.fixtures[0].attributes["colorR"], 0.2)
    }

    func testLiteralWinsOverRef() {
        let paletteID = UUID()
        let fixtureID = UUID()
        var project = ShowProject.empty()
        project.palettes = [
            Palette(id: paletteID, name: "X", type: .color, values: ["colorR": 1])
        ]
        let levels = CueLevelData(fixtures: [
            FixtureCueLevels(
                fixtureId: fixtureID,
                attributes: ["colorR": 0.25],
                paletteRefs: ["color": paletteID]
            )
        ])
        let r = PaletteResolver.resolve(levels: levels, project: project)
        XCTAssertEqual(r.levels.fixtures[0].attributes["colorR"], 0.25)
    }

    func testMissingPaletteIssues() {
        let fixtureID = UUID()
        let missing = UUID()
        let project = ShowProject.empty()
        let levels = CueLevelData(fixtures: [
            FixtureCueLevels(fixtureId: fixtureID, paletteRefs: ["color": missing])
        ])
        let r = PaletteResolver.resolve(levels: levels, project: project)
        XCTAssertFalse(r.issues.isEmpty)
        XCTAssertTrue(r.levels.fixtures[0].attributes.isEmpty)
    }

    func testCueResolverUsesProjectPalettes() {
        let paletteID = UUID()
        let fixtureID = UUID()
        var project = ShowProject.empty()
        project.palettes = [
            Palette(id: paletteID, name: "Warm", type: .intensity, values: ["intensity": 0.8])
        ]
        let cue = Cue(
            number: 1,
            levels: CueLevelData(fixtures: [
                FixtureCueLevels(fixtureId: fixtureID, paletteRefs: ["intensity": paletteID])
            ])
        )
        let look = CueResolver.resolveLook(cues: [cue], index: 0, project: project)
        XCTAssertEqual(look.fixtureAttributes[fixtureID]?["intensity"], 0.8)
    }

    func testIncompatiblePaletteTypeSkipped() {
        let paletteID = UUID()
        let fixtureID = UUID()
        var project = ShowProject.empty()
        project.palettes = [
            Palette(id: paletteID, name: "Warm", type: .color, values: ["colorR": 1])
        ]
        let levels = CueLevelData(fixtures: [
            FixtureCueLevels(fixtureId: fixtureID, paletteRefs: ["intensity": paletteID])
        ])
        let r = PaletteResolver.resolve(levels: levels, project: project)
        XCTAssertFalse(r.issues.isEmpty)
        XCTAssertNil(r.levels.fixtures[0].attributes["colorR"])
    }
}
