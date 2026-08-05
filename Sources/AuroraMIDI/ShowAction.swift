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

    public var storageKey: String {
        switch self {
        case .go: return "go"
        case .stop: return "stop"
        case .back: return "back"
        case .fireCue: return "fireCue"
        case .fireCueIndex: return "fireCueIndex"
        case .programmerAttribute: return "programmerAttr"
        }
    }

    public var parameter: String? {
        switch self {
        case .go, .stop, .back: return nil
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
        default:
            return nil
        }
    }
}
