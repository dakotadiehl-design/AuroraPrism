import Foundation

/// Owns per-universe DMX buffers and fans frames out to registered drivers.
public final class OutputManager: @unchecked Sendable {
    private var buffers: [UInt16: DMXBuffer] = [:]
    private var drivers: [UUID: OutputDriver] = [:]
    private let lock = NSLock()
    private let defaultChannelCount: Int

    public init(defaultChannelCount: Int = 512) {
        self.defaultChannelCount = defaultChannelCount
    }

    public func register(_ driver: OutputDriver) {
        lock.lock()
        drivers[driver.id] = driver
        lock.unlock()
    }

    public func unregister(id: UUID) {
        lock.lock()
        drivers[id] = nil
        lock.unlock()
    }

    public func startAll() throws {
        lock.lock()
        let list = Array(drivers.values)
        lock.unlock()
        for driver in list where !driver.isRunning {
            try driver.start()
        }
    }

    public func stopAll() {
        lock.lock()
        let list = Array(drivers.values)
        lock.unlock()
        for driver in list where driver.isRunning {
            driver.stop()
        }
    }

    public func ensureUniverse(_ number: UInt16, channelCount: Int? = nil) {
        lock.lock()
        if buffers[number] == nil {
            buffers[number] = DMXBuffer(channelCount: channelCount ?? defaultChannelCount)
        }
        lock.unlock()
    }

    public func setLevels(universe: UInt16, values: [UInt8]) {
        lock.lock()
        if buffers[universe] == nil {
            buffers[universe] = DMXBuffer(channelCount: defaultChannelCount)
        }
        buffers[universe]?.setLevels(values)
        lock.unlock()
    }

    public func setChannel(universe: UInt16, address: UInt16, value: UInt8) {
        lock.lock()
        if buffers[universe] == nil {
            buffers[universe] = DMXBuffer(channelCount: defaultChannelCount)
        }
        buffers[universe]?.setDMX(address: address, value: value)
        lock.unlock()
    }

    public func blackout(universe: UInt16) {
        lock.lock()
        buffers[universe]?.blackout()
        lock.unlock()
    }

    public func snapshot(universe: UInt16) -> [UInt8]? {
        lock.lock()
        defer { lock.unlock() }
        return buffers[universe]?.channels
    }

    public func flush(universe: UInt16) {
        lock.lock()
        guard let buffer = buffers[universe] else {
            lock.unlock()
            return
        }
        let channels = buffer.channels
        let activeDrivers = drivers.values.filter(\.isRunning)
        lock.unlock()

        channels.withUnsafeBufferPointer { ptr in
            for driver in activeDrivers {
                driver.send(universe: universe, dmx: ptr)
            }
        }
    }

    public func flushAll() {
        lock.lock()
        let numbers = Array(buffers.keys)
        lock.unlock()
        for number in numbers {
            flush(universe: number)
        }
    }
}
