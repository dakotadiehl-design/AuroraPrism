import Foundation

/// Stable, serialization-safe identity for a parameter that may later be modulated.
///
/// These raw values are public contracts for MIDI/AME/Remote/Conductor integrations.
/// Display names belong in descriptors and may change without breaking mappings.
public struct EffectParameterID: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(rawValue: value) }

    public static let amplitude: Self = "amplitude"
    public static let base: Self = "base"
    public static let speed: Self = "speed"
    public static let phase: Self = "phase"
    public static let spread: Self = "spread"
    public static let gradientPosition: Self = "gradient.position"
    public static let movementSize: Self = "movement.size"
    public static let movementWidth: Self = "movement.width"
    public static let movementHeight: Self = "movement.height"
    public static let movementRotation: Self = "movement.rotation"
    public static let movementCenterPan: Self = "movement.center.pan"
    public static let movementCenterTilt: Self = "movement.center.tilt"
    public static let patternWidth: Self = "pattern.width"
    public static let patternSoftness: Self = "pattern.softness"
    public static let patternDensity: Self = "pattern.density"
    public static let patternTrail: Self = "pattern.trail"
    public static let blendAmount: Self = "composition.blendAmount"
    public static let distributionGrouping: Self = "distribution.grouping"
    public static let cellGrouping: Self = "cells.grouping"
    public static let fanStart: Self = "fan.start"
    public static let fanEnd: Self = "fan.end"
}

public enum EffectParameterUnit: String, Codable, Hashable, Sendable {
    case normalized
    case hertz
    case seconds
    case degrees
    case percent
    case count
}

/// UI-agnostic metadata for discovery, validation, precision entry, and modulation.
public struct EffectParameterDescriptor: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: EffectParameterID
    public var displayName: String
    public var unit: EffectParameterUnit
    public var range: ClosedRange<Double>
    public var defaultValue: Double

    public init(
        id: EffectParameterID,
        displayName: String,
        unit: EffectParameterUnit,
        range: ClosedRange<Double>,
        defaultValue: Double
    ) {
        self.id = id
        self.displayName = displayName
        self.unit = unit
        self.range = range
        self.defaultValue = defaultValue
    }
}

/// Durable clock transition behavior. V2 timing providers apply this policy when
/// their source changes; legacy frequency timing remains continuous and unchanged.
public enum EffectClockSwitchPolicy: String, Codable, Hashable, Sendable {
    case preservePhase
    case requantize
    case restart
}

public enum EffectClockSource: String, Codable, CaseIterable, Hashable, Sendable {
    case freeRun
    case internalBPM
    case musicEngine
    case midiClock
    case ame
}

public enum EffectClockLossPolicy: String, Codable, CaseIterable, Hashable, Sendable {
    case holdPhase
    case continueLastTempo
    case stop
    case fallbackInternal
}

public enum EffectStartQuantization: String, Codable, CaseIterable, Hashable, Sendable {
    case immediate
    case nextBeat
    case nextBar
}

public enum EffectTimingModifier: String, Codable, CaseIterable, Hashable, Sendable {
    case straight
    case dotted
    case triplet

    public var durationMultiplier: Double {
        switch self {
        case .straight: return 1
        case .dotted: return 1.5
        case .triplet: return 2.0 / 3.0
        }
    }
}

public enum EffectNoteDivision: String, Codable, CaseIterable, Hashable, Sendable {
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

public enum EffectMusicalDurationUnit: String, Codable, CaseIterable, Hashable, Sendable {
    case note
    case metricalBeat
    case bar
}

/// A cycle duration expressed on a musical grid. `metricalBeat` follows the
/// meter's beat grouping, including unequal beat lengths in asymmetric meters.
public struct EffectMusicalDuration: Codable, Equatable, Hashable, Sendable {
    public var unit: EffectMusicalDurationUnit
    public var count: Double
    public var noteDivision: EffectNoteDivision
    public var modifier: EffectTimingModifier

    public init(
        unit: EffectMusicalDurationUnit,
        count: Double = 1,
        noteDivision: EffectNoteDivision = .quarter,
        modifier: EffectTimingModifier = .straight
    ) {
        self.unit = unit
        self.count = count.isFinite ? max(0.001, count) : 1
        self.noteDivision = noteDivision
        self.modifier = modifier
    }

