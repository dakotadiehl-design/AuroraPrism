import CryptoKit
import Foundation

public enum PrismACPDiagnosticIdentifier {
    public static func stableUUID(seed: String) -> String {
        if let uuid = UUID(uuidString: seed) { return uuid.uuidString.lowercased() }
        let hex = SHA256.hash(data: Data(seed.utf8)).map { String(format: "%02x", $0) }.joined()
        return "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20).prefix(12))"
    }
}
