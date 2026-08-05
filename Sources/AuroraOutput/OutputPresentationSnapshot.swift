import Foundation
import AuroraModel

/// Semantic output status for Perform chrome / diagnostics (PRE-UI-1).
/// Built from live `healthSnapshots()` — never a stale cached string alone.
public struct OutputPresentationSnapshot: Equatable, Sendable {
    public enum Aggregate: String, Sendable, Equatable {
        case healthy
        case warning
        case failed
        case disabled
    }

    public var aggregate: Aggregate
    public var statusLine: String
    public var details: [String]

    public init(aggregate: Aggregate, statusLine: String, details: [String] = []) {
        self.aggregate = aggregate
        self.statusLine = statusLine
        self.details = details
    }

    public static let disabled = OutputPresentationSnapshot(
        aggregate: .disabled,
        statusLine: "Output: Null only",
        details: []
    )

    /// Derive presentation from driver health snapshots.
    public static func from(health: [OutputHealthSnapshot]) -> OutputPresentationSnapshot {
        let active = health.filter { $0.state != .disabled }
        if active.isEmpty {
            return .disabled
        }

        var aggregate: Aggregate = .healthy
        for h in active {
            switch h.state {
            case .failed, .disconnected:
                aggregate = .failed
            case .degraded, .starting:
                if aggregate != .failed { aggregate = .warning }
            case .ready, .disabled:
                break
            }
        }

        var details: [String] = []
        for h in active {
            let err = h.lastError.map { " err:\($0)" } ?? ""
            let target = h.target.isEmpty ? "" : " \(h.target)"
            details.append("\(h.name) \(h.state.rawValue)\(target)\(err)")
        }

        let line: String
        if details.isEmpty {
            line = "Output: Null only"
        } else {
            line = details.joined(separator: " · ")
        }

        return OutputPresentationSnapshot(aggregate: aggregate, statusLine: line, details: details)
    }
}
