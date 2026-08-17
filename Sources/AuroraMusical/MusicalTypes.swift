import Foundation
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Transport / sync

public enum MusicalTransport: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    case stopped
    case running
    case paused
}

public enum MusicalSyncState: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    case unlocked
    case acquiring
    case locked
    case freewheeling
    case lost
    case internalRunning
    case fallback
}

public enum TimingSourcePolicy: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    case internalOnly
    case externalMIDI
    case externalPreferredFallback
}

public enum TimingSourceHealth: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    case unavailable
    case acquiring
    case healthy
    case degraded
    case lost
}

public enum TimingFallbackState: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    case notApplicable
    case armed
    case freewheeling
    case pending
    case active
}

// MARK: - Host time (monotonic)

/// Monotonic host-time domain for timing math and MIDI ingress (never wall-clock).
public struct HostTime: Codable, Equatable, Sendable, Hashable, Comparable {
    public let nanoseconds: UInt64

    public init(nanoseconds: UInt64) {
        self.nanoseconds = nanoseconds
    }

    /// Seconds since an arbitrary monotonic origin (for APIs that still use TimeInterval).
    public var seconds: TimeInterval {
        TimeInterval(nanoseconds) / 1_000_000_000.0
    }

    public static func < (lhs: HostTime, rhs: HostTime) -> Bool {
        lhs.nanoseconds < rhs.nanoseconds
    }

    /// Current monotonic host time (mach absolute / continuous).
    public static func now() -> HostTime {
        #if canImport(Darwin)
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let ticks = mach_absolute_time()
        let nanos = ticks * UInt64(info.numer) / UInt64(info.denom)
        return HostTime(nanoseconds: nanos)
        #else
        // Aurora product is macOS-only; this branch is for non-Darwin compile probes only.
        return HostTime(nanoseconds: 0)
        #endif
    }
}

// MARK: - Meter / grid / clock domains

/// Supported meter denominators (powers of two).
public enum MusicalMeterDenominator: Int, Codable, Equatable, Sendable, Hashable, CaseIterable {
    case whole = 1
    case half = 2
    case quarter = 4
    case eighth = 8
    case sixteenth = 16
    case thirtySecond = 32
}

/// Canonical meter. **Beat lengths come only from `beatGrouping` + denominator** — never from a singular BeatUnit.
///
/// MIDI Clock does **not** supply meter — song/project metadata does.
/// Asymmetric meters (e.g. 7/8 as [2,2,3]) are first-class; there is no single BeatUnit that describes all beats.
public struct MusicalMeter: Equatable, Sendable, Hashable {
    public var numerator: Int
    public var denominator: Int
    /// Denominator-unit sizes of each metrical beat (e.g. 6/8 → `[3,3]`, 7/8 → `[2,2,3]`).
    /// Required, non-empty, each > 0, sum == numerator. This is the sole metrical-beat source of truth.
    public var beatGrouping: [Int]

    public enum ValidationError: Error, Equatable, Sendable {
        case invalidNumerator
        case unsupportedDenominator
        case invalidGrouping
        case groupingSumMismatch
    }

    public init(numerator: Int, denominator: Int, beatGrouping: [Int]) throws {
        guard numerator >= 1 else { throw ValidationError.invalidNumerator }
        guard MusicalMeterDenominator(rawValue: denominator) != nil else {
            throw ValidationError.unsupportedDenominator
        }
        guard !beatGrouping.isEmpty, beatGrouping.allSatisfy({ $0 > 0 }) else {
            throw ValidationError.invalidGrouping
        }
        guard beatGrouping.reduce(0, +) == numerator else {
            throw ValidationError.groupingSumMismatch
        }
        self.numerator = numerator
        self.denominator = denominator
        self.beatGrouping = beatGrouping
    }

    public static func must(numerator: Int, denominator: Int, beatGrouping: [Int]) -> MusicalMeter {
        do {
            return try MusicalMeter(numerator: numerator, denominator: denominator, beatGrouping: beatGrouping)
        } catch {
            preconditionFailure("Invalid MusicalMeter preset: \(error)")
        }
    }

