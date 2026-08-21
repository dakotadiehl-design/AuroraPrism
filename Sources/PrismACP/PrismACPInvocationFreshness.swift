import AuroraACP
import Foundation

enum PrismACPInvocationFreshness {
    static func rejectionReason(
        payload: [String: AnySendable],
        now: Date = Date()
    ) -> String? {
        guard case .string("live_ephemeral") = payload["delivery"] else {
            return "live_ephemeral_required"
        }
        guard case .string(let issuedText) = payload["issued_at"],
              case .string(let expiresText) = payload["expires_at"],
              let issued = date(issuedText),
              let expires = date(expiresText),
              let maxAgeMS = uint(payload["max_age_ms"])
        else {
            return "freshness_metadata_required"
        }
        guard expires >= issued else { return "invalid_expiry_window" }
        guard issued.timeIntervalSince(now) <= 5 else { return "issued_in_future" }
        guard now <= expires, now.timeIntervalSince(issued) * 1_000 <= Double(maxAgeMS) else {
            return "command_expired"
        }
        return nil
    }

    private static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }

    private static func uint(_ value: AnySendable?) -> UInt64? {
        switch value {
        case .uint(let value): return value
        case .int(let value) where value >= 0: return UInt64(value)
        default: return nil
        }
    }
}
