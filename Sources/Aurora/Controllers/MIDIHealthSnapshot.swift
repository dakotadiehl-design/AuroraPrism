import Foundation

/// Structured MIDI health for toolbar/status (ST-01).
/// Do not derive health solely from free-form status strings.
struct MIDIHealthSnapshot: Equatable, Sendable {
    enum State: String, Sendable, Equatable {
        case off
        /// CoreMIDI running with at least one source connected.
        case ready
        case warning
        case failed
    }

    var state: State
    var connectedSourceCount: Int
    var lastError: String?
    var statusLine: String

    static let off = MIDIHealthSnapshot(
        state: .off,
        connectedSourceCount: 0,
        lastError: nil,
        statusLine: "MIDI: off"
    )

    static func running(sourceCount: Int, detail: String? = nil) -> MIDIHealthSnapshot {
        if sourceCount <= 0 {
            // Usable path not present — not green (ST-01).
            return MIDIHealthSnapshot(
                state: .off,
                connectedSourceCount: 0,
                lastError: nil,
                statusLine: detail ?? "MIDI: 0 sources"
            )
        }
        let line = detail ?? "MIDI: \(sourceCount) sources"
        return MIDIHealthSnapshot(
            state: .ready,
            connectedSourceCount: sourceCount,
            lastError: nil,
            statusLine: line
        )
    }

    static func failed(_ message: String) -> MIDIHealthSnapshot {
        MIDIHealthSnapshot(
            state: .failed,
            connectedSourceCount: 0,
            lastError: message,
            statusLine: "MIDI: error"
        )
    }

    /// Best-effort parse for call sites not yet migrated.
    static func fromLegacyStatusString(_ midiStatus: String) -> MIDIHealthSnapshot {
        let lower = midiStatus.lowercased()
        if lower.contains("error") || lower.contains("fail") {
            return .failed(midiStatus)
        }
        if lower.contains("off") || lower.isEmpty {
            return .off
        }
        // "0 sources" / "0 src" must not be healthy.
        if lower.contains("0 source") || lower.contains("0 src") {
            return MIDIHealthSnapshot(
                state: .off,
                connectedSourceCount: 0,
                lastError: nil,
                statusLine: midiStatus
            )
        }
        return MIDIHealthSnapshot(
            state: .ready,
            connectedSourceCount: 1,
            lastError: nil,
            statusLine: midiStatus
        )
    }
}
