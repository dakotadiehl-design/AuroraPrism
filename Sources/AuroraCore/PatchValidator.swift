import AuroraModel
import Foundation

/// Shared patch placement validation used by patch-related commands.
@MainActor
public enum PatchValidator {
    public static func validatePlacement(
        fixture: PatchedFixture,
        in project: ShowProject,
        ignoringFixtureID: UUID? = nil,
        requireDefinition: Bool = true
    ) throws {
        guard project.universe(id: fixture.universeId) != nil else {
            throw CommandError.universeNotFound(fixture.universeId)
        }
        if requireDefinition {
            guard let definition = project.definition(id: fixture.definitionId) else {
                throw CommandError.definitionNotFound(fixture.definitionId)
            }
            _ = definition
        }
        guard fixture.address >= 1 else {
            throw CommandError.invalidAddress(fixture.address)
        }

        guard let universe = project.universe(id: fixture.universeId) else {
            throw CommandError.universeNotFound(fixture.universeId)
        }
        let count = project.channelCount(for: fixture)
        let end = fixture.endAddress(channelCount: count)
        if end > universe.channelCount {
            throw CommandError.addressOutOfRange(
                address: fixture.address,
                channelCount: count,
                universeCapacity: universe.channelCount
            )
        }

        if !project.canPlace(fixture: fixture, ignoringFixtureID: ignoringFixtureID) {
            // Find a conflicting fixture for a useful error.
            for other in project.fixtures where other.id != ignoringFixtureID
                && other.isPatched
                && other.universeId == fixture.universeId
            {
                let otherCount = project.channelCount(for: other)
                let otherEnd = other.endAddress(channelCount: otherCount)
                if fixture.address <= otherEnd && other.address <= end {
                    throw CommandError.patchOverlap(fixtureID: fixture.id, otherFixtureID: other.id)
                }
            }
            throw CommandError.addressOutOfRange(
                address: fixture.address,
                channelCount: count,
                universeCapacity: universe.channelCount
            )
        }
    }
}
