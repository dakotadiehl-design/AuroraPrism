import Foundation

/// Snapshot of show references to one or more fixtures (for delete confirmation copy).
public struct FixtureReferenceSummary: Equatable, Sendable {
    public var fixtureIDs: [UUID]
    public var groupCount: Int
    public var stagePlacementCount: Int
    public var cueLevelCount: Int
    public var effectCount: Int
    public var midiBehaviorCount: Int

    public init(
        fixtureIDs: [UUID] = [],
        groupCount: Int = 0,
        stagePlacementCount: Int = 0,
        cueLevelCount: Int = 0,
        effectCount: Int = 0,
        midiBehaviorCount: Int = 0
    ) {
        self.fixtureIDs = fixtureIDs
        self.groupCount = groupCount
        self.stagePlacementCount = stagePlacementCount
        self.cueLevelCount = cueLevelCount
        self.effectCount = effectCount
        self.midiBehaviorCount = midiBehaviorCount
    }

    public var hasDependencies: Bool {
        groupCount > 0
            || stagePlacementCount > 0
            || cueLevelCount > 0
            || effectCount > 0
            || midiBehaviorCount > 0
    }

    /// Short operator-facing summary for confirmation dialogs.
    public var confirmationDetail: String {
        var parts: [String] = []
        if groupCount > 0 { parts.append("\(groupCount) group membership\(groupCount == 1 ? "" : "s")") }
        if stagePlacementCount > 0 {
            parts.append("\(stagePlacementCount) Stage placement\(stagePlacementCount == 1 ? "" : "s")")
        }
        if cueLevelCount > 0 { parts.append("\(cueLevelCount) cue level row\(cueLevelCount == 1 ? "" : "s")") }
        if effectCount > 0 { parts.append("\(effectCount) effect\(effectCount == 1 ? "" : "s")") }
        if midiBehaviorCount > 0 {
            parts.append("\(midiBehaviorCount) MIDI behavior\(midiBehaviorCount == 1 ? "" : "s")")
        }
        if parts.isEmpty { return "No additional references detected." }
        return "Also referenced by: " + parts.joined(separator: ", ") + "."
    }
}

public enum FixtureReferenceIndex {
    /// Aggregate references for the given fixture IDs within the project.
    public static func summarize(fixtureIDs: Set<UUID>, in project: ShowProject) -> FixtureReferenceSummary {
        guard !fixtureIDs.isEmpty else { return FixtureReferenceSummary() }

        var groupCount = 0
        for group in project.groups {
            groupCount += group.fixtureIds.filter { fixtureIDs.contains($0) }.count
        }

        let stagePlacementCount = project.stageLayout.fixtures
            .filter { fixtureIDs.contains($0.fixtureID) }
            .count

        var cueLevelCount = 0
        for list in project.cueLists {
            for cue in list.cues {
                cueLevelCount += cue.levels.fixtures.filter { fixtureIDs.contains($0.fixtureId) }.count
            }
        }

        let effectCount = project.effects
            .filter { $0.fixtureIDs.contains(where: { fixtureIDs.contains($0) }) }
            .count

        let midiBehaviorCount = project.midiBehaviors
            .filter { $0.fixtureIDs.contains(where: { fixtureIDs.contains($0) }) }
            .count

        return FixtureReferenceSummary(
            fixtureIDs: fixtureIDs.sorted { $0.uuidString < $1.uuidString },
            groupCount: groupCount,
            stagePlacementCount: stagePlacementCount,
            cueLevelCount: cueLevelCount,
            effectCount: effectCount,
            midiBehaviorCount: midiBehaviorCount
        )
    }
}
