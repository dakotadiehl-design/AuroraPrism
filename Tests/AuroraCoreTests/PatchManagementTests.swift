import AuroraCore
import AuroraModel
import Foundation
import XCTest

@MainActor
final class PatchManagementTests: XCTestCase {
    private func dimmerDefinition(id: UUID = UUID()) -> FixtureDefinition {
        FixtureDefinition(
            id: id,
            manufacturer: "Generic",
            model: "Dimmer",
            modeName: "1-channel",
            channelCount: 1,
            channels: [ChannelDef(offset: 1, name: "Intensity", attribute: "intensity")]
        )
    }

    func testAddUniverseAndPatchFixture() throws {
        let session = DocumentSession(project: ShowProject.empty(name: "Show"))
        let universe = Universe(number: 1, name: "Main")
        let definition = dimmerDefinition()
        try session.perform(AddUniverseCommand(universe: universe))
        try session.perform(
            PatchFixtureCommand(
                definition: definition,
                fixture: PatchedFixture(
                    name: "SL1",
                    definitionId: definition.id,
                    universeId: universe.id,
                    address: 1
                )
            )
        )
        XCTAssertEqual(session.project.universes.count, 1)
        XCTAssertEqual(session.project.fixtureDefinitions.count, 1)
        XCTAssertEqual(session.project.fixtures.count, 1)
    }

    /// PRE-UI-1: AddUniverseCommand rejects duplicate universe numbers.
    func testAddUniverseRejectsDuplicateNumber() throws {
        let session = DocumentSession(project: ShowProject.empty(name: "Show"))
        try session.perform(AddUniverseCommand(universe: Universe(number: 1, name: "A")))
        XCTAssertThrowsError(
            try session.perform(AddUniverseCommand(universe: Universe(number: 1, name: "B")))
        )
        XCTAssertEqual(session.project.universes.count, 1)
    }

    func testCloneFixture() throws {
        let session = DocumentSession(project: ShowProject.empty())
        let universe = Universe(number: 1)
        let definition = dimmerDefinition()
        try session.perform(AddUniverseCommand(universe: universe))
        let original = PatchedFixture(
            name: "F1",
            definitionId: definition.id,
            universeId: universe.id,
            address: 1
        )
        try session.perform(PatchFixtureCommand(definition: definition, fixture: original))
        try session.perform(ClonePatchedFixtureCommand(sourceFixtureID: original.id))
        XCTAssertEqual(session.project.fixtures.count, 2)
        XCTAssertEqual(session.project.fixtures.map(\.address).sorted(), [1, 2])
        XCTAssertTrue(session.project.patchConflicts().isEmpty)
    }

    func testRepatchOverlapThrows() throws {
        let session = DocumentSession(project: ShowProject.empty())
        let universe = Universe(number: 1)
        let definition = dimmerDefinition()
        try session.perform(AddUniverseCommand(universe: universe))
        let a = PatchedFixture(name: "A", definitionId: definition.id, universeId: universe.id, address: 1)
        let b = PatchedFixture(name: "B", definitionId: definition.id, universeId: universe.id, address: 2)
        try session.perform(PatchFixtureCommand(definition: definition, fixture: a))
        try session.perform(AddPatchedFixtureCommand(fixture: b))
        // definition already embedded
        XCTAssertThrowsError(
            try session.perform(RepatchFixtureCommand(fixtureID: b.id, universeID: universe.id, address: 1))
        )
        XCTAssertEqual(session.project.fixtures.first { $0.id == b.id }?.address, 2)
    }

    func testRemoveUniverseWithFixturesThrows() throws {
        let session = DocumentSession(project: ShowProject.empty())
        let universe = Universe(number: 1)
        let definition = dimmerDefinition()
        try session.perform(AddUniverseCommand(universe: universe))
        try session.perform(
            PatchFixtureCommand(
                definition: definition,
                fixture: PatchedFixture(
                    name: "A",
                    definitionId: definition.id,
                    universeId: universe.id,
                    address: 1
                )
            )
        )
        XCTAssertThrowsError(try session.perform(RemoveUniverseCommand(universeID: universe.id))) { error in
            guard case CommandError.universeHasFixtures = error else {
                return XCTFail("Unexpected \(error)")
            }
        }
    }

    func testBatchPatchSingleUndo() throws {
        let session = DocumentSession(project: ShowProject.empty())
        let universe = Universe(number: 1)
        try session.perform(AddUniverseCommand(universe: universe))
        let def = dimmerDefinition()
        try session.patchFixtures([
            PatchRequest(definition: def, name: "A", universeID: universe.id),
            PatchRequest(definition: def, name: "B", universeID: universe.id),
            PatchRequest(definition: def, name: "C", universeID: universe.id),
        ])
        XCTAssertEqual(session.project.fixtures.count, 3)
        XCTAssertEqual(session.project.fixtureDefinitions.count, 1)
        try session.undo()
        XCTAssertEqual(session.project.fixtures.count, 0)
        // Embed was inside the group; undoing group should remove embed too if it was part of group.
        // First perform was AddUniverse outside group; embeds+adds inside group.
        XCTAssertEqual(session.project.fixtureDefinitions.count, 0)
    }

    func testEmbedDefinitionNoOpSecondTime() throws {
        let session = DocumentSession(project: ShowProject.empty())
        let definition = dimmerDefinition()
        try session.perform(EmbedFixtureDefinitionCommand(definition: definition))
        try session.perform(EmbedFixtureDefinitionCommand(definition: definition))
        XCTAssertEqual(session.project.fixtureDefinitions.count, 1)
        try session.undo()
        // Second embed was no-op; only first embed is on stack (two commands though)
        // First undo undoes second no-op; second undoes real embed.
        try session.undo()
        XCTAssertEqual(session.project.fixtureDefinitions.count, 0)
    }

    func testAddressOutOfRange() throws {
        let session = DocumentSession(project: ShowProject.empty())
        let universe = Universe(number: 1, channelCount: 4)
        let definition = FixtureDefinition(
            manufacturer: "G",
            model: "Wide",
            channelCount: 4,
            channels: (1...4).map { ChannelDef(offset: UInt16($0), name: "C\($0)", attribute: "unknown") }
        )
        try session.perform(AddUniverseCommand(universe: universe))
        try session.perform(EmbedFixtureDefinitionCommand(definition: definition))
        let fixture = PatchedFixture(
            name: "X",
            definitionId: definition.id,
            universeId: universe.id,
            address: 2
        )
        XCTAssertThrowsError(try session.perform(AddPatchedFixtureCommand(fixture: fixture)))
    }
}
