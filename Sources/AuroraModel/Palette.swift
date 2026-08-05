import Foundation

/// Reusable attribute information (color, position, etc.) — first-class, referenceable by UUID.
public struct Palette: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var type: PaletteType
    /// Attribute tag → normalized 0…1 (e.g. colorR, intensity, pan).
    public var values: [String: Double]
    public var notes: String

    public init(
        id: UUID = UUID(),
        name: String,
        type: PaletteType = .general,
        values: [String: Double] = [:],
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.values = values
        self.notes = notes
    }

    /// Backward-compatible decode: old `kind` string → type.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        values = try c.decodeIfPresent([String: Double].self, forKey: .values) ?? [:]
        if let type = try c.decodeIfPresent(PaletteType.self, forKey: .type) {
            self.type = type
        } else if let kind = try c.decodeIfPresent(String.self, forKey: .kind) {
            self.type = PaletteType(rawValue: kind) ?? .general
        } else {
            self.type = .general
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(type, forKey: .type)
        try c.encode(values, forKey: .values)
        try c.encode(notes, forKey: .notes)
        // Keep kind for older readers
        try c.encode(type.rawValue, forKey: .kind)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, type, kind, values, notes
    }
}
