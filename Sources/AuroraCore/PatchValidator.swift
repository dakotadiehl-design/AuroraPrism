import AuroraModel
import Foundation

public enum FixtureNameValidator {
    public static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func validate(
        _ name: String,
        in project: ShowProject,
        excluding fixtureIDs: Set<UUID> = []
    ) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CommandError.message("Fixture name cannot be empty") }
        let key = normalized(trimmed)
        if project.fixtures.contains(where: {
            !fixtureIDs.contains($0.id) && normalized($0.name) == key
        }) {
            throw CommandError.message("A fixture named ‘\(trimmed)’ already exists")
        }
    }

    public static func validateBatch(
        _ names: [String],
        in project: ShowProject,
        excluding fixtureIDs: Set<UUID> = []
    ) throws {
        var seen = Set<String>()
        for name in names {
            try validate(name, in: project, excluding: fixtureIDs)
            let key = normalized(name)
            guard seen.insert(key).inserted else {
                throw CommandError.message("Fixture name ‘\(name.trimmingCharacters(in: .whitespacesAndNewlines))’ is duplicated")
            }
        }
    }

    public static func uniqueCopyName(for sourceName: String, in project: ShowProject) -> String {
        let keys = Set(project.fixtures.map { normalized($0.name) })
        var candidate = "\(sourceName) copy"
        var suffix = 2
        while keys.contains(normalized(candidate)) {
            candidate = "\(sourceName) copy \(suffix)"
            suffix += 1
        }
        return candidate
    }
}

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
