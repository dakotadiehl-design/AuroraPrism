import AuroraMusical
import Foundation

// MARK: - Channel voice

/// Channel-voice payload with **monotonic** ingress host time.
public struct MIDIChannelVoiceEvent: Equatable, Sendable {
    public var event: MIDIEvent
    public var hostTime: HostTime

    public init(event: MIDIEvent, hostTime: HostTime) {
        self.event = event
        self.hostTime = hostTime
    }

    public var sourceID: String { event.sourceID }
    public var channel: UInt8 { event.channel }
}

// MARK: - System Real-Time (0xF8–0xFF)

/// MIDI System Real-Time. **Song Position Pointer is not Real-Time.**
public enum MIDISystemRealtimeEvent: Equatable, Sendable {
    case timingClock
    case start
    case `continue`
    case stop
    case activeSensing
    case systemReset
    case other(UInt8)

    public var statusByte: UInt8 {
        switch self {
        case .timingClock: return 0xF8
        case .start: return 0xFA
        case .continue: return 0xFB
        case .stop: return 0xFC
        case .activeSensing: return 0xFE
        case .systemReset: return 0xFF
        case .other(let b): return b
        }
    }

    public static func from(statusByte: UInt8) -> MIDISystemRealtimeEvent? {
        guard statusByte >= 0xF8 else { return nil }
        switch statusByte {
        case 0xF8: return .timingClock
        case 0xFA: return .start
        case 0xFB: return .continue
        case 0xFC: return .stop
        case 0xFE: return .activeSensing
        case 0xFF: return .systemReset
        default: return .other(statusByte)
        }
    }
}

// MARK: - System Common

public enum MIDISystemCommonEvent: Equatable, Sendable {
    case songPositionPointer(sixteenths: UInt16)
    case songSelect(song: UInt8)
    case tuneRequest
    case mtcQuarterFrame(data: UInt8)
}

// MARK: - Unified ingress

public enum MIDIIngressEvent: Equatable, Sendable {
    case channelVoice(MIDIChannelVoiceEvent)
    case systemRealtime(MIDISystemRealtimeEvent, sourceID: String, hostTime: HostTime)
    case systemCommon(MIDISystemCommonEvent, sourceID: String, hostTime: HostTime)

    public var hostTime: HostTime {
        switch self {
        case .channelVoice(let e): return e.hostTime
        case .systemRealtime(_, _, let t), .systemCommon(_, _, let t): return t
        }
    }

    public var sourceID: String {
        switch self {
        case .channelVoice(let e): return e.sourceID
        case .systemRealtime(_, let s, _), .systemCommon(_, let s, _): return s
        }
    }

    public var channelVoiceEvent: MIDIEvent? {
        if case .channelVoice(let e) = self { return e.event }
        return nil
    }
}

public enum MIDIEventNormalization {
    public static func normalizeNoteOnVelocityZero(_ event: MIDIEvent) -> MIDIEvent {
        if case .noteOn(let ch, let note, let vel, let src, let ts) = event, vel == 0 {
            return .noteOff(channel: ch, note: note, velocity: 0, sourceID: src, timestamp: ts)
        }
        return event
    }

    public static func normalizeChannelVoice(_ event: MIDIEvent) -> MIDIEvent {
        normalizeNoteOnVelocityZero(event)
    }
}
