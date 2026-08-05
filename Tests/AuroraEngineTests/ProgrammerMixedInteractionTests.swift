import AuroraEngine
import AuroraModel
import XCTest

/// Mixed presentation → user interaction → common (UI-03 Pass 2 amendment 3).
final class ProgrammerMixedInteractionTests: XCTestCase {
    private let dimDef = UUID(uuidString: "E1000000-0000-4000-8000-000000000001")!
    private let rgbDef = UUID(uuidString: "E1000000-0000-4000-8000-000000000002")!
    private let fA = UUID(uuidString: "E1000000-0000-4000-8000-000000000011")!
    private let fB = UUID(uuidString: "E1000000-0000-4000-8000-000000000012")!
    private let u1 = UUID(uuidString: "E1000000-0000-4000-8000-0000000000AA")!

    private func dimProject() -> ShowProject {
        var p = ShowProject.empty(name: "MixInt")
        p.universes = [Universe(id: u1, number: 1)]
        p.fixtureDefinitions = [
            FixtureDefinition(
                id: dimDef, manufacturer: "G", model: "Dim",
                channels: [ChannelDef(offset: 1, name: "I", attribute: "intensity")]
            )
        ]
        p.fixtures = [
            PatchedFixture(id: fA, name: "A", definitionId: dimDef, universeId: u1, address: 1),
            PatchedFixture(id: fB, name: "B", definitionId: dimDef, universeId: u1, address: 2),
        ]
        return p
    }

    private func rgbProject() -> ShowProject {
        var p = ShowProject.empty(name: "MixRGB")
        p.universes = [Universe(id: u1, number: 1)]
        p.fixtureDefinitions = [
            FixtureDefinition(
                id: rgbDef, manufacturer: "G", model: "RGB",
                channels: [
                    ChannelDef(offset: 1, name: "R", attribute: "colorR"),
                    ChannelDef(offset: 2, name: "G", attribute: "colorG"),
                    ChannelDef(offset: 3, name: "B", attribute: "colorB"),
                ],
                colorModel: .rgb
            )
        ]
        p.fixtures = [
            PatchedFixture(id: fA, name: "A", definitionId: rgbDef, universeId: u1, address: 1),
            PatchedFixture(id: fB, name: "B", definitionId: rgbDef, universeId: u1, address: 10),
        ]
        return p
    }

    func testMixedIntensityInteractionBecomesCommon() {
        let project = dimProject()
        let prog = Programmer()
        prog.set(fixtureID: fA, attribute: "intensity", value: 0.25)
        prog.set(fixtureID: fB, attribute: "intensity", value: 0.75)

        var pres = ProgrammerAttributePresentationResolver.resolve(
            orderedFixtureIDs: [fA, fB],
            project: project,
            programmer: prog.snapshot()
        )
        XCTAssertEqual(pres.intensity.value, .mixed)

        // Simulate first intentional fader move to 0.60
        let map = ProgrammerGeometry.align(fixtureIDs: [fA, fB], value: 0.60)
        prog.setMany(attribute: "intensity", values: map)

        pres = ProgrammerAttributePresentationResolver.resolve(
            orderedFixtureIDs: [fA, fB],
            project: project,
            programmer: prog.snapshot()
        )
        if case .common(let v) = pres.intensity.value {
            XCTAssertEqual(v, 0.60, accuracy: 1e-9)
        } else {
            XCTFail("expected common after interaction: \(pres.intensity.value)")
        }
        XCTAssertEqual(prog.snapshot().values[fA]!["intensity"]!, 0.60, accuracy: 1e-9)
        XCTAssertEqual(prog.snapshot().values[fB]!["intensity"]!, 0.60, accuracy: 1e-9)
    }

    func testMixedRGBBatchedInteractionBecomesCommon() {
        let project = rgbProject()
        let prog = Programmer()
        prog.set(fixtureID: fA, attribute: "colorR", value: 1)
        prog.set(fixtureID: fA, attribute: "colorG", value: 0)
        prog.set(fixtureID: fA, attribute: "colorB", value: 0)
        prog.set(fixtureID: fB, attribute: "colorR", value: 0)
        prog.set(fixtureID: fB, attribute: "colorG", value: 0)
        prog.set(fixtureID: fB, attribute: "colorB", value: 1)

        var pres = ProgrammerAttributePresentationResolver.resolve(
            orderedFixtureIDs: [fA, fB],
            project: project,
            programmer: prog.snapshot()
        )
        XCTAssertTrue(pres.isRGBMixed)
        XCTAssertTrue(pres.hasRGBColor)

        // One batched multi-attr write (color wheel path)
        let target: [String: Double] = ["colorR": 0.2, "colorG": 0.4, "colorB": 0.6]
        var batch: [UUID: [String: Double]] = [:]
        for id in [fA, fB] {
            batch[id] = target
        }
        prog.setMany(batch)

        pres = ProgrammerAttributePresentationResolver.resolve(
            orderedFixtureIDs: [fA, fB],
            project: project,
            programmer: prog.snapshot()
        )
        XCTAssertFalse(pres.isRGBMixed)
        if case .common(let r) = pres.colorR.value {
            XCTAssertEqual(r, 0.2, accuracy: 1e-9)
        } else {
            XCTFail("colorR not common")
        }
        XCTAssertEqual(prog.snapshot().values[fA]!["colorG"]!, 0.4, accuracy: 1e-9)
        XCTAssertEqual(prog.snapshot().values[fB]!["colorB"]!, 0.6, accuracy: 1e-9)
    }

    func testTechnicalOnlyHasNoRGBWheelFamily() {
        var p = ShowProject.empty(name: "UV")
        let uvDef = UUID()
        let f = UUID()
        p.universes = [Universe(id: u1, number: 1)]
        p.fixtureDefinitions = [
            FixtureDefinition(
                id: uvDef, manufacturer: "G", model: "UV",
                channels: [ChannelDef(offset: 1, name: "UV", attribute: "colorUV")]
            )
        ]
        p.fixtures = [PatchedFixture(id: f, name: "UV", definitionId: uvDef, universeId: u1, address: 1)]
        let pres = ProgrammerAttributePresentationResolver.resolve(
            orderedFixtureIDs: [f],
            project: p,
            programmer: .empty
        )
        XCTAssertFalse(pres.hasRGBColor)
        XCTAssertTrue(pres.hasTechnicalColor)
        XCTAssertTrue(pres.technicalColorAttributes.contains("colorUV"))
    }
}
