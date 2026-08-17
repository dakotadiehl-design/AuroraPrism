import AuroraModel
import AuroraMusical
import CoreMIDI
import Foundation

/// Source connect/disconnect events for held-state and health consumers.
public enum MIDISourceLifecycleEvent: Equatable, Sendable {
    case connected(sourceID: String)
    case disconnected(sourceID: String)
}

/// Enumerates and connects CoreMIDI sources; delivers parsed `MIDIEvent`s with stable source IDs.
/// Hotplug reconciles inventory: removed endpoints disconnect, new ones connect (P2-1).
///
/// Packet timestamps are converted to monotonic `HostTime` (never wall-clock).
///
/// **Teardown contract:** CoreMIDI disconnect/dispose never runs while `lock` is held.
/// Callbacks observe `isStopping` and return immediately. Source-ID retainers outlive the
/// input port so in-flight packet callbacks cannot UAF `passUnretained` refCons.
public final class MIDIInputManager: @unchecked Sendable {
    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private let lock = NSLock()
    /// Set under lock before any CoreMIDI teardown; callbacks/reconcile must no-op when true.
    private var isStopping = false
    private var connected: [MIDIEndpointRef: String] = [:]
    private var _sources: [MIDIDeviceInfo] = []
    private var handler: (@Sendable ([MIDIEvent]) -> Void)?
    /// Full ingress (channel voice + system realtime + system common) for Musical Engine / AME.
    private var ingressHandler: (@Sendable ([MIDIIngressEvent]) -> Void)?
    /// ST-01: notified after hotplug inventory reconcile (source count may change without MIDI traffic).
    private var inventoryHandler: (@Sendable (Int) -> Void)?
    /// Lifecycle: individual source connect/disconnect (Wave 4 / P0-11).
    private var sourceLifecycleHandler: (@Sendable (MIDISourceLifecycleEvent) -> Void)?
    /// Keeps source ID strings alive for CoreMIDI refCon pointers (keyed by endpoint, not ID string,
    /// so colliding UIDs cannot overwrite another connection's retainer).
    private var sourceIDRetainers: [MIDIEndpointRef: NSString] = [:]
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

    /// Optional full-ingress observer (timing + performance). Channel-voice still emitted via `setHandler`.
    public func setIngressHandler(_ handler: @escaping @Sendable ([MIDIIngressEvent]) -> Void) {
        lock.lock()
        self.ingressHandler = handler
        lock.unlock()
    }

    /// Called after `reconcileSources` with the current connected source count (ST-01 hotplug).
    public func setInventoryChangeHandler(_ handler: @escaping @Sendable (Int) -> Void) {
        lock.lock()
        self.inventoryHandler = handler
        lock.unlock()
    }

    /// Per-source connect/disconnect (for AME held-state release on unplug).
    public func setSourceLifecycleHandler(_ handler: @escaping @Sendable (MIDISourceLifecycleEvent) -> Void) {
        lock.lock()
        self.sourceLifecycleHandler = handler
        lock.unlock()
    }

    public func setDiagnosticsLogger(_ logger: @escaping (String) -> Void) {
        lock.lock()
        diagnostics = logger
        lock.unlock()
    }

