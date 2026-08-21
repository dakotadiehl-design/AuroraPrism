import AuroraModel
import AuroraMusical
import Foundation

public enum EffectClockTransport: String, Codable, Equatable, Sendable {
    case stopped
    case running
    case paused
}

public enum EffectClockQuality: String, Codable, Equatable, Sendable {
    case unavailable
    case acquiring
    case locked
    case degraded
}

/// Provider-neutral timing input. Providers own clocks; effects consume this
/// immutable snapshot and never query MIDI, AME, or the Musical Engine directly.
public struct EffectClockSnapshot: Equatable, Sendable {
    public var source: EffectClockSource
    public var sourceID: String
    public var monotonicTime: TimeInterval
    public var tempoBPM: Double?
    public var quarterNotePosition: Double?
    public var meter: EffectMusicalMeter?
    public var transport: EffectClockTransport
    public var quality: EffectClockQuality

    public init(
        source: EffectClockSource,
        sourceID: String,
        monotonicTime: TimeInterval,
        tempoBPM: Double? = nil,
        quarterNotePosition: Double? = nil,
        meter: EffectMusicalMeter? = nil,
        transport: EffectClockTransport = .running,
        quality: EffectClockQuality = .locked
    ) {
        self.source = source
        self.sourceID = sourceID
        self.monotonicTime = monotonicTime
        self.tempoBPM = tempoBPM
        self.quarterNotePosition = quarterNotePosition
        self.meter = meter
        self.transport = transport
        self.quality = quality
    }

    public init(musicalState: MusicalState, source: EffectClockSource, monotonicTime: TimeInterval) {
        let timing = musicalState.timing
        self.init(
            source: source,
            sourceID: timing.activeSourceID ?? source.rawValue,
            monotonicTime: monotonicTime,
            tempoBPM: timing.tempoBPM,
            quarterNotePosition: timing.quarterNotePosition?.quarters,
            meter: timing.meter.map {
                EffectMusicalMeter(numerator: $0.numerator, denominator: $0.denominator, beatGrouping: $0.beatGrouping)
            },
            transport: Self.transport(timing.transport),
            quality: Self.quality(timing.sourceHealth)
        )
    }

    public var isUsable: Bool {
        transport == .running && quality != .unavailable && tempoBPM.map { $0.isFinite && $0 > 0 } != false
    }

    private static func transport(_ value: MusicalTransport) -> EffectClockTransport {
        switch value {
        case .stopped: return .stopped
        case .running: return .running
        case .paused: return .paused
        }
    }

    private static func quality(_ value: TimingSourceHealth) -> EffectClockQuality {
        switch value {
        case .unavailable, .lost: return .unavailable
        case .acquiring: return .acquiring
        case .healthy: return .locked
        case .degraded: return .degraded
        }
    }
}

public struct CompiledEffectTiming: Equatable, Sendable {
    public let definition: EffectTimingDefinition

    public init(definition: EffectTimingDefinition) {
        self.definition = definition
    }
}

public enum EffectTimingCompiler {
    public static func compile(_ definition: EffectTimingDefinition) -> CompiledEffectTiming {
        CompiledEffectTiming(definition: definition)
    }
}

public enum EffectTimingStatus: String, Equatable, Sendable {
    case running
    case waitingForQuantization
    case holding
    case stopped
    case fallback
}

public struct EffectTimingSample: Equatable, Sendable {
    public let phase: Double
    public let status: EffectTimingStatus
    public let isActive: Bool
    public let sourceID: String
    public let meter: EffectMusicalMeter?

    public init(phase: Double, status: EffectTimingStatus, isActive: Bool? = nil, sourceID: String, meter: EffectMusicalMeter?) {
        self.phase = EffectTimingRuntime.fract(phase)
        self.status = status
        self.isActive = isActive ?? (status != .waitingForQuantization && status != .stopped)
        self.sourceID = sourceID
        self.meter = meter
    }
}

