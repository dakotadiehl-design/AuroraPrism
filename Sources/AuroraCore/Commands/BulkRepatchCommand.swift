import AuroraModel
import Foundation

/// One fixture address/universe change for atomic bulk patch (UI-09 A2).
public struct PatchAddressChange: Equatable, Sendable {
    public var fixtureID: UUID
    public var universeID: UUID
    public var address: UInt16

    public init(fixtureID: UUID, universeID: UUID, address: UInt16) {
        self.fixtureID = fixtureID
        self.universeID = universeID
        self.address = address
    }
}

/// Preflight proposed final patch, then apply all-or-nothing (UI-09 A2).
@MainActor
public final class BulkRepatchCommand: Command {
    public let name: String
    private let changes: [PatchAddressChange]
    private var previous: [UUID: (universeID: UUID, address: UInt16)] = [:]

    public init(changes: [PatchAddressChange], name: String = "Bulk Repatch") {
        self.changes = changes
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        guard !changes.isEmpty else { return }

        // Capture previous.
        previous = [:]
        for change in changes {
            guard let fx = context.project.fixtures.first(where: { $0.id == change.fixtureID }) else {
                throw CommandError.message("Fixture not found for bulk repatch")
            }
            previous[change.fixtureID] = (fx.universeId, fx.address)
        }

        // Build proposed final project (no mutation yet).
        var proposed = context.project
        for change in changes {
            guard let i = proposed.fixtures.firstIndex(where: { $0.id == change.fixtureID }) else {
                throw CommandError.message("Fixture not found")
            }
            proposed.fixtures[i].universeId = change.universeID
            proposed.fixtures[i].address = change.address
        }

        // PATCH-02: validate changed fixtures + fixtures in affected universes only.
        // Unrelated pre-existing invalid fixtures elsewhere do not block recovery edits.
        // Overlap safety is preserved within every universe touched by the change set.
        var affectedUniverses = Set<UUID>()
        var changedIDs = Set<UUID>()
        for change in changes {
            changedIDs.insert(change.fixtureID)
            affectedUniverses.insert(change.universeID)
            if let prev = previous[change.fixtureID] {
                affectedUniverses.insert(prev.universeID)
            }
        }
        let toValidate = proposed.fixtures.filter {
            changedIDs.contains($0.id) || affectedUniverses.contains($0.universeId)
        }
        for fx in toValidate {
            try PatchValidator.validatePlacement(
                fixture: fx,
                in: proposed,
                ignoringFixtureID: fx.id,
                requireDefinition: true
            )
        }

        // Apply.
        context.updateProject { project in
            for change in self.changes {
                if let i = project.fixtures.firstIndex(where: { $0.id == change.fixtureID }) {
                    project.fixtures[i].universeId = change.universeID
                    project.fixtures[i].address = change.address
                }
            }
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        context.updateProject { project in
            for (id, prev) in self.previous {
                if let i = project.fixtures.firstIndex(where: { $0.id == id }) {
                    project.fixtures[i].universeId = prev.universeID
                    project.fixtures[i].address = prev.address
                }
            }
            project.metadata.modifiedAt = Date()
        }
    }
}
