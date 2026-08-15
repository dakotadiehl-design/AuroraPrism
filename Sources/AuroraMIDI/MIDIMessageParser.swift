import Foundation

/// Stateful MIDI byte stream parser (channel voice).
/// Preserves running status **and** incomplete message data across packet boundaries (UI-GATE-5 / P2-2).
/// Realtime system messages (0xF8–0xFF) may interleave without destroying a pending channel message.
public final class MIDIStreamParser: @unchecked Sendable {
    private let lock = NSLock()
    private var runningStatus: UInt8?
    /// Pending incomplete channel message (status already resolved).
    private var pendingStatus: UInt8?
    private var pendingData: [UInt8] = []
    private var pendingExpected: Int = 0

    public init() {}

    public func reset() {
        lock.lock()
        runningStatus = nil
        pendingStatus = nil
        pendingData = []
        pendingExpected = 0
        lock.unlock()
    }

    public func parse(bytes: [UInt8], sourceID: String) -> [MIDIEvent] {
        lock.lock()
        defer { lock.unlock() }
        var events: [MIDIEvent] = []
        var i = 0

        while i < bytes.count {
            let byte = bytes[i]

            // Realtime system messages interleave without affecting pending channel state.
            if byte >= 0xF8 {
                i += 1
                continue
            }

            // Continue incomplete message first.
            if let pStatus = pendingStatus {
                if byte >= 0x80 && byte < 0xF8 {
                    // New status aborts the incomplete message.
                    clearPending()
                    // Fall through to process this status as a new message (do not advance yet).
                } else {
                    pendingData.append(byte)
                    i += 1
                    if pendingData.count >= pendingExpected {
                        if let event = makeEvent(
                            status: pStatus,
                            data: pendingData,
                            sourceID: sourceID
                        ) {
                            events.append(event)
                        }
                        clearPending()
                    }
                    continue
                }
            }

            var status = bytes[i]
            if status < 0x80 {
                guard let rs = runningStatus else {
                    i += 1
                    continue
                }
                status = rs
                // Data byte is consumed as first data of running-status message.
            } else {
                i += 1
                if status < 0xF0 {
                    runningStatus = status
                } else {
                    // System common (0xF0–0xF7, non-realtime): clear running status.
                    runningStatus = nil
                    // Skip unsupported system common for now.
                    continue
                }
            }

            let expected = Self.dataByteCount(for: status)
            guard expected > 0 else { continue }

            var data: [UInt8] = []
            // If we used running status, current index still points at first data byte.
            // If we just consumed a status byte, index is past status.
            while data.count < expected && i < bytes.count {
                let b = bytes[i]
                if b >= 0xF8 {
                    // Realtime interleaved inside data collection
                    i += 1
                    continue
                }
                if b >= 0x80 {
                    // Nested status before data complete — start over with new status.
                    break
                }
                data.append(b)
                i += 1
            }

            if data.count < expected {
                // Incomplete: preserve for next packet.
                pendingStatus = status
                pendingData = data
                pendingExpected = expected
                return events
            }

            if let event = makeEvent(status: status, data: data, sourceID: sourceID) {
                events.append(event)
            }
        }
        return events
    }

    private func clearPending() {
        pendingStatus = nil
        pendingData = []
        pendingExpected = 0
    }

    private static func dataByteCount(for status: UInt8) -> Int {
        switch status & 0xF0 {
        case 0x80, 0x90, 0xA0, 0xB0, 0xE0:
            return 2
        case 0xC0, 0xD0:
            return 1
        default:
            return 0
        }
    }

    private func makeEvent(status: UInt8, data: [UInt8], sourceID: String) -> MIDIEvent? {
        let type = status & 0xF0
        let channel = status & 0x0F
        let ts = Date().timeIntervalSince1970
        switch type {
        case 0x80:
            guard data.count >= 2 else { return nil }
            return .noteOff(channel: channel, note: data[0], velocity: data[1], sourceID: sourceID, timestamp: ts)
        case 0x90:
            guard data.count >= 2 else { return nil }
            let note = data[0]
            let vel = data[1]
            if vel == 0 {
                return .noteOff(channel: channel, note: note, velocity: 0, sourceID: sourceID, timestamp: ts)
            }
            return .noteOn(channel: channel, note: note, velocity: vel, sourceID: sourceID, timestamp: ts)
        case 0xA0:
            guard data.count >= 2 else { return nil }
            return .polyPressure(channel: channel, note: data[0], pressure: data[1], sourceID: sourceID, timestamp: ts)
        case 0xB0:
            guard data.count >= 2 else { return nil }
            return .controlChange(channel: channel, controller: data[0], value: data[1], sourceID: sourceID, timestamp: ts)
        case 0xC0:
            guard data.count >= 1 else { return nil }
            return .programChange(channel: channel, program: data[0], sourceID: sourceID, timestamp: ts)
        case 0xD0:
            guard data.count >= 1 else { return nil }
            return .channelPressure(channel: channel, pressure: data[0], sourceID: sourceID, timestamp: ts)
        case 0xE0:
            guard data.count >= 2 else { return nil }
            let value14 = UInt16(data[0]) | (UInt16(data[1]) << 7)
            return .pitchBend(channel: channel, value14: value14, sourceID: sourceID, timestamp: ts)
        default:
            return nil
        }
    }
}

/// Pure MIDI byte stream parser (channel voice only for PR16).
public enum MIDIMessageParser {
    /// Parses a flat list of MIDI bytes (running status supported within the buffer only).
    public static func parse(bytes: [UInt8], sourceID: String) -> [MIDIEvent] {
        MIDIStreamParser().parse(bytes: bytes, sourceID: sourceID)
    }
}