    private enum CodingKeys: String, CodingKey { case unit, count, noteDivision, modifier }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let count = try c.decode(Double.self, forKey: .count)
        guard count.isFinite, count > 0 else {
            throw DecodingError.dataCorruptedError(forKey: .count, in: c, debugDescription: "Effect duration count must be finite and positive")
        }
        self.init(
            unit: try c.decode(EffectMusicalDurationUnit.self, forKey: .unit),
            count: count,
            noteDivision: try c.decode(EffectNoteDivision.self, forKey: .noteDivision),
            modifier: try c.decode(EffectTimingModifier.self, forKey: .modifier)
        )
    }
}

public enum EffectTimingRate: Codable, Equatable, Hashable, Sendable {
    case frequencyHz(Double)
    case periodSeconds(Double)
    case musical(EffectMusicalDuration)
}

/// Durable FX-2 timing settings. Runtime clock state deliberately remains in
/// AuroraEngine and is not serialized into effect definitions.
public struct EffectTimingDefinition: Codable, Equatable, Hashable, Sendable {
    public var source: EffectClockSource
    public var rate: EffectTimingRate
    public var internalBPM: Double
    public var phase: Double
    public var startQuantization: EffectStartQuantization
    public var sourceSwitchPolicy: EffectClockSwitchPolicy
    public var clockLossPolicy: EffectClockLossPolicy

    public init(
        source: EffectClockSource = .freeRun,
        rate: EffectTimingRate = .frequencyHz(1),
        internalBPM: Double = 120,
        phase: Double = 0,
        startQuantization: EffectStartQuantization = .immediate,
        sourceSwitchPolicy: EffectClockSwitchPolicy = .preservePhase,
        clockLossPolicy: EffectClockLossPolicy = .holdPhase
    ) {
        self.source = source
        self.rate = rate
        self.internalBPM = internalBPM.isFinite ? min(999, max(1, internalBPM)) : 120
        self.phase = phase.isFinite ? phase - floor(phase) : 0
        self.startQuantization = startQuantization
        self.sourceSwitchPolicy = sourceSwitchPolicy
        self.clockLossPolicy = clockLossPolicy
    }

    private enum CodingKeys: String, CodingKey {
        case source, rate, internalBPM, phase, startQuantization, sourceSwitchPolicy, clockLossPolicy
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let bpm = try c.decode(Double.self, forKey: .internalBPM)
        let phase = try c.decode(Double.self, forKey: .phase)
        guard bpm.isFinite, (1...999).contains(bpm) else {
            throw DecodingError.dataCorruptedError(forKey: .internalBPM, in: c, debugDescription: "Internal BPM must be within 1...999")
        }
        guard phase.isFinite else {
            throw DecodingError.dataCorruptedError(forKey: .phase, in: c, debugDescription: "Effect phase must be finite")
        }
        self.init(
            source: try c.decode(EffectClockSource.self, forKey: .source),
            rate: try c.decode(EffectTimingRate.self, forKey: .rate),
            internalBPM: bpm,
            phase: phase,
            startQuantization: try c.decode(EffectStartQuantization.self, forKey: .startQuantization),
            sourceSwitchPolicy: try c.decode(EffectClockSwitchPolicy.self, forKey: .sourceSwitchPolicy),
            clockLossPolicy: try c.decode(EffectClockLossPolicy.self, forKey: .clockLossPolicy)
        )
    }
}

/// Meter is explicit so a bar is never silently interpreted as 4/4 and beat
/// grouping remains available for compound and asymmetric meters.
public struct EffectMusicalMeter: Codable, Equatable, Hashable, Sendable {
    public var numerator: Int
    public var denominator: Int
    public var beatGrouping: [Int]

    public init(numerator: Int, denominator: Int, beatGrouping: [Int]? = nil) {
        self.numerator = max(1, numerator)
        self.denominator = max(1, denominator)
        let proposed = beatGrouping ?? Array(repeating: 1, count: max(1, numerator))
        self.beatGrouping = !proposed.isEmpty && proposed.allSatisfy({ $0 > 0 }) && proposed.reduce(0, +) == self.numerator
            ? proposed
            : Array(repeating: 1, count: self.numerator)
    }

    public init(beatsPerBar: Int, beatUnit: Int) {
        self.init(numerator: beatsPerBar, denominator: beatUnit)
    }

