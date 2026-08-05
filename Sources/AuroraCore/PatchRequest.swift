import AuroraModel
import Foundation

/// One fixture to patch in a batch operation.
public struct PatchRequest: Sendable, Equatable {
    public var definition: FixtureDefinition
    public var name: String
    public var universeID: UUID
    /// If nil, uses `nextFreeAddress` for the definition footprint.
    public var address: UInt16?
    public var notes: String

    public init(
        definition: FixtureDefinition,
        name: String,
        universeID: UUID,
        address: UInt16? = nil,
        notes: String = ""
    ) {
        self.definition = definition
        self.name = name
        self.universeID = universeID
        self.address = address
        self.notes = notes
    }
}
