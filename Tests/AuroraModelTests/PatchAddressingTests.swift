import AuroraModel
import Foundation
import XCTest

final class PatchAddressingTests: XCTestCase {
    private func projectWithUniverse(capacity: UInt16 = 512) -> (ShowProject, UUID, UUID) {
        var project = ShowProject.empty(name: "P")
        let universeID = UUID()
        let definitionID = UUID()
        project.universes = [Universe(id: universeID, number: 1, channelCount: capacity)]
        project.fixtureDefinitions = [
            FixtureDefinition(
                id: definitionID,
                manufacturer: "G",
                model: "D",
                channelCount: 1,
                channels: [ChannelDef(offset: 1, name: "I", attribute: "intensity")]
            )
        ]
        return (project, universeID, definitionID)
    }

    func testNextFreeAddressAfterSingleChannel() {
        var (project, universeID, definitionID) = projectWithUniverse()
        project.fixtures = [
            PatchedFixture(name: "A", definitionId: definitionID, universeId: universeID, address: 1)
        ]
        XCTAssertEqual(project.nextFreeAddress(in: universeID, channelCount: 1), 2)
    }

    func testNextFreeAddressSkipsMultiChannelSpan() {
        var (project, universeID, _) = projectWithUniverse()
        let def3 = FixtureDefinition(
            id: UUID(),
            manufacturer: "G",
            model: "RGB",
            channelCount: 3,
            channels: [
                ChannelDef(offset: 1, name: "R", attribute: "colorR"),
                ChannelDef(offset: 2, name: "G", attribute: "colorG"),
                ChannelDef(offset: 3, name: "B", attribute: "colorB"),
            ]
        )
        project.fixtureDefinitions.append(def3)
        project.fixtures = [
            PatchedFixture(name: "RGB", definitionId: def3.id, universeId: universeID, address: 1)
        ]
        XCTAssertEqual(project.nextFreeAddress(in: universeID, channelCount: 2), 4)
    }

    func testNoFreeAddressWhenFull() {
        var (project, universeID, definitionID) = projectWithUniverse(capacity: 2)
        project.fixtures = [
            PatchedFixture(name: "A", definitionId: definitionID, universeId: universeID, address: 1),
            PatchedFixture(name: "B", definitionId: definitionID, universeId: universeID, address: 2),
        ]
        XCTAssertNil(project.nextFreeAddress(in: universeID, channelCount: 1))
    }

    func testCanPlaceRejectsOverlap() {
        var (project, universeID, definitionID) = projectWithUniverse()
        project.fixtures = [
            PatchedFixture(name: "A", definitionId: definitionID, universeId: universeID, address: 1)
        ]
        let other = PatchedFixture(name: "B", definitionId: definitionID, universeId: universeID, address: 1)
        XCTAssertFalse(project.canPlace(fixture: other))
    }

    func testCanPlaceIgnoringSelfForRepatch() {
        var (project, universeID, definitionID) = projectWithUniverse()
        let id = UUID()
        let fixture = PatchedFixture(id: id, name: "A", definitionId: definitionID, universeId: universeID, address: 1)
        project.fixtures = [fixture]
        XCTAssertTrue(project.canPlace(fixture: fixture, ignoringFixtureID: id))
    }
}