    public var beatsPerBar: Int { beatGrouping.count }
    public var beatUnit: Int { denominator }
    public var barLengthInQuarterNotes: Double { Double(numerator) * 4 / Double(denominator) }
    public var metricalBeatLengthsInQuarterNotes: [Double] {
        beatGrouping.map { Double($0) * 4 / Double(denominator) }
    }

    private enum CodingKeys: String, CodingKey { case numerator, denominator, beatGrouping }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let numerator = try c.decode(Int.self, forKey: .numerator)
        let denominator = try c.decode(Int.self, forKey: .denominator)
        let grouping = try c.decode([Int].self, forKey: .beatGrouping)
        guard numerator > 0 else {
            throw DecodingError.dataCorruptedError(forKey: .numerator, in: c, debugDescription: "Meter numerator must be positive")
        }
        guard [1, 2, 4, 8, 16, 32].contains(denominator) else {
            throw DecodingError.dataCorruptedError(forKey: .denominator, in: c, debugDescription: "Unsupported meter denominator")
        }
        guard !grouping.isEmpty, grouping.allSatisfy({ $0 > 0 }), grouping.reduce(0, +) == numerator else {
            throw DecodingError.dataCorruptedError(forKey: .beatGrouping, in: c, debugDescription: "Beat grouping must be positive and sum to the numerator")
        }
        self.init(numerator: numerator, denominator: denominator, beatGrouping: grouping)
    }
}

/// Stable address for either a whole fixture or one logical fixture element.
/// Uses the same canonical element IDs as `FixtureTarget` (`cell-0`, `cell-1`, ...).
public struct EffectTargetID: Codable, Equatable, Hashable, Sendable {
    public var fixtureID: UUID
    public var elementID: String?

    public init(fixtureID: UUID, elementID: String? = nil) {
        self.fixtureID = fixtureID
        self.elementID = elementID
    }

    /// Compatibility initializer for the first Effects foundation revision.
    /// Numeric values are canonicalized into Aurora fixture-element IDs.
    public init(fixtureID: UUID, cellID: String?) {
        self.fixtureID = fixtureID
        if let cellID, let index = Int(cellID) {
            self.elementID = FixtureElement.cellID(index: index)
        } else {
            self.elementID = cellID
        }
    }

    public init(_ target: FixtureTarget) {
        self.init(fixtureID: target.fixtureID, elementID: target.elementID)
    }

    public var fixtureTarget: FixtureTarget {
        FixtureTarget(fixtureID: fixtureID, elementID: elementID)
    }
}

public enum EffectDistributionOrder: String, Codable, CaseIterable, Hashable, Sendable {
    case selection
    case fixtureNumber
    case dmxAddress
    case custom
    case stageLeftToRight
    case stageRightToLeft
    case stageFrontToBack
    case stageBackToFront
    case centerOut
    case outsideIn
    case random
    case spatialRadial
    case spatialAngular
}

public enum EffectDistributionSymmetry: String, Codable, CaseIterable, Hashable, Sendable {
    case asymmetric
    case mirror
    case centerOut
    case outsideIn
}

public enum EffectDistributionCurve: String, Codable, CaseIterable, Hashable, Sendable {
    case linear
    case easeIn
    case easeOut
    case easeInOut
    case exponential
    case logarithmic
    case custom
}

/// Durable, property-neutral fixture/cell distribution definition.
/// Spatial rules remain dynamic until `frozenOrder` is populated.
public struct FixtureDistributionDefinition: Codable, Equatable, Hashable, Sendable {
    public var order: EffectDistributionOrder
    public var customOrder: [EffectTargetID]
    public var frozenOrder: [EffectTargetID]?
    public var grouping: Int
    public var repetitions: Int
    public var symmetry: EffectDistributionSymmetry
    public var randomSeed: UInt64
    public var curve: EffectDistributionCurve
    public var curveExponent: Double
    public var customCurve: [EffectCurvePoint]

    public init(
        order: EffectDistributionOrder = .selection,
        customOrder: [EffectTargetID] = [],
        frozenOrder: [EffectTargetID]? = nil,
        grouping: Int = 1,
        repetitions: Int = 1,
        symmetry: EffectDistributionSymmetry = .asymmetric,
        randomSeed: UInt64 = 0,
        curve: EffectDistributionCurve = .linear,
        curveExponent: Double = 2,
        customCurve: [EffectCurvePoint] = []
    ) {
        self.order = order
        self.customOrder = customOrder
        self.frozenOrder = frozenOrder
        self.grouping = max(1, grouping)
        self.repetitions = max(1, repetitions)
        self.symmetry = symmetry
        self.randomSeed = randomSeed
        self.curve = curve
        self.curveExponent = curveExponent.isFinite ? max(0.001, curveExponent) : 2
        self.customCurve = customCurve
    }

