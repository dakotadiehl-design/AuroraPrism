import Foundation
import Network

/// Sends ArtDmx frames over UDP (port 6454 by default).
public final class ArtNetOutputDriver: OutputDriver, @unchecked Sendable {
    public let id: UUID
    public let name: String
    public private(set) var isRunning = false

    private var config: ArtNetConfig
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.aurora.artnet", qos: .userInteractive)
    private let lock = NSLock()
    private var sequence: UInt8 = 1
    private var _lastError: String?

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

    public func updateConfig(_ config: ArtNetConfig) {
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
        let cfg = config
        lock.unlock()

        let host = NWEndpoint.Host(cfg.destinationHost)
        let port = NWEndpoint.Port(rawValue: cfg.destinationPort) ?? 6454
        let params = NWParameters.udp
        if cfg.useBroadcast || cfg.destinationHost.hasSuffix(".255") || cfg.destinationHost == "255.255.255.255" {
            params.allowLocalEndpointReuse = true
            // Broadcast support
            if let ipOpts = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
                ipOpts.version = .v4
            }
        }

        let conn = NWConnection(host: host, port: port, using: params)
        let sem = DispatchSemaphore(value: 0)
        var startError: Error?

        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                sem.signal()
            case .failed(let err):
                startError = err
                sem.signal()
            case .cancelled:
                sem.signal()
            default:
                break
            }
        }
        conn.start(queue: queue)

        // Don't hard-fail if setup is slow; mark running and send opportunistically.
        _ = sem.wait(timeout: .now() + 0.5)
        if let startError {
            lock.lock()
            _lastError = startError.localizedDescription
            lock.unlock()
            // Still allow sends; connection may recover
        }

        lock.lock()
        connection = conn
        isRunning = true
        sequence = 1
        lock.unlock()
    }

    public func stop() {
        lock.lock()
        connection?.cancel()
        connection = nil
        isRunning = false
        lock.unlock()
    }

    public func send(universe: UInt16, dmx: UnsafeBufferPointer<UInt8>) {
        lock.lock()
        guard isRunning, let connection else {
            lock.unlock()
            return
        }
        let cfg = config
        let seq = sequence
        if sequence == 255 {
            sequence = 1
        } else if sequence > 0 {
            sequence &+= 1
        }
        lock.unlock()

        let artUniverse = cfg.artNetUniverse(forShowUniverse: universe)
        let packet = ArtNetPacket.artDmx(universe: artUniverse, sequence: seq, dmx: dmx)

        connection.send(content: packet, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.lock.lock()
                self?._lastError = error.localizedDescription
                self?.lock.unlock()
            }
        })
    }
}
