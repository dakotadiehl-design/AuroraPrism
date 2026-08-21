import AuroraModel
import Foundation

/// Pure group-dimmer math shared by Programmer UI surfaces.
public enum ProgrammerIntensityGroup {
    /// Effective intensity for each capable fixture in selection order.
    /// The resolved look supplies playback + effects + Programmer values. Color-only
    /// fixtures use a neutral virtual dimmer of 1 when no explicit scale is present.
    public static func effectiveValues(
        fixtureIDs: [UUID],
        project: ShowProject,
        resolvedValues: [UUID: [String: Double]]
    ) -> [UUID: Double] {
        let physical = ProgrammerAttributePresentationResolver.physicalCapabilityMap(
            orderedFixtureIDs: fixtureIDs,
            project: project
        )
        var result: [UUID: Double] = [:]
        result.reserveCapacity(fixtureIDs.count)

        for id in fixtureIDs {
            let caps = physical[id] ?? []
            let mode = ProgrammerAttributePresentationResolver.effectiveIntensityMode(physicalCaps: caps)
            guard mode != .unsupported else { continue }
            let attributes = resolvedValues[id] ?? [:]
            if let value = attributes["intensity"] ?? attributes["dimmer"] ?? attributes["dim"] {
                result[id] = min(1, max(0, value))
            } else if mode == .virtualEmitterScale {
                result[id] = 1
            } else {
                // A capable physical dimmer absent from the resolved look is dark.
                result[id] = 0
            }
        }
        return result
    }

    public static func average(_ values: [UUID: Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.values.reduce(0, +) / Double(values.count)
    }

    /// Moves every fixture by the same percentage-point delta from the current
    /// selection average. This preserves the spacing between levels until a fixture
    /// reaches 0 or 1, and ensures dark fixtures participate in group changes.
    public static func shiftedValues(
        _ values: [UUID: Double],
        toAverage targetAverage: Double
    ) -> [UUID: Double] {
        guard !values.isEmpty else { return [:] }
        let target = min(1, max(0, targetAverage))
        let currentAverage = average(values) ?? 0
        let delta = target - currentAverage
        return values.mapValues { min(1, max(0, $0 + delta)) }
    }
}
