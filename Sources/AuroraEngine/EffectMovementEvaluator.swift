import AuroraModel
import Foundation

public struct CompiledEffectMovement: Equatable, Sendable {
    private static let runtimePointID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    public let definition: EffectMovementDefinition
    public let pathSamples: [EffectMovementPoint]

    public init(definition: EffectMovementDefinition) {
        self.definition = definition
        self.pathSamples = (0..<129).map { index in
            let phase = index == 128 ? 0 : Double(index) / 128
            return Self.transformed(
                Self.rawPoint(template: definition.template, phase: phase, definition: definition),
                definition: definition
            )
        }
    }

    public func point(at phase: Double) -> EffectMovementPoint {
        Self.transformed(Self.rawPoint(template: definition.template, phase: fract(phase), definition: definition), definition: definition)
    }

    private static func transformed(_ raw: EffectMovementPoint, definition: EffectMovementDefinition) -> EffectMovementPoint {
        let angle = definition.rotation * 2 * .pi
        let scaledX = raw.x * definition.width * 0.5 * (definition.mirrorPan ? -1 : 1)
        let scaledY = raw.y * definition.height * 0.5 * (definition.mirrorTilt ? -1 : 1)
        return runtimePoint(
            x: scaledX * cos(angle) - scaledY * sin(angle),
            y: scaledX * sin(angle) + scaledY * cos(angle)
        )
    }

    private static func rawPoint(template: EffectMovementTemplate, phase: Double, definition: EffectMovementDefinition) -> EffectMovementPoint {
        let angle = phase * 2 * Double.pi
        switch template {
        case .circle, .ellipse: return runtimePoint(x: cos(angle), y: sin(angle))
        case .figureEight: return runtimePoint(x: sin(angle), y: sin(angle * 2))
        case .diamond: return polygon(vertices: [(-1, 0), (0, -1), (1, 0), (0, 1)], phase: phase, interpolation: definition.interpolation)
        case .square: return polygon(vertices: [(-1, -1), (1, -1), (1, 1), (-1, 1)], phase: phase, interpolation: definition.interpolation)
        case .triangle: return polygon(vertices: [(0, -1), (1, 1), (-1, 1)], phase: phase, interpolation: definition.interpolation)
        case .horizontalSweep: return runtimePoint(x: triangle(phase), y: 0)
        case .verticalSweep: return runtimePoint(x: 0, y: triangle(phase))
        case .diagonalSweep: let value = triangle(phase); return runtimePoint(x: value, y: value)
        case .arc:
            let progress = (triangle(phase) + 1) * 0.5
            return runtimePoint(x: cos(.pi * (1 + progress)), y: sin(.pi * (1 + progress)))
        case .fanSweep: return runtimePoint(x: triangle(phase), y: -abs(triangle(phase)))
        case .randomWander:
            return interpolatedRandom(phase: phase, seed: definition.randomSeed, interpolation: definition.interpolation)
        case .customPath:
            return custom(definition.customPath, phase: phase, interpolation: definition.interpolation)
        }
    }

    private static func polygon(vertices: [(Double, Double)], phase: Double, interpolation: EffectMovementInterpolation) -> EffectMovementPoint {
        custom(vertices.map { runtimePoint(x: $0.0, y: $0.1) }, phase: phase, interpolation: interpolation)
    }

    private static func custom(_ points: [EffectMovementPoint], phase: Double, interpolation: EffectMovementInterpolation) -> EffectMovementPoint {
        guard let first = points.first else { return runtimePoint(x: 0, y: 0) }
        guard points.count > 1 else { return runtimePoint(x: first.x, y: first.y) }
        let scaled = phase * Double(points.count)
        let index = min(points.count - 1, Int(floor(scaled)))
        let next = (index + 1) % points.count
        var amount = scaled - floor(scaled)
        if interpolation == .step { amount = 0 }
        if interpolation == .smooth { amount = amount * amount * (3 - 2 * amount) }
        return runtimePoint(
            x: points[index].x + (points[next].x - points[index].x) * amount,
            y: points[index].y + (points[next].y - points[index].y) * amount
        )
    }

    private static func interpolatedRandom(phase: Double, seed: UInt64, interpolation: EffectMovementInterpolation) -> EffectMovementPoint {
        let count = 16
        let points = (0..<count).map { index -> EffectMovementPoint in
            var value = seed &+ UInt64(index) &* 0x9E3779B97F4A7C15
            value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
            let x = Double(value & 0xffff) / 32767.5 - 1
            value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
            let y = Double(value & 0xffff) / 32767.5 - 1
            return runtimePoint(x: x, y: y)
        }
        return custom(points, phase: phase, interpolation: interpolation)
    }

    private static func triangle(_ phase: Double) -> Double { 1 - 4 * abs(phase - 0.5) }
    private static func runtimePoint(x: Double, y: Double) -> EffectMovementPoint {
        EffectMovementPoint(id: runtimePointID, x: x, y: y)
    }
    private func fract(_ value: Double) -> Double { Self.fract(value) }
    private static func fract(_ value: Double) -> Double {
        let result = value - floor(value)
        return result < 0 ? result + 1 : result
    }
}
