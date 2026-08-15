import AuroraModel
import Foundation

/// Canonical fixture deletion path.
///
/// Removes the fixture from the show and cleans dependent references:
/// - group memberships
/// - Stage placements
/// - cue level rows
/// - effect fixture lists
/// - MIDI behavior fixture lists
///
/// This is **not** Unpatch — use `UnpatchFixtureCommand` to clear DMX only.
@MainActor
public final class RemovePatchedFixtureCommand: Command {
    public let name: String
    private let fixtureIDs: [UUID]

    private var removedFixtures: [PatchedFixture] = []
    private var groupMemberships: [(groupID: UUID, fixtureID: UUID, index: Int)] = []
    private var stagePlacements: [StageFixturePlacement] = []
    private var cueLevels: [(listID: UUID, cueID: UUID, level: FixtureCueLevels)] = []
    private var effectMemberships: [(effectID: UUID, fixtureID: UUID, index: Int)] = []
    private var midiBehaviorMemberships: [(behaviorID: UUID, fixtureID: UUID, index: Int)] = []

    public init(fixtureIDs: [UUID], name: String? = nil) {
        self.fixtureIDs = fixtureIDs
        if let name {
            self.name = name
        } else if fixtureIDs.count == 1 {
            self.name = "Delete Fixture"
        } else {
            self.name = "Delete \(fixtureIDs.count) Fixtures"
        }
    }

    public convenience init(fixtureID: UUID, name: String = "Delete Fixture") {
        self.init(fixtureIDs: [fixtureID], name: name)
    }

    public func perform(context: CommandContext) throws {
        let idSet = Set(fixtureIDs)
        removedFixtures = context.project.fixtures.filter { idSet.contains($0.id) }
        guard !removedFixtures.isEmpty else {
            throw CommandError.fixtureNotFound(fixtureIDs.first ?? UUID())
        }
        let removedIDs = Set(removedFixtures.map(\.id))

        var memberships: [(groupID: UUID, fixtureID: UUID, index: Int)] = []
        var placements: [StageFixturePlacement] = []
        var levels: [(listID: UUID, cueID: UUID, level: FixtureCueLevels)] = []
        var effectMem: [(effectID: UUID, fixtureID: UUID, index: Int)] = []
        var midiMem: [(behaviorID: UUID, fixtureID: UUID, index: Int)] = []

        context.updateProject { project in
            project.fixtures.removeAll { removedIDs.contains($0.id) }

            for g in 0..<project.groups.count {
                var i = 0
                while i < project.groups[g].fixtureIds.count {
                    let fid = project.groups[g].fixtureIds[i]
                    if removedIDs.contains(fid) {
                        memberships.append((project.groups[g].id, fid, i))
                        project.groups[g].fixtureIds.remove(at: i)
                    } else {
                        i += 1
                    }
                }
            }

            var layout = project.stageLayout
            placements = layout.fixtures.filter { removedIDs.contains($0.fixtureID) }
            layout.fixtures.removeAll { removedIDs.contains($0.fixtureID) }
            project.stageLayout = layout

            for li in 0..<project.cueLists.count {
                for ci in 0..<project.cueLists[li].cues.count {
                    let cue = project.cueLists[li].cues[ci]
                    let doomed = cue.levels.fixtures.filter { removedIDs.contains($0.fixtureId) }
                    for level in doomed {
                        levels.append((project.cueLists[li].id, cue.id, level))
                    }
                    if !doomed.isEmpty {
                        project.cueLists[li].cues[ci].levels.fixtures.removeAll {
                            removedIDs.contains($0.fixtureId)
                        }
                    }
                }
            }

            for ei in 0..<project.effects.count {
                var i = 0
                while i < project.effects[ei].fixtureIDs.count {
                    let fid = project.effects[ei].fixtureIDs[i]
                    if removedIDs.contains(fid) {
                        effectMem.append((project.effects[ei].id, fid, i))
                        project.effects[ei].fixtureIDs.remove(at: i)
                    } else {
                        i += 1
                    }
                }
            }

            for bi in 0..<project.midiBehaviors.count {
                var i = 0
                while i < project.midiBehaviors[bi].fixtureIDs.count {
                    let fid = project.midiBehaviors[bi].fixtureIDs[i]
                    if removedIDs.contains(fid) {
                        midiMem.append((project.midiBehaviors[bi].id, fid, i))
                        project.midiBehaviors[bi].fixtureIDs.remove(at: i)
                    } else {
                        i += 1
                    }
                }
            }

            project.metadata.modifiedAt = Date()
        }

        groupMemberships = memberships
        stagePlacements = placements
        cueLevels = levels
        effectMemberships = effectMem
        midiBehaviorMemberships = midiMem
    }

    public func undo(context: CommandContext) throws {
        guard !removedFixtures.isEmpty else { return }
        context.updateProject { project in
            for fx in removedFixtures {
                if !project.fixtures.contains(where: { $0.id == fx.id }) {
                    project.fixtures.append(fx)
                }
            }

            for membership in groupMemberships.reversed() {
                guard let gi = project.groups.firstIndex(where: { $0.id == membership.groupID }) else {
                    continue
                }
                if project.groups[gi].fixtureIds.contains(membership.fixtureID) { continue }
                let idx = min(membership.index, project.groups[gi].fixtureIds.count)
                project.groups[gi].fixtureIds.insert(membership.fixtureID, at: idx)
            }

            var layout = project.stageLayout
            for p in stagePlacements {
                if !layout.fixtures.contains(where: { $0.id == p.id }) {
                    layout.fixtures.append(p)
                }
            }
            project.stageLayout = layout

            for entry in cueLevels {
                guard let li = project.cueLists.firstIndex(where: { $0.id == entry.listID }),
                      let ci = project.cueLists[li].cues.firstIndex(where: { $0.id == entry.cueID })
                else { continue }
                if !project.cueLists[li].cues[ci].levels.fixtures.contains(where: {
                    $0.fixtureId == entry.level.fixtureId
                }) {
                    project.cueLists[li].cues[ci].levels.fixtures.append(entry.level)
                }
            }

            for membership in effectMemberships.reversed() {
                guard let ei = project.effects.firstIndex(where: { $0.id == membership.effectID }) else {
                    continue
                }
                if project.effects[ei].fixtureIDs.contains(membership.fixtureID) { continue }
                let idx = min(membership.index, project.effects[ei].fixtureIDs.count)
                project.effects[ei].fixtureIDs.insert(membership.fixtureID, at: idx)
            }

            for membership in midiBehaviorMemberships.reversed() {
                guard let bi = project.midiBehaviors.firstIndex(where: { $0.id == membership.behaviorID })
                else { continue }
                if project.midiBehaviors[bi].fixtureIDs.contains(membership.fixtureID) { continue }
                let idx = min(membership.index, project.midiBehaviors[bi].fixtureIDs.count)
                project.midiBehaviors[bi].fixtureIDs.insert(membership.fixtureID, at: idx)
            }

            project.metadata.modifiedAt = Date()
        }
    }
}

/// Alias for API clarity — same canonical deletion path as `RemovePatchedFixtureCommand`.
public typealias DeleteFixtureCommand = RemovePatchedFixtureCommand