    public static let fourFour = MusicalMeter.must(numerator: 4, denominator: 4, beatGrouping: [1, 1, 1, 1])
    public static let threeFour = MusicalMeter.must(numerator: 3, denominator: 4, beatGrouping: [1, 1, 1])
    public static let sixEight = MusicalMeter.must(numerator: 6, denominator: 8, beatGrouping: [3, 3])
    public static let nineEight = MusicalMeter.must(numerator: 9, denominator: 8, beatGrouping: [3, 3, 3])
    public static let twelveEight = MusicalMeter.must(numerator: 12, denominator: 8, beatGrouping: [3, 3, 3, 3])
    public static let fiveFour = MusicalMeter.must(numerator: 5, denominator: 4, beatGrouping: [1, 1, 1, 1, 1])
    public static let sevenEight_223 = MusicalMeter.must(numerator: 7, denominator: 8, beatGrouping: [2, 2, 3])
    public static let sevenEight_322 = MusicalMeter.must(numerator: 7, denominator: 8, beatGrouping: [3, 2, 2])
    public static let sevenEight_232 = MusicalMeter.must(numerator: 7, denominator: 8, beatGrouping: [2, 3, 2])

    /// One denominator-unit duration in quarter notes (e.g. eighth-note unit in 6/8 = 0.5).
    public var quarterNotesPerDenominatorUnit: Double {
        4.0 / Double(denominator)
    }

    /// Number of metrical beats per bar (= grouping count).
    public var metricalBeatCount: Int { beatGrouping.count }

    public var barLengthInQuarterNotes: Double {
        Double(numerator) * quarterNotesPerDenominatorUnit
    }

    /// Canonical metrical beat lengths in quarter notes. Sole answer to "how long is each metrical beat?"
    public var metricalBeatLengthsInQuarterNotes: [Double] {
        beatGrouping.map { Double($0) * quarterNotesPerDenominatorUnit }
    }

    /// When all metrical beats share one length, that length in quarter notes; otherwise `nil` (asymmetric).
    public var uniformMetricalBeatLengthInQuarterNotes: Double? {
        let lengths = metricalBeatLengthsInQuarterNotes
        guard let first = lengths.first, lengths.allSatisfy({ abs($0 - first) < 1e-12 }) else { return nil }
        return first
    }
}

extension MusicalMeter: Codable {
    private enum CodingKeys: String, CodingKey {
        case numerator, denominator, beatGrouping
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let numerator = try c.decode(Int.self, forKey: .numerator)
        let denominator = try c.decode(Int.self, forKey: .denominator)
        let beatGrouping = try c.decode([Int].self, forKey: .beatGrouping)
        try self.init(numerator: numerator, denominator: denominator, beatGrouping: beatGrouping)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(numerator, forKey: .numerator)
        try c.encode(denominator, forKey: .denominator)
        try c.encode(beatGrouping, forKey: .beatGrouping)
    }
}

/// Simple note grid unit (not metrical beat).
public enum MusicalGridUnit: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    case thirtySecond
    case sixteenth
    case eighth
    case quarter
    case half
    case whole

    public var quarterNotes: Double {
        switch self {
        case .thirtySecond: return 0.125
        case .sixteenth: return 0.25
        case .eighth: return 0.5
        case .quarter: return 1
        case .half: return 2
        case .whole: return 4
        }
    }
}

public enum MusicalDurationError: Error, Equatable, Sendable {
    case nonPositiveCount
    case nonFiniteCount
    case dottedAndTriplet
}

/// Duration in grid terms (not necessarily metrical beat).
public struct MusicalDuration: Equatable, Sendable, Hashable {
    public var unit: MusicalGridUnit
    public var count: Double
    public var dotted: Bool
    public var triplet: Bool

    public init(
        unit: MusicalGridUnit,
        count: Double = 1,
        dotted: Bool = false,
        triplet: Bool = false
    ) throws {
        guard count.isFinite else { throw MusicalDurationError.nonFiniteCount }
        guard count > 0 else { throw MusicalDurationError.nonPositiveCount }
        guard !(dotted && triplet) else { throw MusicalDurationError.dottedAndTriplet }
        self.unit = unit
        self.count = count
        self.dotted = dotted
        self.triplet = triplet
    }

    public static func must(
        unit: MusicalGridUnit,
        count: Double = 1,
        dotted: Bool = false,
        triplet: Bool = false
    ) -> MusicalDuration {
        try! MusicalDuration(unit: unit, count: count, dotted: dotted, triplet: triplet)
    }

    public var quarterNotes: Double {
        var q = unit.quarterNotes * count
        if dotted { q *= 1.5 }
        if triplet { q *= 2.0 / 3.0 }
        return q
    }
}

