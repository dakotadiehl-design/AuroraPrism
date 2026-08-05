import Foundation

struct SeedCatalog: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var entries: [SeedCatalogEntry]
}

struct SeedCatalogEntry: Codable, Equatable, Sendable {
    var id: UUID
    var manufacturer: String
    var model: String
    var modeName: String
    var file: String
}
