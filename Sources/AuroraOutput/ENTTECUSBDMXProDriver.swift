import AuroraModel
import Foundation

/// ENTTEC **DMX USB Pro** framed serial protocol (label-6 Send DMX Packet).
///
/// This is **not** ENTTEC Open DMX. Open DMX uses a continuous FTDI-style bit stream
/// and different timing; do not present this driver as Open DMX capable (PRE-UI-3).
///
/// Physical USB I/O is abstracted behind `ENTTECSerialTransport` so unit tests can
/// validate packets without hardware. A real macOS serial transport is not yet
/// wired; UI should enumerate `LocalDMXDeviceDescriptor` and only enable devices
/// whose `connectionState` is openable.
public protocol ENTTECSerialTransport: AnyObject {
    var isOpen: Bool { get }
    func open() throws
    func close()
    func write(_ data: Data) throws
}

/// UI-facing local DMX hardware descriptor (PRE-UI-3).
/// Enumeration/open of real USB Pro devices is scheduled separately; mock layer
/// can populate these for Settings UI development.
public struct LocalDMXDeviceDescriptor: Equatable, Sendable, Identifiable, Hashable {
    public enum DeviceType: String, Sendable, Hashable {
        case enttecUSBDMXPro
        /// Reserved — not implemented by `ENTTECUSBDMXProDriver`.
        case enttecOpenDMX
        case other
    }

    public enum ConnectionState: String, Sendable, Hashable {
        case unavailable
        case available
        case open
        case failed
    }

    public var id: String
    public var displayName: String
    public var serialPath: String?
    public var hardwareIdentifier: String?
    public var deviceType: DeviceType
    public var connectionState: ConnectionState
    public var supportedUniverses: [UInt16]

    public init(
        id: String,
        displayName: String,
        serialPath: String? = nil,
        hardwareIdentifier: String? = nil,
        deviceType: DeviceType = .enttecUSBDMXPro,
        connectionState: ConnectionState = .unavailable,
        supportedUniverses: [UInt16] = [1]
    ) {
        self.id = id
        self.displayName = displayName
        self.serialPath = serialPath
        self.hardwareIdentifier = hardwareIdentifier
        self.deviceType = deviceType
        self.connectionState = connectionState
        self.supportedUniverses = supportedUniverses
    }
}

/// Placeholder enumerator until macOS IOKit serial transport lands.
public enum LocalDMXDeviceEnumerator {
    /// Returns discovered local DMX devices. Currently empty (no physical transport).
    public static func enumerate() -> [LocalDMXDeviceDescriptor] {
        []
    }
}

/// In-memory transport for tests / offline.
public final class MockENTTECTransport: ENTTECSerialTransport, @unchecked Sendable {
    public private(set) var isOpen = false
    public private(set) var written: [Data] = []
    public var failOpen = false

    public init() {}

    public func open() throws {
        if failOpen { throw ENTTECError.deviceMissing }
        isOpen = true
    }

    public func close() {
        isOpen = false
    }

    public func write(_ data: Data) throws {
        guard isOpen else { throw ENTTECError.notOpen }
        written.append(data)
    }
}

public enum ENTTECError: Error, Equatable, Sendable {
    case deviceMissing
    case notOpen
    case writeFailed(String)
}

/// Builds ENTTEC DMX USB Pro “Send DMX Packet Request” frames (label 6).
public enum ENTTECUSBDMXProProtocol {
    public static let startCode: UInt8 = 0x7E
    public static let endCode: UInt8 = 0xE7
    public static let labelSendDMX: UInt8 = 6

    /// Frame: 0x7E | label | lenLSB | lenMSB | startCode(0) | 512 DMX | 0xE7
    public static func sendDMXPacket(dmx: UnsafeBufferPointer<UInt8>, universeStartCode: UInt8 = 0) -> Data {
        let payloadLen = 1 + 512 // DMX start code + 512 channels
        var data = Data()
        data.reserveCapacity(5 + payloadLen)
        data.append(startCode)
        data.append(labelSendDMX)
        data.append(UInt8(payloadLen & 0xFF))
        data.append(UInt8((payloadLen >> 8) & 0xFF))
        data.append(universeStartCode)
        let channelCount = min(512, dmx.count)
        for i in 0..<channelCount {
            data.append(dmx[i])
        }
        if channelCount < 512 {
            data.append(contentsOf: Array(repeating: 0 as UInt8, count: 512 - channelCount))
        }
        data.append(endCode)
        return data
    }
}

/// Local DMX output driver using ENTTEC USB DMX Pro framing (P3-1).
public final class ENTTECUSBDMXProDriver: OutputDriver, OutputHealthReporting, @unchecked Sendable {
    public let id: UUID
    public let name: String
    public let outputProtocol: UniverseProtocolHint = .local
    private var _isRunning = false
    /// Thread-safe running flag (PRE-UI-2).
    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isRunning
    }

    private let lock = NSLock()
    private let transport: ENTTECSerialTransport
    private var _lastError: String?
    private var _packetsSent: UInt64 = 0
    private var _packetsDropped: UInt64 = 0
    private var _lastSuccessAt: Date?
    private var _state: OutputDriverState = .disabled
    /// Only show-universe numbers listed here are sent (default: 1).
    public var universeFilter: Set<UInt16>

    public init(
        id: UUID = UUID(),
        name: String = "ENTTEC USB DMX Pro",
        transport: ENTTECSerialTransport,
        universeFilter: Set<UInt16> = [1]
    ) {
        self.id = id
        self.name = name
        self.transport = transport
        self.universeFilter = universeFilter
    }

    public func start() throws {
        lock.lock()
        _state = .starting
        lock.unlock()
        do {
            try transport.open()
            lock.lock()
            _isRunning = true
            _state = .ready
            _lastError = nil
            lock.unlock()
        } catch {
            lock.lock()
            _isRunning = false
            _state = .failed
            _lastError = error.localizedDescription
            lock.unlock()
            throw error
        }
    }

    public func stop() {
        transport.close()
        lock.lock()
        _isRunning = false
        _state = .disabled
        lock.unlock()
    }

    public func send(universe: UInt16, dmx: UnsafeBufferPointer<UInt8>) {
        lock.lock()
        guard _isRunning, universeFilter.contains(universe) else {
            if _isRunning { _packetsDropped &+= 1 }
            lock.unlock()
            return
        }
        lock.unlock()

        let packet = ENTTECUSBDMXProProtocol.sendDMXPacket(dmx: dmx)
        do {
            try transport.write(packet)
            lock.lock()
            _packetsSent &+= 1
            _lastSuccessAt = Date()
            if _state == .degraded { _state = .ready }
            lock.unlock()
        } catch {
            lock.lock()
            _lastError = error.localizedDescription
            _packetsDropped &+= 1
            _state = .degraded
            lock.unlock()
        }
    }

    public func healthSnapshot() -> OutputHealthSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return OutputHealthSnapshot(
            driverID: id,
            name: name,
            outputProtocol: .local,
            state: _state,
            target: "USB serial",
            lastError: _lastError,
            lastSuccessAt: _lastSuccessAt,
            packetsSent: _packetsSent,
            packetsDropped: _packetsDropped,
            activeUniverses: Array(universeFilter).sorted()
        )
    }
}
