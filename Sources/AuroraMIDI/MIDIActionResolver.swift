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

/// Matches incoming MIDI events against project mappings and advanced rules.
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

    /// Match advanced rules (priority descending). Optional song section context.
    public static func matchRules(
        event: MIDIEvent,
        rules: [MIDIRule],
        songSection: String? = nil
    ) -> [ShowAction] {
        let sorted = rules.filter(\.enabled).sorted { $0.priority > $1.priority }
        var actions: [ShowAction] = []
        for rule in sorted {
            if let section = rule.songSectionContext, !section.isEmpty {
                guard section == songSection else { continue }
            }
            guard matches(event: event, rule: rule) else { continue }
            for (i, key) in rule.actionKeys.enumerated() {
                let param = i < rule.actionParameters.count ? rule.actionParameters[i] : nil
                if let action = ShowAction.from(storageKey: key, parameter: param) {
                    actions.append(action)
                }
            }
        }
        return actions
    }

    public static func matches(event: MIDIEvent, mapping: MIDIMapping) -> Bool {
        matches(
            event: event,
            messageType: mapping.messageType,
            channel: mapping.channel,
            data1Min: mapping.data1,
            data1Max: mapping.data1,
            data2Min: mapping.data2,
            data2Max: mapping.data2,
            deviceID: mapping.deviceID
        )
    }

    public static func matches(event: MIDIEvent, rule: MIDIRule) -> Bool {
        matches(
            event: event,
            messageType: rule.messageType,
            channel: rule.channel,
            data1Min: rule.data1Min,
            data1Max: rule.data1Max,
            data2Min: rule.data2Min,
            data2Max: rule.data2Max,
            deviceID: rule.deviceID
        )
    }

    private static func matches(
        event: MIDIEvent,
        messageType: String,
        channel: UInt8?,
        data1Min: UInt8?,
        data1Max: UInt8?,
        data2Min: UInt8?,
        data2Max: UInt8?,
        deviceID: String?
    ) -> Bool {
        guard event.messageTypeKey == messageType ||
                (messageType == "cc" && event.messageTypeKey == "cc") else { return false }
        if let mappedCh = channel, mappedCh != event.channel { return false }
        if let d1 = event.data1 {
            if let lo = data1Min, d1 < lo { return false }
            if let hi = data1Max, d1 > hi { return false }
        } else if data1Min != nil || data1Max != nil {
            return false
        }
        if let d2 = event.data2 {
            if let lo = data2Min, d2 < lo { return false }
            if let hi = data2Max, d2 > hi { return false }
        } else if data2Min != nil || data2Max != nil {
            // Note On/CC require d2 when filter set.
            if messageType == "noteOn" || messageType == "cc" { return false }
        }
        if let deviceID, !deviceID.isEmpty, deviceID != "coremidi" {
            if deviceID != event.sourceID { return false }
        }
        if case .noteOn(_, _, let v, _, _) = event, v == 0 { return false }
        return true
    }

    /// Scalar control value for parameter mappings.
    public static func controlValue(for event: MIDIEvent) -> MIDIControlValue {
        switch event {
        case .noteOn(_, _, let v, _, _):
            return MIDIControlValue(normalized: Double(v) / 127.0, isTrigger: true)
        case .noteOff:
            return MIDIControlValue(normalized: 0, isTrigger: true)
        case .controlChange(_, _, let v, _, _):
            return MIDIControlValue(normalized: Double(v) / 127.0, isTrigger: false)
        case .programChange:
            return MIDIControlValue(normalized: 0, isTrigger: true)
        case .pitchBend(_, let v14, _, _):
            return MIDIControlValue(normalized: Double(v14) / 16383.0, isTrigger: false)
        case .channelPressure(_, let p, _, _), .polyPressure(_, _, let p, _, _):
            return MIDIControlValue(normalized: Double(p) / 127.0, isTrigger: false)
        }
    }

    public static func mapping(from event: MIDIEvent, action: ShowAction, name: String = "") -> MIDIMapping {
        let source = event.sourceID
        switch event {
        case .noteOn(let ch, let n, _, _, _):
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
        case .noteOff(let ch, let n, _, _, _):
            return MIDIMapping(
                name: name.isEmpty ? "Learn \(action.storageKey)" : name,
                deviceID: source,
                channel: ch,
                messageType: "noteOff",
                data1: n,
                action: action.storageKey,
                actionParameter: action.parameter
            )
        case .controlChange(let ch, let c, _, _, _):
            return MIDIMapping(
                name: name.isEmpty ? "Learn \(action.storageKey)" : name,
                deviceID: source,
                channel: ch,
                messageType: "cc",
                data1: c,
                action: action.storageKey,
                actionParameter: action.parameter
            )
        case .programChange(let ch, let p, _, _):
            return MIDIMapping(
                name: name.isEmpty ? "Learn \(action.storageKey)" : name,
                deviceID: source,
                channel: ch,
                messageType: "programChange",
                data1: p,
                action: action.storageKey,
                actionParameter: action.parameter
            )
        case .pitchBend(let ch, _, _, _):
            return MIDIMapping(
                name: name.isEmpty ? "Learn \(action.storageKey)" : name,
                deviceID: source,
                channel: ch,
                messageType: "pitchBend",
                action: action.storageKey,
                actionParameter: action.parameter
            )
        case .channelPressure(let ch, _, _, _):
            return MIDIMapping(
                name: name.isEmpty ? "Learn \(action.storageKey)" : name,
                deviceID: source,
                channel: ch,
                messageType: "channelPressure",
                action: action.storageKey,
                actionParameter: action.parameter
            )
        case .polyPressure(let ch, let n, _, _, _):
            return MIDIMapping(
                name: name.isEmpty ? "Learn \(action.storageKey)" : name,
                deviceID: source,
                channel: ch,
                messageType: "polyPressure",
                data1: n,
                action: action.storageKey,
                actionParameter: action.parameter
            )
        }
    }

    public static func ccNormalized(_ value: UInt8) -> Double {
        Double(value) / 127.0
    }
}
