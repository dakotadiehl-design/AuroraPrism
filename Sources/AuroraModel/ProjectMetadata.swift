import Foundation

/// Top-level show identity and free-form notes (not playback preferences).
public struct ProjectMetadata: Codable, Equatable, Sendable, Hashable {
    public var name: String
    public var author: String
    public var notes: String
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        name: String,
        author: String = "",
        notes: String = "",
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.name = name
        self.author = author
        self.notes = notes
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}
