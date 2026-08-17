import Foundation

/// Generalized semantic control actions (MIDI, remote, keyboard, future show control).
/// Never writes raw DMX buffers.
public enum AuroraAction: Equatable, Sendable, Hashable {
    case go
    case stop
    case back
    case fireCue(UUID)
    case fireCueIndex(Int)
    case blackout
    case blackoutOff
    case toggleBlackout
    case freeze
    case freezeOff
    case toggleFreeze
    case blind
    case blindOff
    case toggleBlind
    case masterIntensity
    case panic
    case clearOverrides
    case toggleMIDIPerformance

    case selectSong(UUID)
    case enterSection(UUID)
    case nextSection
    case previousSection

    case firePreset(UUID)
    case firePalette(UUID)
    case fireLook(UUID)

    case programmerAttribute(String)
    case runBehavior(UUID)

    case advanceSequence(UUID)
    case resetSequence(UUID)
    case fireSequenceStep(sequenceID: UUID, stepIndex: Int)

    case tapTempo
    case setTransportStart
    case setTransportStop
    case setTransportContinue
    case setTempoBPM(Double)

    case triggerEffect(UUID)
    case setEffectRate(UUID, Double)
    case setEffectDepth(UUID, Double)

    case compound([AuroraAction])

    /// Safety actions must never wait for musical quantization.
    /// Classification is **recursive** for compound actions.
    public var isSafetyCritical: Bool {
        switch self {
        case .panic, .blackout, .blackoutOff, .toggleBlackout,
             .clearOverrides, .stop,
             .freeze, .freezeOff, .toggleFreeze,
             .blind, .blindOff, .toggleBlind:
            return true
        case .compound(let actions):
            return actions.contains(where: \.isSafetyCritical)
        default:
            return false
        }
    }

    public var storageKey: String {
        switch self {
        case .go: return "go"
        case .stop: return "stop"
        case .back: return "back"
        case .fireCue: return "fireCue"
        case .fireCueIndex: return "fireCueIndex"
        case .blackout: return "blackout"
        case .blackoutOff: return "blackoutOff"
        case .toggleBlackout: return "toggleBlackout"
        case .freeze: return "freeze"
        case .freezeOff: return "freezeOff"
        case .toggleFreeze: return "toggleFreeze"
        case .blind: return "blind"
        case .blindOff: return "blindOff"
        case .toggleBlind: return "toggleBlind"
        case .masterIntensity: return "masterIntensity"
        case .panic: return "panic"
        case .clearOverrides: return "clearOverrides"
        case .toggleMIDIPerformance: return "toggleMIDIPerformance"
        case .selectSong: return "selectSong"
        case .enterSection: return "enterSection"
        case .nextSection: return "nextSection"
        case .previousSection: return "previousSection"
        case .firePreset: return "firePreset"
        case .firePalette: return "firePalette"
        case .fireLook: return "fireLook"
        case .programmerAttribute: return "programmerAttr"
        case .runBehavior: return "runBehavior"
        case .advanceSequence: return "advanceSequence"
        case .resetSequence: return "resetSequence"
        case .fireSequenceStep: return "fireSequenceStep"
        case .tapTempo: return "tapTempo"
        case .setTransportStart: return "setTransportStart"
        case .setTransportStop: return "setTransportStop"
        case .setTransportContinue: return "setTransportContinue"
        case .setTempoBPM: return "setTempoBPM"
        case .triggerEffect: return "triggerEffect"
        case .setEffectRate: return "setEffectRate"
        case .setEffectDepth: return "setEffectDepth"
        case .compound: return "compound"
        }
    }
}

// MARK: - Lossless recursive Codable (tagged)