/// Per-effect state that turns provider snapshots into a continuous normalized
/// phase. All transition policy lives here, outside the semantic evaluator.
public struct EffectTimingRuntime: Sendable {
    private var sourceID: String?
    private var anchorProgress: Double?
    private var anchorPhase: Double = 0
    private var pendingBoundary: Double?
    private var pendingAnchorPhase: Double?
    private var lastSample: EffectTimingSample?
    private var lastGoodSnapshot: EffectClockSnapshot?
    private var lastMeter: EffectMusicalMeter?
    private var usingFallback = false

    public init() {}

    public mutating func reset() {
        self = EffectTimingRuntime()
    }

    /// Re-anchors edits without throwing away the last evaluated phase. Source
    /// changes are deliberately marked so the next sample executes the selected
    /// Preserve Phase / Re-Quantize / Restart policy.
    mutating func reconfigure(
        from previous: EffectTimingDefinition,
        to next: EffectTimingDefinition,
        clock: EffectClockSnapshot
    ) {
        if previous.source != next.source {
            sourceID = "definition-switch:\(previous.source.rawValue)"
            pendingBoundary = nil
            pendingAnchorPhase = nil
            return
        }
        if previous.phase != next.phase {
            anchorPhase = next.phase
            anchorProgress = progress(definition: next, clock: clock)
            pendingBoundary = nil
            pendingAnchorPhase = nil
            return
        }
        guard previous.rate != next.rate || previous.internalBPM != next.internalBPM else { return }
        anchorPhase = lastSample?.phase ?? next.phase
        anchorProgress = progress(definition: next, clock: clock)
        pendingBoundary = nil
        pendingAnchorPhase = nil
    }

    public mutating func sample(
        compiled: CompiledEffectTiming,
        clock: EffectClockSnapshot
    ) -> EffectTimingSample {
        let definition = compiled.definition
        if definition.source != .freeRun, definition.source != .internalBPM {
            if clock.transport == .paused {
                return remember(.init(phase: lastSample?.phase ?? definition.phase, status: .holding, sourceID: clock.sourceID, meter: clock.meter))
            }
            if clock.transport == .stopped, clock.quality != .unavailable {
                return remember(.init(phase: lastSample?.phase ?? definition.phase, status: .stopped, sourceID: clock.sourceID, meter: clock.meter))
            }
        }
        let effective = effectiveClock(definition: definition, clock: clock)
        guard let effective else {
            let phase = lastSample?.phase ?? definition.phase
            let status: EffectTimingStatus = definition.clockLossPolicy == .stop ? .stopped : .holding
            return remember(.init(phase: phase, status: status, sourceID: clock.sourceID, meter: clock.meter))
        }

        // Clock-loss fallback is continuity for the current provider, not a
        // user-requested provider switch. Only healthy provider identities
        // participate in source-switch policy.
        let transitionSourceID = clock.isUsable ? effective.sourceID : (sourceID ?? effective.sourceID)
        let recovered = usingFallback && clock.isUsable
        let switched = sourceID != nil && sourceID != transitionSourceID
        let isInitial = sourceID == nil
        if switched || recovered || isInitial {
            configureTransition(definition: definition, clock: effective, switched: switched || recovered)
            sourceID = transitionSourceID
        }

        if let previousMeter = lastMeter, let currentMeter = effective.meter,
           previousMeter != currentMeter, !switched, !recovered {
            anchorPhase = lastSample?.phase ?? definition.phase
            anchorProgress = progress(definition: definition, clock: effective)
        }

        if let boundary = pendingBoundary {
            guard let q = effective.quarterNotePosition, q + 1e-9 >= boundary else {
                return remember(.init(
                    phase: lastSample?.phase ?? definition.phase,
                    status: .waitingForQuantization,
                    sourceID: effective.sourceID,
                    meter: effective.meter
                ))
            }
            pendingBoundary = nil
            anchorProgress = progress(definition: definition, clock: effective)
            anchorPhase = pendingAnchorPhase ?? definition.phase
            pendingAnchorPhase = nil
        }

        guard let currentProgress = progress(definition: definition, clock: effective) else {
            return remember(.init(
                phase: lastSample?.phase ?? definition.phase,
                status: .holding,
                sourceID: effective.sourceID,
                meter: effective.meter
            ))
        }
        if anchorProgress == nil { anchorProgress = currentProgress }
        let phase = anchorPhase + currentProgress - (anchorProgress ?? currentProgress)
        if clock.isUsable { lastGoodSnapshot = clock }
        let status: EffectTimingStatus = effective.sourceID == clock.sourceID ? .running : .fallback
        usingFallback = status == .fallback
        lastMeter = effective.meter
        return remember(.init(phase: phase, status: status, sourceID: effective.sourceID, meter: effective.meter))
    }

