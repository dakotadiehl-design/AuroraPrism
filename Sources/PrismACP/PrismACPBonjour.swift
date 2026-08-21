import AuroraACP
import Darwin
import Foundation

public struct ACPDiscoveryTXT: Sendable, Equatable {
    public static let advertisedProfiles = ["core", "remote", "aurora.remote.prism.v1"]

    public var name: String
    public var port: UInt16
    public var nodeID: String
    public var instanceID: String
    public var endpointURL: String

    public init(name: String, port: UInt16, nodeID: String, instanceID: String, endpointURL: String) {
        self.name = name
        self.port = port
        self.nodeID = nodeID
        self.instanceID = instanceID
        self.endpointURL = endpointURL
    }

    public var txtRecord: [String: String] {
        var record = ACPDiscoveryEndpoint(
            nodeID: nodeID,
            instanceID: instanceID,
            role: "prism",
            name: name,
            endpointURL: endpointURL,
            profiles: Self.advertisedProfiles,
            encodings: ["cbor", "json"],
            capabilitiesDigest: "",
            securityMode: "trusted_lan"
        ).bonjourTXT
        record["path"] = "/acp"
        return record
    }

    /// Loopback URLs are only valid for This Mac. LAN advertisements omit `url`
    /// unless a non-loopback address is known so clients use the Bonjour host+port.
    public static func advertisementURL(port: UInt16, loopbackOnly: Bool) -> String {
        if loopbackOnly {
            return "ws://127.0.0.1:\(port)/acp"
        }
        if let ip = firstNonLoopbackIPv4() {
            return "ws://\(ip):\(port)/acp"
        }
        return ""
    }

    public static func firstNonLoopbackIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr = ifaddr
        while let iface = ptr {
            defer { ptr = iface.pointee.ifa_next }
            let flags = Int32(iface.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let addr = iface.pointee.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let len = socklen_t(addr.pointee.sa_len)
            guard getnameinfo(addr, len, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            if !ip.isEmpty { return ip }
        }
        return nil
    }
}