extension AuroraAction: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case index
        case attribute
        case value
        case sequenceID
        case stepIndex
        case actions
        // Legacy Phase A key/parameter (decode only)
        case key
        case parameter
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let type = try c.decodeIfPresent(String.self, forKey: .type) {
            self = try Self.decodeTagged(type: type, container: c)
            return
        }
        // Legacy {key, parameter}
        if let key = try c.decodeIfPresent(String.self, forKey: .key) {
            let parameter = try c.decodeIfPresent(String.self, forKey: .parameter)
            guard let action = Self.fromLegacy(storageKey: key, parameter: parameter) else {
                throw DecodingError.dataCorruptedError(forKey: .key, in: c, debugDescription: "Unknown AuroraAction \(key)")
            }
            self = action
            return
        }
        throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Missing AuroraAction type")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(storageKey, forKey: .type)
        switch self {
        case .go, .stop, .back, .blackout, .blackoutOff, .toggleBlackout,
             .freeze, .freezeOff, .toggleFreeze, .blind, .blindOff, .toggleBlind,
             .masterIntensity, .panic, .clearOverrides, .toggleMIDIPerformance,
             .nextSection, .previousSection, .tapTempo,
             .setTransportStart, .setTransportStop, .setTransportContinue:
            break
        case .fireCue(let id), .selectSong(let id), .enterSection(let id),
             .firePreset(let id), .firePalette(let id), .fireLook(let id),
             .runBehavior(let id), .advanceSequence(let id), .resetSequence(let id),
             .triggerEffect(let id):
            try c.encode(id, forKey: .id)
        case .fireCueIndex(let i):
            try c.encode(i, forKey: .index)
        case .programmerAttribute(let a):
            try c.encode(a, forKey: .attribute)
        case .fireSequenceStep(let seq, let step):
            try c.encode(seq, forKey: .sequenceID)
            try c.encode(step, forKey: .stepIndex)
        case .setTempoBPM(let bpm):
            try c.encode(bpm, forKey: .value)
        case .setEffectRate(let id, let v), .setEffectDepth(let id, let v):
            try c.encode(id, forKey: .id)
            try c.encode(v, forKey: .value)
        case .compound(let actions):
            try c.encode(actions, forKey: .actions)
        }
    }

    private static func decodeTagged(type: String, container c: KeyedDecodingContainer<CodingKeys>) throws -> AuroraAction {
        switch type {
        case "go": return .go
        case "stop": return .stop
        case "back": return .back
        case "fireCue":
            return .fireCue(try c.decode(UUID.self, forKey: .id))
        case "fireCueIndex":
            return .fireCueIndex(try c.decode(Int.self, forKey: .index))
        case "blackout": return .blackout
        case "blackoutOff": return .blackoutOff
        case "toggleBlackout": return .toggleBlackout
        case "freeze": return .freeze
        case "freezeOff": return .freezeOff
        case "toggleFreeze": return .toggleFreeze
        case "blind": return .blind
        case "blindOff": return .blindOff
        case "toggleBlind": return .toggleBlind
        case "masterIntensity": return .masterIntensity
        case "panic": return .panic
        case "clearOverrides": return .clearOverrides
        case "toggleMIDIPerformance": return .toggleMIDIPerformance
        case "selectSong":
            return .selectSong(try c.decode(UUID.self, forKey: .id))
        case "enterSection":
            return .enterSection(try c.decode(UUID.self, forKey: .id))
        case "nextSection": return .nextSection
        case "previousSection": return .previousSection
        case "firePreset":
            return .firePreset(try c.decode(UUID.self, forKey: .id))
        case "firePalette":
            return .firePalette(try c.decode(UUID.self, forKey: .id))
        case "fireLook":
            return .fireLook(try c.decode(UUID.self, forKey: .id))
        case "programmerAttr":
            return .programmerAttribute(try c.decode(String.self, forKey: .attribute))
        case "runBehavior":
            return .runBehavior(try c.decode(UUID.self, forKey: .id))
        case "advanceSequence":
            return .advanceSequence(try c.decode(UUID.self, forKey: .id))
        case "resetSequence":
            return .resetSequence(try c.decode(UUID.self, forKey: .id))
        case "fireSequenceStep":
            return .fireSequenceStep(
                sequenceID: try c.decode(UUID.self, forKey: .sequenceID),
                stepIndex: try c.decode(Int.self, forKey: .stepIndex)
            )
        case "tapTempo": return .tapTempo
        case "setTransportStart": return .setTransportStart
        case "setTransportStop": return .setTransportStop
        case "setTransportContinue": return .setTransportContinue
        case "setTempoBPM":
            return .setTempoBPM(try c.decode(Double.self, forKey: .value))
        case "triggerEffect":
            return .triggerEffect(try c.decode(UUID.self, forKey: .id))
        case "setEffectRate":
            return .setEffectRate(try c.decode(UUID.self, forKey: .id), try c.decode(Double.self, forKey: .value))
        case "setEffectDepth":
            return .setEffectDepth(try c.decode(UUID.self, forKey: .id), try c.decode(Double.self, forKey: .value))
        case "compound":
            // Tagged format requires explicit `actions` key (empty array is intentional empty compound).
            guard c.contains(.actions) else {
                throw DecodingError.keyNotFound(
                    CodingKeys.actions,
                    .init(codingPath: c.codingPath, debugDescription: "compound requires actions array")
                )
            }
            return .compound(try c.decode([AuroraAction].self, forKey: .actions))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown type \(type)")
        }
    }

    /// Legacy key/parameter form. Compound is **not** reconstructible from this format —
    /// returns `nil` rather than a silent empty compound no-op.
    public static func fromLegacy(storageKey: String, parameter: String?) -> AuroraAction? {
        switch storageKey {
        case "go": return .go
        case "stop": return .stop
        case "back": return .back
        case "fireCue":
            guard let parameter, let id = UUID(uuidString: parameter) else { return nil }
            return .fireCue(id)
        case "fireCueIndex":
            guard let parameter, let i = Int(parameter) else { return nil }
            return .fireCueIndex(i)
        case "blackout": return .blackout
        case "blackoutOff": return .blackoutOff
        case "toggleBlackout": return .toggleBlackout
        case "freeze": return .freeze
        case "freezeOff": return .freezeOff
        case "toggleFreeze": return .toggleFreeze
        case "blind": return .blind
        case "blindOff": return .blindOff
        case "toggleBlind": return .toggleBlind
        case "masterIntensity": return .masterIntensity
        case "panic": return .panic
        case "clearOverrides": return .clearOverrides
        case "toggleMIDIPerformance": return .toggleMIDIPerformance
        case "selectSong":
            guard let parameter, let id = UUID(uuidString: parameter) else { return nil }
            return .selectSong(id)
        case "enterSection":
            guard let parameter, let id = UUID(uuidString: parameter) else { return nil }
            return .enterSection(id)
        case "nextSection": return .nextSection
        case "previousSection": return .previousSection
        case "firePreset":
            guard let parameter, let id = UUID(uuidString: parameter) else { return nil }
            return .firePreset(id)
        case "firePalette":
            guard let parameter, let id = UUID(uuidString: parameter) else { return nil }
            return .firePalette(id)
        case "fireLook":
            guard let parameter, let id = UUID(uuidString: parameter) else { return nil }
            return .fireLook(id)
        case "programmerAttr":
            guard let parameter, !parameter.isEmpty else { return nil }
            return .programmerAttribute(parameter)
        case "runBehavior":
            guard let parameter, let id = UUID(uuidString: parameter) else { return nil }
            return .runBehavior(id)
        case "advanceSequence":
            guard let parameter, let id = UUID(uuidString: parameter) else { return nil }
            return .advanceSequence(id)
        case "resetSequence":
            guard let parameter, let id = UUID(uuidString: parameter) else { return nil }
            return .resetSequence(id)
        case "fireSequenceStep":
            guard let parameter else { return nil }
            let parts = parameter.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let id = UUID(uuidString: parts[0]), let step = Int(parts[1]) else { return nil }
            return .fireSequenceStep(sequenceID: id, stepIndex: step)
        case "tapTempo": return .tapTempo
        case "setTransportStart": return .setTransportStart
        case "setTransportStop": return .setTransportStop
        case "setTransportContinue": return .setTransportContinue
        case "setTempoBPM":
            guard let parameter, let bpm = Double(parameter) else { return nil }
            return .setTempoBPM(bpm)
        case "triggerEffect":
            guard let parameter, let id = UUID(uuidString: parameter) else { return nil }
            return .triggerEffect(id)
        case "setEffectRate":
            guard let parameter else { return nil }
            let parts = parameter.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let id = UUID(uuidString: parts[0]), let v = Double(parts[1]) else { return nil }
            return .setEffectRate(id, v)
        case "setEffectDepth":
            guard let parameter else { return nil }
            let parts = parameter.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let id = UUID(uuidString: parts[0]), let v = Double(parts[1]) else { return nil }
            return .setEffectDepth(id, v)
        case "compound":
            // Unrecoverable: flattened legacy storage cannot preserve children.
            return nil
        default:
            return nil
        }
    }
}
