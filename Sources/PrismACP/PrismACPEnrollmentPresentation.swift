import Foundation

public struct PrismACPEnrollmentRequest: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let displayName: String?
    public let nodeID: String?
    public let expiresAt: Date?
}

public enum PrismACPEnrollmentPresentationState: Sendable, Equatable {
    case unavailable(PrismACPBlocker)
    case idle
    case pending([PrismACPEnrollmentRequest])
    case resolving(UUID)
}

/// Human-decision boundary only. ACP must supply the cryptographic coordinator
/// before requests can enter this model; Prism never auto-approves a peer.
public actor PrismACPEnrollmentPresentationModel {
    public private(set) var state: PrismACPEnrollmentPresentationState =
        .unavailable(.enrollmentBootstrapUnavailable)

    public init() {}

    public func serviceStopped() {
        state = .unavailable(.enrollmentBootstrapUnavailable)
    }

    public func approve(_ id: UUID) throws {
        throw PrismACPBlocker.enrollmentBootstrapUnavailable
    }

    public func reject(_ id: UUID) throws {
        throw PrismACPBlocker.enrollmentBootstrapUnavailable
    }
}