    public var isSpatialRule: Bool {
        switch order {
        case .stageLeftToRight, .stageRightToLeft, .stageFrontToBack, .stageBackToFront, .centerOut, .outsideIn:
            return true
        case .selection, .fixtureNumber, .dmxAddress, .custom, .random:
            return false
        case .spatialRadial, .spatialAngular:
            return true
        }
    }

    private enum CodingKeys: String, CodingKey {
        case order, customOrder, frozenOrder, grouping, repetitions, symmetry, randomSeed
        case curve, curveExponent, customCurve
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let grouping = try c.decodeIfPresent(Int.self, forKey: .grouping) ?? 1
        let repetitions = try c.decodeIfPresent(Int.self, forKey: .repetitions) ?? 1
        let exponent = try c.decodeIfPresent(Double.self, forKey: .curveExponent) ?? 2
        guard grouping > 0, repetitions > 0, exponent.isFinite, exponent > 0 else {
            throw DecodingError.dataCorruptedError(forKey: .grouping, in: c, debugDescription: "Distribution grouping, repetitions, and exponent must be positive")
        }
        self.init(
            order: try c.decodeIfPresent(EffectDistributionOrder.self, forKey: .order) ?? .selection,
            customOrder: try c.decodeIfPresent([EffectTargetID].self, forKey: .customOrder) ?? [],
            frozenOrder: try c.decodeIfPresent([EffectTargetID].self, forKey: .frozenOrder),
            grouping: grouping,
            repetitions: repetitions,
            symmetry: try c.decodeIfPresent(EffectDistributionSymmetry.self, forKey: .symmetry) ?? .asymmetric,
            randomSeed: try c.decodeIfPresent(UInt64.self, forKey: .randomSeed) ?? 0,
            curve: try c.decodeIfPresent(EffectDistributionCurve.self, forKey: .curve) ?? .linear,
            curveExponent: exponent,
            customCurve: try c.decodeIfPresent([EffectCurvePoint].self, forKey: .customCurve) ?? []
        )
    }
}

public struct EffectDistributionPreset: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var distribution: FixtureDistributionDefinition

    public init(id: UUID = UUID(), name: String, distribution: FixtureDistributionDefinition) {
        self.id = id; self.name = name; self.distribution = distribution
    }
}

public struct EffectColor: Codable, Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(1, max(0, red))
        self.green = min(1, max(0, green))
        self.blue = min(1, max(0, blue))
    }

    private enum CodingKeys: String, CodingKey { case red, green, blue }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let red = try c.decode(Double.self, forKey: .red)
        let green = try c.decode(Double.self, forKey: .green)
        let blue = try c.decode(Double.self, forKey: .blue)
        guard [red, green, blue].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw DecodingError.dataCorruptedError(forKey: .red, in: c, debugDescription: "Effect color components must be within 0...1")
        }
        self.init(red: red, green: green, blue: blue)
    }
}

public enum EffectColorInterpolation: String, Codable, CaseIterable, Hashable, Sendable {
    case rgb
    case hsvShortest
    case hsvClockwise
    case hsvCounterClockwise
}

public struct EffectGradientStop: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var position: Double
    public var color: EffectColor
    /// Stable palette reference retained for later palette resolution. When nil,
    /// `color` is the durable literal fallback.
    public var paletteID: UUID?

    public init(id: UUID = UUID(), position: Double, color: EffectColor, paletteID: UUID? = nil) {
        self.id = id
        self.position = min(1, max(0, position))
        self.color = color
        self.paletteID = paletteID
    }

    private enum CodingKeys: String, CodingKey { case id, position, color, paletteID }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let position = try c.decode(Double.self, forKey: .position)
        guard position.isFinite, (0...1).contains(position) else {
            throw DecodingError.dataCorruptedError(forKey: .position, in: c, debugDescription: "Gradient stop position must be within 0...1")
        }
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            position: position,
            color: try c.decode(EffectColor.self, forKey: .color),
            paletteID: try c.decodeIfPresent(UUID.self, forKey: .paletteID)
        )
    }
}

