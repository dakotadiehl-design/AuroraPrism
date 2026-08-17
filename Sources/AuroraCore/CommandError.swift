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

extension CommandError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .universeNotFound:
            return "The selected universe could not be found."
        case .fixtureNotFound:
            return "The selected fixture could not be found."
        case .definitionNotFound:
            return "The fixture profile could not be found."
        case .patchOverlap:
            return "That DMX address overlaps another fixture."
        case .invalidAddress(let address):
            return "DMX address \(address) is invalid."
        case .addressOutOfRange(let address, let channelCount, let universeCapacity):
            return "A \(channelCount)-channel fixture at address \(address) exceeds the universe capacity of \(universeCapacity)."
        case .noFreeAddress:
            return "There is not enough free address space in that universe."
        case .universeHasFixtures:
            return "This universe still contains fixtures. Move or delete them first."
        case .notGrouping:
            return "No grouped operation is currently active."
        case .alreadyGrouping:
            return "A grouped operation is already active."
        case .emptyGroup:
            return "The grouped operation did not contain any changes."
        case .nothingToUndo:
            return "There is nothing to undo."
        case .nothingToRedo:
            return "There is nothing to redo."
        case .message(let message):
            return message
        }
    }
}