extension MusicalDuration: Codable {
    private enum CodingKeys: String, CodingKey {
        case unit, count, dotted, triplet
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            unit: try c.decode(MusicalGridUnit.self, forKey: .unit),
            count: try c.decode(Double.self, forKey: .count),
            dotted: try c.decodeIfPresent(Bool.self, forKey: .dotted) ?? false,
            triplet: try c.decodeIfPresent(Bool.self, forKey: .triplet) ?? false
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(unit, forKey: .unit)
        try c.encode(count, forKey: .count)
        try c.encode(dotted, forKey: .dotted)
        try c.encode(triplet, forKey: .triplet)
    }
}

public struct QuarterNotePosition: Equatable, Sendable, Hashable {
    public var quarters: Double

    public enum ValidationError: Error, Equatable, Sendable {
        case nonFinite
    }

    public init(quarters: Double) throws {
        guard quarters.isFinite else { throw ValidationError.nonFinite }
        self.quarters = quarters
    }

    public static func must(_ quarters: Double) -> QuarterNotePosition {
        try! QuarterNotePosition(quarters: quarters)
    }

    public static func fromMIDISongPositionSixteenths(_ sixteenths: UInt16) -> QuarterNotePosition {
        .must(Double(sixteenths) / 4.0)
    }

    public var asMIDISongPositionSixteenths: UInt16 {
        let v = max(0, quarters * 4.0)
        return UInt16(min(Double(UInt16.max), v.rounded()))
    }
}

extension QuarterNotePosition: Codable {
    private enum CodingKeys: String, CodingKey { case quarters }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(quarters: try c.decode(Double.self, forKey: .quarters))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(quarters, forKey: .quarters)
    }
}

/// Bar + metrical beat; `beatPhase` in **[0, 1)** (1.0 normalizes to next beat).
public struct BarBeatPosition: Equatable, Sendable, Hashable {
    public var barIndex: Int
    public var beatIndexInBar: Int
    public var beatPhase: Double

    public init(barIndex: Int, beatIndexInBar: Int, beatPhase: Double) {
        self.barIndex = max(0, barIndex)
        self.beatIndexInBar = max(1, beatIndexInBar)
        var p = beatPhase
        if !p.isFinite { p = 0 }
        // Normalize to [0, 1)
        if p >= 1 || p < 0 {
            p = p - floor(p)
            if p >= 1 { p = 0 }
        }
        self.beatPhase = p
    }
}

extension BarBeatPosition: Codable {
    private enum CodingKeys: String, CodingKey {
        case barIndex, beatIndexInBar, beatPhase
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            barIndex: try c.decode(Int.self, forKey: .barIndex),
            beatIndexInBar: try c.decode(Int.self, forKey: .beatIndexInBar),
            beatPhase: try c.decode(Double.self, forKey: .beatPhase)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(barIndex, forKey: .barIndex)
        try c.encode(beatIndexInBar, forKey: .beatIndexInBar)
        try c.encode(beatPhase, forKey: .beatPhase)
    }
}

// MARK: - Meter math helpers

public enum MusicalMeterMath {
    /// Map absolute quarter-note position into bar + metrical beat.
    public static func barBeat(
        at position: QuarterNotePosition,
        meter: MusicalMeter
    ) -> BarBeatPosition {
        let barLen = meter.barLengthInQuarterNotes
        guard barLen > 0 else {
            return BarBeatPosition(barIndex: 0, beatIndexInBar: 1, beatPhase: 0)
        }
        let q = max(0, position.quarters)
        let barIndex = Int(floor(q / barLen))
        var intoBar = q - Double(barIndex) * barLen
        let lengths = meter.metricalBeatLengthsInQuarterNotes
        var beat = 1
        for (i, len) in lengths.enumerated() {
            if intoBar < len - 1e-12 || i == lengths.count - 1 {
                let phase = len > 0 ? min(0.999999999, max(0, intoBar / len)) : 0
                return BarBeatPosition(barIndex: barIndex, beatIndexInBar: beat, beatPhase: phase)
            }
            intoBar -= len
            beat += 1
        }
        return BarBeatPosition(barIndex: barIndex, beatIndexInBar: lengths.count, beatPhase: 0)
    }

