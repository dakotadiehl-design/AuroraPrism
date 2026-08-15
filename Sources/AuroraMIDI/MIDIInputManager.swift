import CoreMIDI
import Foundation

/// Enumerates and connects CoreMIDI sources; delivers parsed `MIDIEvent`s with stable source IDs.
/// Hotplug reconciles inventory: removed endpoints disconnect, new ones connect (P2-1).
public final class MIDIInputManager: @unchecked Sendable {
    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private let lock = NSLock()
    private var connected: [MIDIEndpointRef: String] = [:]
    private var _sources: [MIDIDeviceInfo] = []
    private var handler: (@Sendable ([MIDIEvent]) -> Void)?
    /// ST-01: notified after hotplug inventory reconcile (source count may change without MIDI traffic).
    private var inventoryHandler: (@Sendable (Int) -> Void)?
    /// Keeps source ID strings alive for CoreMIDI refCon pointers.
    private var sourceIDStorage: [String: NSString] = [:]
    /// Per-source stream parsers so running status survives packet boundaries (P2-2).
    private var streamParsers: [String: MIDIStreamParser] = [:]
    private var diagnostics: ((String) -> Void)?

    public init() {}

    public var sources: [MIDIDeviceInfo] {
        lock.lock()
        defer { lock.unlock() }
        return _sources
    }

