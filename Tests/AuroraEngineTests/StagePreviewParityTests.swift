import AuroraEngine
import AuroraModel
import AuroraOutput
import XCTest

/// A5: Stage preview and DMX share the engine's authoritative resolved snapshot.
@MainActor
final class StagePreviewParityTests: XCTestCase {
    private func rgbDimmerProject() -> (ShowProject, UUID) {
        var project = ShowProject.empty(name: "Parity")
        let u = Universe(number: 1)
        let def = FixtureDefinition(
            manufacturer: "G",
            model: "RGB",
            channels: [
                ChannelDef(offset: 1, name: "R", attribute: "colorR"),
                ChannelDef(offset: 2, name: "G", attribute: "colorG"),
                ChannelDef(offset: 3, name: "B", attribute: "colorB"),
                ChannelDef(offset: 4, name: "Dim", attribute: "intensity"),
            ],
            colorModel: .rgb
        )
        let fx = UUID()
        project.universes = [u]
        project.fixtureDefinitions = [def]
        project.fixtures = [
            PatchedFixture(id: fx, name: "W1", definitionId: def.id, universeId: u.id, address: 1),
        ]
        return (project, fx)
    }

    func testPreviewConsumesAuthoritativeResolvedSnapshot() throws {
        let (project, fx) = rgbDimmerProject()
        let eng = LightingEngine(output: OutputManager())
        eng.load(project: project)
        try eng.start()
        eng.programmer.set(fixtureID: fx, attribute: "intensity", value: 1.0)
        eng.programmer.set(fixtureID: fx, attribute: "colorR", value: 1.0)
        eng.programmer.set(fixtureID: fx, attribute: "colorG", value: 0.0)
        eng.programmer.set(fixtureID: fx, attribute: "colorB", value: 0.0)
        eng.stepForTesting()

        let resolved = eng.currentResolvedSnapshot()
        XCTAssertEqual(resolved.look.fixtureAttributes[fx]?["intensity"] ?? 0, 1.0, accuracy: 0.01)
        XCTAssertEqual(resolved.universeLevels[1]?[3] ?? 0, 255)
        XCTAssertGreaterThan(resolved.universeLevels[1]?[0] ?? 0, 200)

        let preview = StagePreviewBuilder.build(
            project: project,
            look: resolved.presentationLook,
            frameIndex: resolved.frameIndex,
            time: resolved.timestamp,
            global: resolved.global
        )
        let fxPrev = preview.fixtures.first { $0.fixtureID == fx }
        XCTAssertEqual(fxPrev?.intensity ?? 0, 1.0, accuracy: 0.01)
        XCTAssertEqual(fxPrev?.color?.r ?? 0, 1.0, accuracy: 0.01)
        eng.stop()
    }

    func testMasterScalesDimmerNotRGBEmitters() throws {
        let (project, fx) = rgbDimmerProject()
        let eng = LightingEngine(output: OutputManager())
        eng.load(project: project)
        try eng.start()
        eng.programmer.set(fixtureID: fx, attribute: "intensity", value: 1.0)
        eng.programmer.set(fixtureID: fx, attribute: "colorR", value: 1.0)
        eng.programmer.set(fixtureID: fx, attribute: "colorG", value: 0.5)
        eng.programmer.set(fixtureID: fx, attribute: "colorB", value: 0.25)
        eng.stepForTesting()
        let fullR = eng.currentSnapshot().universeLevels[1]?[0] ?? 0
        let fullDim = eng.currentSnapshot().universeLevels[1]?[3] ?? 0

        eng.setMasterIntensity(0.5)
        eng.stepForTesting()
        let halfR = eng.currentSnapshot().universeLevels[1]?[0] ?? 0
        let halfDim = eng.currentSnapshot().universeLevels[1]?[3] ?? 0
        // Dimmer halves; RGB emitters stay at programmed chromatic levels (no double master).
        XCTAssertEqual(halfR, fullR)
        XCTAssertEqual(Int(halfDim), Int(Double(fullDim) * 0.5), accuracy: 2)

        let resolved = eng.currentResolvedSnapshot()
        XCTAssertEqual(resolved.look.fixtureAttributes[fx]?["intensity"] ?? 0, 0.5, accuracy: 0.01)
        XCTAssertEqual(resolved.look.fixtureAttributes[fx]?["colorR"] ?? 0, 1.0, accuracy: 0.01)
        eng.stop()
    }

