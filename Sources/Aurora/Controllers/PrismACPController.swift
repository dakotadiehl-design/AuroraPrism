import AuroraACP
import Combine
import Foundation
import PrismACP
import Security

/// Main-actor presentation bridge for the secure, observation-only ACP host.
@MainActor
final class PrismACPController: ObservableObject {
    @Published private(set) var status: String = "ACP: off"
    @Published private(set) var isRunning = false
    @Published private(set) var nodeID = ""
    @Published private(set) var enrollmentStatus = "Enrollment unavailable"
    @Published private(set) var pendingEnrollments: [PrismACPEnrollmentRequest] = []
    @Published private(set) var trustedPeers: [PrismACPTrustedPeer] = []

    let service: PrismACPService
    private let identity: ACPIdentity
    private let provenanceJSON: Data?
    private let expectedProviderRevision: String?
    private var enrollmentUpdatesTask: Task<Void, Never>?
    private let defaults: UserDefaults
    let authorityEpoch: UInt64
    private var authoritativeRevision: UInt64

    init(bundle: Bundle = .main, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let key = "prism.app.acp.nodeID.v1"
        let stableNodeID: String
        if let stored = defaults.string(forKey: key), UUID(uuidString: stored) != nil {
            stableNodeID = stored.lowercased()
        } else {
            stableNodeID = UUID().uuidString.lowercased()
            defaults.set(stableNodeID, forKey: key)
        }
        identity = ACPIdentity(
            nodeID: stableNodeID,
            instanceID: UUID().uuidString.lowercased(),
            role: "prism",
            name: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Prism")
        provenanceJSON = bundle.url(
            forResource: "acp-apple-full-provider-provenance", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
        expectedProviderRevision = bundle.object(
            forInfoDictionaryKey: "ACPProviderSourceRevision") as? String
        let epochKey = "prism.app.acp.authorityEpoch.v1"
        if let saved = defaults.object(forKey: epochKey) as? NSNumber,
           saved.uint64Value > 0 {
            authorityEpoch = saved.uint64Value
        } else {
            var bytes = [UInt8](repeating: 0, count: 8)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            let generated = bytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) } | 1
            authorityEpoch = generated
            defaults.set(NSNumber(value: generated), forKey: epochKey)
        }
        authoritativeRevision = UInt64(defaults.object(
            forKey: "prism.app.acp.authoritativeRevision.v1") as? Int ?? 0)
        service = PrismACPService(configuration: PrismACPConfiguration(identity: identity))
    }

    func nextAuthoritativeRevision() -> UInt64 {
        authoritativeRevision &+= 1
        defaults.set(Int(min(authoritativeRevision, UInt64(Int.max))),
                     forKey: "prism.app.acp.authoritativeRevision.v1")
        return authoritativeRevision
    }

    func setEnabled(_ enabled: Bool) async {
        await apply(enabled: enabled, discovery: false, port: 27421)
    }

    func apply(enabled: Bool, discovery: Bool, port: UInt16) async {
        do {
            try await service.applyConfiguration(PrismACPConfiguration(
                enabled: enabled,
                enrollmentEnabled: true,
                discoveryEnabled: discovery,
                port: port,
                identity: identity,
                providerProvenanceJSON: provenanceJSON,
                expectedProviderSourceRevision: expectedProviderRevision,
                preferSecureEnclave: true,
                allowNonHardwareFallback: false))
            await refresh()
            observeEnrollmentRequests()
        } catch let blocker as PrismACPBlocker {
            await refresh()
            status = "ACP: blocked · \(blocker.rawValue)"
        } catch {
            await refresh()
            status = "ACP: failed securely"
        }
    }

    func stop() async {
        enrollmentUpdatesTask?.cancel()
        enrollmentUpdatesTask = nil
        pendingEnrollments = []
        await service.stop()
        await refresh()
    }

    func beginEnrollment(enrollmentID: String, candidateNodeID: String,
                         displayName: String?, code: String) async {
        guard let enrollment = ACPEnrollmentID(rawValue: enrollmentID.lowercased()),
              let node = ACPSecurityNodeID(rawValue: candidateNodeID.lowercased()) else {
            enrollmentStatus = "Enrollment identifiers are invalid"
            return
        }
        do {
            let enrollmentCode: PrismACPEnrollmentCode = code.allSatisfy(\.isNumber)
                ? .manualNumeric(code) : .highEntropy(code)
            let outcome = try await service.beginEnrollment(
                enrollmentID: enrollment, candidateNodeID: node,
                displayName: displayName, code: enrollmentCode)
            enrollmentStatus = "Enrollment \(outcome.rawValue)"
        } catch {
            enrollmentStatus = "Enrollment failed securely"
        }
    }

    func approveEnrollment(_ id: ACPEnrollmentAttemptID) async {
        do { try await service.approveEnrollment(id) }
        catch { enrollmentStatus = "Enrollment approval failed securely" }
    }

    func rejectEnrollment(_ id: ACPEnrollmentAttemptID) async {
        do { try await service.rejectEnrollment(id) }
        catch { enrollmentStatus = "Enrollment rejection failed securely" }
    }

    func cancelEnrollment(_ id: ACPEnrollmentAttemptID) async {
        do { try await service.cancelEnrollment(id) }
        catch { enrollmentStatus = "Enrollment cancellation failed securely" }
    }

    func revokePeer(_ credentialID: String) async {
        do {
            _ = try await service.revoke(credentialID: credentialID)
            trustedPeers = await service.trustedPeerSummaries()
        } catch {
            status = "ACP: revocation failed securely"
        }
    }

    private func refresh() async {
        let diagnostics = await service.diagnostics()
        isRunning = diagnostics.isRunning
        nodeID = diagnostics.nodeID
        trustedPeers = await service.trustedPeerSummaries()
        if diagnostics.enrollmentAvailable, let port = diagnostics.enrollmentPort {
            enrollmentStatus = "Enrollment available on ACP enrollment port \(port)"
        } else {
            enrollmentStatus = "Enrollment unavailable"
        }
        if let blocker = diagnostics.blocker {
            status = "ACP: blocked · \(blocker.rawValue)"
        } else if isRunning, diagnostics.discoveryBlocker != nil {
            status = "ACP: secure · observation only · discovery blocked"
        } else {
            status = isRunning ? "ACP: secure · observation only" : "ACP: off"
        }
    }

    private func observeEnrollmentRequests() {
        enrollmentUpdatesTask?.cancel()
        enrollmentUpdatesTask = Task { [weak self] in
            guard let self else { return }
            let updates = await service.enrollmentRequestUpdates()
            for await requests in updates {
                guard !Task.isCancelled else { return }
                pendingEnrollments = requests
            }
        }
    }
}
