import AuroraModel
import Foundation

public struct CompiledEffectPattern: Equatable, Sendable {
    public let definition: EffectPatternDefinition
    public let previewSamples: [Double]

    public init(definition: EffectPatternDefinition) {
        self.definition = definition
        self.previewSamples = (0..<129).map {
            Self.sample(definition: definition, position: Double($0) / 128, phase: 0).value
        }
    }

    public func sample(position: Double, phase: Double) -> (value: Double, hue: Double?) {
        Self.sample(definition: definition, position: position, phase: phase)
    }

    private static func sample(definition d: EffectPatternDefinition, position: Double, phase: Double) -> (value: Double, hue: Double?) {
        let p = fract(position)
        let t = fract(phase)
        let distance = circularDistance(p, t)
        switch d.kind {
        case .chase:
            return (softPulse(distance: distance, width: d.width, softness: d.softness), nil)
        case .scanner, .bounce:
            let head = 1 - abs(2 * t - 1)
            return (softPulse(distance: abs(p - head), width: d.width, softness: d.softness), nil)
        case .fill:
            return (p <= t ? 1 : 0, nil)
        case .wipe:
            return (softEdge(t - p, softness: d.softness), nil)
        case .rain:
            let slot = Int(floor(phase * 12))
            let chance = random(seed: d.randomSeed, a: quantize(p, 256), b: slot)
            let age = fract(phase * 12)
            return (chance < d.density ? max(0, 1 - age / max(0.001, d.trail)) : 0, nil)
        case .meteor, .comet:
            let behind = fract(t - p)
            let head: Double = behind < d.width ? 1 : 0
            let tail = behind <= d.width ? 1 : (behind < d.width + d.trail ? max(0, 1 - (behind - d.width) / max(0.001, d.trail)) : 0)
            return (max(head, tail), nil)
        case .sparkle, .twinkle:
            let slot = Int(floor(phase * (d.kind == .sparkle ? 24 : 8)))
            let active = random(seed: d.randomSeed, a: quantize(p, 4096), b: slot) < d.density
            let envelope = d.kind == .sparkle ? 1 : 0.5 + 0.5 * sin(fract(phase * 8) * .pi)
            return (active ? envelope : 0, nil)
        case .fire:
            let low = random(seed: d.randomSeed, a: quantize(p, 128), b: Int(floor(phase * 9)))
            let high = random(seed: d.randomSeed ^ 0xF1AE, a: quantize(p, 512), b: Int(floor(phase * 31)))
            return (min(1, 0.25 + low * 0.5 + high * 0.25), 20 + high * 35)
        case .pulseTrain:
            let train = fract(p * max(1, round(1 / d.width)) - t)
            return (train < d.width ? 1 : 0, nil)
        case .theaterChase:
            let index = Int(floor(p * 12))
            let step = Int(floor(phase * 12))
            return (((index + step) % 3) == 0 ? 1 : 0, nil)
        case .randomChase:
            let slot = Int(floor(phase * 8))
            let target = random(seed: d.randomSeed, a: slot, b: 0)
            return (softPulse(distance: circularDistance(p, target), width: d.width, softness: d.softness), nil)
        case .colorRoll, .gradientRoll:
            return (1, fract(p - t) * 360)
        case .colorWipe:
            return (p <= t ? 1 : 0, p <= t ? 0 : 240)
        case .ripple:
            let wave = 0.5 + 0.5 * cos((abs(p - 0.5) * 2 - t) * 8 * .pi)
            return (pow(wave, max(1, 1 / max(0.01, d.softness))), nil)
        case .alternator:
            return ((Int(floor(p * 16)) + Int(floor(phase * 2))) % 2 == 0 ? 1 : 0, nil)
        case .noise:
            let slot = Int(floor(phase * 16))
            let a = random(seed: d.randomSeed, a: quantize(p, 256), b: slot)
            let b = random(seed: d.randomSeed, a: quantize(p, 256), b: slot + 1)
            let amount = smooth(fract(phase * 16))
            return (a + (b - a) * amount, nil)
        case .shimmer:
            let noise = random(seed: d.randomSeed, a: quantize(p, 512), b: Int(floor(phase * 40)))
            return (noise < d.density ? 1 : 0.25, nil)
        }
    }

    private static func softPulse(distance: Double, width: Double, softness: Double) -> Double {
        let half = width * 0.5
        guard distance > half else { return 1 }
        guard softness > 0 else { return 0 }
        return max(0, 1 - (distance - half) / (softness * 0.5))
    }
    private static func softEdge(_ value: Double, softness: Double) -> Double {
        guard softness > 0 else { return value >= 0 ? 1 : 0 }
        return min(1, max(0, value / softness + 0.5))
    }
    private static func circularDistance(_ a: Double, _ b: Double) -> Double { min(abs(a - b), 1 - abs(a - b)) }
    private static func quantize(_ value: Double, _ count: Int) -> Int { min(count - 1, max(0, Int(floor(value * Double(count))))) }
    private static func smooth(_ value: Double) -> Double { value * value * (3 - 2 * value) }
    private static func fract(_ value: Double) -> Double { let f = value - floor(value); return f < 0 ? f + 1 : f }
    private static func random(seed: UInt64, a: Int, b: Int) -> Double {
        var x = seed &+ UInt64(bitPattern: Int64(a)) &* 0x9E3779B97F4A7C15 &+ UInt64(bitPattern: Int64(b))
        x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9
        x = (x ^ (x >> 27)) &* 0x94D049BB133111EB
        x ^= x >> 31
        return Double(x >> 11) / Double(UInt64(1) << 53)
    }
}
