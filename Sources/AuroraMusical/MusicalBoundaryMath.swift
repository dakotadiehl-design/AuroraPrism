import Foundation

/// Resolve musical boundaries for scheduling / Effects consumers.
public enum MusicalBoundaryMath {
    /// Next absolute quarter-note position for a boundary, strictly after `from` (except `.immediate` → `from`).
    /// Returns `nil` when musical time is unavailable for a non-immediate boundary.
    public static func resolve(
        _ boundary: MusicalBoundary,
        from position: QuarterNotePosition?,
        meter: MusicalMeter?,
        transport: MusicalTransport
    ) -> QuarterNotePosition? {
        switch boundary {
        case .immediate:
            return position ?? .must(0)
        case .nextBar:
            guard let position, let meter else { return nil }
            let barLen = meter.barLengthInQuarterNotes
            guard barLen > 0 else { return nil }
            let q = position.quarters
            let barIndex = Int(floor(max(0, q) / barLen))
            let barStart = Double(barIndex) * barLen
            let next = barStart + barLen
            if next <= q + 1e-12 {
                return .must(next + barLen)
            }
            return .must(next)
        case .nextMetricalBeat:
            guard let position, let meter else { return nil }
            return MusicalMeterMath.nextMetricalBeatPosition(after: position, meter: meter)
        case .next(let duration):
            guard let position else { return nil }
            let unitQN = duration.quarterNotes
            guard unitQN > 0, unitQN.isFinite else { return nil }
            let q = position.quarters
            let steps = floor(q / unitQN)
            var next = (steps + 1) * unitQN
            if abs(next - q) < 1e-12 {
                next += unitQN
            }
            // If already past this boundary due to float, ensure strictly after
            if next <= q + 1e-12 {
                next = q + unitQN
            }
            return .must(next)
        }
    }

    /// Whether a pending boundary is due given current musical position.
    public static func isDue(
        target: QuarterNotePosition,
        current: QuarterNotePosition,
        epsilon: Double = 1e-9
    ) -> Bool {
        current.quarters + epsilon >= target.quarters
    }
}
