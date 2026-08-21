import Foundation

public enum PrismLogSanitizer {
    public static let publicKeyAllowlist: Set<String> = [
        "code", "category", "level", "count", "enabled", "ok",
        "protocol", "universe", "frameRateHz", "port", "schemaVersion",
        "durationMs", "sampled", "suppressedCount", "profile", "reference", "operation",
    ]

    public static func sanitize(_ event: PrismLogEvent) -> PrismLogEvent {
        var cleaned: [String: PrismLogValue] = [:]
        for (key, value) in event.metadata {
            cleaned[key] = sanitize(key: key, value: value)
        }
        return PrismLogEvent(
            id: event.id,
            timestamp: event.timestamp,
            level: event.level,
            category: event.category,
            code: event.code,
            humanMessage: event.humanMessage,
            technicalMessage: event.technicalMessage,
            metadata: cleaned,
            correlationID: event.correlationID,
            ratePolicy: event.ratePolicy
        )
    }

    public static func sanitize(key: String, value: PrismLogValue) -> PrismLogValue {
        if value.privacy == .public && !publicKeyAllowlist.contains(key) {
            return redacted(value)
        }
        return value
    }

    public static func publicReference(for id: UUID) -> String {
        String(id.uuidString.replacingOccurrences(of: "-", with: "").prefix(8))
    }

    /// Conservative redactor for leftover free text. Prefer omitting raw technical dumps.
    public static func redactFreeText(_ text: String) -> String {
        var result = text
        let patterns: [(String, String)] = [
            (#"(?i)(/Users/|/home/|file://)[^\s]+"#, "<path>"),
            (#"(?i)~(/[^\s]+)+"#, "<path>"),
            (#"\b(?:\d{1,3}\.){3}\d{1,3}\b"#, "<ip>"),
            (#"(?i)\b(pin|password|token|secret|keychain)\s*[:=]\s*\S+"#, "$1=<redacted>"),
            (#"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, "<email>"),
            (#"\{[^{}]{16,}\}"#, "<payload>"),
            (#"\[[^\[\]]{16,}\]"#, "<payload>"),
        ]
        for (pattern, replacement) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replacement)
            }
        }
        return result
    }

    /// Copyable support summary. Only explicitly safe, structured fields are included.
    public static func supportSummary(for report: PrismErrorReport) -> String {
        let reference = publicReference(for: report.correlationID)
        let lines = [
            "Prism support summary",
            "This copy includes only the error code, category, and a short reference ID. It does not include message text or raw system error details.",
            "code=\(report.code)",
            "category=\(report.category.rawValue)",
            "reference=\(reference)",
        ]
        return lines.joined(separator: "\n")
    }

    private static func redacted(_ value: PrismLogValue) -> PrismLogValue {
        switch value {
        case .string(let text, _): return .string(text, privacy: .private)
        case .int(let number, _): return .int(number, privacy: .private)
        case .uint(let number, _): return .uint(number, privacy: .private)
        case .double(let number, _): return .double(number, privacy: .private)
        case .bool(let flag, _): return .bool(flag, privacy: .private)
        case .identifier(let text, _): return .identifier(text, privacy: .private)
        }
    }
}
