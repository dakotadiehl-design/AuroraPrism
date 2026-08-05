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
        precondition(address >= 1)
        let index = Int(address) - 1
        guard index < channels.count else { return }
        channels[index] = value
    }

    public mutating func setLevels(_ values: [UInt8]) {
        let count = min(values.count, channels.count)
        for i in 0..<count {
            channels[i] = values[i]
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