    public func start() throws {
        lock.lock()
        isStopping = false
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
        // Snapshot under lock only. Never call CoreMIDI disconnect/dispose while holding
        // `lock` — those APIs can wait for an active input callback, and the callback
        // needs the same lock (classic hardware-dependent deadlock on quit).
        lock.lock()
        isStopping = true
        let snapshot = connected
        let life = sourceLifecycleHandler
        let port = inputPort
        let clientRef = client
        let endpoints = Array(connected.keys)
        connected.removeAll()
        streamParsers.removeAll()
        // Retainers stay alive until after port/client dispose so in-flight callbacks
        // that still hold passUnretained refCons cannot UAF.
        inputPort = 0
        client = 0
        lock.unlock()

        if port != 0 {
            for endpoint in endpoints {
                MIDIPortDisconnectSource(port, endpoint)
            }
            MIDIPortDispose(port)
        }
        if clientRef != 0 {
            MIDIClientDispose(clientRef)
        }

        lock.lock()
        sourceIDRetainers.removeAll()
        lock.unlock()

        // Lifecycle outside the lock so host unwind cannot re-enter deadlocked.
        // Unique source IDs only once (duplicate canonical IDs would otherwise double-notify).
        var emitted = Set<String>()
        for (_, sourceID) in snapshot {
            guard emitted.insert(sourceID).inserted else { continue }
            life?(.disconnected(sourceID: sourceID))
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
        lock.lock()
        if isStopping {
            lock.unlock()
            return
        }
        let port = inputPort
        lock.unlock()
        guard port != 0 else { return }

        refreshSources()
        let count = MIDIGetNumberOfSources()
        var liveEndpoints = Set<MIDIEndpointRef>()
        for i in 0..<count {
            liveEndpoints.insert(MIDIGetSource(i))
        }

        lock.lock()
        if isStopping {
            lock.unlock()
            return
        }
        let previous = connected
        lock.unlock()

        // Disconnect removed (CoreMIDI outside lock).
        for (endpoint, sourceID) in previous where !liveEndpoints.contains(endpoint) {
            MIDIPortDisconnectSource(port, endpoint)
            lock.lock()
            if isStopping {
                lock.unlock()
                return
            }
            connected[endpoint] = nil
            sourceIDRetainers[endpoint] = nil
            streamParsers[sourceID] = nil
            let life = sourceLifecycleHandler
            lock.unlock()
            logDiag("MIDI source removed: \(sourceID)")
            life?(.disconnected(sourceID: sourceID))
        }

        // Connect new
        for endpoint in liveEndpoints {
            lock.lock()
            if isStopping {
                lock.unlock()
                return
            }
            let already = connected[endpoint] != nil
            lock.unlock()
            if already { continue }

            let sourceID = stableSourceID(endpoint)
            let retained = sourceID as NSString
            lock.lock()
            if isStopping {
                lock.unlock()
                return
            }
            sourceIDRetainers[endpoint] = retained
            streamParsers[sourceID] = MIDIStreamParser()
            lock.unlock()

            let refCon = Unmanaged.passUnretained(retained).toOpaque()
            let status = MIDIPortConnectSource(port, endpoint, refCon)
            if status == noErr {
                lock.lock()
                if isStopping {
                    lock.unlock()
                    return
                }
                connected[endpoint] = sourceID
                let life = sourceLifecycleHandler
                lock.unlock()
                logDiag("MIDI source connected: \(sourceID)")
                life?(.connected(sourceID: sourceID))
            } else {
                lock.lock()
                sourceIDRetainers[endpoint] = nil
                streamParsers[sourceID] = nil
                lock.unlock()
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
        // UID 0 is not a durable identity (can collide); fall back to endpoint ref.
        if status == noErr, unique != 0 {
            return MIDISourceIdentity.coreMIDIUniqueID(unique)
        }
        return MIDISourceIdentity.endpointRef(UInt32(endpoint))
    }

    private func stableSourceID(_ endpoint: MIDIEndpointRef) -> String {
        Self.stableSourceID(for: endpoint)
    }

    private func handleNotification(_ notification: UnsafePointer<MIDINotification>) {
        lock.lock()
        let stopping = isStopping
        lock.unlock()
        guard !stopping else { return }

        let id = notification.pointee.messageID
        if id == .msgObjectAdded || id == .msgObjectRemoved || id == .msgSetupChanged {
            try? reconcileSources()
        }
    }

    private func handlePacketList(
        _ packetList: UnsafePointer<MIDIPacketList>,
        srcConnRefCon: UnsafeMutableRawPointer?
    ) {
        lock.lock()
        if isStopping {
            lock.unlock()
            return
        }
        // Snapshot parser under the same lock pass so we do not process after stop clears maps.
        let sourceID: String
        if let srcConnRefCon {
            sourceID = Unmanaged<NSString>.fromOpaque(srcConnRefCon).takeUnretainedValue() as String
        } else {
            sourceID = "coremidi"
        }
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
        var ingressAll: [MIDIIngressEvent] = []
        for _ in 0..<packetList.pointee.numPackets {
            let length = Int(packet.length)
            var bytes: [UInt8] = []
            withUnsafeBytes(of: packet.data) { raw in
                let buf = raw.bindMemory(to: UInt8.self)
                bytes = Array(buf.prefix(length))
            }
            let hostTime = MIDIHostTime.fromCoreMIDI(packet.timeStamp)
            ingressAll.append(contentsOf: parser.parseIngress(
                bytes: bytes,
                sourceID: sourceID,
                hostTime: hostTime
            ))
            packet = MIDIPacketNext(&packet).pointee
        }
        emitIngress(ingressAll)
        let channelEvents = ingressAll.compactMap(\.channelVoiceEvent)
        emit(channelEvents)
    }

    private func emit(_ events: [MIDIEvent]) {
        guard !events.isEmpty else { return }
        lock.lock()
        if isStopping {
            lock.unlock()
            return
        }
        let h = handler
        lock.unlock()
        h?(events)
    }

    private func emitIngress(_ events: [MIDIIngressEvent]) {
        guard !events.isEmpty else { return }
        lock.lock()
        if isStopping {
            lock.unlock()
            return
        }
        let h = ingressHandler
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
