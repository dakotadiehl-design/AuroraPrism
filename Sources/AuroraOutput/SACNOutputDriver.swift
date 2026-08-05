import AuroraModel
import Foundation
import Network

/// Sends E1.31 DATA frames over UDP (port 5568 by default).
public final class SACNOutputDriver: OutputDriver, @unchecked Sendable {
    public let id: UUID
    public let name: String
    public let outputProtocol: UniverseProtocolHint = .sACN
    private var _isRunning = false
    /// Thread-safe running flag (PRE-UI-2).
    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isRunning
    }

    private var config: SACNConfig
    private let cid: UUID
    private let queue = DispatchQueue(label: "com.aurora.sacn", qos: .userInteractive)
    private let lock = NSLock()
    /// Per-show-universe sACN sequence (P2-3).
    private var sequences: [UInt16: UInt8] = [:]
    private var connections: [String: NWConnection] = [:]
    private var _lastError: String?
    private var _packetsSent: UInt64 = 0
    private var _packetsDropped: UInt64 = 0
    private var _lastSuccessAt: Date?
    private var _state: OutputDriverState = .disabled

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

    public func updateConfig(_ config: SACNConfig) throws {
        lock.lock()
        self.config = config
        let wasRunning = _isRunning
        lock.unlock()
        if wasRunning {
            stop()
            try start()
        }
    }

    public func applyConfig(_ config: SACNConfig) {
        do {
            try updateConfig(config)
        } catch {
            lock.lock()
            _lastError = error.localizedDescription
            _state = .failed
            lock.unlock()
        }
    }

    public func start() throws {
        lock.lock()
        _isRunning = true
        sequences.removeAll()
        _lastError = nil
        _state = .ready
        lock.unlock()
    }

    public func stop() {
        lock.lock()
        for (_, conn) in connections {
            conn.cancel()
        }
        connections.removeAll()
        _isRunning = false
        _state = .disabled
        lock.unlock()
    }

    public func send(universe: UInt16, dmx: UnsafeBufferPointer<UInt8>) {
        lock.lock()
        guard _isRunning else {
            _packetsDropped &+= 1
            lock.unlock()
            return
        }
        let cfg = config
        var seq = sequences[universe] ?? 0
        let current = seq
        seq &+= 1
        sequences[universe] = seq
        let componentID = cid
        lock.unlock()

        let sacnUniverse = cfg.sacnUniverse(forShowUniverse: universe)
        let host = cfg.destinationHost(forSACNUniverse: sacnUniverse)
        let packet = SACNPacket.dataPacket(
            universe: sacnUniverse,
            sequence: current,
            priority: cfg.priority,
            cid: componentID.uuid,
            sourceName: cfg.sourceName,
            dmx: dmx
        )

        let connection = connection(forHost: host, port: cfg.destinationPort)
        connection.send(content: packet, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            self.lock.lock()
            if let error {
                self._lastError = error.localizedDescription
                self._packetsDropped &+= 1
                self._state = .degraded
            } else {
                self._packetsSent &+= 1
                self._lastSuccessAt = Date()
                if self._state == .degraded { self._state = .ready }
            }
            self.lock.unlock()
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

extension SACNOutputDriver: OutputHealthReporting {
    public func healthSnapshot() -> OutputHealthSnapshot {
        lock.lock()
        defer { lock.unlock() }
        let dest = config.destinationHost ?? "multicast"
        return OutputHealthSnapshot(
            driverID: id,
            name: name,
            outputProtocol: outputProtocol,
            state: _isRunning ? _state : .disabled,
            target: "\(dest):\(config.destinationPort)",
            lastError: _lastError,
            lastSuccessAt: _lastSuccessAt,
            packetsSent: _packetsSent,
            packetsDropped: _packetsDropped,
            activeUniverses: Array(sequences.keys).sorted()
        )
    }
}
