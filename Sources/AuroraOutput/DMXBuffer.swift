import Foundation

/// One universe's DMX channel values (default 512).
public struct DMXBuffer: Equatable, Sendable {
    public private(set) var channels: [UInt8]

    public var channelCount: Int { channels.count }

    public init(channelCount: Int = 512, filledWith value: UInt8 = 0) {
        precondition(channelCount > 0)
        self.channels = Array(repeating: value, count: channelCount)
    }

    public subscript(channel: Int) -> UInt8 {
        get {
            precondition(channel >= 0 && channel < channels.count)
            return channels[channel]
        }
        set {
            precondition(channel >= 0 && channel < channels.count)
            channels[channel] = newValue
        }
    }

    /// 1-based DMX address write.
    public mutating func setDMX(address: UInt16, value: UInt8) {
        guard address >= 1 else { return }
        let index = Int(address) - 1
        guard index < channels.count else { return }
        channels[index] = value
    }

    /// Copy levels; **clear unused tail** so short frames never leave stale data (P2-7).
    public mutating func setLevels(_ values: [UInt8]) {
        let count = min(values.count, channels.count)
        if count > 0 {
            channels.replaceSubrange(0..<count, with: values[0..<count])
        }
        if count < channels.count {
            for i in count..<channels.count {
                channels[i] = 0
            }
        }
    }

    /// Resize buffer; new slots zero-filled, existing prefix preserved when shrinking/growing.
    public mutating func resize(to newCount: Int) {
        guard newCount > 0 else { return }
        if newCount == channels.count { return }
        if newCount < channels.count {
            channels = Array(channels.prefix(newCount))
        } else {
            channels.append(contentsOf: Array(repeating: 0, count: newCount - channels.count))
        }
    }

    public mutating func blackout() {
        for i in channels.indices {
            channels[i] = 0
        }
    }

    public func withUnsafeBufferPointer<R>(_ body: (UnsafeBufferPointer<UInt8>) throws -> R) rethrows -> R {
        try channels.withUnsafeBufferPointer(body)
    }
}