public struct EffectColorGradientDefinition: Codable, Equatable, Hashable, Sendable {
    public var stops: [EffectGradientStop]
    public var interpolation: EffectColorInterpolation
    public var reversed: Bool
    public var mirrored: Bool
    public var positionOffset: Double

    public init(
        stops: [EffectGradientStop] = [
            EffectGradientStop(position: 0, color: EffectColor(red: 0, green: 0, blue: 1)),
            EffectGradientStop(position: 1, color: EffectColor(red: 1, green: 0, blue: 0)),
        ],
        interpolation: EffectColorInterpolation = .hsvShortest,
        reversed: Bool = false,
        mirrored: Bool = false,
        positionOffset: Double = 0
    ) {
        self.stops = stops
        self.interpolation = interpolation
        self.reversed = reversed
        self.mirrored = mirrored
        self.positionOffset = positionOffset.isFinite ? positionOffset : 0
    }

    private enum CodingKeys: String, CodingKey { case stops, interpolation, reversed, mirrored, positionOffset }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let offset = try c.decodeIfPresent(Double.self, forKey: .positionOffset) ?? 0
        guard offset.isFinite else {
            throw DecodingError.dataCorruptedError(forKey: .positionOffset, in: c, debugDescription: "Gradient offset must be finite")
        }
        self.init(
            stops: try c.decode([EffectGradientStop].self, forKey: .stops),
            interpolation: try c.decodeIfPresent(EffectColorInterpolation.self, forKey: .interpolation) ?? .hsvShortest,
            reversed: try c.decodeIfPresent(Bool.self, forKey: .reversed) ?? false,
            mirrored: try c.decodeIfPresent(Bool.self, forKey: .mirrored) ?? false,
            positionOffset: offset
        )
    }
}

public struct EffectColorGradientPreset: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var gradient: EffectColorGradientDefinition

    public init(id: UUID = UUID(), name: String, gradient: EffectColorGradientDefinition) {
        self.id = id
        self.name = name
        self.gradient = gradient
    }
}

public enum EffectMovementTemplate: String, Codable, CaseIterable, Hashable, Sendable {
    case circle, ellipse, figureEight, diamond, square, triangle
    case horizontalSweep, verticalSweep, diagonalSweep, arc, fanSweep, randomWander, customPath
}

public enum EffectMovementInterpolation: String, Codable, CaseIterable, Hashable, Sendable {
    case smooth, linear, step
}

public enum EffectMovementCoordinateMode: String, Codable, CaseIterable, Hashable, Sendable {
    case relative, absolute
}

public struct EffectMovementPoint: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var x: Double
    public var y: Double

    public init(id: UUID = UUID(), x: Double, y: Double) {
        self.id = id
        self.x = min(1, max(-1, x))
        self.y = min(1, max(-1, y))
    }

    private enum CodingKeys: String, CodingKey { case id, x, y }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let x = try c.decode(Double.self, forKey: .x)
        let y = try c.decode(Double.self, forKey: .y)
        guard x.isFinite, y.isFinite, (-1...1).contains(x), (-1...1).contains(y) else {
            throw DecodingError.dataCorruptedError(forKey: .x, in: c, debugDescription: "Movement coordinates must be finite and within -1...1")
        }
        self.init(id: try c.decode(UUID.self, forKey: .id), x: x, y: y)
    }
}

public struct EffectMovementDefinition: Codable, Equatable, Hashable, Sendable {
    public var template: EffectMovementTemplate
    public var interpolation: EffectMovementInterpolation
    public var coordinateMode: EffectMovementCoordinateMode
    public var centerPan: Double
    public var centerTilt: Double
    public var width: Double
    public var height: Double
    public var rotation: Double
    public var mirrorPan: Bool
    public var mirrorTilt: Bool
    public var randomSeed: UInt64
    public var customPath: [EffectMovementPoint]

