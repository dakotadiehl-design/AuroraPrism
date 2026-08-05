import AuroraModel
import Foundation

/// Normalized scalar extracted from a MIDI event (P1-6).
public struct MIDIControlValue: Equatable, Sendable {
    /// 0…1
    public var normalized: Double
    /// True for note/program messages (trigger-capable); false for continuous CC.
    public var isTrigger: Bool

    public init(normalized: Double, isTrigger: Bool) {
        self.normalized = min(1, max(0, normalized))
        self.isTrigger = isTrigger
    }
}

/// Matches incoming MIDI events against project mappings.
public enum MIDIActionResolver {
    /// First matching mapping (legacy). Prefer `matchAll` for multi-action inputs.
    public static func match(event: MIDIEvent, mappings: [MIDIMapping]) -> ShowAction? {
        matchAll(event: event, mappings: mappings).first
    }

    /// All matching mappings in array order (P1-7 one-to-many).
    public static func matchAll(event: MIDIEvent, mappings: [MIDIMapping]) -> [ShowAction] {
        var actions: [ShowAction] = []
        for mapping in mappings {
            if matches(event: event, mapping: mapping),
               let action = ShowAction.from(storageKey: mapping.action, parameter: mapping.actionParameter) {
                actions.append(action)
            }
        }
        return actions
    }

    public static func matches(event: MIDIEvent, mapping: MIDIMapping) -> Bool {
        let type: String
        let channel: UInt8
        let data1: UInt8?
        let data2: UInt8?
        switch event {
        case .noteOn(let ch, let n, let v, _):
            guard v > 0 else { return false }
            type = "noteOn"
            channel = ch
            data1 = n
            data2 = v
        case .noteOff(let ch, let n, let v, _):
            type = "noteOff"
            channel = ch
            data1 = n
            data2 = v
        case .controlChange(let ch, let c, let v, _):
            type = "cc"
            channel = ch
            data1 = c
            data2 = v
        case .programChange(let ch, let p, _):
            type = "programChange"
            channel = ch
            data1 = p
            data2 = nil
        }
        guard mapping.messageType == type else { return false }
        if let mappedCh = mapping.channel, mappedCh != channel { return false }
        if let mappedD1 = mapping.data1, mappedD1 != data1 { return false }
        // data2: exact velocity/value filter when set (P1-8). nil = any.
        if let mappedD2 = mapping.data2, let eventD2 = data2, mappedD2 != eventD2 {
            return false
        }
        if mapping.data2 != nil, data2 == nil {
            return false
        }
        if let deviceID = mapping.deviceID, !deviceID.isEmpty, deviceID != "coremidi" {
            if deviceID != eventSourceID(event) { return false }
        }
        return true
    }

    /// Scalar control value for parameter mappings (Note velocity, CC value, Note Off → 0).
    public static func controlValue(for event: MIDIEvent) -> MIDIControlValue {
        switch event {
        case .noteOn(_, _, let v, _):
            return MIDIControlValue(normalized: Double(v) / 127.0, isTrigger: true)
        case .noteOff:
            return MIDIControlValue(normalized: 0, isTrigger: true)
        case .controlChange(_, _, let v, _):
            return MIDIControlValue(normalized: Double(v) / 127.0, isTrigger: false)
        case .programChange:
            return MIDIControlValue(normalized: 0, isTrigger: true)
        }
    }

    private static func eventSourceID(_ event: MIDIEvent) -> String {
        event.sourceID
    }

    public static func mapping(from event: MIDIEvent, action: ShowAction, name: String = "") -> MIDIMapping {
        let source = eventSourceID(event)
        switch event {
        case .noteOn(let ch, let n, _, _):
            return MIDIMapping(
                name: name.isEmpty ? "Learn \(action.storageKey)" : name,
                deviceID: source,
                channel: ch,
                messageType: "noteOn",
                data1: n,
                data2: nil,
                action: action.storageKey,
                actionParameter: action.parameter
            )
        case .noteOff(let ch, let n, _, _):
            return MIDIMapping(
                name: name.isEmpty ? "Learn \(action.storageKey)" : name,
                deviceID: source,
                channel: ch,
                messageType: "noteOff",
                data1: n,
                action: action.storageKey,
                actionParameter: action.parameter
            )
        case .controlChange(let ch, let c, _, _):
            return MIDIMapping(
                name: name.isEmpty ? "Learn \(action.storageKey)" : name,
                deviceID: source,
                channel: ch,
                messageType: "cc",
                data1: c,
                action: action.storageKey,
                actionParameter: action.parameter
            )
        case .programChange(let ch, let p, _):
            return MIDIMapping(
                name: name.isEmpty ? "Learn \(action.storageKey)" : name,
                deviceID: source,
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
