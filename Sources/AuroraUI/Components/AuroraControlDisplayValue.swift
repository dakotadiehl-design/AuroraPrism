import Foundation

/// Semantic display state for Programmer controls (UI-03 Pass 2).
/// Separate from mutation: `.mixed` remains interactive.
public enum AuroraControlDisplayValue: Equatable, Sendable {
    case value(Double)
    case mixed
    case unavailable

    public var isInteractive: Bool {
        switch self {
        case .value, .mixed: return true
        case .unavailable: return false
        }
    }

    public var concreteValue: Double? {
        if case .value(let v) = self { return v }
        return nil
    }

    public static func from(attributeState support: Bool, isMixed: Bool, displayValue: Double?, untreatedDefault: Double = 0) -> AuroraControlDisplayValue {
        guard support else { return .unavailable }
        if isMixed { return .mixed }
        if let displayValue { return .value(displayValue) }
        return .value(untreatedDefault)
    }
}
