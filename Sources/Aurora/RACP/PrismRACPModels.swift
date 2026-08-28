import ReasonableACP
import Foundation

/// Namespace for Prism-owned immutable rACP integration models.
///
/// ReasonableACP remains the source of truth for protocol and transport types.
enum PrismRACPModels {}

enum PrismRACPCapability {
    static let cueBack = "cue.back"
    static let cueCurrent = "cue.current"
    static let cueGo = "cue.go"
    static let cueNext = "cue.next"
    static let cueStop = "cue.stop"
    static let outputBlackout = "output.blackout"
    static let outputBlackoutSet = "output.blackout.set"
    static let outputGrandMaster = "output.grand_master"
    static let outputGrandMasterSet = "output.grand_master.set"
    static let playbackState = "playback.state"
    static let prismStatus = "prism.status"
    static let songCurrent = "song.current"
    static let songSelect = "song.select"
    static let stateSubscribe = "state.subscribe"

    static let all = [
        cueBack, cueCurrent, cueGo, cueNext, cueStop,
        outputBlackout, outputBlackoutSet,
        outputGrandMaster, outputGrandMasterSet,
        playbackState, prismStatus, songCurrent, songSelect, stateSubscribe,
    ].sorted()

    static let stateNames: Set<String> = [
        cueCurrent, cueNext, outputBlackout, outputGrandMaster,
        playbackState, prismStatus, songCurrent,
    ]
}

/// Protocol-neutral result of an authoritative remote command.
///
/// The rACP adapter maps these outcomes onto protocol acknowledgements; the
/// application boundary stays independent of transport and wire concerns.
enum PrismRACPCommandOutcome: Equatable, Sendable {
    case executed
    case unchanged
    case invalidValue
    case invalidTarget
    case unavailable
    case noNextCue
    case noPreviousCue
}

struct PrismRACPStateSnapshot: Equatable, Sendable {
    var authorityEpoch: UInt64
    var revision: UInt64
    var engineRunning: Bool
    var playbackPhase: String
    var currentCue: PerformanceCueSummary
    var nextCue: PerformanceCueSummary
    var song: SongPerformanceSnapshot
    var sectionID: UUID?
    var sectionName: String?
    var grandMaster: Double
    var blackout: Bool

    func stateMessage(named name: String, wireRevision: UInt64) -> StateMessage? {
        let value: JSONValue
        switch name {
        case PrismRACPCapability.cueCurrent:
            value = cueValue(currentCue)
        case PrismRACPCapability.cueNext:
            value = cueValue(nextCue)
        case PrismRACPCapability.outputBlackout:
            value = envelope([JSONMember("enabled", .bool(blackout))])
        case PrismRACPCapability.outputGrandMaster:
            value = envelope([JSONMember("value", .number(grandMaster))])
        case PrismRACPCapability.playbackState:
            value = envelope([JSONMember("phase", .string(playbackPhase))])
        case PrismRACPCapability.prismStatus:
            value = envelope([JSONMember("ready", .bool(engineRunning))])
        case PrismRACPCapability.songCurrent:
            value = envelope([
                JSONMember("id", song.songID.map { .string($0.uuidString.lowercased()) } ?? .null),
                JSONMember("title", .string(song.songTitle)),
                JSONMember("artist", .string(song.artist)),
                JSONMember("section_id", sectionID.map { .string($0.uuidString.lowercased()) } ?? .null),
                JSONMember("section_name", sectionName.map(JSONValue.string) ?? .null),
                JSONMember("entry_index", .integer(Int64(song.entryIndex))),
                JSONMember("entry_count", .integer(Int64(song.entryCount))),
            ])
        default:
            return nil
        }
        return StateMessage(
            name: name,
            revision: min(wireRevision, racpMaximumSafeInteger),
            value: value
        )
    }

    func allStateMessages(wireRevision: UInt64) -> [StateMessage] {
        return PrismRACPCapability.stateNames.sorted().compactMap {
            stateMessage(named: $0, wireRevision: wireRevision)
        }
    }

    private func cueValue(_ cue: PerformanceCueSummary) -> JSONValue {
        envelope([
            JSONMember("list_id", cue.listID.map { .string($0.uuidString.lowercased()) } ?? .null),
            JSONMember("cue_id", cue.cueID.map { .string($0.uuidString.lowercased()) } ?? .null),
            JSONMember("number", cue.number.map { .string(NSDecimalNumber(decimal: $0).stringValue) } ?? .null),
            JSONMember("name", .string(cue.name)),
            JSONMember("section", cue.sectionLabel.map(JSONValue.string) ?? .null),
        ])
    }

    private func envelope(_ members: [JSONMember]) -> JSONValue {
        .object([
            JSONMember("authority_epoch", .integer(safeInteger(authorityEpoch))),
            JSONMember("revision", .integer(safeInteger(revision))),
        ] + members)
    }

    private func safeInteger(_ value: UInt64) -> Int64 {
        Int64(min(value, racpMaximumSafeInteger))
    }
}

struct PrismRACPServiceSnapshot: Equatable, Sendable {
    enum State: String, Equatable, Sendable {
        case disabled
        case starting
        case listening
        case failed
    }

    var state: State
    var port: UInt16?
    var clientCount: Int
    var lastError: String?

    static let disabled = PrismRACPServiceSnapshot(
        state: .disabled,
        port: nil,
        clientCount: 0,
        lastError: nil
    )

    var statusLine: String {
        switch state {
        case .disabled: return "rACP disabled"
        case .starting: return "rACP starting"
        case .listening: return "rACP listening on port \(port.map(String.init) ?? "—")"
        case .failed: return "rACP failed: \(lastError ?? "unknown error")"
        }
    }
}