    public var connectedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return connected.count
    }

    public func setHandler(_ handler: @escaping @Sendable ([MIDIEvent]) -> Void) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    /// Called after `reconcileSources` with the current connected source count (ST-01 hotplug).
    public func setInventoryChangeHandler(_ handler: @escaping @Sendable (Int) -> Void) {
        lock.lock()
        self.inventoryHandler = handler
        lock.unlock()
    }

    public func setDiagnosticsLogger(_ logger: @escaping (String) -> Void) {
        lock.lock()
        diagnostics = logger
        lock.unlock()
    }

    public func start() throws {
        lock.lock()
        let alreadyStarted = client != 0 && inputPort != 0
        lock.unlock()
        if alreadyStarted {
            try reconcileSources()
            return
        }

        let name = "AuroraMIDI" as CFString
        var status = MIDIClientCreateWithBlock(name, &client) { [weak self] notification in
            self?.handleNotification(notification)
        }
        guard status == noErr else {
            client = 0
            throw MIDIError.coreMIDI("MIDIClientCreate failed: \(status)")
        }

        status = MIDIInputPortCreateWithBlock(client, "AuroraInput" as CFString, &inputPort) { [weak self] packetList, srcConnRefCon in
            self?.handlePacketList(packetList, srcConnRefCon: srcConnRefCon)
        }
        guard status == noErr else {
            if client != 0 {
                MIDIClientDispose(client)
                client = 0
            }
            inputPort = 0
            throw MIDIError.coreMIDI("MIDIInputPortCreate failed: \(status)")
        }

        try reconcileSources()
    }

    public func stop() {
        lock.lock()
        for (endpoint, _) in connected {
            MIDIPortDisconnectSource(inputPort, endpoint)
        }
        connected.removeAll()
        sourceIDStorage.removeAll()
        streamParsers.removeAll()
        lock.unlock()
        if inputPort != 0 {
            MIDIPortDispose(inputPort)
            inputPort = 0
        }
        if client != 0 {
            MIDIClientDispose(client)
            client = 0
        }
    }

    public func refreshSources() {
        var list: [MIDIDeviceInfo] = []
        let count = MIDIGetNumberOfSources()
        for i in 0..<count {
            let endpoint = MIDIGetSource(i)
            let id = stableSourceID(endpoint)
            let name = stringProperty(endpoint, kMIDIPropertyName) ?? "Source \(i)"
            let mfg = stringProperty(endpoint, kMIDIPropertyManufacturer) ?? ""
            list.append(MIDIDeviceInfo(id: id, name: name, manufacturer: mfg))
        }
        lock.lock()
        _sources = list
        lock.unlock()
    }

    /// Full inventory reconcile (P2-1).
    public func reconcileSources() throws {
        refreshSources()
        let count = MIDIGetNumberOfSources()
        var liveEndpoints = Set<MIDIEndpointRef>()
        for i in 0..<count {
            liveEndpoints.insert(MIDIGetSource(i))
        }

        lock.lock()
        let previous = connected
        lock.unlock()

        // Disconnect removed
        for (endpoint, sourceID) in previous where !liveEndpoints.contains(endpoint) {
            MIDIPortDisconnectSource(inputPort, endpoint)
            lock.lock()
            connected[endpoint] = nil
            sourceIDStorage[sourceID] = nil
            streamParsers[sourceID] = nil
            lock.unlock()
            logDiag("MIDI source removed: \(sourceID)")
        }

        // Connect new
        for endpoint in liveEndpoints {
            lock.lock()
            let already = connected[endpoint] != nil
            lock.unlock()
            if already { continue }

            let sourceID = stableSourceID(endpoint)
            let retained = sourceID as NSString
            lock.lock()
            sourceIDStorage[sourceID] = retained
            streamParsers[sourceID] = MIDIStreamParser()
            lock.unlock()

            let refCon = Unmanaged.passUnretained(retained).toOpaque()
            let status = MIDIPortConnectSource(inputPort, endpoint, refCon)
            if status == noErr {
                lock.lock()
                connected[endpoint] = sourceID
                lock.unlock()
                logDiag("MIDI source connected: \(sourceID)")
            } else {
                logDiag("MIDI connect failed \(sourceID): \(status)")
            }
        }

        // ST-01: always notify inventory after reconcile so UI updates on hotplug without MIDI notes.
        notifyInventoryChanged()
    }

    private func notifyInventoryChanged() {
        lock.lock()
        let count = connected.count
        let handler = inventoryHandler
        lock.unlock()
        handler?(count)
    }

    public func connectAllSources() throws {
        try reconcileSources()
    }

    public static func stableSourceID(for endpoint: MIDIEndpointRef) -> String {
        var unique: Int32 = 0
        let status = MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &unique)
        if status == noErr {
            return "uid:\(unique)"
        }
        return "ep:\(endpoint)"
    }

    private func stableSourceID(_ endpoint: MIDIEndpointRef) -> String {
        Self.stableSourceID(for: endpoint)
    }

    private func handleNotification(_ notification: UnsafePointer<MIDINotification>) {
        let id = notification.pointee.messageID
        if id == .msgObjectAdded || id == .msgObjectRemoved || id == .msgSetupChanged {
            try? reconcileSources()
        }
    }

    private func handlePacketList(
        _ packetList: UnsafePointer<MIDIPacketList>,
        srcConnRefCon: UnsafeMutableRawPointer?
    ) {
        let sourceID: String
        if let srcConnRefCon {
            sourceID = Unmanaged<NSString>.fromOpaque(srcConnRefCon).takeUnretainedValue() as String
        } else {
            sourceID = "coremidi"
        }

        lock.lock()
        let parser: MIDIStreamParser
        if let existing = streamParsers[sourceID] {
            parser = existing
        } else {
            let created = MIDIStreamParser()
            streamParsers[sourceID] = created
            parser = created
        }
        lock.unlock()

        var packet = packetList.pointee.packet
        var events: [MIDIEvent] = []
        for _ in 0..<packetList.pointee.numPackets {
            let length = Int(packet.length)
            var bytes: [UInt8] = []
            withUnsafeBytes(of: packet.data) { raw in
                let buf = raw.bindMemory(to: UInt8.self)
                bytes = Array(buf.prefix(length))
            }
            events.append(contentsOf: parser.parse(bytes: bytes, sourceID: sourceID))
            packet = MIDIPacketNext(&packet).pointee
        }
        emit(events)
    }

    private func emit(_ events: [MIDIEvent]) {
        guard !events.isEmpty else { return }
        lock.lock()
        let h = handler
        lock.unlock()
        h?(events)
    }

    private func logDiag(_ message: String) {
        lock.lock()
        let d = diagnostics
        lock.unlock()
        d?(message)
    }

    private func stringProperty(_ object: MIDIObjectRef, _ property: CFString) -> String? {
        var unmanaged: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(object, property, &unmanaged)
        guard status == noErr, let value = unmanaged?.takeUnretainedValue() else { return nil }
        return value as String
    }
}

public enum MIDIError: Error, Equatable, Sendable {
    case coreMIDI(String)
}
