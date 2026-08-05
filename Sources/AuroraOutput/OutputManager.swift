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

    /// Starts all registered drivers. On failure, stops drivers started in this call (P2-8).
    public func startAll() throws {
        lock.lock()
        let list = Array(drivers.values)
        lock.unlock()
        var started: [OutputDriver] = []
        do {
            for driver in list where !driver.isRunning {
                try driver.start()
                started.append(driver)
            }
        } catch {
            for driver in started where driver.isRunning {
                driver.stop()
            }
            throw error
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

    /// Universe numbers currently buffered.
    public var activeUniverseNumbers: Set<UInt16> {
        lock.lock()
        defer { lock.unlock() }
        return Set(buffers.keys)
    }

    /// Blackout and remove a universe buffer (P0-5).
    public func removeUniverse(_ number: UInt16, blackout: Bool = true) {
        if blackout {
            lock.lock()
            let count = buffers[number]?.channels.count ?? defaultChannelCount
            lock.unlock()
            let zeros = [UInt8](repeating: 0, count: count)
            setLevels(universe: number, values: zeros)
            flush(universe: number)
        }
        lock.lock()
        buffers[number] = nil
        lock.unlock()
    }

    public func removeAllUniverses(blackout: Bool = true) {
        lock.lock()
        let numbers = Array(buffers.keys)
        lock.unlock()
        for n in numbers {
            removeUniverse(n, blackout: blackout)
        }
    }

    /// Keep only the given universe numbers; blackout+drop the rest (P0-5).
    public func reconcileUniverses(to numbers: Set<UInt16>, blackoutRemoved: Bool = true) {
        lock.lock()
        let existing = Set(buffers.keys)
        lock.unlock()
        for n in existing.subtracting(numbers) {
            removeUniverse(n, blackout: blackoutRemoved)
        }
        for n in numbers {
            ensureUniverse(n)
        }
    }
}
