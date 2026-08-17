import AuroraMusical
import Foundation

/// Stateful MIDI byte stream parser.
///
/// - System Real-Time bytes may interleave between data bytes; emitted immediately.
/// - System Common (SPP) is separate from System Real-Time.
/// - **Timestamp policy:** completed channel/common messages use the **HostTime of the packet
///   that supplied the final data byte** (completion time). Realtime status uses that packet's HostTime.
public final class MIDIStreamParser: @unchecked Sendable {
    private let lock = NSLock()
    private var runningStatus: UInt8?
    private var pendingStatus: UInt8?
    private var pendingData: [UInt8] = []
    private var pendingExpected: Int = 0
    private var pendingCommonStatus: UInt8?
    private var pendingCommonData: [UInt8] = []
    private var pendingCommonExpected: Int = 0

    public init() {}

    public func reset() {
        lock.lock()
        runningStatus = nil
        clearPendingChannel()
        clearPendingCommon()
        lock.unlock()
    }

    public func parseIngress(
        bytes: [UInt8],
        sourceID: String,
        hostTime: HostTime
    ) -> [MIDIIngressEvent] {
        lock.lock()
        defer { lock.unlock() }
        return parseIngressUnlocked(bytes: bytes, sourceID: sourceID, hostTime: hostTime)
    }

    /// Channel-voice only. Uses monotonic host time (never wall-clock).
    public func parse(bytes: [UInt8], sourceID: String, hostTime: HostTime = .now()) -> [MIDIEvent] {
        parseIngress(bytes: bytes, sourceID: sourceID, hostTime: hostTime).compactMap(\.channelVoiceEvent)
    }

