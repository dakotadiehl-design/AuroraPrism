import Foundation

public struct PrismACPIdentity: Sendable, Equatable {
    public var nodeID: String
    public var instanceID: String

    public init(nodeID: String, instanceID: String) {
        self.nodeID = nodeID
        self.instanceID = instanceID
    }
}

public struct PrismACPIdentityStore: Sendable {
    public init() {}

    public func loadOrCreate(in directory: URL) throws -> PrismACPIdentity {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("acp-node-id")
        let node: String
        if let existing = try? String(contentsOf: url, encoding: .utf8),
           let parsed = UUID(uuidString: existing.trimmingCharacters(in: .whitespacesAndNewlines)) {
            node = parsed.uuidString.lowercased()
        } else {
            node = UUID().uuidString.lowercased()
            try node.write(to: url, atomically: true, encoding: .utf8)
        }
        return PrismACPIdentity(nodeID: node, instanceID: UUID().uuidString.lowercased())
    }
}
