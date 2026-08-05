import Foundation

/// Stateful MIDI byte stream parser (channel voice). Running status survives packet boundaries (P2-2).
public final class MIDIStreamParser: @unchecked Sendable {
    private let lock = NSLock()
    private var runningStatus: UInt8?

    public init() {}

    public func reset() {
        lock.lock()
        runningStatus = nil
        lock.unlock()
    }

    public func parse(bytes: [UInt8], sourceID: String) -> [MIDIEvent] {
        lock.lock()
        defer { lock.unlock() }
        var events: [MIDIEvent] = []
        var i = 0

        while i < bytes.count {
            var status = bytes[i]
            if status < 0x80 {
                guard let rs = runningStatus else {
                    i += 1
                    continue
                }
                status = rs
            } else {
                i += 1
                if status < 0xF0 {
                    runningStatus = status
                } else if status >= 0xF8 {
                    continue
                } else {
                    runningStatus = nil
                }
            }

            let type = status & 0xF0
            let channel = status & 0x0F

            switch type {
            case 0x80:
                guard i + 1 < bytes.count else { return events }
                let note = bytes[i]
                let vel = bytes[i + 1]
                i += 2
                events.append(.noteOff(channel: channel, note: note, velocity: vel, sourceID: sourceID))
            case 0x90:
                guard i + 1 < bytes.count else { return events }
                let note = bytes[i]
                let vel = bytes[i + 1]
                i += 2
                if vel == 0 {
                    events.append(.noteOff(channel: channel, note: note, velocity: 0, sourceID: sourceID))
                } else {
                    events.append(.noteOn(channel: channel, note: note, velocity: vel, sourceID: sourceID))
                }
            case 0xB0:
                guard i + 1 < bytes.count else { return events }
                let cc = bytes[i]
                let val = bytes[i + 1]
                i += 2
                events.append(.controlChange(channel: channel, controller: cc, value: val, sourceID: sourceID))
            case 0xC0:
                guard i < bytes.count else { return events }
                let prog = bytes[i]
                i += 1
                events.append(.programChange(channel: channel, program: prog, sourceID: sourceID))
            case 0xA0, 0xE0:
                i = min(i + 2, bytes.count)
            case 0xD0:
                i = min(i + 1, bytes.count)
            default:
                break
            }
        }
        return events
    }
}

/// Pure MIDI byte stream parser (channel voice only for PR16).
public enum MIDIMessageParser {
    /// Parses a flat list of MIDI bytes (running status supported within the buffer only).
    public static func parse(bytes: [UInt8], sourceID: String) -> [MIDIEvent] {
        MIDIStreamParser().parse(bytes: bytes, sourceID: sourceID)
    }
}
