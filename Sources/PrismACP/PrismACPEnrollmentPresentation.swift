import AuroraACP
import AuroraACPAppleSecurity
import Foundation

public enum PrismACPEnrollmentCode: Sendable, Equatable {
    case highEntropy(String)
    case manualNumeric(String)

    func secret() throws -> ACPAppleEnrollmentBootstrapSecret {
        switch self {
        case .highEntropy(let value): return try .highEntropyCode(value)
        case .manualNumeric(let value): return try .manualNumericCode(value)
        }
    }
}

public struct PrismACPEnrollmentRequest: Sendable, Equatable, Identifiable {
    public let id: ACPEnrollmentAttemptID
    public let displayName: String?
    public let nodeID: ACPSecurityNodeID
    public let requestedRole: String
    public let expiresAt: Date

    init(_ request: ACPAppleEnrollmentRequestSummary) {
        id = request.requestID
        displayName = request.displayName
        nodeID = request.candidateNodeID
        requestedRole = request.requestedRole
        expiresAt = request.expiresAt
    }
}

public enum PrismACPEnrollmentPresentationState: Sendable, Equatable {
    case unavailable(PrismACPBlocker)
    case idle
    case pending([PrismACPEnrollmentRequest])
    case resolving(ACPEnrollmentAttemptID)
}

/// Presentation-only projection. The original ACP attempt identifier is
/// retained; all durable decisions and cryptographic work remain host-owned.
public actor PrismACPEnrollmentPresentationModel {
    public private(set) var state: PrismACPEnrollmentPresentationState = .idle

    public init() {}

    func update(_ requests: [ACPAppleEnrollmentRequestSummary]) {
        let values = requests.map(PrismACPEnrollmentRequest.init)
        state = values.isEmpty ? .idle : .pending(values)
    }

    func resolving(_ id: ACPEnrollmentAttemptID) { state = .resolving(id) }
    func unavailable(_ blocker: PrismACPBlocker) { state = .unavailable(blocker) }
    func serviceStopped() { state = .idle }
}
