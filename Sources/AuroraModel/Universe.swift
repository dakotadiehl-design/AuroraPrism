import Foundation

/// Preferred routing for a logical DMX universe (actual drivers land later).
public enum UniverseProtocolHint: String, Codable, Sendable, Hashable, CaseIterable {
    case none
    case local
    case artNet
    case sACN
}

/// A logical DMX universe in the show.
public struct Universe: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    /// User-facing universe index (often 1-based in UI).
    public var number: UInt16
    public var name: String
    /// Channel capacity; industry default is 512.
    public var channelCount: UInt16
    public var protocolHint: UniverseProtocolHint

    public init(
        id: UUID = UUID(),
        number: UInt16,
        name: String = "",
        channelCount: UInt16 = 512,
        protocolHint: UniverseProtocolHint = .none
    ) {
        self.id = id
        self.number = number
        self.name = name.isEmpty ? "Universe \(number)" : name
        self.channelCount = channelCount
        self.protocolHint = protocolHint
    }
}
