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
    /// Uses `Int` math throughout to avoid UInt16 overflow traps on corrupt data (PRE-UI-6).
    func nextFreeAddress(in universeId: UUID, channelCount requested: UInt16) -> UInt16? {
        guard let universe = universe(id: universeId), requested >= 1 else { return nil }
        let capacity = Int(universe.channelCount)
        let need = Int(requested)
        guard need <= capacity else { return nil }

        let occupied: [(start: Int, end: Int)] = fixtures
            .filter { $0.universeId == universeId }
            .map { f in
                let c = Int(channelCount(for: f))
                let start = Int(f.address)
                let end = Int(f.endAddress(channelCount: UInt16(clamping: c)))
                return (start, end)
            }
            .sorted { $0.start < $1.start }

        var candidate = 1
        for (start, end) in occupied {
            if candidate + need - 1 < start {
                return UInt16(candidate)
            }
            if end + 1 > candidate {
                candidate = end + 1
            }
        }
        if candidate + need - 1 <= capacity {
            return UInt16(candidate)
        }
        return nil
    }
}