    /// Absolute quarter-note position of the next metrical beat boundary strictly after `position`.
    public static func nextMetricalBeatPosition(
        after position: QuarterNotePosition,
        meter: MusicalMeter
    ) -> QuarterNotePosition {
        let barLen = meter.barLengthInQuarterNotes
        let lengths = meter.metricalBeatLengthsInQuarterNotes
        guard barLen > 0, !lengths.isEmpty else { return position }

        let q = position.quarters
        let barIndex = Int(floor(max(0, q) / barLen))
        let barStart = Double(barIndex) * barLen
        var cursor = barStart
        let eps = 1e-9
        for len in lengths {
            let boundary = cursor + len
            if boundary > q + eps {
                return .must(boundary)
            }
            cursor = boundary
        }
        // Next bar first beat
        return .must(barStart + barLen)
    }

    /// Next quarter-note boundary strictly after position.
    public static func nextQuarterNotePosition(after position: QuarterNotePosition) -> QuarterNotePosition {
        let q = position.quarters
        let next = floor(q) + 1
        if abs(next - q) < 1e-12 {
            return .must(q + 1)
        }
        return .must(next)
    }
}

// MARK: - Provenance

public enum MusicalValueProvenance: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    case unknown
    case internalTiming
    case midiClock
    case midiSongPosition
    case songMetadata
    case projectDefault
    case showControl
    case user
    case tapTempo
    case freewheel
    case fallback
}

public struct ProvenancedValue<Value: Equatable & Sendable>: Equatable, Sendable {
    public var value: Value
    public var provenance: MusicalValueProvenance

    public init(_ value: Value, provenance: MusicalValueProvenance = .unknown) {
        self.value = value
        self.provenance = provenance
    }
}

// MARK: - Capabilities

public struct TimingSourceCapabilities: Codable, Equatable, Sendable, Hashable {
    public var suppliesTempo: Bool
    public var suppliesPhase: Bool
    public var suppliesTransport: Bool
    /// True only when this source instance currently provides song position (not merely that Aurora can parse SPP).
    public var suppliesSongPosition: Bool
    public var suppliesMeter: Bool
    /// Parser/adapter can accept SPP even if not currently supplying.
    public var supportsSongPositionInput: Bool

    public init(
        suppliesTempo: Bool = false,
        suppliesPhase: Bool = false,
        suppliesTransport: Bool = false,
        suppliesSongPosition: Bool = false,
        suppliesMeter: Bool = false,
        supportsSongPositionInput: Bool = false
    ) {
        self.suppliesTempo = suppliesTempo
        self.suppliesPhase = suppliesPhase
        self.suppliesTransport = suppliesTransport
        self.suppliesSongPosition = suppliesSongPosition
        self.suppliesMeter = suppliesMeter
        self.supportsSongPositionInput = supportsSongPositionInput
    }

    public static let internalSource = TimingSourceCapabilities(
        suppliesTempo: true,
        suppliesPhase: true,
        suppliesTransport: true,
        suppliesSongPosition: true,
        suppliesMeter: false,
        supportsSongPositionInput: false
    )

    /// Generic MIDI Clock pulse/transport. SPP is separate System Common — not implied by clock alone.
    public static let midiClock = TimingSourceCapabilities(
        suppliesTempo: true,
        suppliesPhase: true,
        suppliesTransport: true,
        suppliesSongPosition: false,
        suppliesMeter: false,
        supportsSongPositionInput: true
    )
}

public struct MusicalTimingDiagnostics: Codable, Equatable, Sendable, Hashable {
    public var estimatedJitterMilliseconds: Double?
    public var lastPulseAgeMilliseconds: Double?
    public var pulsesReceived: UInt64
    public var lastError: String?

    public init(
        estimatedJitterMilliseconds: Double? = nil,
        lastPulseAgeMilliseconds: Double? = nil,
        pulsesReceived: UInt64 = 0,
        lastError: String? = nil
    ) {
        self.estimatedJitterMilliseconds = estimatedJitterMilliseconds
        self.lastPulseAgeMilliseconds = lastPulseAgeMilliseconds
        self.pulsesReceived = pulsesReceived
        self.lastError = lastError
    }

    public static let empty = MusicalTimingDiagnostics()
}

// MARK: - BPM helpers

public enum MusicalNumeric {
    public static let minBPM: Double = 20
    public static let maxBPM: Double = 400

    public static func isValidBPM(_ bpm: Double) -> Bool {
        bpm.isFinite && bpm >= minBPM && bpm <= maxBPM
    }
}
