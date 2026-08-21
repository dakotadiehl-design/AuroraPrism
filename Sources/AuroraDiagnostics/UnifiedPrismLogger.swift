import Foundation
import OSLog

/// One joinable Unified Logging payload per structured event.
public struct PrismUnifiedLogRecord: Equatable, Sendable {
    public let code: String
    public let reference: String
    public let category: String
    public let level: String
    public let humanMessage: String
    public let technicalMessage: String
    public let publicMetadata: String

    public var independentlyJoinableText: String {
        "code=\(code) ref=\(reference) category=\(category) level=\(level) \(publicMetadata)"
    }
}

public final class UnifiedPrismLogger: PrismLogging, @unchecked Sendable {
    public static let subsystem = "com.aurora.lighting"

    private let lock = NSLock()
    private var loggers: [PrismLogCategory: Logger] = [:]
    private let configuration: () -> PrismLogConfiguration
    /// Test hook: last records emitted, bounded.
    private var captured: [PrismUnifiedLogRecord] = []
    private let captureLimit: Int

    public init(
        configuration: @escaping () -> PrismLogConfiguration = { PrismLogConfigurationStore.shared.current() },
        captureLimit: Int = 0
    ) {
        self.configuration = configuration
        self.captureLimit = max(0, captureLimit)
    }

    public func isEnabled(_ level: PrismLogLevel, category: PrismLogCategory) -> Bool {
        configuration().accepts(level, category: category)
    }

    public func log(_ event: PrismLogEvent) {
        guard isEnabled(event.level, category: event.category) else { return }
        let record = Self.makeRecord(from: event)
        if captureLimit > 0 {
            lock.lock()
            captured.append(record)
            if captured.count > captureLimit {
                captured.removeFirst(captured.count - captureLimit)
            }
            lock.unlock()
        }
        let logger = logger(for: event.category)
        logger.log(
            level: event.level.osLogType,
            "\(record.code, privacy: .public) ref=\(record.reference, privacy: .public) \(record.humanMessage, privacy: .private) \(record.technicalMessage, privacy: .private) \(record.publicMetadata, privacy: .public)"
        )
    }

    public func capturedRecords() -> [PrismUnifiedLogRecord] {
        lock.lock()
        defer { lock.unlock() }
        return captured
    }

    public static func makeRecord(from event: PrismLogEvent) -> PrismUnifiedLogRecord {
        let sanitized = PrismLogSanitizer.sanitize(event)
        let reference = PrismLogSanitizer.publicReference(for: sanitized.correlationID ?? sanitized.id)
        return PrismUnifiedLogRecord(
            code: sanitized.code,
            reference: reference,
            category: sanitized.category.rawValue,
            level: sanitized.level.rawValue,
            humanMessage: sanitized.humanMessage,
            technicalMessage: sanitized.technicalMessage ?? "",
            publicMetadata: sanitized.publicMetadataDescription
        )
    }

    private func logger(for category: PrismLogCategory) -> Logger {
        lock.lock()
        defer { lock.unlock() }
        if let existing = loggers[category] {
            return existing
        }
        let created = Logger(subsystem: Self.subsystem, category: category.rawValue)
        loggers[category] = created
        return created
    }
}
