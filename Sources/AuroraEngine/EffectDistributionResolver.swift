import AuroraModel
import Foundation

public struct ResolvedEffectTarget: Equatable, Sendable, Identifiable {
    public var id: EffectTargetID { target }
    public let target: EffectTargetID
    public let orderIndex: Int
    public let distributionPosition: Double

    public init(target: EffectTargetID, orderIndex: Int, distributionPosition: Double) {
        self.target = target
        self.orderIndex = orderIndex
        self.distributionPosition = distributionPosition
    }
}

public struct EffectDistributionContext: Equatable, Sendable {
    public var stagePlacements: [StageFixturePlacement]
    public var fixtureNumbers: [UUID: Int]
    public var dmxAddresses: [UUID: Int]
    public var paletteColors: [UUID: EffectColor]
    public var fixtureElementIDs: [UUID: [String]]
    public var fixtureGroups: [UUID: Set<UUID>]
    /// Effect definitions available for resolving linked reusable effects.
    public var templateEffects: [UUID: EffectInstance]

    public init(
        stagePlacements: [StageFixturePlacement] = [],
        fixtureNumbers: [UUID: Int] = [:],
        dmxAddresses: [UUID: Int] = [:],
        paletteColors: [UUID: EffectColor] = [:],
        fixtureElementIDs: [UUID: [String]] = [:],
        fixtureGroups: [UUID: Set<UUID>] = [:],
        templateEffects: [UUID: EffectInstance] = [:]
    ) {
        self.stagePlacements = stagePlacements
        self.fixtureNumbers = fixtureNumbers
        self.dmxAddresses = dmxAddresses
        self.paletteColors = paletteColors
        self.fixtureElementIDs = fixtureElementIDs
        self.fixtureGroups = fixtureGroups
        self.templateEffects = templateEffects
    }
}

/// Resolves dynamic stage rules and normalized fan positions during compilation.
/// No distribution sorting or grouping belongs in the frame evaluator.
public enum EffectDistributionResolver {
    public static func resolve(
        targets: [EffectTargetID],
        definition: FixtureDistributionDefinition,
        stagePlacements: [StageFixturePlacement]
    ) -> [ResolvedEffectTarget] {
        resolve(targets: targets, definition: definition, context: .init(stagePlacements: stagePlacements))
    }

    public static func resolve(
        targets: [EffectTargetID],
        definition: FixtureDistributionDefinition,
        context: EffectDistributionContext
    ) -> [ResolvedEffectTarget] {
        let uniqueTargets = stableUnique(targets)
        guard !uniqueTargets.isEmpty else { return [] }
        var placements: [UUID: StageFixturePlacement] = [:]
        for placement in context.stagePlacements where placements[placement.fixtureID] == nil {
            placements[placement.fixtureID] = placement
        }
        let ordered = orderedTargets(uniqueTargets, definition: definition, placements: placements, context: context)
        let groupCount = max(1, Int(ceil(Double(ordered.count) / Double(definition.grouping))))

        return ordered.enumerated().map { index, target in
            let groupIndex = index / definition.grouping
            var position = groupCount > 1 ? Double(groupIndex) / Double(groupCount - 1) : 0
            position = repeatPosition(position, repetitions: definition.repetitions)
            position = symmetricPosition(position, mode: definition.symmetry)
            position = distributionCurve(position, definition: definition)
            return ResolvedEffectTarget(target: target, orderIndex: index, distributionPosition: position)
        }
    }

    /// Converts the currently calculated order into an explicit custom order.
    public static func freezeCurrentSpatialOrder(
        targets: [EffectTargetID],
        definition: FixtureDistributionDefinition,
        stagePlacements: [StageFixturePlacement]
    ) -> FixtureDistributionDefinition {
        var frozen = definition
        frozen.frozenOrder = resolve(
            targets: targets,
            definition: definition,
            stagePlacements: stagePlacements
        ).map(\.target)
        return frozen
    }

