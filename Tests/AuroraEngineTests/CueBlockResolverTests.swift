import AuroraEngine
import AuroraModel
import Foundation
import XCTest

final class CueBlockResolverTests: XCTestCase {
    func testDuplicateCueBlockIDsDoNotTrapAndFirstWins() {
        let fx = UUID()
        var project = rgbProject(fixtureIDs: [fx])
        let sharedID = UUID()
        let first = CueBlock(
            id: sharedID,
            name: "First",
            type: .intensity,
            levels: CueLevelData(fixtures: [FixtureCueLevels(fixtureId: fx, attributes: ["intensity": 0.25])])
        )
        let duplicate = CueBlock(
            id: sharedID,
            name: "Duplicate",
            type: .intensity,
            levels: CueLevelData(fixtures: [FixtureCueLevels(fixtureId: fx, attributes: ["intensity": 0.9])])
        )
        project.cueBlocks = [first, duplicate]
        let cue = Cue(number: 1, cueBlockRefs: [CueBlockReference(cueBlockID: sharedID)])

        let result = CueBlockResolver.resolveCueLevels(cue: cue, project: project)
        XCTAssertEqual(result.levels.fixtures.first?.attributes["intensity"], 0.25)
    }

    private func rgbProject(fixtureIDs: [UUID]) -> ShowProject {
        var project = ShowProject.empty(name: "RGB")
        let def = FixtureDefinition(
            id: UUID(),
            manufacturer: "Generic",
            model: "RGB",
            channelCount: 4,
            channels: [
                ChannelDef(offset: 1, name: "Dim", attribute: "intensity"),
                ChannelDef(offset: 2, name: "R", attribute: "colorR"),
                ChannelDef(offset: 3, name: "G", attribute: "colorG"),
                ChannelDef(offset: 4, name: "B", attribute: "colorB"),
            ],
            colorModel: .rgb
        )
        project.fixtureDefinitions = [def]
        let u = Universe(id: UUID(), number: 1, name: "U1")
        project.universes = [u]
        project.fixtures = fixtureIDs.enumerated().map { i, id in
            PatchedFixture(
                id: id,
                name: "F\(i + 1)",
                definitionId: def.id,
                universeId: u.id,
                address: UInt16(1 + i * 4)
            )
        }
        return project
    }

    func testEmptyRefsMatchesPaletteOnlyPath() {
        let fx = UUID()
        var project = rgbProject(fixtureIDs: [fx])
        let palette = Palette(id: UUID(), name: "Blue", type: .color, values: ["colorB": 1, "colorR": 0, "colorG": 0])
        project.palettes = [palette]
        let cue = Cue(
            number: 1,
            levels: CueLevelData(fixtures: [
                FixtureCueLevels(fixtureId: fx, attributes: ["intensity": 0.5], paletteRefs: ["color": palette.id])
            ])
        )
        project.cueLists = [CueList(name: "M", cues: [cue])]

        let legacy = PaletteResolver.resolve(levels: cue.levels, project: project, cueID: cue.id)
        let composed = CueBlockResolver.resolveCueLevels(cue: cue, project: project)
        XCTAssertEqual(composed.levels.fixtures.first?.attributes["intensity"], 0.5)
        XCTAssertEqual(composed.levels.fixtures.first?.attributes["colorB"], 1)
        // Same keys as legacy palette path for this fixture.
        let composedKeys = Set(composed.levels.fixtures.first?.attributes.keys.map { $0 } ?? [String]())
        let legacyKeys = Set(legacy.levels.fixtures.first?.attributes.keys.map { $0 } ?? [String]())
        XCTAssertEqual(composedKeys, legacyKeys)
    }

    func testLaterBlockWinsAndLiteralWinsOverBlocks() {
        let fx = UUID()
        var project = rgbProject(fixtureIDs: [fx])
        let dim50 = CueBlock(
            name: "50%",
            type: .intensity,
            levels: CueLevelData(fixtures: [FixtureCueLevels(fixtureId: fx, attributes: ["intensity": 0.5])])
        )
        let dim75 = CueBlock(
            name: "75%",
            type: .intensity,
            levels: CueLevelData(fixtures: [FixtureCueLevels(fixtureId: fx, attributes: ["intensity": 0.75])])
        )
        project.cueBlocks = [dim50, dim75]
        let cue = Cue(
            number: 1,
            levels: CueLevelData(fixtures: [
                FixtureCueLevels(fixtureId: fx, attributes: ["intensity": 0.65])
            ]),
            cueBlockRefs: [
                CueBlockReference(cueBlockID: dim50.id),
                CueBlockReference(cueBlockID: dim75.id),
            ]
        )
        let result = CueBlockResolver.resolveCueLevels(cue: cue, project: project)
        XCTAssertEqual(result.levels.fixtures.first?.attributes["intensity"], 0.65)
    }

