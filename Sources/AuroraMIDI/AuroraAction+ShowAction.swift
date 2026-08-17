import AuroraModel
import Foundation

/// Bridge between persisted `AuroraAction` (AuroraModel) and control-plane `ShowAction` (AuroraMIDI).
public extension AuroraAction {
    init?(showAction: ShowAction) {
        switch showAction {
        case .go: self = .go
        case .stop: self = .stop
        case .back: self = .back
        case .fireCue(let id): self = .fireCue(id)
        case .fireCueIndex(let i): self = .fireCueIndex(i)
        case .programmerAttribute(let a): self = .programmerAttribute(a)
        case .blackout: self = .blackout
        case .blackoutOff: self = .blackoutOff
        case .toggleBlackout: self = .toggleBlackout
        case .freeze: self = .freeze
        case .freezeOff: self = .freezeOff
        case .toggleFreeze: self = .toggleFreeze
        case .blind: self = .blind
        case .blindOff: self = .blindOff
        case .toggleBlind: self = .toggleBlind
        case .masterIntensity: self = .masterIntensity
        case .panic: self = .panic
        case .clearOverrides: self = .clearOverrides
        case .toggleMIDIPerformance: self = .toggleMIDIPerformance
        }
    }

    var asShowAction: ShowAction? {
        switch self {
        case .go: return .go
        case .stop: return .stop
        case .back: return .back
        case .fireCue(let id): return .fireCue(id)
        case .fireCueIndex(let i): return .fireCueIndex(i)
        case .programmerAttribute(let a): return .programmerAttribute(a)
        case .blackout: return .blackout
        case .blackoutOff: return .blackoutOff
        case .toggleBlackout: return .toggleBlackout
        case .freeze: return .freeze
        case .freezeOff: return .freezeOff
        case .toggleFreeze: return .toggleFreeze
        case .blind: return .blind
        case .blindOff: return .blindOff
        case .toggleBlind: return .toggleBlind
        case .masterIntensity: return .masterIntensity
        case .panic: return .panic
        case .clearOverrides: return .clearOverrides
        case .toggleMIDIPerformance: return .toggleMIDIPerformance
        default: return nil
        }
    }
}
