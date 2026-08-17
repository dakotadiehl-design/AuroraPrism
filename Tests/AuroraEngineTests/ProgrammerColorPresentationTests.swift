import AuroraEngine
import AuroraModel
import XCTest

final class ProgrammerColorPresentationTests: XCTestCase {

    private func makeProject(attributes: [(String, String)]) -> (ShowProject, UUID) {
        var project = ShowProject.empty(name: "Color")
        let defID = UUID()
        let uniID = UUID()
        let fxID = UUID()
        var channels: [ChannelDef] = []
        for (i, pair) in attributes.enumerated() {
            channels.append(ChannelDef(offset: UInt16(i + 1), name: pair.0, attribute: pair.1))
        }
        project.fixtureDefinitions = [
            FixtureDefinition(
                id: defID,
                manufacturer: "Test",
                model: "LED",
                channelCount: UInt16(channels.count),
                channels: channels
            )
        ]
        project.universes = [Universe(id: uniID, number: 1, channelCount: 512)]
        project.fixtures = [
            PatchedFixture(
                id: fxID,
                name: "F1",
                definitionId: defID,
                universeId: uniID,
                address: 1
            )
        ]
        return (project, fxID)
    }

    func testRGBOnlyShowsNoDedicatedEmitters() {
        let (project, id) = makeProject(attributes: [
            ("Dimmer", "intensity"),
            ("R", "colorR"),
            ("G", "colorG"),
            ("B", "colorB"),
        ])
        let pres = ProgrammerColorPresentationResolver.resolve(
            orderedFixtureIDs: [id],
            project: project,
            programmer: .empty
        )
        XCTAssertTrue(pres.hasRGB)
        XCTAssertTrue(pres.emitters.isEmpty)
        XCTAssertTrue(pres.dimmer.isSupported)
    }

    func testRGBWShowsWhite() {
        let (project, id) = makeProject(attributes: [
            ("Dimmer", "intensity"),
            ("R", "colorR"), ("G", "colorG"), ("B", "colorB"), ("W", "colorW"),
        ])
        let pres = ProgrammerColorPresentationResolver.resolve(
            orderedFixtureIDs: [id],
            project: project,
            programmer: .empty
        )
        XCTAssertEqual(pres.emitters.map(\.kind), [.white])
    }

    func testRGBWAUVShowsWhiteAmberUVInOrder() {
        let (project, id) = makeProject(attributes: [
            ("Dimmer", "intensity"),
            ("R", "colorR"), ("G", "colorG"), ("B", "colorB"),
            ("W", "colorW"), ("A", "colorA"), ("UV", "colorUV"),
        ])
        let pres = ProgrammerColorPresentationResolver.resolve(
            orderedFixtureIDs: [id],
            project: project,
            programmer: .empty
        )
        XCTAssertEqual(pres.emitters.map(\.kind), [.white, .amber, .uv])
    }

    /// Shehds-style RGBWA+UV uses Cool White (`colorCoolWhite`), not generic `colorW`.
    func testRGBCoolWhiteAmberUVShowsCoolWhiteAmberUV() {
        let (project, id) = makeProject(attributes: [
            ("Dimmer", "intensity"),
            ("R", "colorR"), ("G", "colorG"), ("B", "colorB"),
            ("CoolWhite", "colorCoolWhite"), ("A", "colorA"), ("UV", "colorUV"),
        ])
        let pres = ProgrammerColorPresentationResolver.resolve(
            orderedFixtureIDs: [id],
            project: project,
            programmer: .empty
        )
        XCTAssertEqual(pres.emitters.map(\.kind), [.coolWhite, .amber, .uv])
        XCTAssertEqual(pres.emitters.map(\.attribute), ["colorCoolWhite", "colorA", "colorUV"])
    }

    func testAuthoringStateRetainedOnResolve() {
        let (project, id) = makeProject(attributes: [
            ("R", "colorR"), ("G", "colorG"), ("B", "colorB"),
        ])
        var prog = ProgrammerState.empty
        let auth = ColorAuthoringState(hue: 200, saturation: 0.9, brightness: 0.7, whiteBalance: -0.4)
        prog.values[id] = ColorMath.programmerColorBatch(from: auth)

        let pres = ProgrammerColorPresentationResolver.resolve(
            orderedFixtureIDs: [id],
            project: project,
            programmer: prog
        )
        XCTAssertEqual(pres.hue ?? -1, 200, accuracy: 0.5)
        XCTAssertEqual(pres.saturation ?? -1, 0.9, accuracy: 0.01)
        XCTAssertEqual(pres.brightness ?? -1, 0.7, accuracy: 0.01)
        XCTAssertEqual(pres.whiteBalance ?? 0, -0.4, accuracy: 0.01)
        // Preview must use ColorMath (not raw ignore of WB)
        let expected = ColorMath.resolvedRGB(from: auth)
        XCTAssertEqual(pres.previewRGB.r, expected.r, accuracy: 0.02)
        XCTAssertEqual(pres.previewRGB.g, expected.g, accuracy: 0.02)
        XCTAssertEqual(pres.previewRGB.b, expected.b, accuracy: 0.02)
    }

    func testLegacyRGBOnlyGetsNeutralWB() {
        let (project, id) = makeProject(attributes: [
            ("R", "colorR"), ("G", "colorG"), ("B", "colorB"),
        ])
        var prog = ProgrammerState.empty
        prog.values[id] = ["colorR": 1, "colorG": 0, "colorB": 0]
        let pres = ProgrammerColorPresentationResolver.resolve(
            orderedFixtureIDs: [id],
            project: project,
            programmer: prog
        )
        XCTAssertEqual(pres.whiteBalance ?? -99, 0, accuracy: 0.001)
        XCTAssertEqual(pres.hue ?? -1, 0, accuracy: 5)
    }

    func testEmitterIndependenceFromAuthoringBatch() {
        let batch = ColorMath.programmerColorBatch(
            from: ColorAuthoringState(hue: 30, saturation: 1, brightness: 1, whiteBalance: 0.5)
        )
        XCTAssertNil(batch["colorW"])
        XCTAssertNil(batch["colorA"])
        XCTAssertNil(batch["colorUV"])
    }

    func testPrimaryEmitterOrderStable() {
        XCTAssertEqual(
            ColorEmitterKind.primaryDedicated.map(\.attribute),
            ["colorW", "colorA", "colorUV"]
        )
        // Full dedicated column order used by the Color Programmer.
        XCTAssertEqual(
            ColorEmitterKind.dedicatedUIOrder.map(\.attribute),
            ["colorW", "colorWarmWhite", "colorCoolWhite", "colorA", "colorLime", "colorCyan", "colorUV"]
        )
    }
}
