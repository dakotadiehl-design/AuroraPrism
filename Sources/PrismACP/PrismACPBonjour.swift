import Foundation

/// Bonjour is an endpoint hint only. It never carries credentials or grants trust.
final class PrismACPBonjourPublisher: NSObject, @unchecked Sendable {
    private var service: NetService?

    func start(port: UInt16, nodeID: String, instanceID: String) {
        stop()
        let service = NetService(domain: "local.", type: "_acp._tcp.", name: "Prism", port: Int32(port))
        let fields = [
            "node_id": nodeID,
            "instance_id": instanceID,
            "role": "prism",
            "profile": "full",
            "security": "aurora_trust",
            "tls": "required",
            "read_only": "true",
            "acp": "1.2",
        ]
        service.setTXTRecord(NetService.data(fromTXTRecord: fields.mapValues { Data($0.utf8) }))
        service.publish()
        self.service = service
    }

    func stop() {
        service?.stop()
        service = nil
    }

    var isActive: Bool { service != nil }
}
