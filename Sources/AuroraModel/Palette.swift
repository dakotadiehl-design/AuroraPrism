import Foundation

/// Reusable attribute values applied to fixtures (color, position, beam, etc.).
public struct Palette: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    /// Free-form category (e.g. `color`, `position`).
    public var kind: String
    /// Sparse attribute values keyed by attribute tag.
    public var values: [String: Double]
    public var notes: String

    public init(
        id: UUID = UUID(),
        name: String,
        kind: String = "general",
        values: [String: Double] = [:],
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.values = values
        self.notes = notes
    }
}
