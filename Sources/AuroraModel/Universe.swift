import Foundation

/// Preferred routing for a logical DMX universe (UI-GATE-3).
///
/// | Case | Meaning |
/// |------|---------|
/// | `none` | **No physical output** (safe default) |
/// | `local` | Local DMX driver only (e.g. ENTTEC USB Pro) |
/// | `artNet` | Art-Net drivers only |
/// | `sACN` | sACN drivers only |
/// | `mirror` | Explicit fan-out to **all** physical protocol drivers |
///
/// Do **not** treat `none` as “send everywhere”. Use `mirror` when that is intended.
public enum UniverseProtocolHint: String, Codable, Sendable, Hashable, CaseIterable {
    case none
    case local
    case artNet
    case sACN
    /// Explicit multi-protocol fan-out (not the default).
    case mirror
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
