import Foundation

/// Tunable MIDI Clock phase/tempo estimator (24 PPQN).
public struct ClockEstimatorConfig: Equatable, Sendable {
    public var lockPulseCount: Int
    public var stableIntervalTolerance: Double
    public var tempoEMAAlpha: Double
    /// Grace period after last pulse before entering freewheel (as multiple of expected interval).
    public var dropoutIntervalMultiplier: Double
    /// Duration **after** entering freewheel before lost (not including dropout grace).
    public var freewheelSeconds: Double
    /// Max seconds in acquiring without a valid interval before full reset (stray single pulse).
    public var acquisitionTimeoutSeconds: Double

    public init(
        lockPulseCount: Int = 12,
        stableIntervalTolerance: Double = 0.12,
        tempoEMAAlpha: Double = 0.15,
        dropoutIntervalMultiplier: Double = 3.0,
        freewheelSeconds: Double = 2.0,
        acquisitionTimeoutSeconds: Double = 1.0
    ) {
        self.lockPulseCount = max(3, lockPulseCount)
        self.stableIntervalTolerance = max(0.01, stableIntervalTolerance)
        self.tempoEMAAlpha = min(1, max(0.01, tempoEMAAlpha))
        self.dropoutIntervalMultiplier = max(1.5, dropoutIntervalMultiplier)
        self.freewheelSeconds = max(0.1, freewheelSeconds)
        self.acquisitionTimeoutSeconds = max(0.2, acquisitionTimeoutSeconds)
    }

    public static let `default` = ClockEstimatorConfig()
}

public enum ClockEstimatorSync: Equatable, Sendable {
    case unlocked
    case acquiring
    case locked
    case freewheeling
    case lost
}

/// Estimates tempo/phase from MIDI Clock pulses (24 PPQN).
public struct ClockEstimator: Equatable, Sendable {
    public var config: ClockEstimatorConfig
    public private(set) var sync: ClockEstimatorSync
    public private(set) var tempoBPM: Double?
    /// Last freewheel tempo (may be kept briefly after loss for diagnostics).
    public private(set) var lastKnownTempoBPM: Double?
    public private(set) var pulsesReceived: UInt64
    public private(set) var lastPulseHostTime: HostTime?
    public private(set) var consecutiveStable: Int
    public private(set) var quarterPhaseFromPulses: Double
    public private(set) var estimatedJitterMilliseconds: Double?

    private var pulseInQuarter: Int
    private var lastIntervalSeconds: Double?
    private var freewheelStart: HostTime?
    private var firstAcquisitionPulse: HostTime?
    private var intervalEMA: Double?

    public init(config: ClockEstimatorConfig = .default) {
        self.config = config
        self.sync = .unlocked
        self.tempoBPM = nil
        self.lastKnownTempoBPM = nil
        self.pulsesReceived = 0
        self.lastPulseHostTime = nil
        self.consecutiveStable = 0
        self.quarterPhaseFromPulses = 0
        self.estimatedJitterMilliseconds = nil
        self.pulseInQuarter = 0
        self.lastIntervalSeconds = nil
        self.freewheelStart = nil
        self.firstAcquisitionPulse = nil
        self.intervalEMA = nil
    }

    public static let quartersPerPulse: Double = 1.0 / 24.0

    // MARK: - Lifecycle

    /// Full reset when switching physical/logical sources (no A→B contamination).
    public mutating func resetForNewSource() {
        let cfg = config
        self = ClockEstimator(config: cfg)
    }

    /// On freewheel entry: clear lock evidence, keep last tempo for freewheel advance only.
    public mutating func beginFreewheelPreservingTempo() {
        consecutiveStable = 0
        lastIntervalSeconds = nil
        intervalEMA = nil
        if let t = tempoBPM { lastKnownTempoBPM = t }
        sync = .freewheeling
    }

    /// MIDI Start: phase origin at 0 within the quarter.
    public mutating func resetPhaseForStart() {
        pulseInQuarter = 0
        quarterPhaseFromPulses = 0
    }

    /// Align pulse phase to a canonical quarter-note position (e.g. after SPP).
    public mutating func alignPhase(to position: QuarterNotePosition) {
        let frac = position.quarters - floor(position.quarters)
        var idx = Int((frac * 24.0).rounded()) % 24
        if idx < 0 { idx += 24 }
        pulseInQuarter = idx
        quarterPhaseFromPulses = Double(pulseInQuarter) / 24.0
    }

    // MARK: - Pulse intake

