import Foundation

/// Named selection of fixtures.
public struct Group: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var fixtureIds: [UUID]
    public var notes: String

    public init(
        id: UUID = UUID(),
        name: String,
        fixtureIds: [UUID] = [],
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.fixtureIds = fixtureIds
        self.notes = notes
    }
}
