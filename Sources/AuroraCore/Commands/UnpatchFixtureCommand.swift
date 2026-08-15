import AuroraModel
import Foundation

/// Clears DMX assignment for fixtures while preserving identity and project references.
///
/// Unpatch:
/// - sets `address` to `PatchedFixture.unpatchedAddress` (0)
/// - keeps `universeId` as preferred repatch target
/// - does **not** remove groups, Stage placement, cues, effects, or programming
@MainActor
public final class UnpatchFixtureCommand: Command {
    public let name: String
    private let fixtureIDs: [UUID]
    private var previous: [UUID: (universeId: UUID, address: UInt16)] = [:]

    public init(fixtureIDs: [UUID], name: String? = nil) {
        self.fixtureIDs = fixtureIDs
        if let name {
            self.name = name
        } else if fixtureIDs.count == 1 {
            self.name = "Unpatch Fixture"
        } else {
            self.name = "Unpatch \(fixtureIDs.count) Fixtures"
        }
    }

    public convenience init(fixtureID: UUID, name: String = "Unpatch Fixture") {
        self.init(fixtureIDs: [fixtureID], name: name)
    }

    public func perform(context: CommandContext) throws {
        previous = [:]
        var missing: [UUID] = []
        for id in fixtureIDs {
            guard let fx = context.project.fixtures.first(where: { $0.id == id }) else {
                missing.append(id)
                continue
            }
            if fx.isPatched {
                previous[id] = (fx.universeId, fx.address)
            }
        }
        if previous.isEmpty {
            if !missing.isEmpty {
                throw CommandError.fixtureNotFound(missing[0])
            }
            // All already unpatched — no-op (not an error).
            return
        }

        context.updateProject { project in
            for (id, prior) in previous {
                guard let idx = project.fixtures.firstIndex(where: { $0.id == id }) else { continue }
                project.fixtures[idx].universeId = prior.universeId
                project.fixtures[idx].address = PatchedFixture.unpatchedAddress
            }
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard !previous.isEmpty else { return }
        context.updateProject { project in
            for (id, prior) in previous {
                guard let idx = project.fixtures.firstIndex(where: { $0.id == id }) else { continue }
                project.fixtures[idx].universeId = prior.universeId
                project.fixtures[idx].address = prior.address
            }
            project.metadata.modifiedAt = Date()
        }
    }
}
