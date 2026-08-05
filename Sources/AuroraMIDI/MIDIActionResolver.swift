import AuroraModel
import Foundation
// MIDIMapping lives in AuroraModel

/// Matches incoming MIDI events against project mappings.
public enum MIDIActionResolver {
    public static func match(event: MIDIEvent, mappings: [MIDIMapping]) -> ShowAction? {
        for mapping in mappings {
            if matches(event: event, mapping: mapping) {
                return ShowAction.from(storageKey: mapping.action, parameter: mapping.actionParameter)
            }
        }
        return nil
    }

    public static func matches(event: MIDIEvent, mapping: MIDIMapping) -> Bool {
        let type: String
        let channel: UInt8
        let data1: UInt8?
        switch event {
        case .noteOn(let ch, let n, let v, _):
            guard v > 0 else { return false }
            type = "noteOn"
            channel = ch
            data1 = n
        case .noteOff(let ch, let n, _, _):
            type = "noteOff"
            channel = ch
            data1 = n
        case .controlChange(let ch, let c, _, _):
            type = "cc"
            channel = ch
            data1 = c
        case .programChange(let ch, let p, _):
            type = "programChange"
            channel = ch
            data1 = p
        }
        guard mapping.messageType == type else { return false }
        if let mappedCh = mapping.channel, mappedCh != channel { return false }
        if let mappedD1 = mapping.data1, mappedD1 != data1 { return false }
        return true
    }

    public static func mapping(from event: MIDIEvent, action: ShowAction, name: String = "") -> MIDIMapping {
        switch event {
        case .noteOn(let ch, let n, _, _):
            return MIDIMapping(
                name: name.isEmpty ? "Learn \(action.storageKey)" : name,
                channel: ch,
                messageType: "noteOn",
                data1: n,
                action: action.storageKey,
                actionParameter: action.parameter
            )
        case .noteOff(let ch, let n, _, _):
            return MIDIMapping(
                name: name.isEmpty ? "Learn \(action.storageKey)" : name,
                channel: ch,
                messageType: "noteOff",
                data1: n,
                action: action.storageKey,
                actionParameter: action.parameter
            )
        case .controlChange(let ch, let c, _, _):
            return MIDIMapping(
                name: name.isEmpty ? "Learn \(action.storageKey)" : name,
                channel: ch,
                messageType: "cc",
                data1: c,
                action: action.storageKey,
                actionParameter: action.parameter
            )
        case .programChange(let ch, let p, _):
            return MIDIMapping(
                name: name.isEmpty ? "Learn \(action.storageKey)" : name,
                channel: ch,
                messageType: "programChange",
                data1: p,
                action: action.storageKey,
                actionParameter: action.parameter
            )
        }
    }

    public static func ccNormalized(_ value: UInt8) -> Double {
        Double(value) / 127.0
    }
}