    private static func orderedTargets(
        _ targets: [EffectTargetID],
        definition: FixtureDistributionDefinition,
        placements: [UUID: StageFixturePlacement],
        context: EffectDistributionContext
    ) -> [EffectTargetID] {
        if let frozen = definition.frozenOrder, !frozen.isEmpty {
            return mergeExplicitOrder(frozen, eligible: targets)
        }

        switch definition.order {
        case .selection:
            return targets
        case .fixtureNumber:
            return keyedSort(targets, values: context.fixtureNumbers)
        case .dmxAddress:
            return keyedSort(targets, values: context.dmxAddresses)
        case .custom:
            return mergeExplicitOrder(definition.customOrder, eligible: targets)
        case .random:
            return seededShuffle(targets, seed: definition.randomSeed)
        case .stageLeftToRight:
            return spatialSort(targets, placements: placements, axis: \StageFixturePlacement.x, ascending: true)
        case .stageRightToLeft:
            return spatialSort(targets, placements: placements, axis: \StageFixturePlacement.x, ascending: false)
        case .stageFrontToBack:
            return spatialSort(targets, placements: placements, axis: \StageFixturePlacement.y, ascending: true)
        case .stageBackToFront:
            return spatialSort(targets, placements: placements, axis: \StageFixturePlacement.y, ascending: false)
        case .centerOut, .outsideIn:
            let positioned = targets.compactMap { target -> (EffectTargetID, Double)? in
                placements[target.fixtureID].map { (target, $0.x) }
            }
            let center = positioned.isEmpty
                ? 0
                : (positioned.map(\.1).min()! + positioned.map(\.1).max()!) / 2
            let placed = positioned.sorted {
                let l = abs($0.1 - center)
                let r = abs($1.1 - center)
                if l != r { return definition.order == .centerOut ? l < r : l > r }
                if $0.1 != $1.1 { return $0.1 < $1.1 }
                return stableTargetLess($0.0, $1.0)
            }.map(\.0)
            let missing = targets.filter { placements[$0.fixtureID] == nil }
            return placed + missing
        case .spatialRadial, .spatialAngular:
            let positioned = targets.compactMap { target -> (EffectTargetID, StageFixturePlacement)? in
                placements[target.fixtureID].map { (target, $0) }
            }
            let centerX = positioned.isEmpty ? 0 : positioned.map { $0.1.x }.reduce(0, +) / Double(positioned.count)
            let centerY = positioned.isEmpty ? 0 : positioned.map { $0.1.y }.reduce(0, +) / Double(positioned.count)
            let placed = positioned.sorted { lhs, rhs in
                let l = definition.order == .spatialRadial
                    ? hypot(lhs.1.x - centerX, lhs.1.y - centerY)
                    : atan2(lhs.1.y - centerY, lhs.1.x - centerX)
                let r = definition.order == .spatialRadial
                    ? hypot(rhs.1.x - centerX, rhs.1.y - centerY)
                    : atan2(rhs.1.y - centerY, rhs.1.x - centerX)
                return l == r ? stableTargetLess(lhs.0, rhs.0) : l < r
            }.map(\.0)
            let placedSet = Set(placed)
            return placed + targets.filter { !placedSet.contains($0) }
        }
    }

    private static func keyedSort(_ targets: [EffectTargetID], values: [UUID: Int]) -> [EffectTargetID] {
        targets.sorted { lhs, rhs in
            switch (values[lhs.fixtureID], values[rhs.fixtureID]) {
            case let (l?, r?) where l != r: return l < r
            case (_?, nil): return true
            case (nil, _?): return false
            default: return stableTargetLess(lhs, rhs)
            }
        }
    }

    private static func distributionCurve(_ position: Double, definition: FixtureDistributionDefinition) -> Double {
        switch definition.curve {
        case .linear: return position
        case .easeIn: return position * position
        case .easeOut: return 1 - (1 - position) * (1 - position)
        case .easeInOut: return position * position * (3 - 2 * position)
        case .exponential: return pow(position, definition.curveExponent)
        case .logarithmic: return 1 - pow(1 - position, definition.curveExponent)
        case .custom:
            return EffectGeneratorEvaluator.value(
                generator: CompiledEffectGenerator(definition: .init(shape: .customCurve, customCurve: definition.customCurve)),
                phase: position == 1 ? 1.nextDown : position
            )
        }
    }

    private static func spatialSort(
        _ targets: [EffectTargetID],
        placements: [UUID: StageFixturePlacement],
        axis: KeyPath<StageFixturePlacement, Double>,
        ascending: Bool
    ) -> [EffectTargetID] {
        let placed = targets.filter { placements[$0.fixtureID] != nil }.sorted { lhs, rhs in
            let l = placements[lhs.fixtureID]![keyPath: axis]
            let r = placements[rhs.fixtureID]![keyPath: axis]
            if l != r { return ascending ? l < r : l > r }
            return stableTargetLess(lhs, rhs)
        }
        return placed + targets.filter { placements[$0.fixtureID] == nil }
    }

    private static func mergeExplicitOrder(_ explicit: [EffectTargetID], eligible: [EffectTargetID]) -> [EffectTargetID] {
        let eligibleSet = Set(eligible)
        let prefix = stableUnique(explicit).filter(eligibleSet.contains)
        let prefixSet = Set(prefix)
        return prefix + eligible.filter { !prefixSet.contains($0) }
    }

    private static func stableUnique(_ targets: [EffectTargetID]) -> [EffectTargetID] {
        var seen: Set<EffectTargetID> = []
        return targets.filter { seen.insert($0).inserted }
    }

    private static func repeatPosition(_ position: Double, repetitions: Int) -> Double {
        guard repetitions > 1 else { return position }
        if position == 1 { return 1 }
        return (position * Double(repetitions)).truncatingRemainder(dividingBy: 1)
    }

    private static func symmetricPosition(_ position: Double, mode: EffectDistributionSymmetry) -> Double {
        switch mode {
        case .asymmetric: return position
        case .mirror, .centerOut: return abs(position * 2 - 1)
        case .outsideIn: return 1 - abs(position * 2 - 1)
        }
    }

    private static func seededShuffle(_ targets: [EffectTargetID], seed: UInt64) -> [EffectTargetID] {
        guard targets.count > 1 else { return targets }
        var result = targets
        var generator = SplitMix64(state: seed)
        for index in stride(from: result.count - 1, through: 1, by: -1) {
            let swapIndex = Int(generator.next() % UInt64(index + 1))
            if index != swapIndex { result.swapAt(index, swapIndex) }
        }
        return result
    }

    private static func stableTargetLess(_ lhs: EffectTargetID, _ rhs: EffectTargetID) -> Bool {
        if lhs.fixtureID != rhs.fixtureID { return lhs.fixtureID.uuidString < rhs.fixtureID.uuidString }
        return (lhs.elementID ?? "") < (rhs.elementID ?? "")
    }
}

private struct SplitMix64 {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
