import AuroraModel
import CoreGraphics
import Foundation

public struct FixtureGlyphApertureGeometry: Equatable, Sendable, Hashable, Identifiable {
    public var id: String
    public var center: CGPoint
    public var bounds: CGRect
    public var shape: FixtureElementShape
}

public enum FixtureGlyphHitTarget: Equatable, Sendable {
    case physicalElement(String)
    case fixtureBody
}

public struct FixtureGlyphGeometry: Equatable, Sendable {
    public var bodyBounds: CGRect
    public var hitTestBounds: CGRect
    public var apertures: [FixtureGlyphApertureGeometry]
    /// Complete physical topology used for interaction even when visual LOD hides dots.
    public var interactionApertures: [FixtureGlyphApertureGeometry]
    public var headCenters: [CGPoint]
    public var opticalOrigins: [String: CGPoint]
    public var orientationReference: CGPoint
    public var componentBounds: [String: CGRect]

    public func stagePoint(localPoint: CGPoint, fixtureOrigin: CGPoint, rotation: Double) -> CGPoint {
        let localX = Double(localPoint.x - bodyBounds.midX)
        let localY = Double(localPoint.y - bodyBounds.midY)
        let c = cos(rotation), s = sin(rotation)
        return CGPoint(
            x: fixtureOrigin.x + CGFloat(localX * c - localY * s),
            y: fixtureOrigin.y + CGFloat(localX * s + localY * c)
        )
    }

    /// Apertures win over the chassis so Stage can distinguish direct physical
    /// manipulation from whole-fixture selection without knowing DMX semantics.
    public func hitTest(localPoint: CGPoint) -> FixtureGlyphHitTarget? {
        // Dense arrays necessarily have overlapping minimum-size hit regions. Pick
        // the nearest aperture rather than relying on draw order, which otherwise
        // makes the rightmost pixels steal clicks from their neighbours.
        let candidates = interactionApertures.filter { $0.bounds.insetBy(dx: -2, dy: -2).contains(localPoint) }
        if let aperture = candidates.min(by: {
            hypot($0.center.x - localPoint.x, $0.center.y - localPoint.y)
                < hypot($1.center.x - localPoint.x, $1.center.y - localPoint.y)
        }) {
            return .physicalElement(aperture.id)
        }
        return hitTestBounds.contains(localPoint) ? .fixtureBody : nil
    }

}

public enum FixtureGlyphGeometryBuilder {
    public static var cacheBuildCount: Int { FixtureGlyphGeometryCache.shared.buildCount }
    public static func resetCacheForTesting() { FixtureGlyphGeometryCache.shared.reset() }
    public static func build(
        descriptor: FixtureVisualizationDescriptor,
        baseHeight: Double,
        detailLevel: Int
    ) -> FixtureGlyphGeometry {
        FixtureGlyphGeometryCache.shared.value(
            key: "\(descriptor.physicalTopologySignature)#\(descriptor.form.rawValue)#\(Int(baseHeight * 100))#\(detailLevel)"
        ) {
            makeGeometry(descriptor: descriptor, baseHeight: baseHeight, detailLevel: detailLevel)
        }
    }

    private static func makeGeometry(
        descriptor: FixtureVisualizationDescriptor,
        baseHeight: Double,
        detailLevel: Int
    ) -> FixtureGlyphGeometry {
        let canonical = canonicalAspect(form: descriptor.form, descriptorAspect: descriptor.aspectRatio)
        let height = max(20, baseHeight)
        let width = max(20, height * canonical)
        let body = CGRect(x: 0, y: 0, width: width, height: height)
        let indices = Set(FixtureGlyphLevelOfDetail.visibleEmitterIndices(count: descriptor.emitters.count, detailLevel: detailLevel))
        let allApertures = descriptor.emitters.enumerated().map { index, emitter -> FixtureGlyphApertureGeometry in
            let apertureWidth = max(detailLevel == 0 ? 3 : 5, width * emitter.width)
            let apertureHeight = max(detailLevel == 0 ? 3 : 5, height * emitter.height)
            let center = CGPoint(x: width * emitter.x, y: height * emitter.y)
            return FixtureGlyphApertureGeometry(
                id: emitter.id,
                center: center,
                bounds: CGRect(x: center.x - apertureWidth / 2, y: center.y - apertureHeight / 2, width: apertureWidth, height: apertureHeight),
                shape: emitter.shape
            )
        }
        let apertures = allApertures.enumerated().compactMap { indices.contains($0.offset) ? $0.element : nil }
        let allOrigins = Dictionary(uniqueKeysWithValues: descriptor.emitters.map { emitter in
            (emitter.id, CGPoint(x: width * emitter.x, y: height * emitter.y))
        })
        let headIDs = Set(descriptor.componentGroups.filter { $0.role == .movingHead }.flatMap(\.emitterIDs))
        let heads = descriptor.emitters.filter { headIDs.contains($0.id) }.map { CGPoint(x: width * $0.x, y: height * $0.y) }
        let componentBounds = Dictionary(uniqueKeysWithValues: descriptor.componentGroups.map { group in
            let groupWidth = width * group.width
            let groupHeight = height * group.height
            return (group.id, CGRect(x: width * group.x - groupWidth / 2, y: height * group.y - groupHeight / 2, width: groupWidth, height: groupHeight))
        })
        return FixtureGlyphGeometry(
            bodyBounds: body,
            hitTestBounds: body.insetBy(dx: -4, dy: -4),
            apertures: apertures,
            interactionApertures: allApertures,
            headCenters: heads,
            opticalOrigins: allOrigins,
            orientationReference: CGPoint(x: body.midX, y: body.minY),
            componentBounds: componentBounds
        )
    }

    public static func canonicalAspect(form: FixturePhysicalForm, descriptorAspect: Double) -> Double {
        let supplied = descriptorAspect.isFinite ? min(20, max(0.2, descriptorAspect)) : 1
        switch form {
        case .linearBar, .strip: return max(3.2, supplied)
        case .multiHeadBar: return max(3.8, supplied)
        case .panel, .blinder, .strobe: return max(1.2, supplied)
        case .scanner: return max(1.25, supplied)
        default: return supplied
        }
    }
}

private final class FixtureGlyphGeometryCache: @unchecked Sendable {
    static let shared = FixtureGlyphGeometryCache()
    private let lock = NSLock()
    private var values: [String: FixtureGlyphGeometry] = [:]
    private var misses = 0
    var buildCount: Int { lock.lock(); defer { lock.unlock() }; return misses }

    func value(key: String, make: () -> FixtureGlyphGeometry) -> FixtureGlyphGeometry {
        lock.lock()
        if let cached = values[key] { lock.unlock(); return cached }
        lock.unlock()
        let value = make()
        lock.lock()
        misses += 1
        if values.count > 1024 { values.removeAll(keepingCapacity: true) }
        values[key] = value
        lock.unlock()
        return value
    }

    func reset() {
        lock.lock(); values.removeAll(); misses = 0; lock.unlock()
    }
}