    func testMultipleBlocksCombineNonConflicting() {
        let fx = UUID()
        var project = rgbProject(fixtureIDs: [fx])
        let color = CueBlock(
            name: "Blue",
            type: .color,
            levels: CueLevelData(fixtures: [
                FixtureCueLevels(fixtureId: fx, attributes: ["colorB": 1, "colorR": 0, "colorG": 0])
            ])
        )
        let dim = CueBlock(
            name: "75%",
            type: .intensity,
            levels: CueLevelData(fixtures: [
                FixtureCueLevels(fixtureId: fx, attributes: ["intensity": 0.75])
            ])
        )
        project.cueBlocks = [color, dim]
        let cue = Cue(
            number: 1,
            cueBlockRefs: [
                CueBlockReference(cueBlockID: color.id),
                CueBlockReference(cueBlockID: dim.id),
            ]
        )
        let look = CueResolver.resolveLook(cues: [cue], index: 0, project: project)
        XCTAssertEqual(look.fixtureAttributes[fx]?["intensity"], 0.75)
        XCTAssertEqual(look.fixtureAttributes[fx]?["colorB"], 1)
    }

    func testDisabledReferenceContributesNothing() {
        let fx = UUID()
        var project = rgbProject(fixtureIDs: [fx])
        let dim = CueBlock(
            name: "100%",
            type: .intensity,
            levels: CueLevelData(fixtures: [FixtureCueLevels(fixtureId: fx, attributes: ["intensity": 1])])
        )
        project.cueBlocks = [dim]
        let cue = Cue(
            number: 1,
            cueBlockRefs: [CueBlockReference(cueBlockID: dim.id, enabled: false)]
        )
        let result = CueBlockResolver.resolveCueLevels(cue: cue, project: project)
        XCTAssertTrue(result.levels.fixtures.isEmpty)
    }

    func testMissingBlockIssuesAndContinues() {
        let fx = UUID()
        var project = rgbProject(fixtureIDs: [fx])
        let good = CueBlock(
            name: "Good",
            type: .intensity,
            levels: CueLevelData(fixtures: [FixtureCueLevels(fixtureId: fx, attributes: ["intensity": 0.4])])
        )
        project.cueBlocks = [good]
        let missing = UUID()
        let cue = Cue(
            number: 1,
            cueBlockRefs: [
                CueBlockReference(cueBlockID: missing, enabled: true),
                CueBlockReference(cueBlockID: good.id, enabled: true),
            ]
        )
        let detailed = CueResolver.resolveLookDetailed(cues: [cue], index: 0, project: project)
        XCTAssertEqual(detailed.look.fixtureAttributes[fx]?["intensity"], 0.4)
        XCTAssertTrue(detailed.issues.contains { $0.code == "missing-cue-block" })
    }

    func testLiveUpdateChangesReferencingCues() {
        let fx = UUID()
        var project = rgbProject(fixtureIDs: [fx])
        var block = CueBlock(
            id: UUID(),
            name: "Blue",
            type: .color,
            levels: CueLevelData(fixtures: [
                FixtureCueLevels(fixtureId: fx, attributes: ["colorB": 1, "colorR": 0, "colorG": 0])
            ])
        )
        project.cueBlocks = [block]
        let cues = (0..<3).map { i in
            Cue(
                number: Decimal(i + 1),
                cueBlockRefs: [CueBlockReference(cueBlockID: block.id)]
            )
        }
        for i in 0..<3 {
            let look = CueResolver.resolveLook(cues: cues, index: i, project: project)
            XCTAssertEqual(look.fixtureAttributes[fx]?["colorB"], 1)
        }
        block.levels = CueLevelData(fixtures: [
            FixtureCueLevels(fixtureId: fx, attributes: ["colorB": 0.2, "colorR": 0, "colorG": 0])
        ])
        project.cueBlocks = [block]
        for i in 0..<3 {
            let look = CueResolver.resolveLook(cues: cues, index: i, project: project)
            XCTAssertEqual(look.fixtureAttributes[fx]?["colorB"], 0.2)
        }
    }

    func testFannedValuesPreserved() {
        let ids = (0..<4).map { _ in UUID() }
        var project = rgbProject(fixtureIDs: ids)
        let hues = [0.78, 0.72, 0.66, 0.60]
        let block = CueBlock(
            name: "Fan",
            type: .color,
            levels: CueLevelData(fixtures: zip(ids, hues).map { id, h in
                FixtureCueLevels(fixtureId: id, attributes: ["colorHue": h, "colorR": h, "colorG": 0, "colorB": 1 - h])
            })
        )
        project.cueBlocks = [block]
        let cue = Cue(number: 1, cueBlockRefs: [CueBlockReference(cueBlockID: block.id)])
        let result = CueBlockResolver.resolveCueLevels(cue: cue, project: project)
        XCTAssertEqual(result.levels.fixtures.count, 4)
        for (i, fx) in result.levels.fixtures.enumerated() {
            XCTAssertEqual(fx.fixtureId, ids[i])
        }
    }

