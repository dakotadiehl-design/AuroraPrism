import AuroraModel
import AuroraMusical
import Foundation

// MARK: - Performance mode

/// Runtime performance posture for AME evaluation.
///
/// - `edit`: configuration mode — no evaluation / no emissions.
/// - `dryRun`: full evaluation + diagnostics; emissions are non-executing.
/// - `armed`: full evaluation; emissions may execute on the live control path.
public enum AMEPerformanceMode: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    case edit
    case dryRun
    case armed
}

// MARK: - Normalized performance event

/// Channel-voice performance event after I/O normalization.
/// Independent of CoreMIDI / `MIDIEvent` so AuroraEngine stays free of AuroraMIDI.
public struct AMENormalizedEvent: Equatable, Sendable, Hashable {
    public var messageType: AMEMIDIMessageType
    public var channel: UInt8
    public var data1: UInt8?
    public var data2: UInt8?
    public var sourceID: String
    public var hostTime: HostTime
    /// End-to-end latency correlation id (set at ingress or evaluation entry).
    public var latencyID: UUID

    public init(
        messageType: AMEMIDIMessageType,
        channel: UInt8,
        data1: UInt8? = nil,
        data2: UInt8? = nil,
        sourceID: String,
        hostTime: HostTime = .now(),
        latencyID: UUID = UUID()
    ) {
        self.messageType = messageType
        self.channel = channel
        self.data1 = data1
        self.data2 = data2
        self.sourceID = sourceID
        self.hostTime = hostTime
        self.latencyID = latencyID
    }

    /// Note On velocity 0 → Note Off (defensive re-normalization).
    public func normalized() -> AMENormalizedEvent {
        if messageType == .noteOn, data2 == 0 {
            var copy = self
            copy.messageType = .noteOff
            return copy
        }
        return self
    }

    /// Primary continuous / velocity scalar in 0…1 before mapping transform.
    public var rawNormalizedValue: Double {
        switch messageType {
        case .noteOn:
            return Double(data2 ?? 0) / 127.0
        case .noteOff:
            return 0
        case .cc, .channelPressure, .polyPressure:
            return Double(data2 ?? 0) / 127.0
        case .programChange:
            return Double(data1 ?? 0) / 127.0
        case .pitchBend:
            // data1 = LSB-ish packed high 7 of 14-bit if provided; data2 preferred as high byte
            if let d2 = data2, let d1 = data1 {
                let v14 = (UInt16(d2) << 7) | UInt16(d1 & 0x7F)
                return Double(v14) / 16383.0
            }
            if let d2 = data2 {
                return Double(d2) / 127.0
            }
            return 0.5
        }
    }

    public var isNoteOnEdge: Bool { messageType == .noteOn }
    public var isNoteOffEdge: Bool { messageType == .noteOff }
    public var isContinuous: Bool {
        switch messageType {
        case .cc, .pitchBend, .channelPressure, .polyPressure:
            return true
        default:
            return false
        }
    }
}

// MARK: - Show / timing context

/// Song/section identity for scope evaluation (not musical clock).
public struct AMEShowContext: Equatable, Sendable, Hashable {
    public var activeSongID: UUID?
    public var activeSectionID: UUID?

    public init(activeSongID: UUID? = nil, activeSectionID: UUID? = nil) {
        self.activeSongID = activeSongID
        self.activeSectionID = activeSectionID
    }

    public static let empty = AMEShowContext()
}

/// Timing facts AME needs for `AMETimingRequirement` / quantize failure (no MusicalEngine ownership).
public struct AMETimingSnapshot: Equatable, Sendable, Hashable {
    public var musicalTimeAvailable: Bool
    public var transportRunning: Bool
    public var externalSyncLocked: Bool

    public init(
        musicalTimeAvailable: Bool = true,
        transportRunning: Bool = false,
        externalSyncLocked: Bool = false
    ) {
        self.musicalTimeAvailable = musicalTimeAvailable
        self.transportRunning = transportRunning
        self.externalSyncLocked = externalSyncLocked
    }

    /// Default for internal-only timing (always have musical time from internal clock).
    public static let internalAvailable = AMETimingSnapshot(
        musicalTimeAvailable: true,
        transportRunning: true,
        externalSyncLocked: false
    )

    public static func from(musical state: MusicalState) -> AMETimingSnapshot {
        let t = state.timing
        let timeAvailable = t.tempoBPM != nil && t.quarterNotePosition != nil
        let running = t.transport == .running
        let locked = t.sync == .locked
        return AMETimingSnapshot(
            musicalTimeAvailable: timeAvailable,
            transportRunning: running,
            externalSyncLocked: locked
        )
    }

    public func satisfies(_ requirement: AMETimingRequirement) -> Bool {
        switch requirement {
        case .none:
            return true
        case .musicalTimeAvailable:
            return musicalTimeAvailable
        case .transportRunning:
            return transportRunning
        case .externalSyncLocked:
            return externalSyncLocked
        }
    }
}