    public init(
        template: EffectMovementTemplate = .circle,
        interpolation: EffectMovementInterpolation = .smooth,
        coordinateMode: EffectMovementCoordinateMode = .relative,
        centerPan: Double = 0.5,
        centerTilt: Double = 0.5,
        width: Double = 0.5,
        height: Double = 0.5,
        rotation: Double = 0,
        mirrorPan: Bool = false,
        mirrorTilt: Bool = false,
        randomSeed: UInt64 = 0,
        customPath: [EffectMovementPoint] = []
    ) {
        self.template = template
        self.interpolation = interpolation
        self.coordinateMode = coordinateMode
        self.centerPan = min(1, max(0, centerPan))
        self.centerTilt = min(1, max(0, centerTilt))
        self.width = min(1, max(0, width))
        self.height = min(1, max(0, height))
        self.rotation = rotation.isFinite ? rotation : 0
        self.mirrorPan = mirrorPan
        self.mirrorTilt = mirrorTilt
        self.randomSeed = randomSeed
        self.customPath = customPath
    }

    private enum CodingKeys: String, CodingKey {
        case template, interpolation, coordinateMode, centerPan, centerTilt, width, height, rotation
        case mirrorPan, mirrorTilt, randomSeed, customPath
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let centerPan = try c.decode(Double.self, forKey: .centerPan)
        let centerTilt = try c.decode(Double.self, forKey: .centerTilt)
        let width = try c.decode(Double.self, forKey: .width)
        let height = try c.decode(Double.self, forKey: .height)
        let rotation = try c.decode(Double.self, forKey: .rotation)
        guard [centerPan, centerTilt, width, height].allSatisfy({ $0.isFinite && (0...1).contains($0) }), rotation.isFinite else {
            throw DecodingError.dataCorruptedError(forKey: .width, in: c, debugDescription: "Movement dimensions and centers must be finite normalized values")
        }
        self.init(
            template: try c.decode(EffectMovementTemplate.self, forKey: .template),
            interpolation: try c.decode(EffectMovementInterpolation.self, forKey: .interpolation),
            coordinateMode: try c.decode(EffectMovementCoordinateMode.self, forKey: .coordinateMode),
            centerPan: centerPan,
            centerTilt: centerTilt,
            width: width,
            height: height,
            rotation: rotation,
            mirrorPan: try c.decode(Bool.self, forKey: .mirrorPan),
            mirrorTilt: try c.decode(Bool.self, forKey: .mirrorTilt),
            randomSeed: try c.decode(UInt64.self, forKey: .randomSeed),
            customPath: try c.decode([EffectMovementPoint].self, forKey: .customPath)
        )
    }
}

public enum EffectPatternKind: String, Codable, CaseIterable, Hashable, Sendable {
    case chase, scanner, bounce, fill, wipe, rain, meteor, sparkle, twinkle, fire
    case pulseTrain, theaterChase, randomChase, colorRoll, colorWipe, gradientRoll
    case comet, ripple, alternator, noise, shimmer
}

public struct EffectPatternDefinition: Codable, Equatable, Hashable, Sendable {
    public var kind: EffectPatternKind
    public var width: Double
    public var softness: Double
    public var density: Double
    public var trail: Double
    public var randomSeed: UInt64
    public var secondaryColor: EffectColor

    public init(
        kind: EffectPatternKind = .chase,
        width: Double = 0.2,
        softness: Double = 0.1,
        density: Double = 0.2,
        trail: Double = 0.3,
        randomSeed: UInt64 = 0,
        secondaryColor: EffectColor = .init(red: 0, green: 0, blue: 0)
    ) {
        self.kind = kind
        self.width = min(1, max(0.001, width))
        self.softness = min(1, max(0, softness))
        self.density = min(1, max(0, density))
        self.trail = min(1, max(0, trail))
        self.randomSeed = randomSeed
        self.secondaryColor = secondaryColor
    }

    private enum CodingKeys: String, CodingKey { case kind, width, softness, density, trail, randomSeed, secondaryColor }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let width = try c.decode(Double.self, forKey: .width)
        let softness = try c.decode(Double.self, forKey: .softness)
        let density = try c.decode(Double.self, forKey: .density)
        let trail = try c.decode(Double.self, forKey: .trail)
        guard width.isFinite, width > 0, width <= 1,
              [softness, density, trail].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw DecodingError.dataCorruptedError(forKey: .width, in: c, debugDescription: "Pattern parameters must be finite normalized values")
        }
        self.init(
            kind: try c.decode(EffectPatternKind.self, forKey: .kind), width: width, softness: softness,
            density: density, trail: trail, randomSeed: try c.decode(UInt64.self, forKey: .randomSeed),
            secondaryColor: try c.decode(EffectColor.self, forKey: .secondaryColor)
        )
    }
}

