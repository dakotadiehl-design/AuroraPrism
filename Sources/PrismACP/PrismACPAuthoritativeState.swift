import AuroraACP
import Foundation

public struct PrismACPAuthoritativeState: Sendable, Equatable {
    public var authorityEpoch: UInt64
    public var revision: UInt64
    public var showID: String
    public var showName: String
    public var engineRunning: Bool
    public var currentCueID: String
    public var currentCueName: String
    public var nextCueID: String
    public var nextCueName: String
    public var outputStatus: String
    public var masterIntensity: Double
    public var blackout: Bool

    public init(
        authorityEpoch: UInt64,
        revision: UInt64,
        showID: String,
        showName: String,
        engineRunning: Bool,
        currentCueID: String,
        currentCueName: String = "",
        nextCueID: String,
        nextCueName: String = "",
        outputStatus: String,
        masterIntensity: Double,
        blackout: Bool
    ) {
        self.authorityEpoch = authorityEpoch
        self.revision = revision
        self.showID = showID
        self.showName = showName
        self.engineRunning = engineRunning
        self.currentCueID = currentCueID
        self.currentCueName = currentCueName
        self.nextCueID = nextCueID
        self.nextCueName = nextCueName
        self.outputStatus = outputStatus
        self.masterIntensity = masterIntensity
        self.blackout = blackout
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
                resource("show.setlist", revision: revision, value: .object(["songs": .array([])])),
                resource("show.selected_song", revision: revision, value: .object(["song_id": .string("")])),
                resource("show.current_song", revision: revision, value: .object(["song_id": .string("")])),
                resource("show.current_section", revision: revision, value: .object([
                    "section_id": .string(currentCueID),
                    "name": .string(currentCueName),
                ])),
                resource("show.next_section", revision: revision, value: .object([
                    "section_id": .string(nextCueID),
                    "name": .string(nextCueName),
                ])),
                resource("show.mode", revision: revision, value: .object(["mode": .string("programmed")])),
                resource("show.running", revision: revision, value: .object(["value": .bool(engineRunning)])),
                resource("show.progression", revision: revision, value: .object([
                    "held": .bool(false),
                ])),
                resource("show.project", revision: revision, value: .object([
                    "show_id": .string(showID),
                    "name": .string(showName),
                ])),
                resource("look.catalog", revision: revision, value: .object(["looks": .array([])])),
                resource("look.current", revision: revision, value: .object(["look_id": .string("")])),
                resource("look.preview", revision: revision, value: .object([
                    "active": .bool(false),
                ])),
                resource("output.grand_master", revision: revision, value: .object(["value": .double(masterIntensity)])),
                resource("output.blackout", revision: revision, value: .object(["value": .bool(blackout)])),
                resource("system.health", revision: revision, value: .object([
                    "status": .string("ok"),
                    "prism": .string("ok"),
                    "acp": .string("connected"),
                    "output": .string(outputStatus),
                    "warnings": .array([]),
                ])),
            ]
        )
    }
}