    private mutating func configureTransition(
        definition: EffectTimingDefinition,
        clock: EffectClockSnapshot,
        switched: Bool
    ) {
        let policy = switched ? definition.sourceSwitchPolicy : .restart
        anchorPhase = policy == .preservePhase ? (lastSample?.phase ?? definition.phase) : definition.phase
        anchorProgress = progress(definition: definition, clock: clock)

        let shouldQuantize = policy == .requantize || (!switched && definition.startQuantization != .immediate)
        guard shouldQuantize, let q = clock.quarterNotePosition, let meter = clock.meter else { return }
        let quantization = policy == .requantize ? definition.startQuantization : definition.startQuantization
        pendingBoundary = nextBoundary(after: q, quantization: quantization == .immediate ? .nextBeat : quantization, meter: meter)
        pendingAnchorPhase = policy == .preservePhase ? (lastSample?.phase ?? definition.phase) : definition.phase
    }

    private mutating func effectiveClock(
        definition: EffectTimingDefinition,
        clock: EffectClockSnapshot
    ) -> EffectClockSnapshot? {
        if definition.source == .freeRun || definition.source == .internalBPM {
            return internalClock(definition: definition, clock: clock, sourceID: definition.source.rawValue)
        }
        guard !clock.isUsable else { return clock }
        switch definition.clockLossPolicy {
        case .holdPhase, .stop:
            return nil
        case .fallbackInternal:
            return internalClock(definition: definition, clock: clock, sourceID: "fallback.internal")
        case .continueLastTempo:
            guard let previous = lastGoodSnapshot, let tempo = previous.tempoBPM else { return nil }
            let elapsed = max(0, clock.monotonicTime - previous.monotonicTime)
            var continued = clock
            continued.sourceID = "\(previous.sourceID).continued"
            continued.tempoBPM = tempo
            continued.quarterNotePosition = (previous.quarterNotePosition ?? 0) + elapsed * tempo / 60
            continued.meter = previous.meter ?? clock.meter
            continued.transport = .running
            continued.quality = .degraded
            return continued
        }
    }

    private func internalClock(
        definition: EffectTimingDefinition,
        clock: EffectClockSnapshot,
        sourceID: String
    ) -> EffectClockSnapshot {
        var result = clock
        result.sourceID = sourceID
        result.tempoBPM = definition.internalBPM
        result.quarterNotePosition = clock.monotonicTime * definition.internalBPM / 60
        result.meter = result.meter ?? EffectMusicalMeter(numerator: 4, denominator: 4)
        result.transport = .running
        result.quality = .locked
        return result
    }

    private func progress(definition: EffectTimingDefinition, clock: EffectClockSnapshot) -> Double? {
        switch definition.rate {
        case let .frequencyHz(hz):
            return clock.monotonicTime * max(0, hz.isFinite ? hz : 0)
        case let .periodSeconds(seconds):
            return clock.monotonicTime / max(0.001, seconds.isFinite ? seconds : 1)
        case let .musical(duration):
            guard let q = clock.quarterNotePosition else { return nil }
            let count = duration.count * duration.modifier.durationMultiplier
            switch duration.unit {
            case .note:
                return q / (duration.noteDivision.quarterNotes * count)
            case .bar:
                guard let meter = clock.meter else { return nil }
                return q / (meter.barLengthInQuarterNotes * count)
            case .metricalBeat:
                guard let meter = clock.meter else { return nil }
                return metricalBeatPosition(q, meter: meter) / count
            }
        }
    }