public enum EffectCellTargetMode: String, Codable, CaseIterable, Hashable, Sendable { case fixtures, allCells, selectedCells }
public enum EffectCellOrder: String, Codable, CaseIterable, Hashable, Sendable { case forward, reverse }

/// Lighting-aware stack composition. `replace` preserves legacy behavior.
public enum EffectBlendMode: String, Codable, CaseIterable, Hashable, Sendable {
    case replace, add, multiply, maximum, minimum
}

public enum EffectMaskKind: String, Codable, CaseIterable, Hashable, Sendable {
    case none, fixtureGroup, odd, even, firstHalf, secondHalf, center, edges, everyNth, selectedTargets, spatialRegion
}

/// A mask is resolved once at compilation, after target ordering and before frame evaluation.
public struct EffectMaskDefinition: Codable, Equatable, Hashable, Sendable {
    public var kind: EffectMaskKind
    public var everyNth: Int
    public var fixtureGroupID: UUID?
    public var selectedTargets: [EffectTargetID]
    public var minimumX: Double
    public var maximumX: Double
    public var minimumY: Double
    public var maximumY: Double

    public init(
        kind: EffectMaskKind = .none,
        everyNth: Int = 2,
        fixtureGroupID: UUID? = nil,
        selectedTargets: [EffectTargetID] = [],
        minimumX: Double = -1.0e12,
        maximumX: Double = 1.0e12,
        minimumY: Double = -1.0e12,
        maximumY: Double = 1.0e12
    ) {
        self.kind = kind
        self.everyNth = max(1, everyNth)
        self.fixtureGroupID = fixtureGroupID
        self.selectedTargets = selectedTargets
        self.minimumX = minimumX
        self.maximumX = maximumX
        self.minimumY = minimumY
        self.maximumY = maximumY
    }

    private enum CodingKeys: String, CodingKey { case kind, everyNth, fixtureGroupID, selectedTargets, minimumX, maximumX, minimumY, maximumY }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let everyNth = try c.decode(Int.self, forKey: .everyNth)
        let minimumX = try c.decode(Double.self, forKey: .minimumX)
        let maximumX = try c.decode(Double.self, forKey: .maximumX)
        let minimumY = try c.decode(Double.self, forKey: .minimumY)
        let maximumY = try c.decode(Double.self, forKey: .maximumY)
        guard everyNth > 0,
              [minimumX, maximumX, minimumY, maximumY].allSatisfy(\.isFinite),
              minimumX <= maximumX, minimumY <= maximumY else {
            throw DecodingError.dataCorruptedError(forKey: .everyNth, in: c, debugDescription: "Effect mask bounds and stride are invalid")
        }
        self.init(
            kind: try c.decode(EffectMaskKind.self, forKey: .kind), everyNth: everyNth,
            fixtureGroupID: try c.decodeIfPresent(UUID.self, forKey: .fixtureGroupID),
            selectedTargets: try c.decode([EffectTargetID].self, forKey: .selectedTargets),
            minimumX: minimumX, maximumX: maximumX, minimumY: minimumY, maximumY: maximumY
        )
    }
}

public enum EffectTemplateLinkMode: String, Codable, CaseIterable, Hashable, Sendable {
    case detached, linked
}

/// Static scalar/property fan mapped through the generalized distribution engine.
public struct EffectScalarFanDefinition: Codable, Equatable, Hashable, Sendable {
    public var attribute: String
    public var start: Double
    public var end: Double

    public init(attribute: String = "intensity", start: Double = 0, end: Double = 1) {
        self.attribute = attribute.isEmpty ? "intensity" : attribute
        self.start = min(1, max(0, start.isFinite ? start : 0))
        self.end = min(1, max(0, end.isFinite ? end : 1))
    }

    private enum CodingKeys: String, CodingKey { case attribute, start, end }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let attribute = try c.decode(String.self, forKey: .attribute)
        let start = try c.decode(Double.self, forKey: .start)
        let end = try c.decode(Double.self, forKey: .end)
        guard !attribute.isEmpty, start.isFinite, end.isFinite, (0...1).contains(start), (0...1).contains(end) else {
            throw DecodingError.dataCorruptedError(forKey: .start, in: c, debugDescription: "Scalar fan values must be normalized and have a semantic property")
        }
        self.init(attribute: attribute, start: start, end: end)
    }
}

