import AuroraDiagnostics
import AuroraModel
import Foundation
#if os(macOS)
import Darwin
#endif

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

/// Injectable local-DMX discovery (HW-01 / CR integration).
public protocol LocalDMXDeviceDiscovering: AnyObject {
    func enumerate() -> [LocalDMXDeviceDescriptor]
}

/// Default production enumerator — macOS serial discovery when available.
///
/// HW-05: presents candidates as **Serial device** (not confirmed ENTTEC) unless
/// the path name strongly suggests DMX/Pro. Path is the current endpoint; full
/// IOKit vendor/serial identity is a follow-up for UI-08 persistence.
public final class MacLocalDMXDeviceEnumerator: LocalDMXDeviceDiscovering {
    public init() {}

    public func enumerate() -> [LocalDMXDeviceDescriptor] {
        #if os(macOS)
        let fm = FileManager.default
        let dev = "/dev"
        guard let names = try? fm.contentsOfDirectory(atPath: dev) else { return [] }
        let candidates = names.filter { name in
            name.hasPrefix("cu.") && (
                name.localizedCaseInsensitiveContains("usbserial")
                || name.localizedCaseInsensitiveContains("usbmodem")
                || name.localizedCaseInsensitiveContains("SLAB")
                || name.localizedCaseInsensitiveContains("DMX")
                || name.localizedCaseInsensitiveContains("FTDI")
            )
        }
        return candidates.sorted().map { name in
            let path = "\(dev)/\(name)"
            // Only strongly DMX/ENTTEC-named paths are labeled Pro; generic FTDI/usbmodem stay `.other`
            // so Aurora does not write ENTTEC label-6 frames to arbitrary serial devices (Post-C6).
            let looksDMX = name.localizedCaseInsensitiveContains("DMX")
                || name.localizedCaseInsensitiveContains("ENTTEC")
            return LocalDMXDeviceDescriptor(
                id: path,
                displayName: looksDMX ? "Likely DMX \(name)" : "Serial \(name)",
                serialPath: path,
                hardwareIdentifier: path,
                deviceType: looksDMX ? .enttecUSBDMXPro : .other,
                connectionState: .available,
                supportedUniverses: [1]
            )
        }
        #else
        return []
        #endif
    }
}

/// Test double for Local DMX discovery.
public final class MockLocalDMXDeviceEnumerator: LocalDMXDeviceDiscovering {
    public var devices: [LocalDMXDeviceDescriptor] = []
    public init(devices: [LocalDMXDeviceDescriptor] = []) {
        self.devices = devices
    }
    public func enumerate() -> [LocalDMXDeviceDescriptor] { devices }
}

/// Back-compat static entry point.
public enum LocalDMXDeviceEnumerator {
    public static var shared: LocalDMXDeviceDiscovering = MacLocalDMXDeviceEnumerator()

    public static func enumerate() -> [LocalDMXDeviceDescriptor] {
        shared.enumerate()
    }
}

/// POSIX raw serial transport for ENTTEC USB Pro binary framing (HW-04).
///
/// Opens the tty with `O_RDWR | O_NOCTTY | O_NONBLOCK`, applies raw termios, and
/// **keeps the fd non-blocking**. Blocking serial I/O is a known quit hang:
/// engine frames call `write` while `applicationWillTerminate` calls `close`, and
/// a stuck USB VCOM can block both until the device is unplugged.
///
/// Locking contract:
/// - `ioLock` only protects the fd / `isOpen` fields — never held across `write`/`close` syscalls.
/// - Writers `dup()` the live fd under the lock, then write on the duplicate outside the lock.
///   That keeps the open-file description alive if `close()` reclaims the canonical fd number
///   (raw snapshot of `fd` is unsafe: the OS can reuse the integer for an unrelated file).
/// - `close` marks closed first so new writers bail, then closes the canonical fd outside the lock.
public final class MacENTTECSerialTransport: ENTTECSerialTransport, @unchecked Sendable {
    private let path: String
    private var fd: Int32 = -1
    private let ioLock = NSLock()
    public private(set) var isOpen = false

    /// Max time a single DMX frame write may spend waiting for USB buffer space.
    public var writeTimeout: TimeInterval = 0.05

    public init(path: String) {
        self.path = path
    }

    public func open() throws {
        ioLock.lock()
        defer { ioLock.unlock() }
        if isOpen { return }
        #if os(macOS)
        let opened = path.withCString { cPath in
            Darwin.open(cPath, O_RDWR | O_NOCTTY | O_NONBLOCK)
        }
        guard opened >= 0 else {
            isOpen = false
            throw ENTTECError.deviceMissing
        }
        // Keep O_NONBLOCK for the lifetime of the port (do not clear).
        var tio = termios()
        if tcgetattr(opened, &tio) == 0 {
            // Raw binary: disable ICANON, ECHO, ISIG, and output post-processing.
            cfmakeraw(&tio)
            tio.c_cflag |= tcflag_t(CLOCAL | CREAD)
            tio.c_cflag &= ~tcflag_t(CRTSCTS)
            tio.c_iflag &= ~tcflag_t(IXON | IXOFF | IXANY)
            // VMIN/VTIME unused for non-blocking; baud is dummy on USB VCOM.
            _ = tcsetattr(opened, TCSANOW, &tio)
        }
        fd = opened
        isOpen = true
        #else
        throw ENTTECError.deviceMissing
        #endif
    }

