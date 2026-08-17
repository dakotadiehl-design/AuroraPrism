import Foundation

/// Continuous timing source interface.
///
/// **Tap tempo is not a TimingProvider** — it is an estimator that updates internal BPM.
public protocol TimingProvider: AnyObject, Sendable {
    var id: String { get }
    var displayName: String { get }
    var capabilities: TimingSourceCapabilities { get }
    func start()
    func stop()
}

/// Sink for continuous providers and MIDI timing adapters.
///
/// Every event identifies **which source** produced it so the Musical Engine retains
/// source-selection authority (selected vs active vs unselected).
public protocol MusicalTimingSink: AnyObject, Sendable {
    func receiveClockPulse(from sourceID: String, at hostTime: HostTime)
    func receiveTransportStart(from sourceID: String, at hostTime: HostTime)
    func receiveTransportStop(from sourceID: String, at hostTime: HostTime)
    func receiveTransportContinue(from sourceID: String, at hostTime: HostTime)
    func receiveSongPosition(_ position: QuarterNotePosition, from sourceID: String, at hostTime: HostTime)
}

public struct TapTempoEstimator: Equatable, Sendable {
    public var maxIntervals: Int
    public private(set) var tapTimes: [TimeInterval]

    public init(maxIntervals: Int = 8) {
        self.maxIntervals = max(2, maxIntervals)
        self.tapTimes = []
    }

    @discardableResult
    public mutating func tap(at time: TimeInterval) -> Double? {
        tapTimes.append(time)
        if tapTimes.count > maxIntervals + 1 {
            tapTimes.removeFirst(tapTimes.count - (maxIntervals + 1))
        }
        return estimatedBPM
    }

    public mutating func reset() {
        tapTimes.removeAll()
    }

    public var estimatedBPM: Double? {
        guard tapTimes.count >= 2 else { return nil }
        var intervals: [TimeInterval] = []
        for i in 1..<tapTimes.count {
            let dt = tapTimes[i] - tapTimes[i - 1]
            if dt > 0.05 && dt < 2.5 {
                intervals.append(dt)
            }
        }
        guard !intervals.isEmpty else { return nil }
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        guard mean > 0 else { return nil }
        let bpm = 60.0 / mean
        return MusicalNumeric.isValidBPM(bpm) ? bpm : nil
    }
}

public struct InternalTimingSourceInfo: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let capabilities: TimingSourceCapabilities

    public init(
        id: String = MusicalEngine.internalSourceID,
        displayName: String = "Internal Tempo",
        capabilities: TimingSourceCapabilities = .internalSource
    ) {
        self.id = id
        self.displayName = displayName
        self.capabilities = capabilities
    }
}