    func testBlackoutAndFreezeOnResolvedPath() throws {
        let (project, fx) = rgbDimmerProject()
        let eng = LightingEngine(output: OutputManager())
        eng.load(project: project)
        try eng.start()
        eng.programmer.set(fixtureID: fx, attribute: "intensity", value: 1.0)
        eng.programmer.set(fixtureID: fx, attribute: "colorR", value: 1.0)
        eng.stepForTesting()

        eng.setBlackout(true)
        eng.stepForTesting()
        let bo = eng.currentResolvedSnapshot()
        XCTAssertTrue(bo.global.blackout)
        XCTAssertEqual(bo.universeLevels[1]?[3] ?? 1, 0)
        let previewBO = StagePreviewBuilder.build(
            project: project,
            look: bo.presentationLook,
            frameIndex: bo.frameIndex,
            time: bo.timestamp,
            global: bo.global
        )
        XCTAssertTrue(previewBO.blackout)
        XCTAssertEqual(previewBO.fixtures.first { $0.fixtureID == fx }?.intensity ?? 1, 0, accuracy: 0.01)

        eng.setBlackout(false)
        eng.stepForTesting()
        eng.setFreeze(true)
        eng.stepForTesting()
        let heldDim = eng.currentResolvedSnapshot().universeLevels[1]?[3] ?? 0
        XCTAssertGreaterThan(heldDim, 200)

        eng.programmer.set(fixtureID: fx, attribute: "intensity", value: 0.1)
        eng.stepForTesting()
        let frozen = eng.currentResolvedSnapshot()
        XCTAssertEqual(frozen.universeLevels[1]?[3] ?? 0, heldDim)
        // Semantic presentation holds freeze look (not live 0.1).
        XCTAssertEqual(frozen.presentationLook.fixtureAttributes[fx]?["intensity"] ?? 0, 1.0, accuracy: 0.05)
        let previewFZ = StagePreviewBuilder.build(
            project: project,
            look: frozen.presentationLook,
            frameIndex: frozen.frameIndex,
            time: frozen.timestamp,
            global: frozen.global
        )
        XCTAssertTrue(previewFZ.freeze)
        XCTAssertEqual(previewFZ.fixtures.first { $0.fixtureID == fx }?.intensity ?? 0, 1.0, accuracy: 0.05)
        eng.stop()
    }

    func testMultiCellCompileExpandsRuntimeAttributes() throws {
        let cellCh = [
            ChannelDef(offset: 1, name: "R", attribute: "colorR"),
            ChannelDef(offset: 2, name: "G", attribute: "colorG"),
            ChannelDef(offset: 3, name: "B", attribute: "colorB"),
        ]
        let def = FixtureDefinition(
            manufacturer: "G",
            model: "PixelBar",
            channels: [],
            cellBlock: FixtureCellBlock(channels: cellCh, cellCount: 4),
            category: "pixel"
        )
        XCTAssertEqual(def.calculatedFootprint, 12)

        let writes = CompiledShow.compileAttributeWrites(definition: def)
        let attrs = Set(writes.map(\.attribute))
        XCTAssertTrue(attrs.contains("colorR@0"))
        XCTAssertTrue(attrs.contains("colorR@3"))
        XCTAssertTrue(attrs.contains("colorB@2"))
        XCTAssertEqual(attrs.count, 12)

        var project = ShowProject.empty(name: "Cells")
        let u = Universe(number: 1)
        let fx = UUID()
        project.universes = [u]
        project.fixtureDefinitions = [def]
        project.fixtures = [
            PatchedFixture(id: fx, name: "Bar", definitionId: def.id, universeId: u.id, address: 1),
        ]
        let eng = LightingEngine(output: OutputManager())
        eng.load(project: project)
        try eng.start()
        eng.programmer.set(fixtureID: fx, attribute: "colorR@0", value: 1.0)
        eng.programmer.set(fixtureID: fx, attribute: "colorG@0", value: 0.0)
        eng.programmer.set(fixtureID: fx, attribute: "colorB@0", value: 0.0)
        eng.programmer.set(fixtureID: fx, attribute: "colorR@3", value: 0.0)
        eng.programmer.set(fixtureID: fx, attribute: "colorG@3", value: 0.0)
        eng.programmer.set(fixtureID: fx, attribute: "colorB@3", value: 1.0)
        eng.stepForTesting()
        let dmx = eng.currentSnapshot().universeLevels[1] ?? []
        XCTAssertGreaterThan(dmx[0], 200) // cell0 R
        XCTAssertEqual(dmx[1], 0)
        XCTAssertEqual(dmx[2], 0)
        XCTAssertEqual(dmx[9], 0) // cell3 R
        XCTAssertEqual(dmx[10], 0)
        XCTAssertGreaterThan(dmx[11], 200) // cell3 B
        eng.stop()
    }

    func testCuePlaybackOnResolvedPreviewPath() throws {
        let (project, fx) = rgbDimmerProject()
        var p = project
        let listID = UUID()
        let cue = Cue(
            number: 1,
            name: "Full",
            fadeIn: 0,
            levels: CueLevelData(fixtures: [
                FixtureCueLevels(fixtureId: fx, attributes: [
                    "intensity": 0.8,
                    "colorR": 0.0,
                    "colorG": 1.0,
                    "colorB": 0.0,
                ]),
            ])
        )
        p.cueLists = [CueList(id: listID, name: "Main", cues: [cue])]

        let eng = LightingEngine(output: OutputManager())
        eng.load(project: p)
        try eng.start()
        eng.loadCueList(p.cueLists[0])
        eng.fire(cueID: cue.id)
        eng.stepForTesting()

        let resolved = eng.currentResolvedSnapshot()
        XCTAssertEqual(resolved.look.fixtureAttributes[fx]?["intensity"] ?? 0, 0.8, accuracy: 0.02)
        XCTAssertEqual(resolved.look.fixtureAttributes[fx]?["colorG"] ?? 0, 1.0, accuracy: 0.02)
        let preview = StagePreviewBuilder.build(
            project: p,
            look: resolved.presentationLook,
            frameIndex: resolved.frameIndex,
            time: resolved.timestamp,
            global: resolved.global
        )
        XCTAssertEqual(preview.fixtures.first { $0.fixtureID == fx }?.intensity ?? 0, 0.8, accuracy: 0.02)
        XCTAssertEqual(preview.fixtures.first { $0.fixtureID == fx }?.color?.g ?? 0, 1.0, accuracy: 0.02)
        eng.stop()
    }
}
