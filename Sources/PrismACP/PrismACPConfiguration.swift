import AuroraACP
import Foundation

public struct PrismACPConfiguration: Sendable {
    public var enabled: Bool
    public var enrollmentEnabled: Bool
    public var discoveryEnabled: Bool
    public var port: UInt16
    public var enrollmentPort: UInt16
    public var identity: ACPIdentity
    public var storageNamespace: String
    public var keychainAccessGroup: String?
    public var providerProvenanceJSON: Data?
    public var expectedProviderSourceRevision: String?
    public var preferSecureEnclave: Bool
    public var allowNonHardwareFallback: Bool

    public init(
        enabled: Bool = false,
        enrollmentEnabled: Bool = true,
        discoveryEnabled: Bool = false,
        port: UInt16 = 27421,
        enrollmentPort: UInt16 = 0,
        identity: ACPIdentity = ACPIdentity(role: "prism", name: "Prism"),
        storageNamespace: String = "com.aurora.lighting.acp",
        keychainAccessGroup: String? = nil,
        providerProvenanceJSON: Data? = nil,
        expectedProviderSourceRevision: String? = nil,
        preferSecureEnclave: Bool = true,
        allowNonHardwareFallback: Bool = false
    ) {
        self.enabled = enabled
        self.enrollmentEnabled = enrollmentEnabled
        self.discoveryEnabled = discoveryEnabled
        self.port = port
        self.enrollmentPort = enrollmentPort
        self.identity = identity
        self.storageNamespace = storageNamespace
        self.keychainAccessGroup = keychainAccessGroup
        self.providerProvenanceJSON = providerProvenanceJSON
        self.expectedProviderSourceRevision = expectedProviderSourceRevision
        self.preferSecureEnclave = preferSecureEnclave
        self.allowNonHardwareFallback = allowNonHardwareFallback
    }
}

public enum PrismACPListenerState: String, Sendable, Equatable {
    case stopped, starting, blocked, ready, stopping, failed
}

public enum PrismACPBlocker: String, Error, Sendable, Equatable {
    case providerManifestMissing = "The qualified ACP Apple provider manifest is not bundled. Secure ACP remains stopped."
    case providerManifestInvalid = "The bundled ACP Apple provider manifest is invalid or unqualified. Secure ACP remains stopped."
    case providerRevisionMismatch = "The ACP provider manifest does not match the linked provider revision. Secure ACP remains stopped."
    case hostProvisioningUnavailable = "ACP could not open or provision the secure Prism host. Secure ACP remains stopped."
    case discoveryContractUnavailable = "ACP does not define a canonical URL for framed TLS or enrollment discovery. Bonjour remains stopped."
}
