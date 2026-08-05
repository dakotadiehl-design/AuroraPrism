import Foundation

/// Stored multi-fixture look (broader than a single palette).
public struct Preset: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var levels: CueLevelData
    public var notes: String

    public init(
        id: UUID = UUID(),
        name: String,
        levels: CueLevelData = CueLevelData(),
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.levels = levels
        self.notes = notes
    }
}
