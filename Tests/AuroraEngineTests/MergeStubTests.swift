import AuroraEngine
import AuroraModel
import XCTest

final class MergeStubTests: XCTestCase {
    private func dimmerProject(
        address: UInt16 = 1,
        universeNumber: UInt16 = 1
    ) -> (ShowProject, UUID) {
        var project = ShowProject.empty(name: "M")
        let universeID = UUID()
        let definitionID = UUID()
        let fixtureID = UUID()
        project.universes = [
            Universe(id: universeID, number: universeNumber, name: "U\(universeNumber)", channelCount: 512)
        ]
        project.fixtureDefinitions = [
            FixtureDefinition(
                id: definitionID,
                manufacturer: "G",
                model: "Dimmer",
                channelCount: 1,
                channels: [
                    ChannelDef(offset: 1, name: "Int", attribute: "intensity", defaultValue: 0)
                ]
            )
        ]
        project.fixtures = [
            PatchedFixture(
                id: fixtureID,
                name: "F",
                definitionId: definitionID,
                universeId: universeID,
                address: address
            )
        ]
        return (project, fixtureID)
    }

    func testIntensityFullWrites255() {
        let (project, fixtureID) = dimmerProject()
        var look = ActiveLook()
        look.set(fixtureID: fixtureID, attribute: "intensity", value: 1.0)
        let levels = MergeStub.merge(project: project, look: look)
        XCTAssertEqual(levels[1]?[0], 255)
    }

    func testDefaultValueWhenAttributeMissing() {
        let (project, _) = dimmerProject()
        let levels = MergeStub.merge(project: project, look: .empty)
        XCTAssertEqual(levels[1]?[0], 0)
    }

    func testAddressOffset() {
        let (project, fixtureID) = dimmerProject(address: 5)
        var look = ActiveLook()
        look.set(fixtureID: fixtureID, attribute: "intensity", value: 1.0)
        let levels = MergeStub.merge(project: project, look: look)
        XCTAssertEqual(levels[1]?[4], 255)
        XCTAssertEqual(levels[1]?[0], 0)
    }

    func testRGBAtAddress() {
        var project = ShowProject.empty()
        let universeID = UUID()
        let definitionID = UUID()
        let fixtureID = UUID()
        project.universes = [Universe(id: universeID, number: 1, channelCount: 512)]
        project.fixtureDefinitions = [
            FixtureDefinition(
                id: definitionID,
                manufacturer: "G",
                model: "RGB",
                channelCount: 3,
                channels: [
                    ChannelDef(offset: 1, name: "R", attribute: "colorR", defaultValue: 0),
                    ChannelDef(offset: 2, name: "G", attribute: "colorG", defaultValue: 0),
                    ChannelDef(offset: 3, name: "B", attribute: "colorB", defaultValue: 0),
                ]
            )
        ]
        project.fixtures = [
            PatchedFixture(
                id: fixtureID,
                name: "RGB",
                definitionId: definitionID,
                universeId: universeID,
                address: 5
            )
        ]
        var look = ActiveLook()
        look.set(fixtureID: fixtureID, attribute: "colorR", value: 1)
        look.set(fixtureID: fixtureID, attribute: "colorG", value: 0.5)
        look.set(fixtureID: fixtureID, attribute: "colorB", value: 0)
        let levels = MergeStub.merge(project: project, look: look)
        XCTAssertEqual(levels[1]?[4], 255)
        XCTAssertEqual(levels[1]?[5], 128)
        XCTAssertEqual(levels[1]?[6], 0)
    }

    // MARK: - 16-bit coarse/fine (P0-4)

    private func movingHeadProject() -> (ShowProject, UUID) {
        var project = ShowProject.empty(name: "MH")
        let universeID = UUID()
        let definitionID = UUID()
        let fixtureID = UUID()
        project.universes = [Universe(id: universeID, number: 1, channelCount: 512)]
        project.fixtureDefinitions = [
            FixtureDefinition(
                id: definitionID,
                manufacturer: "Generic",
                model: "Moving Head",
                channelCount: 4,
                channels: [
                    ChannelDef(offset: 1, name: "Pan", attribute: "pan", resolution: .coarse, defaultValue: 128),
                    ChannelDef(offset: 2, name: "Pan Fine", attribute: "pan", resolution: .fine, defaultValue: 0),
                    ChannelDef(offset: 3, name: "Tilt", attribute: "tilt", resolution: .coarse, defaultValue: 128),
                    ChannelDef(offset: 4, name: "Tilt Fine", attribute: "tilt", resolution: .fine, defaultValue: 0),
                ],
                hasPanTilt: true
            )
        ]
        project.fixtures = [
            PatchedFixture(
                id: fixtureID,
                name: "MH1",
                definitionId: definitionID,
                universeId: universeID,
                address: 1
            )
        ]
        return (project, fixtureID)
    }

