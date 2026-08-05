import Foundation

/// Parsed channel voice MIDI message (PR16). Learn/mapping is PR17.
public enum MIDIEvent: Equatable, Sendable {
    case noteOn(channel: UInt8, note: UInt8, velocity: UInt8, sourceID: String)
    case noteOff(channel: UInt8, note: UInt8, velocity: UInt8, sourceID: String)
    case controlChange(channel: UInt8, controller: UInt8, value: UInt8, sourceID: String)
    case programChange(channel: UInt8, program: UInt8, sourceID: String)

    public var sourceID: String {
        switch self {
        case .noteOn(_, _, _, let s),
             .noteOff(_, _, _, let s),
             .controlChange(_, _, _, let s),
             .programChange(_, _, let s):
            return s
        }
    }

    public var summary: String {
        switch self {
        case .noteOn(let ch, let n, let v, _):
            return "NoteOn ch\(ch + 1) n\(n) v\(v)"
        case .noteOff(let ch, let n, let v, _):
            return "NoteOff ch\(ch + 1) n\(n) v\(v)"
        case .controlChange(let ch, let c, let v, _):
            return "CC ch\(ch + 1) #\(c) =\(v)"
        case .programChange(let ch, let p, _):
            return "PC ch\(ch + 1) prog\(p)"
        }
    }
}
