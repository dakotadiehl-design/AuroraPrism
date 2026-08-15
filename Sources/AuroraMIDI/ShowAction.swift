import Foundation

/// Control-plane actions that MIDI (and UI) can invoke.
public enum ShowAction: Equatable, Sendable {
    case go
    case stop
    case back
    case fireCue(UUID)
    case fireCueIndex(Int)
    /// CC 0…127 maps to 0…1 for this attribute on current selection.
    case programmerAttribute(String)
    // Global show control (P0-I / PR-P1)
    case blackout
    case blackoutOff
    case toggleBlackout
    case freeze
    case freezeOff
    case toggleFreeze
    case blind
    case blindOff
    case toggleBlind
    /// Scalar 0…1 grand master intensity.
    case masterIntensity
    case panic
    case clearOverrides
    case toggleMIDIPerformance

    public var storageKey: String {
        switch self {
        case .go: return "go"
        case .stop: return "stop"
        case .back: return "back"
        case .fireCue: return "fireCue"
        case .fireCueIndex: return "fireCueIndex"
        case .programmerAttribute: return "programmerAttr"
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
        }
    }

    public var parameter: String? {
        switch self {
        case .go, .stop, .back,
             .blackout, .blackoutOff, .toggleBlackout,
             .freeze, .freezeOff, .toggleFreeze,
             .blind, .blindOff, .toggleBlind,
             .masterIntensity, .panic, .clearOverrides, .toggleMIDIPerformance:
            return nil
        case .fireCue(let id): return id.uuidString
        case .fireCueIndex(let i): return String(i)
        case .programmerAttribute(let a): return a
        }
    }

    public static func from(storageKey: String, parameter: String?) -> ShowAction? {
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
        case "programmerAttr":
            guard let parameter, !parameter.isEmpty else { return nil }
            return .programmerAttribute(parameter)
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
        default:
            return nil
        }
    }
}
