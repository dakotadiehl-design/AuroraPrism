import Foundation

/// An instance of a personality patched into a universe.
public struct PatchedFixture: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var definitionId: UUID
    public var universeId: UUID
    /// 1-based DMX start address within the universe.
    public var address: UInt16
    public var groupIds: [UUID]
    public var notes: String

    public init(
        id: UUID = UUID(),
        name: String,
        definitionId: UUID,
        universeId: UUID,
        address: UInt16,
        groupIds: [UUID] = [],
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.definitionId = definitionId
        self.universeId = universeId
        self.address = address
        self.groupIds = groupIds
        self.notes = notes
    }

    /// Inclusive DMX end address for a fixture of the given footprint.
    public func endAddress(channelCount: UInt16) -> UInt16 {
        guard channelCount > 0 else { return address }
        return address + channelCount - 1
    }
}