    public func close() {
        // Mark closed under lock first so concurrent writers stop issuing new dups.
        ioLock.lock()
        let closeFd = fd
        fd = -1
        isOpen = false
        ioLock.unlock()

        guard closeFd >= 0 else { return }
        #if os(macOS)
        // Best-effort: keep non-blocking so close is less likely to wait on drain.
        _ = fcntl(closeFd, F_SETFL, O_NONBLOCK)
        // Discard pending output — better than hanging terminate on a wedged VCOM.
        _ = tcflush(closeFd, TCOFLUSH)
        _ = Darwin.close(closeFd)
        #endif
    }

    public func write(_ data: Data) throws {
        #if os(macOS)
        // Dup under the lock so a concurrent close of the canonical fd cannot cause us to
        // write into a recycled descriptor number belonging to some other file.
        ioLock.lock()
        guard isOpen, fd >= 0 else {
            ioLock.unlock()
            throw ENTTECError.notOpen
        }
        let writeFd = Darwin.dup(fd)
        let timeout = writeTimeout
        ioLock.unlock()

        guard writeFd >= 0 else {
            throw ENTTECError.writeFailed("dup failed errno \(errno)")
        }
        defer { _ = Darwin.close(writeFd) }

        // Ensure the duplicate stays non-blocking (dup inherits flags, but be explicit).
        let flags = fcntl(writeFd, F_GETFL)
        if flags >= 0 {
            _ = fcntl(writeFd, F_SETFL, flags | O_NONBLOCK)
        }

        try POSIXWrite.completeWrite(fd: writeFd, data: data, timeout: timeout)
        #else
        throw ENTTECError.notOpen
        #endif
    }

    deinit {
        close()
    }
}

/// Full-write loop for partial POSIX writes (testable).
public enum POSIXWrite {
    /// Writes all bytes with a wall-clock budget.
    /// Retries `EINTR` and `EAGAIN`/`EWOULDBLOCK` until `timeout` elapses, then fails.
    /// Never blocks indefinitely on a stalled USB serial device.
    public static func completeWrite(
        fd: Int32,
        data: Data,
        timeout: TimeInterval = 0.05
    ) throws {
        #if os(macOS)
        try data.withUnsafeBytes { buf in
            guard let base = buf.baseAddress else {
                throw ENTTECError.writeFailed("empty buffer")
            }
            var offset = 0
            let total = buf.count
            let deadline = Date().addingTimeInterval(max(0.001, timeout))
            while offset < total {
                let n = Darwin.write(fd, base.advanced(by: offset), total - offset)
                if n < 0 {
                    let err = errno
                    if err == EINTR { continue }
                    if err == EAGAIN || err == EWOULDBLOCK {
                        if Date() >= deadline {
                            throw ENTTECError.writeFailed("write timeout")
                        }
                        // Brief poll for writability (≤2ms) without busy-spinning.
                        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                        _ = poll(&pfd, 1, 2)
                        continue
                    }
                    // EBADF after concurrent close — treat as closed.
                    if err == EBADF {
                        throw ENTTECError.notOpen
                    }
                    throw ENTTECError.writeFailed("write errno \(err)")
                }
                if n == 0 {
                    throw ENTTECError.writeFailed("write returned 0")
                }
                offset += n
            }
        }
        #else
        throw ENTTECError.notOpen
        #endif
    }
}

/// In-memory transport for tests / offline.
public final class MockENTTECTransport: ENTTECSerialTransport, @unchecked Sendable {
    public private(set) var isOpen = false
    public private(set) var written: [Data] = []
    public private(set) var openCount = 0
    public private(set) var closeCount = 0
    public var failOpen = false
    /// When true, a second open() throws (detects double-open) (HW-02 tests).
    public var failOnSecondOpen = false

    public init() {}

    public func open() throws {
        if failOpen { throw ENTTECError.deviceMissing }
        if failOnSecondOpen, openCount >= 1 {
            throw ENTTECError.deviceMissing
        }
        openCount += 1
        isOpen = true
    }

