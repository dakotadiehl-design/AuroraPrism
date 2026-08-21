import Foundation
import OSLog

/// Operator-facing and internal severity. Ordered for threshold comparison.
public enum PrismLogLevel: String, Codable, Sendable, CaseIterable, Comparable {
    case off
    case debug
    case info
    case notice
    case warning
    case error
    case fault

    public var rank: Int {
        switch self {
        case .off: return 0
        case .debug: return 1
        case .info: return 2
        case .notice: return 3
        case .warning: return 4
        case .error: return 5
        case .fault: return 6
        }
    }

    public static func < (lhs: PrismLogLevel, rhs: PrismLogLevel) -> Bool {
        lhs.rank < rhs.rank
    }

    /// Settings picker values. `off` always preserves error and fault diagnostics.
    public func accepts(_ eventLevel: PrismLogLevel) -> Bool {
        guard eventLevel != .off else { return false }
        if self == .off {
            return eventLevel >= .error
        }
        return eventLevel >= self
    }

    public var osLogType: OSLogType {
        switch self {
        case .off: return .debug
        case .debug: return .debug
        case .info: return .info
        case .notice: return .default
        case .warning, .error: return .error
        case .fault: return .fault
        }
    }

    /// Label shown in Settings.
    public var settingsLabel: String {
        switch self {
        case .off: return "Off (errors still logged)"
        case .error: return "Errors only"
        case .notice: return "High-level"
        case .info: return "Information"
        case .debug: return "Verbose"
        case .warning: return "Warnings"
        case .fault: return "Faults"
        }
    }

    /// Levels the Settings picker offers per category.
    public static var settingsChoices: [PrismLogLevel] {
        [.off, .error, .notice, .info, .debug]
    }
}