    private func parseIngressUnlocked(
        bytes: [UInt8],
        sourceID: String,
        hostTime: HostTime
    ) -> [MIDIIngressEvent] {
        var events: [MIDIIngressEvent] = []
        var i = 0
        let ts = hostTime.legacyTimeInterval

        while i < bytes.count {
            let byte = bytes[i]

            if byte >= 0xF8 {
                if let rt = MIDISystemRealtimeEvent.from(statusByte: byte) {
                    events.append(.systemRealtime(rt, sourceID: sourceID, hostTime: hostTime))
                }
                i += 1
                continue
            }

            if let cStatus = pendingCommonStatus {
                if byte >= 0x80 {
                    clearPendingCommon()
                } else {
                    pendingCommonData.append(byte)
                    i += 1
                    if pendingCommonData.count >= pendingCommonExpected {
                        if let common = makeSystemCommon(status: cStatus, data: pendingCommonData) {
                            events.append(.systemCommon(common, sourceID: sourceID, hostTime: hostTime))
                        }
                        clearPendingCommon()
                    }
                    continue
                }
            }

            if let pStatus = pendingStatus {
                if byte >= 0x80 && byte < 0xF8 {
                    clearPendingChannel()
                } else {
                    pendingData.append(byte)
                    i += 1
                    if pendingData.count >= pendingExpected {
                        if let voice = makeChannelEvent(
                            status: pStatus,
                            data: pendingData,
                            sourceID: sourceID,
                            timestamp: ts
                        ) {
                            let normalized = MIDIEventNormalization.normalizeChannelVoice(voice)
                            events.append(.channelVoice(MIDIChannelVoiceEvent(event: normalized, hostTime: hostTime)))
                        }
                        clearPendingChannel()
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
            } else {
                i += 1
                if status < 0xF0 {
                    runningStatus = status
                } else {
                    runningStatus = nil
                    let expected = Self.systemCommonDataByteCount(for: status)
                    if expected < 0 { continue }
                    if expected == 0 {
                        if let common = makeSystemCommon(status: status, data: []) {
                            events.append(.systemCommon(common, sourceID: sourceID, hostTime: hostTime))
                        }
                        continue
                    }
                    var data: [UInt8] = []
                    while data.count < expected && i < bytes.count {
                        let b = bytes[i]
                        if b >= 0xF8 {
                            if let rt = MIDISystemRealtimeEvent.from(statusByte: b) {
                                events.append(.systemRealtime(rt, sourceID: sourceID, hostTime: hostTime))
                            }
                            i += 1
                            continue
                        }
                        if b >= 0x80 { break }
                        data.append(b)
                        i += 1
                    }
                    if data.count < expected {
                        pendingCommonStatus = status
                        pendingCommonData = data
                        pendingCommonExpected = expected
                        return events
                    }
                    if let common = makeSystemCommon(status: status, data: data) {
                        events.append(.systemCommon(common, sourceID: sourceID, hostTime: hostTime))
                    }
                    continue
                }
            }

            let expected = Self.channelDataByteCount(for: status)
            guard expected > 0 else { continue }

            var data: [UInt8] = []
            while data.count < expected && i < bytes.count {
                let b = bytes[i]
                if b >= 0xF8 {
                    if let rt = MIDISystemRealtimeEvent.from(statusByte: b) {
                        events.append(.systemRealtime(rt, sourceID: sourceID, hostTime: hostTime))
                    }
                    i += 1
                    continue
                }
                if b >= 0x80 { break }
                data.append(b)
                i += 1
            }

            if data.count < expected {
                pendingStatus = status
                pendingData = data
                pendingExpected = expected
                return events
            }

            if let voice = makeChannelEvent(status: status, data: data, sourceID: sourceID, timestamp: ts) {
                let normalized = MIDIEventNormalization.normalizeChannelVoice(voice)
                events.append(.channelVoice(MIDIChannelVoiceEvent(event: normalized, hostTime: hostTime)))
            }
        }
        return events
    }

    private func clearPendingChannel() {
        pendingStatus = nil
        pendingData = []
        pendingExpected = 0
    }

    private func clearPendingCommon() {
        pendingCommonStatus = nil
        pendingCommonData = []
        pendingCommonExpected = 0
    }

    private static func channelDataByteCount(for status: UInt8) -> Int {
        switch status & 0xF0 {
        case 0x80, 0x90, 0xA0, 0xB0, 0xE0: return 2
        case 0xC0, 0xD0: return 1
        default: return 0
        }
    }

    private static func systemCommonDataByteCount(for status: UInt8) -> Int {
        switch status {
        case 0xF1: return 1
        case 0xF2: return 2
        case 0xF3: return 1
        case 0xF6: return 0
        case 0xF0, 0xF7: return -1
        default: return -1
        }
    }

    private func makeSystemCommon(status: UInt8, data: [UInt8]) -> MIDISystemCommonEvent? {
        switch status {
        case 0xF1:
            guard data.count >= 1 else { return nil }
            return .mtcQuarterFrame(data: data[0])
        case 0xF2:
            guard data.count >= 2 else { return nil }
            let sixteenths = UInt16(data[0] & 0x7F) | (UInt16(data[1] & 0x7F) << 7)
            return .songPositionPointer(sixteenths: sixteenths)
        case 0xF3:
            guard data.count >= 1 else { return nil }
            return .songSelect(song: data[0] & 0x7F)
        case 0xF6:
            return .tuneRequest
        default:
            return nil
        }
    }

    private func makeChannelEvent(
        status: UInt8,
        data: [UInt8],
        sourceID: String,
        timestamp: TimeInterval
    ) -> MIDIEvent? {
        let type = status & 0xF0
        let channel = status & 0x0F
        switch type {
        case 0x80:
            guard data.count >= 2 else { return nil }
            return .noteOff(channel: channel, note: data[0], velocity: data[1], sourceID: sourceID, timestamp: timestamp)
        case 0x90:
            guard data.count >= 2 else { return nil }
            return .noteOn(channel: channel, note: data[0], velocity: data[1], sourceID: sourceID, timestamp: timestamp)
        case 0xA0:
            guard data.count >= 2 else { return nil }
            return .polyPressure(channel: channel, note: data[0], pressure: data[1], sourceID: sourceID, timestamp: timestamp)
        case 0xB0:
            guard data.count >= 2 else { return nil }
            return .controlChange(channel: channel, controller: data[0], value: data[1], sourceID: sourceID, timestamp: timestamp)
        case 0xC0:
            guard data.count >= 1 else { return nil }
            return .programChange(channel: channel, program: data[0], sourceID: sourceID, timestamp: timestamp)
        case 0xD0:
            guard data.count >= 1 else { return nil }
            return .channelPressure(channel: channel, pressure: data[0], sourceID: sourceID, timestamp: timestamp)
        case 0xE0:
            guard data.count >= 2 else { return nil }
            let value14 = UInt16(data[0]) | (UInt16(data[1]) << 7)
            return .pitchBend(channel: channel, value14: value14, sourceID: sourceID, timestamp: timestamp)
        default:
            return nil
        }
    }
}

public enum MIDIMessageParser {
    public static func parse(bytes: [UInt8], sourceID: String) -> [MIDIEvent] {
        MIDIStreamParser().parse(bytes: bytes, sourceID: sourceID)
    }

    public static func parseIngress(
        bytes: [UInt8],
        sourceID: String,
        hostTime: HostTime = .now()
    ) -> [MIDIIngressEvent] {
        MIDIStreamParser().parseIngress(bytes: bytes, sourceID: sourceID, hostTime: hostTime)
    }
}
