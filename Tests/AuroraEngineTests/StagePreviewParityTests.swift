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

    func testEffectiveBeamLevelCombinesDimmerAndActiveColorBrightness() {
        let (project, fx) = rgbDimmerProject()
        let definition = project.definition(id: project.fixtures[0].definitionId)
        let level = StagePreviewBuilder.effectiveBeamLevel(
            attributes: [
                "intensity": 0.8,
                ColorAuthoringAttribute.brightness: 0.25,
                "colorR": 0.25,
                "colorG": 0.10,
                "colorB": 0.05,
            ],
            definition: definition
        )
        XCTAssertEqual(level, 0.2, accuracy: 0.001, "fixture \(fx)")
    }

    func testRGBBrightnessZeroDoesNotSuppressDedicatedEmitters() {
        let definition = FixtureDefinition(
            manufacturer: "G",
            model: "RGBACWUV with dimmer",
            channels: [
                ChannelDef(offset: 1, name: "Dimmer", attribute: "intensity"),
                ChannelDef(offset: 2, name: "R", attribute: "colorR"),
                ChannelDef(offset: 3, name: "G", attribute: "colorG"),
                ChannelDef(offset: 4, name: "B", attribute: "colorB"),
                ChannelDef(offset: 5, name: "Amber", attribute: "colorA"),
                ChannelDef(offset: 6, name: "Cool White", attribute: "colorCoolWhite"),
                ChannelDef(offset: 7, name: "UV", attribute: "colorUV"),
            ],
            colorModel: .rgb
        )
        let level = StagePreviewBuilder.effectiveBeamLevel(
            attributes: [
                "intensity": 0.8,
                ColorAuthoringAttribute.brightness: 0,
                "colorR": 0,
                "colorG": 0,
                "colorB": 0,
                "colorA": 0.6,
                "colorCoolWhite": 0.4,
                "colorUV": 0.3,
            ],
            definition: definition
        )
        XCTAssertEqual(level, 0.48, accuracy: 0.001)
    }

    func testRGBBrightnessStillControlsRGBWhenDedicatedEmittersAreOff() {
        let (project, _) = rgbDimmerProject()
        let definition = project.definition(id: project.fixtures[0].definitionId)
        let level = StagePreviewBuilder.effectiveBeamLevel(
            attributes: [
                "intensity": 0.8,
                ColorAuthoringAttribute.brightness: 0,
                "colorR": 0,
                "colorG": 0,
                "colorB": 0,
                "colorA": 0,
            ],
            definition: definition
        )
        XCTAssertEqual(level, 0, accuracy: 0.001)
    }

    func testEffectiveBeamLevelUsesVirtualDimmerForRGBOnlyFixture() {
        let definition = FixtureDefinition(
            manufacturer: "G",
            model: "RGB only",
            channels: [
                ChannelDef(offset: 1, name: "R", attribute: "colorR"),
                ChannelDef(offset: 2, name: "G", attribute: "colorG"),
                ChannelDef(offset: 3, name: "B", attribute: "colorB"),
            ],
            colorModel: .rgb
        )
        let level = StagePreviewBuilder.effectiveBeamLevel(
            attributes: [
                "intensity": 0.5,
                "colorR": 0.6,
                "colorG": 0.2,
                "colorB": 0.1,
            ],
            definition: definition
        )
        XCTAssertEqual(level, 0.3, accuracy: 0.001)
    }

    func testPreviewNormalizesBeamChromaSeparatelyFromLevel() {
        let (project, fx) = rgbDimmerProject()
        let preview = StagePreviewBuilder.build(
            project: project,
            look: ActiveLook(fixtureAttributes: [fx: [
                "intensity": 1,
                ColorAuthoringAttribute.brightness: 0.4,
                "colorR": 0.4,
                "colorG": 0.2,
                "colorB": 0.1,
            ]]),
            frameIndex: 1,
            time: 0,
            global: .default
        )
        let fixture = preview.fixtures.first { $0.fixtureID == fx }
        XCTAssertEqual(fixture?.intensity ?? -1, 0.4, accuracy: 0.001)
        XCTAssertEqual(fixture?.color?.r ?? -1, 1, accuracy: 0.001)
        XCTAssertEqual(fixture?.color?.g ?? -1, 0.5, accuracy: 0.001)
        XCTAssertEqual(fixture?.color?.b ?? -1, 0.25, accuracy: 0.001)
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
        eng.programmer.set(fixtureID: fx, attribute: "colorR@1", value: 0.0)
        eng.programmer.set(fixtureID: fx, attribute: "colorG@1", value: 1.0)
        eng.programmer.set(fixtureID: fx, attribute: "colorB@1", value: 0.0)
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

        let resolved = eng.currentResolvedSnapshot()
        let preview = StagePreviewBuilder.build(
            project: project,
            look: resolved.presentationLook,
            frameIndex: resolved.frameIndex,
            time: resolved.timestamp,
            global: resolved.global
        )
        let elements = preview.fixtures.first?.elements ?? []
        XCTAssertEqual(elements.count, 4)
        XCTAssertEqual(elements[0].color?.r ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(elements[1].color?.g ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(elements[2].intensity, 0, accuracy: 0.001)
        XCTAssertEqual(elements[3].color?.b ?? 0, 1, accuracy: 0.001)
        eng.stop()
    }

    func testExplicitElementOwnershipDrivesDMXAndIndependentPreviewElements() throws {
        let channels = (0..<3).flatMap { element in
            ["colorR", "colorG", "colorB"].enumerated().map { index, attribute in
                ChannelDef(
                    offset: UInt16(element * 3 + index + 1),
                    name: attribute,
                    attribute: attribute,
                    elementID: "pixel-\(element)"
                )
            }
        } + [ChannelDef(offset: 10, name: "Master", attribute: "intensity")]
        let definition = FixtureDefinition(
            manufacturer: "User",
            model: "Linear RGB",
            channelCount: 10,
            channels: channels,
            visual: FixtureVisualDefinition(
                role: .linearLight,
                bodyAspectRatio: 3,
                layout: .row,
                elements: FixtureVisualInference.makeElements(ids: ["pixel-0", "pixel-1", "pixel-2"], layout: .row)
            )
        )
        let writes = CompiledShow.compileAttributeWrites(definition: definition)
        XCTAssertEqual(writes.first { $0.attribute == "colorR@pixel-1" }?.kind, .eightBit(offset: 4, defaultValue: 0))
        XCTAssertEqual(writes.first { $0.attribute == "intensity" }?.kind, .eightBit(offset: 10, defaultValue: 0))

        let universe = Universe(number: 1)
        let fixtureID = UUID()
        var project = ShowProject.empty(name: "Native Visual")
        project.universes = [universe]
        project.fixtureDefinitions = [definition]
        project.fixtures = [PatchedFixture(id: fixtureID, name: "Bar", definitionId: definition.id, universeId: universe.id, address: 1)]

        let engine = LightingEngine(output: OutputManager())
        engine.load(project: project)
        try engine.start()
        engine.programmer.set(fixtureID: fixtureID, attribute: "intensity", value: 1)
        engine.programmer.set(fixtureID: fixtureID, attribute: "colorR@pixel-0", value: 1)
        engine.programmer.set(fixtureID: fixtureID, attribute: "colorG@pixel-1", value: 1)
        engine.programmer.set(fixtureID: fixtureID, attribute: "colorB@pixel-2", value: 1)
        engine.stepForTesting()

        let resolved = engine.currentResolvedSnapshot()
        XCTAssertGreaterThan(resolved.universeLevels[1]?[0] ?? 0, 200)
        XCTAssertGreaterThan(resolved.universeLevels[1]?[4] ?? 0, 200)
        XCTAssertGreaterThan(resolved.universeLevels[1]?[8] ?? 0, 200)
        let preview = StagePreviewBuilder.build(project: project, look: resolved.presentationLook, frameIndex: 1, time: 0, global: resolved.global)
        let elements = preview.fixtures.first?.elements ?? []
        XCTAssertEqual(elements.map(\.elementID), ["pixel-0", "pixel-1", "pixel-2"])
        XCTAssertGreaterThan(elements[0].color?.r ?? 0, 0.9)
        XCTAssertGreaterThan(elements[1].color?.g ?? 0, 0.9)
        XCTAssertGreaterThan(elements[2].color?.b ?? 0, 0.9)
        engine.stop()
    }

    func testAtmosphericSemanticOutputFeedsGlyphIndicator() {
        let definition = FixtureDefinition(
            manufacturer: "User",
            model: "Atmospheric",
            channels: [
                ChannelDef(offset: 1, name: "Fan", attribute: "fanSpeed"),
                ChannelDef(offset: 2, name: "Haze", attribute: "fogOutput"),
            ]
        )
        let fixtureID = UUID()
        var project = ShowProject.empty(name: "Atmosphere")
        project.fixtureDefinitions = [definition]
        project.fixtures = [PatchedFixture(id: fixtureID, name: "Hazer", definitionId: definition.id, universeId: UUID(), address: 1)]

        let preview = StagePreviewBuilder.build(
            project: project,
            look: ActiveLook(fixtureAttributes: [fixtureID: ["fanSpeed": 0.4, "fogOutput": 0.75]]),
            frameIndex: 1,
            time: 0,
            global: GlobalShowControlState()
        )
        XCTAssertEqual(definition.resolvedVisual.role, .atmospheric)
        XCTAssertEqual(preview.fixtures.first?.environmental["fogOutput"] ?? 0, 0.75, accuracy: 0.001)
        XCTAssertEqual(preview.fixtures.first?.environmental["fanSpeed"] ?? 0, 0.4, accuracy: 0.001)
    }

    func testManyToManyMappingsProjectControlStateOntoIndependentPhysicalEmitters() {
        let physical = FixturePhysicalDefinition(
            manufacturer: "Synthetic",
            model: "Mapped Hybrid",
            form: .panel,
            emitters: [
                .init(id: "aperture-left", name: "Left", x: 0.25, y: 0.5),
                .init(id: "aperture-right", name: "Right", x: 0.75, y: 0.5),
            ],
            componentGroups: [.init(id: "pair", role: .emitterArray, topology: .linear, emitterIDs: ["aperture-left", "aperture-right"])]
        )
        let definition = FixtureDefinition(
            manufacturer: "Synthetic",
            model: "Mapped Hybrid",
            channels: [
                ChannelDef(offset: 1, name: "Red A", attribute: "colorR", elementID: "control-a"),
                ChannelDef(offset: 2, name: "Blue B", attribute: "colorB", elementID: "control-b"),
            ],
            physicalFixtureID: physical.id,
            portablePhysicalDefinition: physical,
            controlElements: [.init(id: "control-a", name: "A"), .init(id: "control-b", name: "B")],
            emitterMappings: [
                .init(id: "a-to-both", controlElementIDs: ["control-a"], physicalEmitterIDs: ["aperture-left", "aperture-right"]),
                .init(id: "both-to-right", controlElementIDs: ["control-a", "control-b"], physicalEmitterIDs: ["aperture-right"], combination: .additive),
            ]
        )
        let universe = Universe(number: 1)
        let fixtureID = UUID()
        var project = ShowProject.empty(name: "Mappings")
        project.universes = [universe]
        project.fixtureDefinitions = [definition]
        project.physicalFixtureDefinitions = [physical]
        project.fixtures = [.init(id: fixtureID, name: "Hybrid", definitionId: definition.id, universeId: universe.id, address: 1)]
        let look = ActiveLook(fixtureAttributes: [fixtureID: [
            "colorR@control-a": 1,
            "colorB@control-b": 1,
        ]])

        let preview = StagePreviewBuilder.build(project: project, look: look, frameIndex: 1, time: 0, global: .init())
        let physicalStates = preview.fixtures.first?.physicalEmitters ?? []
        XCTAssertEqual(physicalStates.map(\.elementID), ["aperture-left", "aperture-right"])
        XCTAssertGreaterThan(physicalStates[0].color?.r ?? 0, 0.9)
        XCTAssertGreaterThan(physicalStates[1].color?.r ?? 0, 0.6)
        XCTAssertGreaterThan(physicalStates[1].color?.b ?? 0, 0.2)
    }

    func testDedicatedCellEmittersReachDMXAndStagePreview() throws {
        let emitters = [
            ChannelDef(offset: 1, name: "R", attribute: "colorR"),
            ChannelDef(offset: 2, name: "G", attribute: "colorG"),
            ChannelDef(offset: 3, name: "B", attribute: "colorB"),
            ChannelDef(offset: 4, name: "Amber", attribute: "colorA"),
            ChannelDef(offset: 5, name: "Cool White", attribute: "colorCoolWhite"),
            ChannelDef(offset: 6, name: "UV", attribute: "colorUV"),
        ]
        let definition = FixtureDefinition(
            manufacturer: "Generic",
            model: "Compound Hex",
            channels: [ChannelDef(offset: 1, name: "Master", attribute: "intensity")],
            cellBlock: FixtureCellBlock(channels: emitters, cellCount: 4)
        )
        let universe = Universe(number: 1)
        let fixtureID = UUID()
        var project = ShowProject.empty(name: "Dedicated Emitters")
        project.universes = [universe]
        project.fixtureDefinitions = [definition]
        project.fixtures = [PatchedFixture(
            id: fixtureID,
            name: "Hex 1",
            definitionId: definition.id,
            universeId: universe.id,
            address: 1
        )]

        let engine = LightingEngine(output: OutputManager())
        engine.load(project: project)
        try engine.start()
        engine.programmer.set(fixtureID: fixtureID, attribute: "intensity", value: 1)
        engine.programmer.set(fixtureID: fixtureID, attribute: "colorA@0", value: 0.8)
        engine.programmer.set(fixtureID: fixtureID, attribute: "colorUV@1", value: 0.6)
        engine.programmer.set(fixtureID: fixtureID, attribute: "colorCoolWhite@2", value: 0.7)
        engine.stepForTesting()

        let resolved = engine.currentResolvedSnapshot()
        let dmx = resolved.universeLevels[1] ?? []
        XCTAssertEqual(dmx[0], 255) // shared master
        XCTAssertEqual(Int(dmx[4]), Int(0.8 * 255), accuracy: 1) // element 0 amber
        XCTAssertEqual(Int(dmx[12]), Int(0.6 * 255), accuracy: 1) // element 1 UV
        XCTAssertEqual(Int(dmx[17]), Int(0.7 * 255), accuracy: 1) // element 2 cool white

        let preview = StagePreviewBuilder.build(
            project: project,
            look: resolved.presentationLook,
            frameIndex: resolved.frameIndex,
            time: resolved.timestamp,
            global: resolved.global
        )
        let cells = preview.fixtures.first?.elements ?? []
        XCTAssertGreaterThan(cells[0].color?.r ?? 0, 0.9)
        XCTAssertLessThan(cells[0].color?.b ?? 1, 0.1)
        XCTAssertGreaterThan(cells[1].color?.b ?? 0, 0.9)
        XCTAssertGreaterThan(cells[1].color?.r ?? 0, 0.4)
        XCTAssertGreaterThan(cells[2].color?.r ?? 0, 0.7)
        XCTAssertGreaterThan(cells[2].color?.b ?? 0, 0.9)
        XCTAssertEqual(cells[3].intensity, 0, accuracy: 0.001)
        let physical = preview.fixtures.first?.physicalEmitters ?? []
        XCTAssertEqual(physical.count, 4)
        XCTAssertGreaterThan(physical[0].color?.r ?? 0, 0.9)
        XCTAssertLessThan(physical[0].color?.b ?? 1, 0.1)
        XCTAssertGreaterThan(physical[1].color?.b ?? 0, 0.9)
        XCTAssertGreaterThan(physical[2].color?.r ?? 0, 0.7)
        XCTAssertGreaterThan(physical[2].color?.b ?? 0, 0.9)
        XCTAssertEqual(physical[3].intensity, 0, accuracy: 0.001)
        engine.stop()
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
