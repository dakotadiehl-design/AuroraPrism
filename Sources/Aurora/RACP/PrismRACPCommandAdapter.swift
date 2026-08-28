import ReasonableACP
import Foundation

@MainActor
enum PrismRACPCommandAdapter {
    static func execute(
        _ command: Command,
        controller: ShowControlController,
        sessionID: String
    ) -> RACPCommandDisposition {
        let origin = ControlActionOrigin(
            sourceType: .remote,
            sessionID: sessionID,
            commandID: String(command.requestID),
            displayName: "rACP"
        )

        let outcome: PrismRACPCommandOutcome
        switch command.name {
        case PrismRACPCapability.cueGo:
            guard !command.hasValue else { return .error("invalid_value") }
            outcome = controller.executeRemoteGo(origin: origin)
        case PrismRACPCapability.cueBack:
            guard !command.hasValue else { return .error("invalid_value") }
            outcome = controller.executeRemoteBack(origin: origin)
        case PrismRACPCapability.cueStop:
            guard !command.hasValue else { return .error("invalid_value") }
            outcome = controller.executeRemoteStop(origin: origin)
        case PrismRACPCapability.outputGrandMasterSet:
            guard command.hasValue, let value = number(command.value) else {
                return .error("invalid_value")
            }
            outcome = controller.executeRemoteGrandMaster(value: value, origin: origin)
        case PrismRACPCapability.outputBlackoutSet:
            guard command.hasValue, case .bool(let enabled) = command.value else {
                return .error("invalid_value")
            }
            outcome = controller.executeRemoteBlackout(enabled: enabled, origin: origin)
        case PrismRACPCapability.songSelect:
            guard command.hasValue,
                  case .string(let rawID) = command.value,
                  let id = UUID(uuidString: rawID)
            else { return .error("invalid_value") }
            outcome = controller.executeRemoteSongSelection(id: id, origin: origin)
        default:
            return .error("unsupported_capability")
        }
        return disposition(for: outcome)
    }

    private static func number(_ value: JSONValue?) -> Double? {
        switch value {
        case .number(let value): return value
        case .integer(let value): return Double(value)
        default: return nil
        }
    }

    private static func disposition(for outcome: PrismRACPCommandOutcome) -> RACPCommandDisposition {
        switch outcome {
        case .executed, .unchanged: return .success
        case .invalidValue: return .error("invalid_value")
        case .invalidTarget: return .error("invalid_target")
        case .unavailable: return .error("unavailable")
        case .noNextCue: return .error("no_next_cue")
        case .noPreviousCue: return .error("no_previous_cue")
        }
    }
}