public struct EffectCellTargetingDefinition: Codable, Equatable, Hashable, Sendable {
    public var mode: EffectCellTargetMode
    public var order: EffectCellOrder
    public var grouping: Int
    public var selectedTargets: [EffectTargetID]

    public init(mode: EffectCellTargetMode = .fixtures, order: EffectCellOrder = .forward, grouping: Int = 1, selectedTargets: [EffectTargetID] = []) {
        self.mode = mode; self.order = order; self.grouping = max(1, grouping); self.selectedTargets = selectedTargets
    }

    private enum CodingKeys: String, CodingKey { case mode, order, grouping, selectedTargets }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let grouping = try container.decode(Int.self, forKey: .grouping)
        guard grouping > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .grouping,
                in: container,
                debugDescription: "Cell grouping must be greater than zero"
            )
        }
        self.init(
            mode: try container.decode(EffectCellTargetMode.self, forKey: .mode),
            order: try container.decode(EffectCellOrder.self, forKey: .order),
            grouping: grouping,
            selectedTargets: try container.decode([EffectTargetID].self, forKey: .selectedTargets)
        )
    }
}

public enum EffectGeneratorShape: String, Codable, CaseIterable, Hashable, Sendable {
    case sine
    case triangle
    case sawUp
    case sawDown
    case ramp
    case square
    case pulse
    case bounce
    case exponential
    case logarithmic
    case smoothstep
    case random
    case smoothNoise
    case customCurve
}

public struct EffectCurvePoint: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var position: Double
    public var value: Double

    public init(id: UUID = UUID(), position: Double, value: Double) {
        self.id = id
        self.position = min(1, max(0, position))
        self.value = min(1, max(0, value))
    }

    private enum CodingKeys: String, CodingKey { case id, position, value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let position = try c.decode(Double.self, forKey: .position)
        let value = try c.decode(Double.self, forKey: .value)
        guard position.isFinite, (0...1).contains(position) else {
            throw DecodingError.dataCorruptedError(forKey: .position, in: c, debugDescription: "Curve position must be within 0...1")
        }
        guard value.isFinite, (0...1).contains(value) else {
            throw DecodingError.dataCorruptedError(forKey: .value, in: c, debugDescription: "Curve value must be within 0...1")
        }
        self.init(id: try c.decode(UUID.self, forKey: .id), position: position, value: value)
    }
}

/// Durable generator settings. Evaluation produces normalized 0...1 output;
/// property mapping owns conversion into semantic ranges and units.
public struct EffectGeneratorDefinition: Codable, Equatable, Hashable, Sendable {
    public var shape: EffectGeneratorShape
    public var dutyCycle: Double
    public var exponent: Double
    public var randomSeed: UInt64
    public var customCurve: [EffectCurvePoint]

    public init(
        shape: EffectGeneratorShape = .sine,
        dutyCycle: Double = 0.5,
        exponent: Double = 2,
        randomSeed: UInt64 = 0,
        customCurve: [EffectCurvePoint] = []
    ) {
        self.shape = shape
        self.dutyCycle = min(0.999, max(0.001, dutyCycle))
        self.exponent = max(0.001, exponent)
        self.randomSeed = randomSeed
        self.customCurve = customCurve
    }

    private enum CodingKeys: String, CodingKey { case shape, dutyCycle, exponent, randomSeed, customCurve }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let dutyCycle = try c.decode(Double.self, forKey: .dutyCycle)
        let exponent = try c.decode(Double.self, forKey: .exponent)
        guard dutyCycle.isFinite, dutyCycle > 0, dutyCycle < 1 else {
            throw DecodingError.dataCorruptedError(forKey: .dutyCycle, in: c, debugDescription: "Duty cycle must be between zero and one")
        }
        guard exponent.isFinite, exponent > 0 else {
            throw DecodingError.dataCorruptedError(forKey: .exponent, in: c, debugDescription: "Generator exponent must be finite and positive")
        }
        self.init(
            shape: try c.decode(EffectGeneratorShape.self, forKey: .shape),
            dutyCycle: dutyCycle,
            exponent: exponent,
            randomSeed: try c.decode(UInt64.self, forKey: .randomSeed),
            customCurve: try c.decode([EffectCurvePoint].self, forKey: .customCurve)
        )
    }
}
