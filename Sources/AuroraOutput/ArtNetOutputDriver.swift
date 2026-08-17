import AuroraModel
import Foundation
import Network

/// Sends ArtDmx frames over UDP (port 6454 by default).
public final class ArtNetOutputDriver: OutputDriver, @unchecked Sendable {
    public let id: UUID
    public let name: String
    public let outputProtocol: UniverseProtocolHint = .artNet
    private var _isRunning = false
    /// Thread-safe running flag (PRE-UI-2); engine flush may read concurrently with start/stop.
    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isRunning
    }

    private var config: ArtNetConfig
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.aurora.artnet", qos: .userInteractive)
    private let lock = NSLock()
    /// Per-show-universe Art-Net sequence (P2-3).
    private var sequences: [UInt16: UInt8] = [:]
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

    public var configSnapshot: ArtNetConfig {
        lock.lock()
        defer { lock.unlock() }
        return config
    }

    public init(id: UUID = UUID(), name: String = "Art-Net", config: ArtNetConfig = .default) {
        self.id = id
        self.name = name
        self.config = config
    }

    public func updateConfig(_ config: ArtNetConfig) throws {
        lock.lock()
        self.config = config
        let wasRunning = _isRunning
        lock.unlock()
        if wasRunning {
            stop()
            try start()
        }
    }

    /// Soft update that records errors into health instead of throwing (UI paths).
    public func applyConfig(_ config: ArtNetConfig) {
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
        _state = .starting
        let cfg = config
        lock.unlock()

        let host = NWEndpoint.Host(cfg.destinationHost)
        let port = NWEndpoint.Port(rawValue: cfg.destinationPort) ?? 6454
        let params = NWParameters.udp
        if cfg.useBroadcast || cfg.destinationHost.hasSuffix(".255") || cfg.destinationHost == "255.255.255.255" {
            params.allowLocalEndpointReuse = true
            if let ipOpts = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
                ipOpts.version = .v4
            }
        }

        let conn = NWConnection(host: host, port: port, using: params)
        let sem = DispatchSemaphore(value: 0)
        // Queue-confined startup result (Post-C6: no unsynchronized startError race).
        final class StartupBox: @unchecked Sendable {
            let lock = NSLock()
            var error: Error?
            var becameReady = false
            var cancelled = false
        }
        let box = StartupBox()

        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                box.lock.lock()
                box.becameReady = true
                box.lock.unlock()
                self?.lock.lock()
                self?._state = .ready
                self?._lastError = nil
                self?.lock.unlock()
                sem.signal()
            case .failed(let err):
                box.lock.lock()
                box.error = err
                box.lock.unlock()
                self?.lock.lock()
                self?._lastError = err.localizedDescription
                self?._state = .failed
                self?.lock.unlock()
                sem.signal()
            case .cancelled:
                box.lock.lock()
                box.cancelled = true
                box.lock.unlock()
                self?.lock.lock()
                if self?._isRunning == true {
                    self?._state = .disabled
                }
                self?.lock.unlock()
                sem.signal()
            case .waiting(let err):
                self?.lock.lock()
                self?._lastError = err.localizedDescription
                if self?._state == .ready {
                    self?._state = .degraded
                }
                self?.lock.unlock()
            default:
                break
            }
        }
        conn.start(queue: queue)

        let waitResult = sem.wait(timeout: .now() + 0.5)
        box.lock.lock()
        let startError = box.error
        let ready = box.becameReady
        let cancelled = box.cancelled
        box.lock.unlock()

        lock.lock()
        connection = conn
        _isRunning = true
        sequences.removeAll()
        if let startError {
            _lastError = startError.localizedDescription
            _state = .failed
        } else if cancelled {
            _state = .disabled
        } else if ready {
            _lastError = nil
            _state = .ready
        } else if waitResult == .timedOut {
            // Timeout while still preparing — never report ready (Post-C6 audit).
            _lastError = "Art-Net connection timed out while starting"
            _state = .degraded
        } else {
            _state = .starting
        }
        lock.unlock()
    }

    public func stop() {
        // Snapshot under lock; cancel outside so NW path callbacks cannot re-enter deadlocked.
        lock.lock()
        let conn = connection
        connection = nil
        _isRunning = false
        _state = .disabled
        lock.unlock()
        conn?.cancel()
    }

    public func send(universe: UInt16, dmx: UnsafeBufferPointer<UInt8>) {
        lock.lock()
        guard _isRunning, let connection else {
            _packetsDropped &+= 1
            lock.unlock()
            return
        }
        let cfg = config
        var seq = sequences[universe] ?? 1
        let current = seq
        if seq == 255 {
            seq = 1
        } else {
            seq &+= 1
        }
        sequences[universe] = seq
        lock.unlock()

        let artUniverse = cfg.artNetUniverse(forShowUniverse: universe)
        let packet = ArtNetPacket.artDmx(universe: artUniverse, sequence: current, dmx: dmx)

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
}

extension ArtNetOutputDriver: OutputHealthReporting {
    public func healthSnapshot() -> OutputHealthSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return OutputHealthSnapshot(
            driverID: id,
            name: name,
            outputProtocol: outputProtocol,
            state: _isRunning ? _state : .disabled,
            target: "\(config.destinationHost):\(config.destinationPort)",
            lastError: _lastError,
            lastSuccessAt: _lastSuccessAt,
            packetsSent: _packetsSent,
            packetsDropped: _packetsDropped,
            activeUniverses: Array(sequences.keys).sorted()
        )
    }
}