    @discardableResult
    public mutating func receivePulse(at hostTime: HostTime) -> Bool {
        pulsesReceived &+= 1
        freewheelStart = nil

        if firstAcquisitionPulse == nil {
            firstAcquisitionPulse = hostTime
        }

        if let last = lastPulseHostTime, hostTime.nanoseconds > last.nanoseconds {
            let interval = Double(hostTime.nanoseconds - last.nanoseconds) / 1_000_000_000.0
            if interval > 0, interval.isFinite {
                let instantBPM = 60.0 / (interval * 24.0)
                if MusicalNumeric.isValidBPM(instantBPM) {
                    if let prev = lastIntervalSeconds, prev > 0 {
                        let rel = abs(interval - prev) / prev
                        if rel <= config.stableIntervalTolerance {
                            consecutiveStable += 1
                        } else {
                            consecutiveStable = 1
                        }
                        let jitterMs = abs(interval - prev) * 1000.0
                        if let j = estimatedJitterMilliseconds {
                            estimatedJitterMilliseconds = j * 0.8 + jitterMs * 0.2
                        } else {
                            estimatedJitterMilliseconds = jitterMs
                        }
                    } else {
                        consecutiveStable = 1
                    }
                    lastIntervalSeconds = interval
                    if let ema = intervalEMA {
                        intervalEMA = ema * (1 - config.tempoEMAAlpha) + interval * config.tempoEMAAlpha
                    } else {
                        intervalEMA = interval
                    }
                    if let existing = tempoBPM {
                        tempoBPM = existing * (1 - config.tempoEMAAlpha) + instantBPM * config.tempoEMAAlpha
                    } else {
                        tempoBPM = instantBPM
                    }
                    lastKnownTempoBPM = tempoBPM
                } else {
                    // Long gap / invalid return interval — do not keep pre-gap stability.
                    consecutiveStable = 0
                    lastIntervalSeconds = nil
                }
            }
        }

        lastPulseHostTime = hostTime
        pulseInQuarter = (pulseInQuarter + 1) % 24
        quarterPhaseFromPulses = Double(pulseInQuarter) / 24.0

        switch sync {
        case .unlocked, .lost, .freewheeling:
            sync = .acquiring
            if consecutiveStable >= config.lockPulseCount {
                sync = .locked
            }
        case .acquiring:
            if consecutiveStable >= config.lockPulseCount {
                sync = .locked
            }
        case .locked:
            break
        }
        return true
    }

    /// Update freewheel/lost / acquisition timeout without a pulse.
    public mutating func evaluateDropout(at hostTime: HostTime) {
        guard let last = lastPulseHostTime else { return }
        guard hostTime.nanoseconds >= last.nanoseconds else { return }
        let age = Double(hostTime.nanoseconds - last.nanoseconds) / 1_000_000_000.0

        // Acquisition timeout: single stray pulse never freezes forever.
        if sync == .acquiring || sync == .unlocked {
            if let first = firstAcquisitionPulse,
               hostTime.nanoseconds >= first.nanoseconds {
                let acqAge = Double(hostTime.nanoseconds - first.nanoseconds) / 1_000_000_000.0
                if acqAge >= config.acquisitionTimeoutSeconds, consecutiveStable < config.lockPulseCount {
                    // Soft reset acquisition history but keep no lock
                    consecutiveStable = 0
                    lastIntervalSeconds = nil
                    firstAcquisitionPulse = nil
                    lastPulseHostTime = nil
                    sync = .unlocked
                    return
                }
            }
        }

        let expectedInterval: Double
        if let bpm = tempoBPM ?? lastKnownTempoBPM, bpm > 0 {
            expectedInterval = 60.0 / (bpm * 24.0)
        } else if let li = lastIntervalSeconds {
            expectedInterval = li
        } else {
            // One pulse only: use acquisition timeout path above
            return
        }

        let dropoutAfter = expectedInterval * config.dropoutIntervalMultiplier
        if age >= dropoutAfter {
            if sync == .locked || sync == .acquiring {
                beginFreewheelPreservingTempo()
                // Freewheel window starts at the dropout threshold, not the evaluate call time.
                let startNs = last.nanoseconds + UInt64(min(Double(UInt64.max - last.nanoseconds), dropoutAfter * 1_000_000_000.0))
                freewheelStart = HostTime(nanoseconds: startNs)
            }
            if sync == .freewheeling {
                // Age since freewheel began ≈ time past dropout threshold.
                let freewheelAge = age - dropoutAfter
                if freewheelAge >= config.freewheelSeconds {
                    sync = .lost
                    consecutiveStable = 0
                    lastIntervalSeconds = nil
                }
            }
        }
    }

    /// Whether estimator is usable as active timing authority.
    public var isUsableAuthority: Bool {
        sync == .locked || sync == .freewheeling
    }
}
