import Foundation

public struct PrismACPAuthorizationPolicy: Sendable, Equatable {
    public var allowMutations: Bool
    public var operatorNodeIDs: Set<String>
    public var blackoutClearNodeIDs: Set<String>

    public init(
        allowMutations: Bool = false,
        operatorNodeIDs: Set<String> = [],
        blackoutClearNodeIDs: Set<String>? = nil
    ) {
        self.allowMutations = allowMutations
        self.operatorNodeIDs = Set(operatorNodeIDs.map { $0.lowercased() })
        self.blackoutClearNodeIDs = Set((blackoutClearNodeIDs ?? []).map { $0.lowercased() })
    }

    public func permitsMutation() -> Bool {
        allowMutations
    }

    public func permitsMutation(principalNodeID: String) -> Bool {
        guard allowMutations else { return false }
        return operatorNodeIDs.contains(principalNodeID.lowercased())
    }

    public func permitsBlackoutClear(principalNodeID: String) -> Bool {
        guard permitsMutation(principalNodeID: principalNodeID) else { return false }
        return blackoutClearNodeIDs.contains(principalNodeID.lowercased())
    }
}
