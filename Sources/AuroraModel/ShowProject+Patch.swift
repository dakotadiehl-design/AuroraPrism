import Foundation

public extension ShowProject {
    func definition(id: UUID) -> FixtureDefinition? {
        fixtureDefinitions.first { $0.id == id }
    }

    func universe(id: UUID) -> Universe? {
        universes.first { $0.id == id }
    }

    /// Channel footprint for a patched fixture (definition channelCount, else 1).
    func channelCount(for fixture: PatchedFixture) -> UInt16 {
        definition(id: fixture.definitionId)?.channelCount ?? 1
    }

    /// Inclusive DMX span for a fixture within its universe, if address is valid.
    func dmxSpan(for fixture: PatchedFixture) -> ClosedRange<UInt16>? {
        let count = channelCount(for: fixture)
        guard fixture.address >= 1, count >= 1 else { return nil }
        let end = fixture.endAddress(channelCount: count)
        return fixture.address...end
    }

    /// All pairwise patch overlaps in the project.
    func patchConflicts() -> [PatchOverlap] {
        overlappingPatchRanges()
    }

    /// Whether `fixture` can be placed without overlap and within universe capacity.
    /// - Parameter ignoringFixtureID: exclude an existing fixture (for repatch in place).
    func canPlace(fixture: PatchedFixture, ignoringFixtureID: UUID? = nil) -> Bool {
        guard let universe = universe(id: fixture.universeId) else { return false }
        guard fixture.address >= 1 else { return false }
        let count = channelCount(for: fixture)
        guard count >= 1 else { return false }
        let end = fixture.endAddress(channelCount: count)
        guard end <= universe.channelCount else { return false }

        for other in fixtures where other.id != ignoringFixtureID && other.universeId == fixture.universeId {
            let otherCount = channelCount(for: other)
            let otherEnd = other.endAddress(channelCount: otherCount)
            if fixture.address <= otherEnd && other.address <= end {
                return false
            }
        }
        return true
    }

    /// First 1-based start address in the universe that fits `channelCount` without overlap.
    func nextFreeAddress(in universeId: UUID, channelCount requested: UInt16) -> UInt16? {
        guard let universe = universe(id: universeId), requested >= 1 else { return nil }
        let capacity = universe.channelCount
        guard requested <= capacity else { return nil }

        let occupied: [(UInt16, UInt16)] = fixtures
            .filter { $0.universeId == universeId }
            .map { f in
                let c = channelCount(for: f)
                return (f.address, f.endAddress(channelCount: c))
            }
            .sorted { $0.0 < $1.0 }

        var candidate: UInt16 = 1
        for (start, end) in occupied {
            if candidate + requested - 1 < start {
                return candidate
            }
            if end + 1 > candidate {
                candidate = end + 1
            }
        }
        if candidate + requested - 1 <= capacity {
            return candidate
        }
        return nil
    }
}
