import AuroraModel
import Foundation
import Network

/// Sends E1.31 DATA frames over UDP (port 5568 by default).
public final class SACNOutputDriver: OutputDriver, @unchecked Sendable {
    public let id: UUID
    public let name: String
    public let outputProtocol: UniverseProtocolHint = .sACN
    public private(set) var isRunning = false

    private var config: SACNConfig
    private let cid: UUID
    private let queue = DispatchQueue(label: "com.aurora.sacn", qos: .userInteractive)
    private let lock = NSLock()
    private var sequence: UInt8 = 0
    private var connections: [String: NWConnection] = [:]
    private var _lastError: String?

    public var lastError: String? {
        lock.lock()
        defer { lock.unlock() }
        return _lastError
    }

    public var configSnapshot: SACNConfig {
        lock.lock()
        defer { lock.unlock() }
        return config
    }

    public init(
        id: UUID = UUID(),
        name: String = "sACN",
        config: SACNConfig = .default,
        cid: UUID = UUID()
    ) {
        self.id = id
        self.name = name
        self.config = config
        self.cid = cid
    }

    public func updateConfig(_ config: SACNConfig) {
        lock.lock()
        self.config = config
        lock.unlock()
        if isRunning {
            stop()
            try? start()
        }
    }

    public func start() throws {
        lock.lock()
        isRunning = true
        sequence = 0
        _lastError = nil
        lock.unlock()
    }

    public func stop() {
        lock.lock()
        for (_, conn) in connections {
            conn.cancel()
        }
        connections.removeAll()
        isRunning = false
        lock.unlock()
    }

    public func send(universe: UInt16, dmx: UnsafeBufferPointer<UInt8>) {
        lock.lock()
        guard isRunning else {
            lock.unlock()
            return
        }
        let cfg = config
        let seq = sequence
        sequence &+= 1
        let componentID = cid
        lock.unlock()

        let sacnUniverse = cfg.sacnUniverse(forShowUniverse: universe)
        let host = cfg.destinationHost(forSACNUniverse: sacnUniverse)
        let packet = SACNPacket.dataPacket(
            universe: sacnUniverse,
            sequence: seq,
            priority: cfg.priority,
            cid: componentID.uuid,
            sourceName: cfg.sourceName,
            dmx: dmx
        )

        let connection = connection(forHost: host, port: cfg.destinationPort)
        connection.send(content: packet, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.lock.lock()
                self?._lastError = error.localizedDescription
                self?.lock.unlock()
            }
        })
    }

    private func connection(forHost host: String, port: UInt16) -> NWConnection {
        lock.lock()
        if let existing = connections[host] {
            lock.unlock()
            return existing
        }
        lock.unlock()

        let endpointHost = NWEndpoint.Host(host)
        let endpointPort = NWEndpoint.Port(rawValue: port) ?? 5568
        let params = NWParameters.udp
        let conn = NWConnection(host: endpointHost, port: endpointPort, using: params)
        conn.start(queue: queue)

        lock.lock()
        connections[host] = conn
        lock.unlock()
        return conn
    }
}
