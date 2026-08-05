import AuroraModel
import Foundation

/// Removes a patched fixture and strips its id from groups (restored on undo).
@MainActor
public final class RemovePatchedFixtureCommand: Command {
    public let name: String
    private let fixtureID: UUID
    private var removed: PatchedFixture?
    private var groupMemberships: [(groupID: UUID, index: Int)] = []

    public init(fixtureID: UUID, name: String = "Remove Fixture") {
        self.fixtureID = fixtureID
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        guard let index = context.project.fixtures.firstIndex(where: { $0.id == fixtureID }) else {
            throw CommandError.fixtureNotFound(fixtureID)
        }
        let fixture = context.project.fixtures[index]
        removed = fixture

        var memberships: [(groupID: UUID, index: Int)] = []
        context.updateProject { project in
            project.fixtures.remove(at: index)
            for g in 0..<project.groups.count {
                if let fi = project.groups[g].fixtureIds.firstIndex(of: fixtureID) {
                    memberships.append((project.groups[g].id, fi))
                    project.groups[g].fixtureIds.remove(at: fi)
                }
            }
            project.metadata.modifiedAt = Date()
        }
        groupMemberships = memberships
    }

    public func undo(context: CommandContext) throws {
        guard let fixture = removed else { return }
        context.updateProject { project in
            project.fixtures.append(fixture)
            // Restore group memberships at recorded indices when possible.
            for membership in groupMemberships.reversed() {
                guard let gi = project.groups.firstIndex(where: { $0.id == membership.groupID }) else {
                    continue
                }
                let idx = min(membership.index, project.groups[gi].fixtureIds.count)
                project.groups[gi].fixtureIds.insert(fixtureID, at: idx)
            }
            project.metadata.modifiedAt = Date()
        }
    }
}
