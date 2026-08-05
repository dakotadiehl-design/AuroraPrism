import Foundation

/// Failures from command validation or apply. Failed perform must leave the project unchanged.
public enum CommandError: Error, Equatable, Sendable {
    case universeNotFound(UUID)
    case fixtureNotFound(UUID)
    case definitionNotFound(UUID)
    case patchOverlap(fixtureID: UUID, otherFixtureID: UUID)
    case invalidAddress(UInt16)
    case notGrouping
    case alreadyGrouping
    case emptyGroup
    case nothingToUndo
    case nothingToRedo
    case message(String)
}