    func test16BitMidpointWrites8000() {
        let (project, fixtureID) = movingHeadProject()
        var look = ActiveLook()
        look.set(fixtureID: fixtureID, attribute: "pan", value: 0.5)
        look.set(fixtureID: fixtureID, attribute: "tilt", value: 0.5)
        let levels = MergeStub.merge(project: project, look: look)
        // 0.5 * 65535 ≈ 32768 = 0x8000 → coarse 128, fine 0
        let expected = MergeStub.split16(MergeStub.dmx16Value(normalized: 0.5))
        XCTAssertEqual(levels[1]?[0], expected.coarse)
        XCTAssertEqual(levels[1]?[1], expected.fine)
        XCTAssertEqual(levels[1]?[2], expected.coarse)
        XCTAssertEqual(levels[1]?[3], expected.fine)
        // Must not write independent 8-bit (128, 128).
        XCTAssertNotEqual(levels[1]?[1], 128)
    }

    func test16BitZeroAndFull() {
        let (project, fixtureID) = movingHeadProject()
        var look = ActiveLook()
        look.set(fixtureID: fixtureID, attribute: "pan", value: 0)
        look.set(fixtureID: fixtureID, attribute: "tilt", value: 1)
        let levels = MergeStub.merge(project: project, look: look)
        XCTAssertEqual(levels[1]?[0], 0)
        XCTAssertEqual(levels[1]?[1], 0)
        let full = MergeStub.split16(MergeStub.dmx16Value(normalized: 1))
        XCTAssertEqual(levels[1]?[2], full.coarse)
        XCTAssertEqual(levels[1]?[3], full.fine)
        XCTAssertEqual(levels[1]?[2], 255)
        XCTAssertEqual(levels[1]?[3], 255)
    }

    func test16BitFractionalExactBytes() {
        let (project, fixtureID) = movingHeadProject()
        let samples: [Double] = [0.0, 0.25, 0.5, 0.75, 1.0, 0.123456, 0.999]
        for sample in samples {
            var look = ActiveLook()
            look.set(fixtureID: fixtureID, attribute: "pan", value: sample)
            let levels = MergeStub.merge(project: project, look: look)
            let expected = MergeStub.split16(MergeStub.dmx16Value(normalized: sample))
            XCTAssertEqual(levels[1]?[0], expected.coarse, "coarse for \(sample)")
            XCTAssertEqual(levels[1]?[1], expected.fine, "fine for \(sample)")
        }
    }

    func test16BitDefaultsWhenAttributeMissing() {
        let (project, _) = movingHeadProject()
        let levels = MergeStub.merge(project: project, look: .empty)
        XCTAssertEqual(levels[1]?[0], 128)
        XCTAssertEqual(levels[1]?[1], 0)
        XCTAssertEqual(levels[1]?[2], 128)
        XCTAssertEqual(levels[1]?[3], 0)
    }

    func testUniverseIsolation() {
        var project = ShowProject.empty()
        let u1 = UUID()
        let u2 = UUID()
        let def = UUID()
        let f1 = UUID()
        let f2 = UUID()
        project.universes = [
            Universe(id: u1, number: 1, channelCount: 512),
            Universe(id: u2, number: 2, channelCount: 512),
        ]
        project.fixtureDefinitions = [
            FixtureDefinition(
                id: def,
                manufacturer: "G",
                model: "D",
                channelCount: 1,
                channels: [ChannelDef(offset: 1, name: "I", attribute: "intensity")]
            )
        ]
        project.fixtures = [
            PatchedFixture(id: f1, name: "A", definitionId: def, universeId: u1, address: 1),
            PatchedFixture(id: f2, name: "B", definitionId: def, universeId: u2, address: 1),
        ]
        var look = ActiveLook()
        look.set(fixtureID: f1, attribute: "intensity", value: 1)
        look.set(fixtureID: f2, attribute: "intensity", value: 0.2)
        let levels = MergeStub.merge(project: project, look: look)
        XCTAssertEqual(levels[1]?[0], 255)
        XCTAssertEqual(levels[2]?[0], 51)
    }
}
