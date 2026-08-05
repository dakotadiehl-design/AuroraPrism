import CoreMIDI
import Foundation

/// Enumerates and connects CoreMIDI sources; delivers parsed `MIDIEvent`s.
public final class MIDIInputManager: @unchecked Sendable {
    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private let lock = NSLock()
    private var connected: [MIDIEndpointRef: String] = [:]
    private var _sources: [MIDIDeviceInfo] = []
    private var handler: (@Sendable ([MIDIEvent]) -> Void)?

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

    public func start() throws {
        let name = "AuroraMIDI" as CFString
        var status = MIDIClientCreateWithBlock(name, &client) { [weak self] notification in
            self?.handleNotification(notification)
        }
        guard status == noErr else {
            throw MIDIError.coreMIDI("MIDIClientCreate failed: \(status)")
        }

        status = MIDIInputPortCreateWithBlock(client, "AuroraInput" as CFString, &inputPort) { [weak self] packetList, _ in
            self?.handlePacketList(packetList)
        }
        guard status == noErr else {
            throw MIDIError.coreMIDI("MIDIInputPortCreate failed: \(status)")
        }

        refreshSources()
        try connectAllSources()
    }

    public func stop() {
        lock.lock()
        for (endpoint, _) in connected {
            MIDIPortDisconnectSource(inputPort, endpoint)
        }
        connected.removeAll()
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
            let id = String(endpoint)
            let name = stringProperty(endpoint, kMIDIPropertyName) ?? "Source \(i)"
            let mfg = stringProperty(endpoint, kMIDIPropertyManufacturer) ?? ""
            list.append(MIDIDeviceInfo(id: id, name: name, manufacturer: mfg))
        }
        lock.lock()
        _sources = list
        lock.unlock()
    }

    public func connectAllSources() throws {
        refreshSources()
        let count = MIDIGetNumberOfSources()
        for i in 0..<count {
            let endpoint = MIDIGetSource(i)
            lock.lock()
            let already = connected[endpoint] != nil
            lock.unlock()
            if already { continue }
            let status = MIDIPortConnectSource(inputPort, endpoint, nil)
            if status == noErr {
                lock.lock()
                connected[endpoint] = String(endpoint)
                lock.unlock()
            }
        }
    }

    private func handleNotification(_ notification: UnsafePointer<MIDINotification>) {
        let id = notification.pointee.messageID
        if id == .msgObjectAdded || id == .msgObjectRemoved || id == .msgSetupChanged {
            refreshSources()
            try? connectAllSources()
        }
    }

    private func handlePacketList(_ packetList: UnsafePointer<MIDIPacketList>) {
        var packet = packetList.pointee.packet
        var events: [MIDIEvent] = []
        for _ in 0..<packetList.pointee.numPackets {
            let length = Int(packet.length)
            var bytes: [UInt8] = []
            withUnsafeBytes(of: packet.data) { raw in
                let buf = raw.bindMemory(to: UInt8.self)
                bytes = Array(buf.prefix(length))
            }
            events.append(contentsOf: MIDIMessageParser.parse(bytes: bytes, sourceID: "coremidi"))
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
