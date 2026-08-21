import AuroraDiagnostics
import Foundation

/// Persisted metrical structure for songs/projects (AuroraModel).
///
/// Storage/domain data — converts to/from `AuroraMusical.MusicalMeter` via Engine bridge.
/// Full structure (numerator, denominator, **beatGrouping**) must survive save/load so Phase B
/// never re-guesses compound or asymmetric pulses.
public struct ShowMusicalMeter: Equatable, Sendable, Hashable {
    public var numerator: Int
    public var denominator: Int
    /// Denominator-unit grouping per metrical beat. Required and explicit in v4 closeout.
    public var beatGrouping: [Int]

    public enum ValidationError: Error, Equatable, Sendable {
        case invalidNumerator
        case unsupportedDenominator
        case invalidGrouping
        case groupingSumMismatch
    }

    public init(numerator: Int, denominator: Int, beatGrouping: [Int]) throws {
        guard numerator >= 1 else { throw ValidationError.invalidNumerator }
        guard [1, 2, 4, 8, 16, 32].contains(denominator) else {
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

    public static func must(numerator: Int, denominator: Int, beatGrouping: [Int]) -> ShowMusicalMeter {
        try! ShowMusicalMeter(numerator: numerator, denominator: denominator, beatGrouping: beatGrouping)
    }

    public static let fourFour = ShowMusicalMeter.must(numerator: 4, denominator: 4, beatGrouping: [1, 1, 1, 1])
    public static let threeFour = ShowMusicalMeter.must(numerator: 3, denominator: 4, beatGrouping: [1, 1, 1])
    public static let sixEight = ShowMusicalMeter.must(numerator: 6, denominator: 8, beatGrouping: [3, 3])
    public static let nineEight = ShowMusicalMeter.must(numerator: 9, denominator: 8, beatGrouping: [3, 3, 3])
    public static let twelveEight = ShowMusicalMeter.must(numerator: 12, denominator: 8, beatGrouping: [3, 3, 3, 3])
    public static let sevenEight_223 = ShowMusicalMeter.must(numerator: 7, denominator: 8, beatGrouping: [2, 2, 3])
    public static let sevenEight_322 = ShowMusicalMeter.must(numerator: 7, denominator: 8, beatGrouping: [3, 2, 2])

    /// Deterministic migration when only numerator/denominator were stored.
    ///
    /// - 4/4, 3/4, n/4 → unit groups of 1
    /// - 6/8, 9/8, 12/8 → groups of 3
    /// - other → unit-pulse `[1] * numerator` (documented default, not an invented compound feel)
    public static func migrating(numerator: Int, denominator: Int) -> ShowMusicalMeter? {
        guard numerator >= 1, [1, 2, 4, 8, 16, 32].contains(denominator) else { return nil }
        let grouping: [Int]
        if denominator == 8, numerator % 3 == 0, numerator >= 6 {
            grouping = Array(repeating: 3, count: numerator / 3)
        } else {
            grouping = Array(repeating: 1, count: numerator)
        }
        return try? ShowMusicalMeter(numerator: numerator, denominator: denominator, beatGrouping: grouping)
    }
}

extension ShowMusicalMeter: Codable {
    private enum CodingKeys: String, CodingKey {
        case numerator, denominator, beatGrouping
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            numerator: try c.decode(Int.self, forKey: .numerator),
            denominator: try c.decode(Int.self, forKey: .denominator),
            beatGrouping: try c.decode([Int].self, forKey: .beatGrouping)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(numerator, forKey: .numerator)
        try c.encode(denominator, forKey: .denominator)
        try c.encode(beatGrouping, forKey: .beatGrouping)
    }
}

extension ShowMusicalMeter.ValidationError: LocalizedError, PrismDiagnosableError {
    public var errorDescription: String? { userMessage }
    public var prismErrorCode: String { "music.song.invalid_meter" }
    public var userTitle: String { "That Meter Isn’t Valid" }
    public var userMessage: String { "That meter isn’t valid." }
    public var recoverySuggestion: String? { "Choose a supported time signature and grouping that adds up to the numerator." }
    public var technicalDetails: String { String(reflecting: self) }
    public var prismCategory: PrismLogCategory { .musicSong }
    public var prismSeverity: PrismLogLevel { .error }
}
