import Foundation

public enum PrismErrorReporting {
    /// Builds the report and logs it exactly once.
    @discardableResult
    public static func report(
        error: Error,
        context: PrismErrorContext,
        logger: (any PrismLogging)? = nil,
        correlationID: UUID = UUID()
    ) -> PrismErrorReport {
        let built = makeReport(error: error, context: context, correlationID: correlationID)
        let sink = logger ?? PrismLog.shared
        sink.log(
            PrismLogEvent(
                level: built.severity,
                category: built.category,
                code: built.code,
                humanMessage: built.userMessage,
                technicalMessage: technicalField(for: built),
                metadata: built.metadata,
                correlationID: built.correlationID
            )
        )
        return built
    }

    public static func makeReport(
        error: Error,
        context: PrismErrorContext,
        correlationID: UUID = UUID()
    ) -> PrismErrorReport {
        let chain = underlyingChain(from: error)
        if let diagnosed = error as? PrismDiagnosableError {
            return PrismErrorReport(
                code: diagnosed.prismErrorCode,
                userTitle: diagnosed.userTitle,
                userMessage: diagnosed.userMessage,
                recoverySuggestion: context.recoverySuggestion ?? diagnosed.recoverySuggestion,
                technicalDescription: diagnosed.technicalDetails,
                underlyingChain: chain,
                category: context.category ?? diagnosed.prismCategory,
                severity: diagnosed.prismSeverity,
                metadata: [
                    "operation": .string(context.operation, privacy: .public),
                ],
                correlationID: correlationID
            )
        }

        return PrismErrorReport(
            code: context.eventCode ?? "error.unknown",
            userTitle: context.fallbackTitle,
            userMessage: context.fallbackMessage,
            recoverySuggestion: context.recoverySuggestion,
            technicalDescription: technicalDescription(for: error),
            underlyingChain: chain,
            category: context.category ?? .appLifecycle,
            severity: .error,
            metadata: [
                "operation": .string(context.operation, privacy: .public),
            ],
            correlationID: correlationID
        )
    }

    @discardableResult
    public static func statusMessage(
        for error: Error,
        operation: String,
        category: PrismLogCategory = .projectDocument,
        logger: (any PrismLogging)? = nil
    ) -> String {
        report(
            error: error,
            context: .command(operation: operation, category: category),
            logger: logger
        ).userMessage
    }

    public static func userFacingMessage(
        for error: Error,
        context: PrismErrorContext? = nil,
        fallback: String = "Something went wrong."
    ) -> String {
        if let diagnosed = error as? PrismDiagnosableError {
            return diagnosed.userMessage
        }
        if let localized = error as? LocalizedError, let description = localized.errorDescription, !description.isEmpty {
            return description
        }
        return context?.fallbackMessage ?? fallback
    }

    public static func underlyingChain(from error: Error) -> [String] {
        var chain: [String] = []
        var current: Error? = error
        var seen = 0
        while let item = current, seen < 8 {
            chain.append(describe(item))
            current = (item as NSError).userInfo[NSUnderlyingErrorKey] as? Error
            seen += 1
        }
        return chain
    }

    private static func technicalField(for report: PrismErrorReport) -> String {
        var parts = [report.technicalDescription]
        if !report.underlyingChain.isEmpty {
            parts.append("cause=" + report.underlyingChain.joined(separator: " <- "))
        }
        return parts.joined(separator: "; ")
    }

    private static func technicalDescription(for error: Error) -> String {
        let ns = error as NSError
        var parts = [
            String(reflecting: error),
            "domain=\(ns.domain)",
            "code=\(ns.code)",
        ]
        if let reason = ns.localizedFailureReason, !reason.isEmpty {
            parts.append("failureReason=\(reason)")
        }
        return parts.joined(separator: "; ")
    }

    private static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(String(reflecting: error)) [\(ns.domain)#\(ns.code)]"
    }
}
