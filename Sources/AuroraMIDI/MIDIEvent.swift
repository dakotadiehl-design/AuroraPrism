import Foundation

/// Parsed channel voice MIDI message with expressive types (Pass-1 P0-J).
public enum MIDIEvent: Equatable, Sendable {
    case noteOn(channel: UInt8, note: UInt8, velocity: UInt8, sourceID: String, timestamp: TimeInterval)
    case noteOff(channel: UInt8, note: UInt8, velocity: UInt8, sourceID: String, timestamp: TimeInterval)
    case controlChange(channel: UInt8, controller: UInt8, value: UInt8, sourceID: String, timestamp: TimeInterval)
    case programChange(channel: UInt8, program: UInt8, sourceID: String, timestamp: TimeInterval)
    case pitchBend(channel: UInt8, value14: UInt16, sourceID: String, timestamp: TimeInterval)
    case channelPressure(channel: UInt8, pressure: UInt8, sourceID: String, timestamp: TimeInterval)
    case polyPressure(channel: UInt8, note: UInt8, pressure: UInt8, sourceID: String, timestamp: TimeInterval)

    public var sourceID: String {
        switch self {
        case .noteOn(_, _, _, let s, _),
             .noteOff(_, _, _, let s, _),
             .controlChange(_, _, _, let s, _),
             .programChange(_, _, let s, _),
             .pitchBend(_, _, let s, _),
             .channelPressure(_, _, let s, _),
             .polyPressure(_, _, _, let s, _):
            return s
        }
    }

    public var timestamp: TimeInterval {
        switch self {
        case .noteOn(_, _, _, _, let t),
             .noteOff(_, _, _, _, let t),
             .controlChange(_, _, _, _, let t),
             .programChange(_, _, _, let t),
             .pitchBend(_, _, _, let t),
             .channelPressure(_, _, _, let t),
             .polyPressure(_, _, _, _, let t):
            return t
        }
    }

    public var channel: UInt8 {
        switch self {
        case .noteOn(let ch, _, _, _, _),
             .noteOff(let ch, _, _, _, _),
             .controlChange(let ch, _, _, _, _),
             .programChange(let ch, _, _, _),
             .pitchBend(let ch, _, _, _),
             .channelPressure(let ch, _, _, _),
             .polyPressure(let ch, _, _, _, _):
            return ch
        }
    }

    public var messageTypeKey: String {
        switch self {
        case .noteOn: return "noteOn"
        case .noteOff: return "noteOff"
        case .controlChange: return "cc"
        case .programChange: return "programChange"
        case .pitchBend: return "pitchBend"
        case .channelPressure: return "channelPressure"
        case .polyPressure: return "polyPressure"
        }
    }

    public var data1: UInt8? {
        switch self {
        case .noteOn(_, let n, _, _, _), .noteOff(_, let n, _, _, _), .polyPressure(_, let n, _, _, _):
            return n
        case .controlChange(_, let c, _, _, _):
            return c
        case .programChange(_, let p, _, _):
            return p
        case .pitchBend, .channelPressure:
            return nil
        }
    }

    public var data2: UInt8? {
        switch self {
        case .noteOn(_, _, let v, _, _), .noteOff(_, _, let v, _, _),
             .controlChange(_, _, let v, _, _), .channelPressure(_, let v, _, _),
             .polyPressure(_, _, let v, _, _):
            return v
        case .pitchBend(_, let v14, _, _):
            return UInt8(min(127, v14 >> 7))
        case .programChange:
            return nil
        }
    }

    public var summary: String {
        switch self {
        case .noteOn(let ch, let n, let v, _, _):
            return "NoteOn ch\(ch + 1) n\(n) v\(v)"
        case .noteOff(let ch, let n, let v, _, _):
            return "NoteOff ch\(ch + 1) n\(n) v\(v)"
        case .controlChange(let ch, let c, let v, _, _):
            return "CC ch\(ch + 1) #\(c) =\(v)"
        case .programChange(let ch, let p, _, _):
            return "PC ch\(ch + 1) prog\(p)"
        case .pitchBend(let ch, let v, _, _):
            return "Bend ch\(ch + 1) \(v)"
        case .channelPressure(let ch, let p, _, _):
            return "AT ch\(ch + 1) \(p)"
        case .polyPressure(let ch, let n, let p, _, _):
            return "PolyAT ch\(ch + 1) n\(n) \(p)"
        }
    }
}
