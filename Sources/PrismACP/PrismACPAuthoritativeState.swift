import AuroraACP
import Foundation

public struct PrismACPAuthoritativeState: Sendable, Equatable {
    public var authorityEpoch: UInt64
    public var revision: UInt64
    public var showID: String
    public var showName: String

    public init(
        authorityEpoch: UInt64,
        revision: UInt64,
        showID: String,
        showName: String
    ) {
        self.authorityEpoch = authorityEpoch
        self.revision = revision
        self.showID = showID
        self.showName = showName
    }

    public func snapshotPayload(ownerNodeID: String) -> [String: AnySendable] {
        let owner: AnySendable = .object(["node_id": .string(ownerNodeID)])
        func resource(_ name: String, revision: UInt64, value: AnySendable) -> AnySendable {
            .object([
                "resource": .string(name),
                "revision": .uint(revision),
                "owner": owner,
                "value": value,
                "confidence": .string("confirmed"),
            ])
        }
        return ACPStateRevision.snapshotPayload(
            authorityEpoch: authorityEpoch,
            revision: revision,
            resources: [
                resource("show.project", revision: revision, value: .object([
                    "show_id": .string(showID),
                    "name": .string(showName),
                    "loaded": .bool(!showName.isEmpty),
                ])),
                resource("system.health", revision: revision, value: .object([
                    "status": .string("ok"),
                    "prism": .string("ok"),
                    "acp": .string("secure_read_only"),
                    "mutation_path": .string("unavailable"),
                    "warnings": .array([]),
                ])),
            ]
        )
    }
}