    func testCapabilityFiltersStaleAttributesFromBlocksOnly() {
        let fx = UUID()
        var project = rgbProject(fixtureIDs: [fx])
        // Block stores pan which RGB fixture does not support.
        let block = CueBlock(
            name: "Pos",
            type: .position,
            levels: CueLevelData(fixtures: [
                FixtureCueLevels(fixtureId: fx, attributes: ["pan": 0.5, "intensity": 0.8])
            ])
        )
        project.cueBlocks = [block]
        // Literal pan on the cue should still pass through (legacy path not filtered).
        let cue = Cue(
            number: 1,
            levels: CueLevelData(fixtures: [
                FixtureCueLevels(fixtureId: fx, attributes: ["pan": 0.9])
            ]),
            cueBlockRefs: [CueBlockReference(cueBlockID: block.id)]
        )
        let result = CueBlockResolver.resolveCueLevels(cue: cue, project: project)
        // Block pan dropped; cue literal pan remains (legacy path unfiltered).
        XCTAssertEqual(result.levels.fixtures.first?.attributes["pan"], 0.9)
        XCTAssertEqual(result.levels.fixtures.first?.attributes["intensity"], 0.8)
        XCTAssertTrue(result.issues.contains { $0.code == "capability-filtered-attribute" && $0.attribute == "pan" })
    }

    func testCuePaletteWinsOverBlock() {
        let fx = UUID()
        var project = rgbProject(fixtureIDs: [fx])
        let block = CueBlock(
            name: "BlockBlue",
            type: .color,
            levels: CueLevelData(fixtures: [
                FixtureCueLevels(fixtureId: fx, attributes: ["colorB": 0.2, "colorR": 0, "colorG": 0])
            ])
        )
        let palette = Palette(id: UUID(), name: "PalBlue", type: .color, values: ["colorB": 1, "colorR": 0, "colorG": 0])
        project.cueBlocks = [block]
        project.palettes = [palette]
        let cue = Cue(
            number: 1,
            levels: CueLevelData(fixtures: [
                FixtureCueLevels(fixtureId: fx, paletteRefs: ["color": palette.id])
            ]),
            cueBlockRefs: [CueBlockReference(cueBlockID: block.id)]
        )
        let result = CueBlockResolver.resolveCueLevels(cue: cue, project: project)
        XCTAssertEqual(result.levels.fixtures.first?.attributes["colorB"], 1)
    }

    func testTrackingAndCueOnlyShareComposition() {
        let fx = UUID()
        var project = rgbProject(fixtureIDs: [fx])
        let block = CueBlock(
            name: "I",
            type: .intensity,
            levels: CueLevelData(fixtures: [FixtureCueLevels(fixtureId: fx, attributes: ["intensity": 0.3])])
        )
        project.cueBlocks = [block]
        let trackCue = Cue(
            number: 1,
            tracking: .track,
            cueBlockRefs: [CueBlockReference(cueBlockID: block.id)]
        )
        let cueOnly = Cue(
            number: 2,
            tracking: .cueOnly,
            levels: CueLevelData(fixtures: [
                FixtureCueLevels(fixtureId: fx, attributes: ["colorR": 1])
            ]),
            cueBlockRefs: [CueBlockReference(cueBlockID: block.id)]
        )
        let tracked = CueResolver.resolveLookDetailed(cues: [trackCue, cueOnly], index: 0, project: project)
        XCTAssertEqual(tracked.look.fixtureAttributes[fx]?["intensity"], 0.3)

        let only = CueResolver.resolveLookDetailed(cues: [trackCue, cueOnly], index: 1, project: project)
        XCTAssertEqual(only.look.fixtureAttributes[fx]?["intensity"], 0.3)
        XCTAssertEqual(only.look.fixtureAttributes[fx]?["colorR"], 1)
    }

    func testRecallResolvesBlock() {
        let fx = UUID()
        let project = rgbProject(fixtureIDs: [fx])
        let block = CueBlock(
            name: "R",
            type: .intensity,
            levels: CueLevelData(fixtures: [FixtureCueLevels(fixtureId: fx, attributes: ["intensity": 0.55])])
        )
        let result = CueBlockResolver.resolveBlockForRecall(cueBlock: block, project: project)
        XCTAssertEqual(result.levels.fixtures.first?.attributes["intensity"], 0.55)
    }
}
