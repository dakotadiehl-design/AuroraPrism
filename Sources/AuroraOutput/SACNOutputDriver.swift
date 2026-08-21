import AuroraDiagnostics
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
    private let noteFrameSummary: @Sendable () -> Int?

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
        cid: UUID = UUID(),
        frameSummaryNote: (@Sendable () -> Int?)? = nil
    ) {
        self.id = id
        self.name = name
        self.config = config
        self.cid = cid
        if let frameSummaryNote {
            noteFrameSummary = frameSummaryNote
        } else {
            let counter = PrismIntervalCounter(interval: 1)
            noteFrameSummary = { counter.note() }
        }
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
            _lastError = PrismErrorReporting.userFacingMessage(for: error)
            _state = .failed
            lock.unlock()
            PrismLog.error(
                .outputSacn,
                "output.sacn.failed",
                "Prism couldn't update sACN.",
                technical: String(reflecting: error),
                ratePolicy: .oncePerSecond
            )
        }
    }

    public func start() throws {
        lock.lock()
        _isRunning = true
        sequences.removeAll()
        _lastError = nil
        _state = .ready
        lock.unlock()
        PrismLog.notice(.outputSacn, "output.sacn.started", "sACN output is on.")
    }

    public func stop() {
        // Snapshot under lock; cancel outside so NW path callbacks cannot re-enter deadlocked.
        lock.lock()
        let wasRunning = _isRunning
        let open = Array(connections.values)
        connections.removeAll()
        _isRunning = false
        _state = .disabled
        lock.unlock()
        for conn in open {
            conn.cancel()
        }
        if wasRunning {
            PrismLog.notice(.outputSacn, "output.sacn.stopped", "sACN output is off.")
        }
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
            self?.handleSendCompletion(error)
        })
    }

    /// Kept internal so completion-state behavior can be tested without a live UDP failure.
    func handleSendCompletion(_ error: NWError?) {
        lock.lock()
        guard _isRunning else {
            lock.unlock()
            return
        }
        if let error {
            _lastError = PrismErrorReporting.userFacingMessage(for: error)
            _packetsDropped &+= 1
            _state = .degraded
            lock.unlock()
            PrismLog.error(
                .outputSacn,
                "output.sacn.failed",
                "Prism couldn't send an sACN frame.",
                technical: String(reflecting: error),
                ratePolicy: .oncePerSecond
            )
            return
        }

        _packetsSent &+= 1
        _lastSuccessAt = Date()
        let recovered = _state == .degraded
        if recovered { _state = .ready }
        lock.unlock()
        if recovered {
            PrismLog.info(.outputSacn, "output.sacn.recovered", "sACN recovered.")
        }
        guard PrismLog.isEnabled(.debug, category: .outputSacn),
              let count = noteFrameSummary() else { return }
        PrismLog.debug(
            .outputSacn,
            "output.sacn.frame_summary",
            "sACN frame summary.",
            metadata: ["count": .count(count), "sampled": .flag(true)]
        )
    }

    private func connection(forHost host: String, port: UInt16) -> NWConnection {
        // Key by host+port so destination port changes don't orphan sockets.
        let key = "\(host):\(port)"
        lock.lock()
        if let existing = connections[key] {
            lock.unlock()
            return existing
        }
        // Create under lock to prevent dual untracked connections (Post-C6 audit).
        let endpointHost = NWEndpoint.Host(host)
        let endpointPort = NWEndpoint.Port(rawValue: port) ?? 5568
        let params = NWParameters.udp
        let conn = NWConnection(host: endpointHost, port: endpointPort, using: params)
        connections[key] = conn
        lock.unlock()
        conn.start(queue: queue)
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
