import AuroraModel
import CoreMIDI
import Foundation

/// Outbound CoreMIDI channel voice messages (P0-J feedback baseline).
///
/// **Teardown contract:** `MIDIClientDispose` never runs while `lock` is held.
/// Notification-driven `reconcileDestinations` no-ops once shutdown begins, so a
/// pending setup-changed callback cannot deadlock against `stop()`.
public final class MIDIOutputManager: @unchecked Sendable {
    private var client = MIDIClientRef()
    private var outputPort = MIDIPortRef()
    private let lock = NSLock()
    /// Set under lock before CoreMIDI dispose; reconcile/send must no-op when true.
    private var isStopping = false
    private var destinations: [MIDIEndpointRef: String] = [:]
    private var destinationByID: [String: MIDIEndpointRef] = [:]
    private var diagnostics: ((String) -> Void)?
    /// Source IDs that recently sent input — used for feedback loop prevention.
    private var recentInputSources: [String: TimeInterval] = [:]
    private var idStorage: [String: NSString] = [:]

    public init() {}

    public func setDiagnosticsLogger(_ logger: @escaping (String) -> Void) {
        lock.lock()
        diagnostics = logger
        lock.unlock()
    }

    public func noteInputFrom(sourceID: String, now: TimeInterval = Date().timeIntervalSince1970) {
        lock.lock()
        recentInputSources[sourceID] = now
        // prune
        recentInputSources = recentInputSources.filter { now - $0.value < 0.05 }
        lock.unlock()
    }

    public func start() throws {
        lock.lock()
        isStopping = false
        let started = client != 0 && outputPort != 0
        lock.unlock()
        if started {
            try reconcileDestinations()
            return
        }
        let name = "AuroraMIDIOut" as CFString
        var status = MIDIClientCreateWithBlock(name, &client) { [weak self] _ in
            try? self?.reconcileDestinations()
        }
        guard status == noErr else {
            client = 0
            throw MIDIError.coreMIDI("MIDI out client failed: \(status)")
        }
        status = MIDIOutputPortCreate(client, "AuroraOutput" as CFString, &outputPort)
        guard status == noErr else {
            let doomed = client
            client = 0
            outputPort = 0
            if doomed != 0 {
                MIDIClientDispose(doomed)
            }
            throw MIDIError.coreMIDI("MIDI out port failed: \(status)")
        }
        try reconcileDestinations()
    }

    public func stop() {
        // Snapshot/clear under lock only. Dispose outside — CoreMIDI may invoke the
        // client notification block while disposing, and that block calls reconcile.
        lock.lock()
        isStopping = true
        destinations.removeAll()
        destinationByID.removeAll()
        recentInputSources.removeAll()
        let clientRef = client
        outputPort = 0
        client = 0
        lock.unlock()

        if clientRef != 0 {
            MIDIClientDispose(clientRef)
        }

        lock.lock()
        idStorage.removeAll()
        lock.unlock()
    }

    public func reconcileDestinations() throws {
        lock.lock()
        if isStopping || client == 0 {
            lock.unlock()
            return
        }
        destinations.removeAll()
        destinationByID.removeAll()
        let count = MIDIGetNumberOfDestinations()
        for i in 0..<count {
            let dest = MIDIGetDestination(i)
            guard dest != 0 else { continue }
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(dest, kMIDIPropertyDisplayName, &name)
            let label = name?.takeRetainedValue() as String? ?? "Dest \(i)"
            let id = "dest:\(i):\(label)"
            destinations[dest] = id
            destinationByID[id] = dest
            idStorage[id] = id as NSString
        }
        let diag = diagnostics
        let destCount = destinations.count
        lock.unlock()
        diag?("MIDI destinations: \(destCount)")
    }

    public var destinationIDs: [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(destinationByID.keys).sorted()
    }

    public func sendNoteOn(channel: UInt8, note: UInt8, velocity: UInt8, deviceID: String? = nil) {
        send(status: 0x90 | (channel & 0x0F), d1: note & 0x7F, d2: velocity & 0x7F, deviceID: deviceID)
    }

    public func sendNoteOff(channel: UInt8, note: UInt8, velocity: UInt8 = 0, deviceID: String? = nil) {
        send(status: 0x80 | (channel & 0x0F), d1: note & 0x7F, d2: velocity & 0x7F, deviceID: deviceID)
    }

    public func sendCC(channel: UInt8, controller: UInt8, value: UInt8, deviceID: String? = nil) {
        send(status: 0xB0 | (channel & 0x0F), d1: controller & 0x7F, d2: value & 0x7F, deviceID: deviceID)
    }

    /// Apply feedback profiles from global show state (master / blackout / GO pulse).
    public func applyFeedback(
        profiles: [MIDIFeedbackProfile],
        masterIntensity: Double,
        blackout: Bool,
        goPulse: Bool = false
    ) {
        for profile in profiles where profile.enabled {
            if profile.preventFeedbackLoop, let did = profile.deviceID {
                lock.lock()
                let recent = recentInputSources[did] != nil
                lock.unlock()
                if recent { continue }
            }
            let ch = profile.channel
            if let cc = profile.masterIntensityCC {
                let v = UInt8(min(127, max(0, Int((masterIntensity * 127).rounded()))))
                sendCC(channel: ch, controller: cc, value: v, deviceID: profile.deviceID)
            }
            if let note = profile.blackoutNote {
                if blackout {
                    sendNoteOn(channel: ch, note: note, velocity: 127, deviceID: profile.deviceID)
                } else {
                    sendNoteOff(channel: ch, note: note, deviceID: profile.deviceID)
                }
            }
            if goPulse, let note = profile.goNote {
                sendNoteOn(channel: ch, note: note, velocity: 100, deviceID: profile.deviceID)
                sendNoteOff(channel: ch, note: note, deviceID: profile.deviceID)
            }
        }
    }

    private func send(status: UInt8, d1: UInt8, d2: UInt8, deviceID: String?) {
        lock.lock()
        if isStopping {
            lock.unlock()
            return
        }
        let port = outputPort
        let targets: [MIDIEndpointRef]
        if let deviceID, let ep = destinationByID[deviceID] {
            targets = [ep]
        } else if deviceID == nil {
            targets = Array(destinations.keys)
        } else {
            targets = []
        }
        lock.unlock()
        guard port != 0, !targets.isEmpty else { return }

        var packet = MIDIPacket()
        packet.timeStamp = 0
        packet.length = 3
        packet.data.0 = status
        packet.data.1 = d1
        packet.data.2 = d2
        var packetList = MIDIPacketList(numPackets: 1, packet: packet)
        for dest in targets {
            _ = MIDISend(port, dest, &packetList)
        }
    }
}

/// Pure encode helpers for tests (no CoreMIDI).
public enum MIDIMessageEncoder {
    public static func noteOn(channel: UInt8, note: UInt8, velocity: UInt8) -> [UInt8] {
        [0x90 | (channel & 0x0F), note & 0x7F, velocity & 0x7F]
    }
    public static func controlChange(channel: UInt8, controller: UInt8, value: UInt8) -> [UInt8] {
        [0xB0 | (channel & 0x0F), controller & 0x7F, value & 0x7F]
    }
}
