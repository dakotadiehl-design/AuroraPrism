import Foundation

/// Reference to a media file stored inside the project package (or external path later).
public struct MediaAssetRef: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    /// Path relative to the package root (e.g. `media/logo.png`).
    public var relativePath: String
    public var notes: String

    public init(
        id: UUID = UUID(),
        name: String,
        relativePath: String,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.relativePath = relativePath
        self.notes = notes
    }
}
