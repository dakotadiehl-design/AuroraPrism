import Foundation

public enum DiagnosticSeverity: String, Codable, Sendable, Hashable {
    case debug
    case info
    case warning
    case error
}

public enum DiagnosticSubsystem: String, Codable, Sendable, Hashable {
    case app
    case engine
    case output
    case midi
    case remote
    case project
    case resolution
}

/// Typed diagnostics event (P2-2).
public struct DiagnosticEvent: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var timestamp: Date
    public var subsystem: DiagnosticSubsystem
    public var severity: DiagnosticSeverity
    public var code: String?
    public var message: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        subsystem: DiagnosticSubsystem,
        severity: DiagnosticSeverity,
        code: String? = nil,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.subsystem = subsystem
        self.severity = severity
        self.code = code
        self.message = message
    }
}

/// Bounded ring buffer of diagnostic events.
public final class DiagnosticsStore: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [DiagnosticEvent] = []
    private let capacity: Int

    public init(capacity: Int = 500) {
        self.capacity = max(10, capacity)
    }

    public func record(_ event: DiagnosticEvent) {
        lock.lock()
        events.append(event)
        if events.count > capacity {
            events.removeFirst(events.count - capacity)
        }
        lock.unlock()
    }

    public func info(_ message: String, subsystem: DiagnosticSubsystem = .app) {
        record(DiagnosticEvent(subsystem: subsystem, severity: .info, message: message))
    }

    public func warning(_ message: String, subsystem: DiagnosticSubsystem = .app, code: String? = nil) {
        record(DiagnosticEvent(subsystem: subsystem, severity: .warning, code: code, message: message))
    }

    public func error(_ message: String, subsystem: DiagnosticSubsystem = .app, code: String? = nil) {
        record(DiagnosticEvent(subsystem: subsystem, severity: .error, code: code, message: message))
    }

    public func snapshot(limit: Int = 200) -> [DiagnosticEvent] {
        lock.lock()
        defer { lock.unlock() }
        return Array(events.suffix(limit))
    }

    public func clear() {
        lock.lock()
        events.removeAll()
        lock.unlock()
    }
}
