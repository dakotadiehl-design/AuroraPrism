import Foundation

public struct PrismACPAvailability: Sendable, Equatable {
    public var action: String
    public var available: Bool
    public var reason: String?

    public init(action: String, available: Bool, reason: String? = nil) {
        self.action = action
        self.available = available
        self.reason = reason
    }
}

public struct PrismACPAvailabilityProvider: Sendable {
    public init() {}

    public func availability(for action: String, showLoaded: Bool) -> PrismACPAvailability {
        if !showLoaded {
            return PrismACPAvailability(action: action, available: false, reason: "no_show_loaded")
        }
        switch action {
        case "performance.go", "performance.fire_cue", "output.master", "blackoutOn", "blackoutOff":
            return PrismACPAvailability(action: action, available: true)
        default:
            return PrismACPAvailability(action: action, available: false, reason: "permission_denied")
        }
    }
}
