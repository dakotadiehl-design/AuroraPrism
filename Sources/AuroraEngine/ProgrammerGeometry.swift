import Foundation

/// Fan / align helpers for multi-fixture programmer edits (UI-03 amended semantics).
public enum ProgrammerGeometry {
    /// Same value for every fixture id (order irrelevant).
    public static func align(fixtureIDs: [UUID], value: Double) -> [UUID: Double] {
        let v = clamp01(value)
        var result: [UUID: Double] = [:]
        for id in fixtureIDs {
            result[id] = v
        }
        return result
    }

    /// Align to First: all capable IDs receive the **Programmer-owned** value of the first ID.
    /// `fixtureIDs` must already be ordered capable fixtures only; first entry is the reference.
    /// Returns `nil` when empty or the first fixture has no programmer value (never invents 0).
    public static func alignToFirst(fixtureIDs: [UUID], values: [UUID: Double]) -> [UUID: Double]? {
        guard let first = fixtureIDs.first,
              let ref = values[first]
        else { return nil }
        return align(fixtureIDs: fixtureIDs, value: ref)
    }

    /// Linear fan from `start` to `end` across ordered fixture ids (legacy helper).
    public static func fan(fixtureIDs: [UUID], start: Double, end: Double) -> [UUID: Double] {
        guard !fixtureIDs.isEmpty else { return [:] }
        if fixtureIDs.count == 1 {
            return [fixtureIDs[0]: clamp01(start)]
        }
        var result: [UUID: Double] = [:]
        let last = Double(fixtureIDs.count - 1)
        for (i, id) in fixtureIDs.enumerated() {
            let t = Double(i) / last
            result[id] = clamp01(start + (end - start) * t)
        }
        return result
    }

    /// UI-03 Fan: center + spread over ordered selection.
    ///
    /// Phase runs approximately −1…+1 across ordered indices.
    /// `value_i = clamp(center + phase_i * spread, 0…1)`.
    ///
    /// - Parameters:
    ///   - fixtureIDs: ordered capable fixtures only (caller filters support)
    ///   - center: center value 0…1
    ///   - spread: half-range around center (0…1 typical)
    public static func fan(
        fixtureIDs: [UUID],
        center: Double,
        spread: Double
    ) -> [UUID: Double] {
        guard !fixtureIDs.isEmpty else { return [:] }
        let c = clamp01(center)
        let s = max(0, spread)
        if fixtureIDs.count == 1 {
            return [fixtureIDs[0]: c]
        }
        var result: [UUID: Double] = [:]
        let last = Double(fixtureIDs.count - 1)
        for (i, id) in fixtureIDs.enumerated() {
            // Map i to phase in [-1, +1]
            let phase = (Double(i) / last) * 2 - 1
            result[id] = clamp01(c + phase * s)
        }
        return result
    }

    /// Derive center/spread from existing values when unambiguous (all present).
    /// Returns nil if values empty or mixed without clear span intent.
    public static func suggestCenterSpread(values: [Double]) -> (center: Double, spread: Double)? {
        guard !values.isEmpty else { return nil }
        let minV = values.min()!
        let maxV = values.max()!
        let center = (minV + maxV) / 2
        let spread = (maxV - minV) / 2
        return (center, max(spread, 0))
    }

    private static func clamp01(_ v: Double) -> Double {
        min(1, max(0, v))
    }
}
