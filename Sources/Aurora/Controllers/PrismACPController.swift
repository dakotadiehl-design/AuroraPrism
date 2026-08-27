import Combine
import Foundation
import PrismACP

/// Main-actor presentation bridge for the secure, read-only ACP host.
@MainActor
final class PrismACPController: ObservableObject {
    @Published private(set) var status: String = "ACP: off"
    @Published private(set) var isRunning = false
    @Published private(set) var nodeID = ""
    @Published private(set) var enrollmentStatus = "Enrollment unavailable: ACP public bootstrap API required"

    let service: PrismACPService
    private let secureHostMaterial: PrismACPSecureHostMaterial?

    init(secureHostMaterial: PrismACPSecureHostMaterial? = nil) {
        self.secureHostMaterial = secureHostMaterial
        service = PrismACPService(configuration: PrismACPConfiguration())
    }

    func setEnabled(_ enabled: Bool) async {
        await apply(enabled: enabled, discovery: false, port: 27421)
    }

    func apply(enabled: Bool, discovery: Bool, port: UInt16) async {
        do {
            try await service.applyConfiguration(PrismACPConfiguration(
                enabled: enabled,
                discoveryEnabled: discovery,
                port: port,
                secureHostMaterial: secureHostMaterial
            ))
            await refresh()
        } catch let blocker as PrismACPBlocker {
            await refresh()
            status = "ACP: blocked · \(blocker.rawValue)"
        } catch {
            await refresh()
            status = "ACP: failed securely"
        }
    }

    func stop() async {
        await service.stop()
        await refresh()
    }

    private func refresh() async {
        let diagnostics = await service.diagnostics()
        isRunning = diagnostics.isRunning
        nodeID = diagnostics.nodeID
        if let blocker = diagnostics.blocker {
            status = "ACP: blocked · \(blocker.rawValue)"
        } else {
            status = isRunning ? "ACP: secure · read only" : "ACP: off"
        }
    }
}
