import Foundation

public protocol PrismLogging: Sendable {
    func log(_ event: PrismLogEvent)
    func isEnabled(_ level: PrismLogLevel, category: PrismLogCategory) -> Bool
}

public extension PrismLogging {
    func isEnabled(_ level: PrismLogLevel, category: PrismLogCategory) -> Bool {
        PrismLogConfigurationStore.shared.current().accepts(level, category: category)
    }
}

/// Process-wide bootstrap. Controllers may also hold an injected `any PrismLogging`.
public enum PrismLog {
    private static let lock = NSLock()
    private static var _shared: any PrismLogging = PrismNoOpLogger()

    public static var shared: any PrismLogging {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _shared
        }
        set {
            lock.lock()
            _shared = newValue
            lock.unlock()
        }
    }

    public static func debug(
        _ category: PrismLogCategory,
        _ code: String,
        _ message: @autoclosure () -> String,
        technical: @autoclosure () -> String? = nil,
        metadata: @autoclosure () -> [String: PrismLogValue] = [:],
        correlationID: UUID? = nil,
        ratePolicy: PrismLogRatePolicy? = nil,
        logger: (any PrismLogging)? = nil
    ) {
        emit(
            .debug,
            category,
            code,
            { message() },
            technical: { technical() },
            metadata: { metadata() },
            correlationID: correlationID,
            ratePolicy: ratePolicy,
            logger: logger
        )
    }

    public static func info(
        _ category: PrismLogCategory,
        _ code: String,
        _ message: @autoclosure () -> String,
        technical: @autoclosure () -> String? = nil,
        metadata: @autoclosure () -> [String: PrismLogValue] = [:],
        correlationID: UUID? = nil,
        ratePolicy: PrismLogRatePolicy? = nil,
        logger: (any PrismLogging)? = nil
    ) {
        emit(
            .info,
            category,
            code,
            { message() },
            technical: { technical() },
            metadata: { metadata() },
            correlationID: correlationID,
            ratePolicy: ratePolicy,
            logger: logger
        )
    }

    public static func notice(
        _ category: PrismLogCategory,
        _ code: String,
        _ message: @autoclosure () -> String,
        technical: @autoclosure () -> String? = nil,
        metadata: @autoclosure () -> [String: PrismLogValue] = [:],
        correlationID: UUID? = nil,
        ratePolicy: PrismLogRatePolicy? = nil,
        logger: (any PrismLogging)? = nil
    ) {
        emit(
            .notice,
            category,
            code,
            { message() },
            technical: { technical() },
            metadata: { metadata() },
            correlationID: correlationID,
            ratePolicy: ratePolicy,
            logger: logger
        )
    }

    public static func warning(
        _ category: PrismLogCategory,
        _ code: String,
        _ message: @autoclosure () -> String,
        technical: @autoclosure () -> String? = nil,
        metadata: @autoclosure () -> [String: PrismLogValue] = [:],
        correlationID: UUID? = nil,
        ratePolicy: PrismLogRatePolicy? = nil,
        logger: (any PrismLogging)? = nil
    ) {
        emit(
            .warning,
            category,
            code,
            { message() },
            technical: { technical() },
            metadata: { metadata() },
            correlationID: correlationID,
            ratePolicy: ratePolicy,
            logger: logger
        )
    }

    public static func error(
        _ category: PrismLogCategory,
        _ code: String,
        _ message: @autoclosure () -> String,
        technical: @autoclosure () -> String? = nil,
        metadata: @autoclosure () -> [String: PrismLogValue] = [:],
        correlationID: UUID? = nil,
        ratePolicy: PrismLogRatePolicy? = nil,
        logger: (any PrismLogging)? = nil
    ) {
        emit(
            .error,
            category,
            code,
            { message() },
            technical: { technical() },
            metadata: { metadata() },
            correlationID: correlationID,
            ratePolicy: ratePolicy,
            logger: logger
        )
    }

    public static func fault(
        _ category: PrismLogCategory,
        _ code: String,
        _ message: @autoclosure () -> String,
        technical: @autoclosure () -> String? = nil,
        metadata: @autoclosure () -> [String: PrismLogValue] = [:],
        correlationID: UUID? = nil,
        ratePolicy: PrismLogRatePolicy? = nil,
        logger: (any PrismLogging)? = nil
    ) {
        emit(
            .fault,
            category,
            code,
            { message() },
            technical: { technical() },
            metadata: { metadata() },
            correlationID: correlationID,
            ratePolicy: ratePolicy,
            logger: logger
        )
    }

    public static func resetForTests() {
        shared = PrismNoOpLogger()
        PrismLogConfigurationStore.shared.replace(.productionDefaults)
    }

    /// Cheap threshold probe for callers that must avoid diagnostic work on hot paths.
    public static func isEnabled(_ level: PrismLogLevel, category: PrismLogCategory) -> Bool {
        guard PrismLogConfigurationStore.shared.current().accepts(level, category: category) else { return false }
        return shared.isEnabled(level, category: category)
    }

    private static func emit(
        _ level: PrismLogLevel,
        _ category: PrismLogCategory,
        _ code: String,
        _ message: () -> String,
        technical: () -> String?,
        metadata: () -> [String: PrismLogValue],
        correlationID: UUID?,
        ratePolicy: PrismLogRatePolicy?,
        logger: (any PrismLogging)?
    ) {
        let sink = logger ?? shared
        guard PrismLogConfigurationStore.shared.current().accepts(level, category: category) else { return }
        guard sink.isEnabled(level, category: category) else { return }
        sink.log(
            PrismLogEvent(
                level: level,
                category: category,
                code: code,
                humanMessage: message(),
                technicalMessage: technical(),
                metadata: metadata(),
                correlationID: correlationID,
                ratePolicy: ratePolicy
            )
        )
    }
}

public struct PrismNoOpLogger: PrismLogging {
    public init() {}

    public func log(_ event: PrismLogEvent) {}

    public func isEnabled(_ level: PrismLogLevel, category: PrismLogCategory) -> Bool {
        false
    }
}