    public func close() {
        if isOpen {
            closeCount += 1
        }
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

extension ENTTECError: LocalizedError, PrismDiagnosableError {
    public var errorDescription: String? { userMessage }
    public var prismErrorCode: String {
        switch self {
        case .deviceMissing: return "output.localDMX.device_missing"
        case .notOpen: return "output.localDMX.not_open"
        case .writeFailed: return "output.localDMX.write_failed"
        }
    }
    public var userTitle: String { "Prism Couldn't Use the USB DMX Interface" }
    public var userMessage: String { "Prism couldn’t talk to the USB DMX interface." }
    public var recoverySuggestion: String? {
        "Check the cable, confirm the device is a DMX USB Pro, and try another port."
    }
    public var technicalDetails: String { String(reflecting: self) }
    public var prismCategory: PrismLogCategory { .outputLocalDMX }
    public var prismSeverity: PrismLogLevel { .error }
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
    private let noteFrameSummary: @Sendable () -> Int?
    /// Only show-universe numbers listed here are sent (default: 1). Locked storage.
    private var _universeFilter: Set<UInt16>

    public var universeFilter: Set<UInt16> {
        get {
            lock.lock(); defer { lock.unlock() }
            return _universeFilter
        }
        set {
            lock.lock()
            _universeFilter = newValue
            lock.unlock()
        }
    }

    public init(
        id: UUID = UUID(),
        name: String = "ENTTEC USB DMX Pro",
        transport: ENTTECSerialTransport,
        universeFilter: Set<UInt16> = [1],
        frameSummaryNote: (@Sendable () -> Int?)? = nil
    ) {
        self.id = id
        self.name = name
        self.transport = transport
        self._universeFilter = universeFilter
        if let frameSummaryNote {
            noteFrameSummary = frameSummaryNote
        } else {
            let counter = PrismIntervalCounter(interval: 1)
            noteFrameSummary = { counter.note() }
        }
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
            PrismLog.notice(.outputLocalDMX, "output.localDMX.started", "Local DMX is on.")
        } catch {
            lock.lock()
            _isRunning = false
            _state = .failed
            _lastError = PrismErrorReporting.userFacingMessage(for: error)
            lock.unlock()
            PrismLog.error(
                .outputLocalDMX,
                "output.localDMX.failed",
                "Prism couldn't start Local DMX.",
                technical: String(reflecting: error),
                ratePolicy: .oncePerSecond
            )
            throw error
        }
    }

    public func stop() {
        // ENTTEC USB Pro keeps retransmitting the last DMX packet in hardware until it
        // receives new data or loses the host session. Lightkey-style shutdown:
        // 1) stop accepting engine frames, 2) push a zero universe while the port is open,
        // 3) close the serial session synchronously.
        lock.lock()
        let wasRunning = _isRunning
        let filter = _universeFilter
        _isRunning = false
        _state = .disabled
        lock.unlock()

        if wasRunning, transport.isOpen {
            let zeros = [UInt8](repeating: 0, count: 512)
            zeros.withUnsafeBufferPointer { ptr in
                let packet = ENTTECUSBDMXProProtocol.sendDMXPacket(dmx: ptr)
                // One blackout frame per mapped show universe (default: U1).
                for _ in filter {
                    try? transport.write(packet)
                }
            }
        }
        // Close must run on this call stack (not a detached queue) so quit cannot exit
        // with the VCOM session still open and the Pro LED still ticking.
        transport.close()
        if wasRunning {
            PrismLog.notice(.outputLocalDMX, "output.localDMX.stopped", "Local DMX is off.")
        }
    }

    public func send(universe: UInt16, dmx: UnsafeBufferPointer<UInt8>) {
        lock.lock()
        guard _isRunning, _universeFilter.contains(universe) else {
            if _isRunning { _packetsDropped &+= 1 }
            lock.unlock()
            return
        }
        lock.unlock()

        let packet = ENTTECUSBDMXProProtocol.sendDMXPacket(dmx: dmx)
        // Re-check after building the packet: stop() may have raced us.
        lock.lock()
        let stillRunning = _isRunning
        lock.unlock()
        guard stillRunning else {
            lock.lock()
            _packetsDropped &+= 1
            lock.unlock()
            return
        }

        do {
            try transport.write(packet)
            lock.lock()
            // Drop success accounting if we were stopped mid-write.
            guard _isRunning else {
                lock.unlock()
                return
            }
            _packetsSent &+= 1
            _lastSuccessAt = Date()
            let recovered = _state == .degraded
            if recovered { _state = .ready }
            lock.unlock()
            if recovered {
                PrismLog.info(.outputLocalDMX, "output.localDMX.recovered", "Local DMX recovered.")
            }
            if PrismLog.isEnabled(.debug, category: .outputLocalDMX),
               let count = noteFrameSummary() {
                PrismLog.debug(
                    .outputLocalDMX,
                    "output.localDMX.frame_summary",
                    "Local DMX frame summary.",
                    metadata: [
                        "count": .count(count),
                        "sampled": .flag(true),
                    ]
                )
            }
        } catch {
            lock.lock()
            guard _isRunning else {
                lock.unlock()
                return
            }
            _lastError = PrismErrorReporting.userFacingMessage(for: error)
            _packetsDropped &+= 1
            _state = .degraded
            lock.unlock()
            PrismLog.error(
                .outputLocalDMX,
                "output.localDMX.failed",
                "Prism couldn't write to the USB DMX interface.",
                technical: String(reflecting: error),
                ratePolicy: .oncePerSecond
            )
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
            activeUniverses: Array(_universeFilter).sorted()
        )
    }
}
