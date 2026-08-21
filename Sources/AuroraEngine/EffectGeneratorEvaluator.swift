import AuroraModel
import Foundation

public struct CompiledEffectGenerator: Equatable, Sendable {
    public let definition: EffectGeneratorDefinition
    public let curvePoints: [EffectCurvePoint]

    public init(definition: EffectGeneratorDefinition) {
        self.definition = definition
        let sorted = definition.customCurve.sorted {
            if $0.position != $1.position { return $0.position < $1.position }
            return $0.id.uuidString < $1.id.uuidString
        }
        var merged: [EffectCurvePoint] = []
        var mergedCounts: [Int] = []
        for point in sorted {
            if let last = merged.last, last.position == point.position {
                let priorCount = mergedCounts[mergedCounts.count - 1]
                merged[merged.count - 1].value = (last.value * Double(priorCount) + point.value) / Double(priorCount + 1)
                mergedCounts[mergedCounts.count - 1] = priorCount + 1
            } else {
                merged.append(point)
                mergedCounts.append(1)
            }
        }
        self.curvePoints = merged
    }
}

/// Pure normalized generator math shared by output evaluation and visual sampling.
public enum EffectGeneratorEvaluator {
    public static func value(generator: CompiledEffectGenerator, phase: Double) -> Double {
        let cycle = floor(phase)
        let x = fract(phase)
        let definition = generator.definition
        switch definition.shape {
        case .sine:
            return 0.5 + 0.5 * sin(2 * Double.pi * x)
        case .triangle:
            return 1 - abs(2 * x - 1)
        case .sawUp, .ramp:
            return x
        case .sawDown:
            return 1 - x
        case .square:
            return x < 0.5 ? 1 : 0
        case .pulse:
            return x < definition.dutyCycle ? 1 : 0
        case .bounce:
            return abs(sin(Double.pi * x))
        case .exponential:
            return pow(x, definition.exponent)
        case .logarithmic:
            let exponent = definition.exponent
            return log1p(x * exponent) / log1p(exponent)
        case .smoothstep:
            return x * x * (3 - 2 * x)
        case .random:
            return unitRandom(seed: definition.randomSeed, index: Int64(cycle))
        case .smoothNoise:
            let index = Int64(cycle)
            let left = unitRandom(seed: definition.randomSeed, index: index)
            let right = unitRandom(seed: definition.randomSeed, index: index &+ 1)
            let eased = x * x * (3 - 2 * x)
            return left + (right - left) * eased
        case .customCurve:
            return customCurveValue(points: generator.curvePoints, position: x)
        }
    }

    public static func samples(
        generator: CompiledEffectGenerator,
        count: Int,
        startingPhase: Double = 0
    ) -> [Double] {
        let count = max(2, count)
        return (0..<count).map { index in
            value(generator: generator, phase: startingPhase + Double(index) / Double(count - 1))
        }
    }

    private static func customCurveValue(points: [EffectCurvePoint], position: Double) -> Double {
        guard let first = points.first else { return position }
        if position <= first.position { return first.value }
        guard let last = points.last, position < last.position else { return points.last?.value ?? position }
        for index in 1..<points.count where position <= points[index].position {
            let left = points[index - 1]
            let right = points[index]
            let span = right.position - left.position
            guard span > 0 else { return right.value }
            let amount = (position - left.position) / span
            return left.value + (right.value - left.value) * amount
        }
        return last.value
    }

    private static func unitRandom(seed: UInt64, index: Int64) -> Double {
        var value = seed &+ UInt64(bitPattern: index) &* 0x9E3779B97F4A7C15
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return Double(value >> 11) / Double(UInt64(1) << 53)
    }

    private static func fract(_ value: Double) -> Double {
        let fraction = value - floor(value)
        return fraction < 0 ? fraction + 1 : fraction
    }
}