    private func metricalBeatPosition(_ q: Double, meter: EffectMusicalMeter) -> Double {
        let barLength = meter.barLengthInQuarterNotes
        guard barLength > 0 else { return 0 }
        let bar = floor(max(0, q) / barLength)
        var intoBar = max(0, q) - bar * barLength
        var beat = 0.0
        for length in meter.metricalBeatLengthsInQuarterNotes {
            if intoBar < length { return bar * Double(meter.beatsPerBar) + beat + intoBar / length }
            intoBar -= length
            beat += 1
        }
        return (bar + 1) * Double(meter.beatsPerBar)
    }

    private func nextBoundary(
        after q: Double,
        quantization: EffectStartQuantization,
        meter: EffectMusicalMeter
    ) -> Double? {
        switch quantization {
        case .immediate: return nil
        case .nextBar:
            let length = meter.barLengthInQuarterNotes
            return (floor(q / length) + 1) * length
        case .nextBeat:
            let length = meter.barLengthInQuarterNotes
            let barStart = floor(max(0, q) / length) * length
            var cursor = barStart
            for beatLength in meter.metricalBeatLengthsInQuarterNotes {
                cursor += beatLength
                if cursor > q + 1e-9 { return cursor }
            }
            return barStart + length
        }
    }

    @discardableResult
    private mutating func remember(_ sample: EffectTimingSample) -> EffectTimingSample {
        lastSample = sample
        return sample
    }

    fileprivate static func fract(_ value: Double) -> Double {
        let result = value - floor(value)
        return result < 0 ? result + 1 : result
    }
}

/// Owns the small amount of per-effect transition state needed by FX-2. It
/// accepts provider snapshots once per frame and emits evaluator-ready samples.
public final class EffectTimingCoordinator: @unchecked Sendable {
    private struct Entry {
        var definition: EffectTimingDefinition
        var runtime: EffectTimingRuntime
    }

    private let lock = NSLock()
    private var runtimes: [UUID: Entry] = [:]
    private var activeIDs: [UUID] = []
    private var sampleBuffer: [UUID: EffectTimingSample] = [:]

    public init() {}

    public func samples(
        for effects: [CompiledPrismEffect],
        clocks: [EffectClockSource: EffectClockSnapshot],
        monotonicTime: TimeInterval,
        defaultMeter: EffectMusicalMeter = .init(numerator: 4, denominator: 4)
    ) -> [UUID: EffectTimingSample] {
        lock.lock()
        defer { lock.unlock() }
        let membershipChanged = effects.count != activeIDs.count
            || effects.enumerated().contains { index, effect in activeIDs[index] != effect.id }
        if membershipChanged {
            activeIDs = effects.map(\.id)
            let requestedIDs = Set(activeIDs)
            runtimes = runtimes.filter { requestedIDs.contains($0.key) }
        }
        sampleBuffer.removeAll(keepingCapacity: true)
        sampleBuffer.reserveCapacity(effects.count)
        for effect in effects {
            guard let timing = effect.timing else { continue }
            let source = timing.definition.source
            let clock = clocks[source] ?? EffectClockSnapshot(
                source: source,
                sourceID: source.rawValue,
                monotonicTime: monotonicTime,
                meter: defaultMeter,
                transport: .stopped,
                quality: .unavailable
            )
            let entry = runtimes[effect.id]
            var runtime = entry?.runtime ?? EffectTimingRuntime()
            if let previous = entry?.definition, previous != timing.definition {
                runtime.reconfigure(from: previous, to: timing.definition, clock: clock)
            }
            sampleBuffer[effect.id] = runtime.sample(compiled: timing, clock: clock)
            runtimes[effect.id] = Entry(definition: timing.definition, runtime: runtime)
        }
        return sampleBuffer
    }

    public func reset(effectID: UUID? = nil) {
        lock.lock()
        if let effectID {
            runtimes[effectID] = nil
            activeIDs.removeAll { $0 == effectID }
            sampleBuffer[effectID] = nil
        } else {
            runtimes.removeAll(keepingCapacity: true)
            activeIDs.removeAll(keepingCapacity: true)
            sampleBuffer.removeAll(keepingCapacity: true)
        }
        lock.unlock()
    }
}
