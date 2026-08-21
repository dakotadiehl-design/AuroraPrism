import Combine
import Foundation
import PrismACP

/// App-owned ACP lifecycle. Does not construct snapshots on a timer.
@MainActor
final class PrismACPController: ObservableObject {
    @Published private(set) var status: String = "ACP: off"
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var nodeID: String = ""

    let service: PrismACPService

    init(applicationSupportDirectory: URL? = nil) {
        let support = applicationSupportDirectory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("Prism/ACP", isDirectory: true)
        service = PrismACPService(
            configuration: PrismACPConfiguration(
                enabled: false,
                discoveryEnabled: false,
                advertiseControl: false,
                applicationSupportDirectory: support
            )
        )
    }

    func setEnabled(_ enabled: Bool) async {
        await apply(enabled: enabled, discovery: false, port: 27421, loopbackOnly: true)
    }

    func apply(
        enabled: Bool,
        discovery: Bool,
        port: UInt16,
        loopbackOnly: Bool,
        advertiseControl: Bool = false,
        operatorNodeIDs: Set<String> = [],
        blackoutClearNodeIDs: Set<String> = []
    ) async {
        do {
            // A claimed node ID is sufficient for local integration testing,
            // but not for LAN control until ACP transport trust/pairing binds
            // that identity cryptographically. Keep LAN mutation fail-closed.
            let trustedControl = advertiseControl && loopbackOnly && !operatorNodeIDs.isEmpty
            try await service.applyConfiguration(
                PrismACPConfiguration(
                    enabled: enabled,
                    discoveryEnabled: discovery,
                    advertiseControl: trustedControl,
                    operatorNodeIDs: operatorNodeIDs,
                    blackoutClearNodeIDs: blackoutClearNodeIDs,
                    webSocketPort: port,
                    loopbackOnly: loopbackOnly,
                    applicationSupportDirectory: FileManager.default.urls(
                        for: .applicationSupportDirectory, in: .userDomainMask
                    ).first!.appendingPathComponent("Prism/ACP", isDirectory: true)
                )
            )
            let diag = await service.diagnostics()
            isRunning = diag.listenerState == .ready
            nodeID = diag.nodeID
            status = isRunning ? (trustedControl ? "ACP: ready · GO enabled" : "ACP: ready · view only") : "ACP: off"
        } catch {
            isRunning = false
            status = "ACP: failed"
        }
    }

    func stop() async {
        await service.stop()
        isRunning = false
        status = "ACP: off"
    }
}
