import AuroraModel
import Foundation

/// Resolves Cue Blocks into literal levels with capability filtering and structured issues.
public enum CueBlockResolver {
    public struct Result: Equatable, Sendable {
        public var levels: CueLevelData
        public var issues: [CueBlockResolutionIssue]

        public init(levels: CueLevelData = .empty, issues: [CueBlockResolutionIssue] = []) {
            self.levels = levels
            self.issues = issues
        }
    }

    /// Recall a single Cue Block for Programmer (no mutation). Always capability-filters.
    public static func resolveBlockForRecall(
        cueBlock: CueBlock,
        project: ShowProject
    ) -> Result {
        resolveBlock(
            cueBlock: cueBlock,
            project: project,
            cueID: nil,
            referenceID: nil,
            capabilityMap: FixtureCapabilityMap.build(from: project)
        )
    }

    /// Compose a cue: enabled Cue Blocks (order, later wins) then cue palette refs then cue literals.
    /// Capability filtering applies **only** to Cue Block contributions.
    public static func resolveCueLevels(
        cue: Cue,
        project: ShowProject
    ) -> Result {
        let capabilityMap = FixtureCapabilityMap.build(from: project)
        var issues: [CueBlockResolutionIssue] = []
        var mergedByFixture: [UUID: [String: Double]] = [:]
        var fixtureOrder: [UUID] = []

        // Malformed/imported projects may contain duplicate IDs. Validation reports them,
        // but live resolution must never trap; first document occurrence is authoritative.
        var blockByID: [UUID: CueBlock] = [:]
        for block in project.cueBlocks where blockByID[block.id] == nil {
            blockByID[block.id] = block
        }

        for ref in cue.cueBlockRefs {
            if blockByID[ref.cueBlockID] == nil {
                issues.append(CueBlockResolutionIssue(
                    code: "missing-cue-block",
                    severity: .error,
                    message: "Missing Cue Block \(ref.cueBlockID.uuidString)",
                    cueID: cue.id,
                    referenceID: ref.id,
                    cueBlockID: ref.cueBlockID
                ))
                continue
            }
            guard ref.enabled else { continue }
            guard let block = blockByID[ref.cueBlockID] else { continue }

            let blockResult = resolveBlock(
                cueBlock: block,
                project: project,
                cueID: cue.id,
                referenceID: ref.id,
                capabilityMap: capabilityMap
            )
            issues.append(contentsOf: blockResult.issues)

            for fx in blockResult.levels.fixtures {
                if mergedByFixture[fx.fixtureId] == nil {
                    fixtureOrder.append(fx.fixtureId)
                    mergedByFixture[fx.fixtureId] = [:]
                }
                for (k, v) in fx.attributes {
                    mergedByFixture[fx.fixtureId]?[k] = v
                }
            }
        }

        // Existing cue palette + literal path (unchanged; not capability-filtered here).
        let cueResolved = PaletteResolver.resolve(levels: cue.levels, project: project, cueID: cue.id)
        for issue in cueResolved.issues {
            issues.append(CueBlockResolutionIssue(
                code: "palette-resolution",
                severity: .warning,
                message: issue.message,
                cueID: issue.cueID ?? cue.id,
                paletteID: issue.paletteID,
                attribute: issue.attribute
            ))
        }
        for fx in cueResolved.levels.fixtures {
            if mergedByFixture[fx.fixtureId] == nil {
                fixtureOrder.append(fx.fixtureId)
                mergedByFixture[fx.fixtureId] = [:]
            }
            for (k, v) in fx.attributes {
                mergedByFixture[fx.fixtureId]?[k] = v
            }
        }

        // Preserve deterministic fixture order: first appearance from blocks (array order), then cue levels.
        var fixtures: [FixtureCueLevels] = []
        var seen = Set<UUID>()
        for id in fixtureOrder {
            guard !seen.contains(id), let attrs = mergedByFixture[id], !attrs.isEmpty else { continue }
            seen.insert(id)
            fixtures.append(FixtureCueLevels(fixtureId: id, attributes: attrs, paletteRefs: [:]))
        }
        for (id, attrs) in mergedByFixture.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            guard !seen.contains(id), !attrs.isEmpty else { continue }
            seen.insert(id)
            fixtures.append(FixtureCueLevels(fixtureId: id, attributes: attrs, paletteRefs: [:]))
        }

        return Result(levels: CueLevelData(fixtures: fixtures), issues: issues)
    }

    // MARK: - Internals

    private static func resolveBlock(
        cueBlock: CueBlock,
        project: ShowProject,
        cueID: UUID?,
        referenceID: UUID?,
        capabilityMap: [UUID: Set<String>]
    ) -> Result {
        var issues: [CueBlockResolutionIssue] = []

        if cueBlock.levels.fixtures.isEmpty {
            issues.append(CueBlockResolutionIssue(
                code: "empty-cue-block",
                severity: .warning,
                message: "Cue Block \(cueBlock.name) is empty",
                cueID: cueID,
                referenceID: referenceID,
                cueBlockID: cueBlock.id
            ))
            return Result(levels: .empty, issues: issues)
        }

        let paletteResolved = PaletteResolver.resolve(
            levels: cueBlock.levels,
            project: project,
            cueID: cueID
        )
        for issue in paletteResolved.issues {
            issues.append(CueBlockResolutionIssue(
                code: "missing-palette-in-block",
                severity: .warning,
                message: "Cue Block \(cueBlock.name): \(issue.message)",
                cueID: cueID,
                referenceID: referenceID,
                cueBlockID: cueBlock.id,
                paletteID: issue.paletteID,
                attribute: issue.attribute
            ))
        }

        var fixtures: [FixtureCueLevels] = []
        for fx in paletteResolved.levels.fixtures {
            let patchExists = project.fixtures.contains(where: { $0.id == fx.fixtureId })
            if !patchExists {
                issues.append(CueBlockResolutionIssue(
                    code: "missing-fixture",
                    severity: .warning,
                    message: "Cue Block \(cueBlock.name) references missing fixture \(fx.fixtureId.uuidString)",
                    cueID: cueID,
                    referenceID: referenceID,
                    cueBlockID: cueBlock.id,
                    fixtureID: fx.fixtureId
                ))
            }

            let supported = capabilityMap[fx.fixtureId] ?? []
            if patchExists && supported.isEmpty {
                issues.append(CueBlockResolutionIssue(
                    code: "fixture-no-supported-attributes",
                    severity: .warning,
                    message: "Fixture \(fx.fixtureId.uuidString) has no supported attributes",
                    cueID: cueID,
                    referenceID: referenceID,
                    cueBlockID: cueBlock.id,
                    fixtureID: fx.fixtureId
                ))
            }

            let filtered = FixtureCapabilityMap.filterAttributes(fx.attributes, supported: supported)
            for attr in filtered.dropped {
                issues.append(CueBlockResolutionIssue(
                    code: "capability-filtered-attribute",
                    severity: .warning,
                    message: "Dropped unsupported attribute \(attr) from Cue Block \(cueBlock.name)",
                    cueID: cueID,
                    referenceID: referenceID,
                    cueBlockID: cueBlock.id,
                    fixtureID: fx.fixtureId,
                    attribute: attr
                ))
            }
            if !filtered.kept.isEmpty {
                fixtures.append(FixtureCueLevels(
                    fixtureId: fx.fixtureId,
                    attributes: filtered.kept,
                    paletteRefs: [:]
                ))
            }
        }

        return Result(levels: CueLevelData(fixtures: fixtures), issues: issues)
    }
}
