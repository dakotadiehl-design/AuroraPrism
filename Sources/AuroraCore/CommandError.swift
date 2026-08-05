import Foundation

/// Failures from command validation or apply. Failed perform must leave the project unchanged.
public enum CommandError: Error, Equatable, Sendable {
    case universeNotFound(UUID)
    case fixtureNotFound(UUID)
    case definitionNotFound(UUID)
    case patchOverlap(fixtureID: UUID, otherFixtureID: UUID)
    case invalidAddress(UInt16)
    case addressOutOfRange(address: UInt16, channelCount: UInt16, universeCapacity: UInt16)
    case noFreeAddress(universeID: UUID, channelCount: UInt16)
    case universeHasFixtures(UUID)
    case notGrouping
    case alreadyGrouping
    case emptyGroup
    case nothingToUndo
    case nothingToRedo
    case message(String)
}
