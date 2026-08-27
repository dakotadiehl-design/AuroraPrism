import AuroraACPAppleSecurity
import Foundation

/// ACP-owned security material already provisioned for this signed Prism app.
/// Prism cannot create this material because ACP's authority/bootstrap and
/// enrollment coordinators are not public at the current integration baseline.
public struct PrismACPSecureHostMaterial: @unchecked Sendable {
    public let configuration: ACPAppleFullProviderConfiguration

    public init(configuration: ACPAppleFullProviderConfiguration) {
        self.configuration = configuration
    }
}

public struct PrismACPConfiguration: @unchecked Sendable {
    public var enabled: Bool
    public var discoveryEnabled: Bool
    public var port: UInt16
    public var secureHostMaterial: PrismACPSecureHostMaterial?

    public init(
        enabled: Bool = false,
        discoveryEnabled: Bool = false,
        port: UInt16 = 27421,
        secureHostMaterial: PrismACPSecureHostMaterial? = nil
    ) {
        self.enabled = enabled
        self.discoveryEnabled = discoveryEnabled
        self.port = port
        self.secureHostMaterial = secureHostMaterial
    }
}

public enum PrismACPListenerState: String, Sendable, Equatable {
    case stopped
    case starting
    case blocked
    case ready
    case stopping
    case failed
}

public enum PrismACPBlocker: String, Error, Sendable, Equatable {
    case enrollmentBootstrapUnavailable = "ACP does not expose the public bootstrap/enrollment API required to provision Prism's first secure identity."
    case secureIdentityUnavailable = "No ACP-provisioned Apple Full identity is available. Secure ACP remains stopped."
}
