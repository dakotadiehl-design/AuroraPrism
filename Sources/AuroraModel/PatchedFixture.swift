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
    /// Uses `Int` arithmetic to avoid trapping UInt16 overflow on bad imports (P2-10).
    public func endAddress(channelCount: UInt16) -> UInt16 {
        guard channelCount > 0 else { return address }
        let end = Int(address) + Int(channelCount) - 1
        if end < 1 { return 1 }
        if end > Int(UInt16.max) { return UInt16.max }
        return UInt16(end)
    }

    /// Validates standard DMX universe bounds (1…512).
    public static func validateDMXFootprint(address: UInt16, channelCount: UInt16, universeChannels: UInt16 = 512) -> Bool {
        guard address >= 1, channelCount >= 1 else { return false }
        let end = Int(address) + Int(channelCount) - 1
        return end <= Int(universeChannels)
    }
}
