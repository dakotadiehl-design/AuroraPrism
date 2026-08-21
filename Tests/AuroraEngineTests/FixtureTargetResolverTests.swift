import AuroraEngine
import AuroraModel
import XCTest

final class FixtureTargetResolverTests: XCTestCase {
    func testTestShowPhysicalGroupResolvesToOnlyItsScopedProgrammerKeys() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let project = try ProjectPackage.load(from: repository.appendingPathComponent("smoketest files/Test Show.prism"))
        let fixture = try XCTUnwrap(project.fixtures.first { fixture in
            project.definition(id: fixture.definitionId)?.model == "COLORband Q3BT ILS"
                && project.definition(id: fixture.definitionId)?.channelCount == 16
        })
        let definition = try XCTUnwrap(project.definition(id: fixture.definitionId))
        let descriptor = project.visualizationDescriptor(for: definition)
        let emitter = try XCTUnwrap(descriptor.emitters.first)
        let resolution = FixturePhysicalControlMapper.resolve(
            physicalEmitterID: emitter.id,
            descriptor: descriptor,
            definition: definition
        )
        guard case .controls(let controls) = resolution.disposition else {
            return XCTFail("Expected a controllable COLORband physical group")
        }
        let control = try XCTUnwrap(controls.first)
        let batch = FixtureTargetResolver.batch(
            targets: [FixtureTarget(fixtureID: fixture.id, elementID: control)],
            attributes: ["colorR": 1, "colorG": 0, "colorB": 0],
            project: project
        )
        let keys = Set(batch[fixture.id].map { Array($0.keys) } ?? [])
        XCTAssertEqual(keys, Set(["colorR@\(control)", "colorG@\(control)", "colorB@\(control)"]))
        XCTAssertFalse(keys.contains { key in definition.controlElements.contains { other in other.id != control && key.hasSuffix("@\(other.id)") } })
    }

    func testTestShowSharedPersonalityExplicitlyResolvesPhysicalClickToWholeFixture() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let project = try ProjectPackage.load(from: repository.appendingPathComponent("smoketest files/Test Show.prism"))
        let fixture = try XCTUnwrap(project.fixtures.first { fixture in
            project.definition(id: fixture.definitionId)?.model == "4Bar Hex ILS"
                && project.definition(id: fixture.definitionId)?.channelCount == 6
        })
        let definition = try XCTUnwrap(project.definition(id: fixture.definitionId))
        let descriptor = project.visualizationDescriptor(for: definition)
        let emitter = try XCTUnwrap(descriptor.emitters.first)
        XCTAssertEqual(
            FixturePhysicalControlMapper.resolve(
                physicalEmitterID: emitter.id,
                descriptor: descriptor,
                definition: definition
            ).disposition,
            .wholeFixture
        )
    }

    func testElementScopesCellAttributesButKeepsSharedAttributes() {
        let fixtureID = UUID()
        let universe = Universe(number: 1)
        let definition = FixtureDefinition(
            manufacturer: "Chauvet",
            model: "4Bar",
            channels: [ChannelDef(offset: 1, name: "Master", attribute: "intensity")],
            cellBlock: FixtureCellBlock(
                channels: [
                    ChannelDef(offset: 1, name: "R", attribute: "colorR"),
                    ChannelDef(offset: 2, name: "G", attribute: "colorG"),
                    ChannelDef(offset: 3, name: "B", attribute: "colorB"),
                ],
                cellCount: 4,
                cellLabelPrefix: "Pod"
            )
        )
        var project = ShowProject.empty(name: "Elements")
        project.universes = [universe]
        project.fixtureDefinitions = [definition]
        project.fixtures = [PatchedFixture(
            id: fixtureID,
            name: "Bar 1",
            definitionId: definition.id,
            universeId: universe.id,
            address: 1
        )]

        let batch = FixtureTargetResolver.batch(
            targets: [.cell(fixtureID: fixtureID, index: 2)],
            attributes: ["colorR": 0.8, "colorHue": 0.25, "intensity": 0.6],
            project: project
        )

        XCTAssertEqual(batch[fixtureID]?["colorR@2"], 0.8)
        XCTAssertEqual(batch[fixtureID]?["colorHue@2"], 0.25)
        XCTAssertEqual(batch[fixtureID]?["intensity"], 0.6)
        XCTAssertNil(batch[fixtureID]?["colorR"])
        XCTAssertNil(batch[fixtureID]?["colorHue"])
    }

    func testWholeFixtureExpandsCellAttributesAcrossAllElements() {
        let fixtureID = UUID()
        let universe = Universe(number: 1)
        let definition = FixtureDefinition(
            manufacturer: "Generic",
            model: "Pixel Bar",
            channels: [],
            cellBlock: FixtureCellBlock(
                channels: [ChannelDef(offset: 1, name: "R", attribute: "colorR")],
                cellCount: 4
            )
        )
        var project = ShowProject.empty(name: "Elements")
        project.universes = [universe]
        project.fixtureDefinitions = [definition]
        project.fixtures = [PatchedFixture(id: fixtureID, name: "Bar", definitionId: definition.id, universeId: universe.id, address: 1)]

        let batch = FixtureTargetResolver.batch(
            targets: [FixtureTarget(fixtureID: fixtureID)],
            attributes: ["colorR": 1],
            project: project
        )

        XCTAssertEqual(Set(batch[fixtureID].map { Array($0.keys) } ?? []), Set(["colorR@0", "colorR@1", "colorR@2", "colorR@3"]))
    }

    func testExplicitGroupedFixtureWritesOnlyTheSelectedGroup() {
        let fixtureID = UUID()
        let universe = Universe(number: 1)
        let channels = (0..<3).flatMap { group in
            ["colorR", "colorG", "colorB", "colorA"].enumerated().map { index, attribute in
                ChannelDef(
                    offset: UInt16(group * 4 + index + 1), name: attribute,
                    attribute: attribute, elementID: "element-\(group)"
                )
            }
        }
        let definition = FixtureDefinition(manufacturer: "Synthetic", model: "Grouped Bar", channels: channels)
        var project = ShowProject.empty(name: "Grouped")
        project.universes = [universe]
        project.fixtureDefinitions = [definition]
        project.fixtures = [PatchedFixture(
            id: fixtureID, name: "Bar", definitionId: definition.id,
            universeId: universe.id, address: 1
        )]

        let batch = FixtureTargetResolver.batch(
            targets: [FixtureTarget(fixtureID: fixtureID, elementID: "element-1")],
            attributes: ["colorR": 1, "colorG": 0.25, "colorB": 0],
            project: project
        )
        XCTAssertEqual(batch[fixtureID], [
            "colorR@element-1": 1,
            "colorG@element-1": 0.25,
            "colorB@element-1": 0,
        ])
        XCTAssertFalse(batch[fixtureID]?.keys.contains(where: { $0.contains("element-0") || $0.contains("element-2") }) == true)
    }
}
