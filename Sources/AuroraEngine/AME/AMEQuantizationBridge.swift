import AuroraModel
import AuroraMusical
import Foundation

/// Maps AME quantization model types → Musical Engine scheduler types (Phase G).
public enum AMEQuantizationBridge {
    public static func musicalBoundary(from ame: AMEQuantizationBoundary?) -> MusicalBoundary {
        guard let ame else { return .immediate }
        switch ame {
        case .immediate:
            return .immediate
        case .nextSixteenth:
            return .next(.must(unit: .sixteenth, count: 1))
        case .nextEighth:
            return .next(.must(unit: .eighth, count: 1))
        case .nextQuarter:
            return .next(.must(unit: .quarter, count: 1))
        case .nextMetricalBeat:
            return .nextMetricalBeat
        case .nextBar:
            return .nextBar
        }
    }

    public static func failurePolicy(from ame: AMEQuantizationFailurePolicy) -> QuantizationFailurePolicy {
        switch ame {
        case .cancel: return .cancel
        case .executeImmediately: return .executeImmediately
        case .holdUntilTimingAvailable: return .holdUntilTimingAvailable
        }
    }

    /// Whether the host should schedule via MusicalEngine rather than applying immediately.
    public static func shouldSchedule(_ emission: AMEActionEmission) -> Bool {
        guard emission.shouldExecute, emission.isLiveSupported else { return false }
        if emission.executeImmediately { return false }
        if emission.action.isSafetyCritical { return false }
        if emission.isRelease { return false } // releases always immediate
        // Non-immediate boundary (including hold-until-timing with deferred execution).
        if let boundary = emission.quantizeBoundary, boundary != .immediate {
            return true
        }
        // holdUntilTimingAvailable with missing musical time still needs scheduler hold.
        if emission.quantizationFailurePolicy == .holdUntilTimingAvailable,
           emission.quantizeBoundary != nil, emission.quantizeBoundary != .immediate {
            return true
        }
        return false
    }
}
