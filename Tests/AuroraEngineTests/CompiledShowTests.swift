import AuroraEngine
import AuroraModel
import AuroraOutput
import XCTest

final class CompiledShowTests: XCTestCase {
    private func makeShow() -> (ShowProject, UUID, UUID) {
        var project = ShowProject.empty(name: "C")
        let universeID = UUID()
        let definitionID = UUID()
        let fixtureID = UUID()
        project.universes = [Universe(id: universeID, number: 1, channelCount: 512)]
        project.fixtureDefinitions = [
            FixtureDefinition(
                id: definitionID,
                manufacturer: "G",
                model: "MH",
                channelCount: 4,
                channels: [
                    ChannelDef(offset: 1, name: "Pan", attribute: "pan", resolution: .coarse, defaultValue: 128),
                    ChannelDef(offset: 2, name: "Pan Fine", attribute: "pan", resolution: .fine, defaultValue: 0),
                    ChannelDef(offset: 3, name: "Dim", attribute: "intensity", resolution: .eightBit, defaultValue: 0),
                ],
                hasPanTilt: true,
                panInvert: true
            )
        ]
        project.fixtures = [
            PatchedFixture(
                id: fixtureID,
                name: "F1",
                definitionId: definitionID,
                universeId: universeID,
                address: 1
            )
        ]
        project.groups = [Group(name: "All", fixtureIds: [fixtureID])]
        return (project, fixtureID, universeID)
    }

    func testCompileIndexes() {
        let (project, fixtureID, universeID) = makeShow()
        let compiled = CompiledShow.compile(project)
        XCTAssertEqual(compiled.fixtureByID[fixtureID]?.name, "F1")
        XCTAssertEqual(compiled.universeByID[universeID]?.number, 1)
        XCTAssertEqual(compiled.fixtures.count, 1)
        XCTAssertEqual(compiled.channelCountByUniverse[1], 512)
        XCTAssertEqual(compiled.groupByID.count, 1)
    }

    func testCompilePairs16BitAndRecordsInvert() {
        let (project, _, _) = makeShow()
        let compiled = CompiledShow.compile(project)
        let writes = compiled.fixtures[0].attributeWrites
        let pan = writes.first { $0.attribute == "pan" }
        XCTAssertEqual(
            pan?.kind,
            .sixteenBit(coarseOffset: 1, fineOffset: 2, coarseDefault: 128, fineDefault: 0)
        )
        XCTAssertEqual(pan?.invert, true)
        let dim = writes.first { $0.attribute == "intensity" }
        XCTAssertEqual(dim?.kind, .eightBit(offset: 3, defaultValue: 0))
        XCTAssertEqual(dim?.invert, false)
    }

    /// UI-FOUNDATION-5: home/highlight use full 16-bit coarse|fine, not coarse/255 alone.
    func testHomeHighlightUsesFull16BitDefaults() {
        var project = ShowProject.empty(name: "H")
        let u = UUID()
        let d = UUID()
        let f = UUID()
        project.universes = [Universe(id: u, number: 1)]
        project.fixtureDefinitions = [
            FixtureDefinition(
                id: d,
                manufacturer: "G",
                model: "16",
                channelCount: 2,
                channels: [
                    ChannelDef(
                        offset: 1,
                        name: "Pan",
                        attribute: "pan",
                        resolution: .coarse,
                        defaultValue: 0x80,
                        highlightValue: 0x40
                    ),
                    ChannelDef(
                        offset: 2,
                        name: "Pan Fine",
                        attribute: "pan",
                        resolution: .fine,
                        defaultValue: 0x10,
                        highlightValue: 0x20
                    ),
                ],
                hasPanTilt: true
            )
        ]
        project.fixtures = [
            PatchedFixture(id: f, name: "F", definitionId: d, universeId: u, address: 1)
        ]
        let compiled = CompiledShow.compile(project)
        let fixture = compiled.fixtures[0]
        let expectedHome = Double((UInt16(0x80) << 8) | 0x10) / 65535.0
        let expectedHigh = Double((UInt16(0x40) << 8) | 0x20) / 65535.0
        XCTAssertEqual(fixture.homeValues["pan"] ?? -1, expectedHome, accuracy: 1e-12)
        XCTAssertEqual(fixture.highlightValues["pan"] ?? -1, expectedHigh, accuracy: 1e-12)
        // Must not equal coarse-only normalization when fine is non-zero.
        XCTAssertNotEqual(fixture.homeValues["pan"] ?? 0, 0x80 / 255.0, accuracy: 1e-9)
    }

    func testCompiledMergeMatchesProjectMerge() {
        let (project, fixtureID, _) = makeShow()
        var look = ActiveLook()
        look.set(fixtureID: fixtureID, attribute: "pan", value: 0.25)
        look.set(fixtureID: fixtureID, attribute: "intensity", value: 1)

        let fromProject = MergeStub.merge(project: project, look: look)
        let compiled = CompiledShow.compile(project)
        let fromCompiled = MergeStub.merge(compiled: compiled, look: look)

        XCTAssertEqual(fromProject[1], fromCompiled[1])
        // panInvert: 1 - 0.25 = 0.75
        let expectedPan = MergeStub.split16(MergeStub.dmx16Value(normalized: 0.75))
        XCTAssertEqual(fromCompiled[1]?[0], expectedPan.coarse)
        XCTAssertEqual(fromCompiled[1]?[1], expectedPan.fine)
        XCTAssertEqual(fromCompiled[1]?[2], 255)
    }

    func testEngineStoresCompiledOnLoad() {
        let (project, _, _) = makeShow()
        let engine = LightingEngine(output: OutputManager())
        engine.load(project: project)
        XCTAssertEqual(engine.compiledShowSnapshot.fixtures.count, 1)
        XCTAssertEqual(engine.compiledShowSnapshot.fixtures[0].attributeWrites.count, 2)
    }

    func testEngineRecompilesOnUpdateProject() {
        var (project, fixtureID, _) = makeShow()
        let engine = LightingEngine(output: OutputManager())
        engine.load(project: project)
        XCTAssertEqual(engine.compiledShowSnapshot.fixtures.count, 1)

        // Remove fixture — compiled set shrinks without destructive playback API change.
        project.fixtures = []
        engine.updateProject(project)
        XCTAssertTrue(engine.compiledShowSnapshot.fixtures.isEmpty)
        XCTAssertNil(engine.compiledShowSnapshot.fixtureByID[fixtureID])
    }
}
