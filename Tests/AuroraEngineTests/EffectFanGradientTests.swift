import AuroraEngine
import AuroraModel
import XCTest

final class EffectFanGradientTests: XCTestCase {
    private let a = UUID(uuidString: "50000000-0000-4000-8000-000000000001")!
    private let b = UUID(uuidString: "50000000-0000-4000-8000-000000000002")!
    private let c = UUID(uuidString: "50000000-0000-4000-8000-000000000003")!

    func testColorGradientUsesResolvedFanPositionsForSemanticRGB() {
        let gradient = EffectColorGradientDefinition(
            stops: [
                .init(position: 0, color: .init(red: 0, green: 0, blue: 1)),
                .init(position: 1, color: .init(red: 1, green: 0, blue: 0)),
            ],
            interpolation: .rgb
        )
        let effect = EffectInstance(
            kind: .colorGradient,
            rateHz: 0,
            fixtureIDs: [a, b, c],
            distribution: .init(order: .selection),
            colorGradient: gradient
        )
        let result = PrismEffectEvaluator.evaluate(baseLook: .empty, time: 0, effects: [PrismEffectCompiler.compile(effect)])
        XCTAssertEqual(result.semanticLook.fixtureAttributes[a]?["colorB"], 1)
        XCTAssertEqual(result.semanticLook.fixtureAttributes[b]?["colorR"] ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(result.semanticLook.fixtureAttributes[b]?["colorB"] ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(result.semanticLook.fixtureAttributes[c]?["colorR"], 1)
    }

    func testHueShortestPathPassesThroughMagentaNotGreen() {
        let gradient = CompiledEffectColorGradient(.init(
            stops: [
                .init(position: 0, color: .init(red: 1, green: 0, blue: 0)),
                .init(position: 1, color: .init(red: 0, green: 0, blue: 1)),
            ],
            interpolation: .hsvShortest
        ))!
        let midpoint = EffectColorGradientEvaluator.color(at: 0.5, gradient: gradient)
        XCTAssertGreaterThan(midpoint.r, 0.9)
        XCTAssertGreaterThan(midpoint.b, 0.9)
        XCTAssertLessThan(midpoint.g, 0.1)
    }

    func testFixtureNumberDMXRadialAndAngularOrdersUseCompilationContext() {
        let targets = [a, b, c].map { EffectTargetID(fixtureID: $0) }
        let context = EffectDistributionContext(
            stagePlacements: [
                .init(fixtureID: a, x: 0, y: 0),
                .init(fixtureID: b, x: 10, y: 0),
                .init(fixtureID: c, x: 0, y: 10),
            ],
            fixtureNumbers: [a: 3, b: 1, c: 2],
            dmxAddresses: [a: 1, b: 100, c: 50]
        )
        XCTAssertEqual(EffectDistributionResolver.resolve(targets: targets, definition: .init(order: .fixtureNumber), context: context).map(\.target.fixtureID), [b, c, a])
        XCTAssertEqual(EffectDistributionResolver.resolve(targets: targets, definition: .init(order: .dmxAddress), context: context).map(\.target.fixtureID), [a, c, b])
        XCTAssertEqual(Set(EffectDistributionResolver.resolve(targets: targets, definition: .init(order: .spatialRadial), context: context).map(\.target.fixtureID)), Set([a, b, c]))
        XCTAssertEqual(Set(EffectDistributionResolver.resolve(targets: targets, definition: .init(order: .spatialAngular), context: context).map(\.target.fixtureID)), Set([a, b, c]))
    }

    func testDistributionCurveTransformsCompiledPositions() {
        let targets = [a, b, c].map { EffectTargetID(fixtureID: $0) }
        let result = EffectDistributionResolver.resolve(
            targets: targets,
            definition: .init(curve: .easeIn),
            stagePlacements: []
        )
        XCTAssertEqual(result.map(\.distributionPosition), [0, 0.25, 1])
    }

    func testGradientAndFanRoundTripDurably() throws {
        let effect = EffectDefinition(
            kind: EffectKind.colorGradient.rawValue,
            fixtureIDs: [a, b],
            distribution: .init(order: .random, grouping: 2, repetitions: 3, symmetry: .mirror, randomSeed: 99, curve: .easeInOut),
            colorGradient: .init(interpolation: .hsvClockwise, reversed: true, mirrored: true, positionOffset: 0.25)
        )
        let decoded = try JSONDecoder().decode(EffectDefinition.self, from: JSONEncoder().encode(effect))
        XCTAssertEqual(decoded, effect)
    }

    func testPaletteLinkedStopResolvesAtCompilationAndMissingPaletteUsesFallback() {
        let paletteID = UUID()
        let stop = EffectGradientStop(position: 0, color: .init(red: 1, green: 0, blue: 0), paletteID: paletteID)
        let effect = EffectInstance(kind: .colorGradient, fixtureIDs: [a], colorGradient: .init(stops: [stop]))
        let resolved = PrismEffectCompiler.compile(effect, context: .init(paletteColors: [paletteID: .init(red: 0, green: 1, blue: 0)]))
        let resolvedLook = PrismEffectEvaluator.evaluate(baseLook: .empty, time: 0, effects: [resolved]).semanticLook
        XCTAssertEqual(resolvedLook.fixtureAttributes[a]?["colorG"], 1)
        let missing = PrismEffectCompiler.compile(effect)
        XCTAssertTrue(missing.compatibilityIssues.contains { $0.id.hasPrefix("gradient.missing-palette") })
        let fallbackLook = PrismEffectEvaluator.evaluate(baseLook: .empty, time: 0, effects: [missing]).semanticLook
        XCTAssertEqual(fallbackLook.fixtureAttributes[a]?["colorR"], 1)
    }

    func testScalarFanUsesTheSameResolvedDistributionAndRoundTrips() throws {
        let effect = EffectInstance(
            kind: .wave, fixtureIDs: [a, b, c],
            distribution: .init(order: .selection, curve: .easeIn),
            scalarFan: .init(attribute: "zoom", start: 0.2, end: 0.8)
        )
        let compiled = PrismEffectCompiler.compile(effect)
        let result = PrismEffectEvaluator.evaluate(baseLook: .empty, time: 999, effects: [compiled])
        XCTAssertEqual(result.semanticLook.fixtureAttributes[a]?["zoom"] ?? -1, 0.2, accuracy: 1e-12)
        XCTAssertEqual(result.semanticLook.fixtureAttributes[b]?["zoom"] ?? -1, 0.35, accuracy: 1e-12)
        XCTAssertEqual(result.semanticLook.fixtureAttributes[c]?["zoom"] ?? -1, 0.8, accuracy: 1e-12)
        let visualValues = result.visualizations[effect.id]?.targets.compactMap(\.value) ?? []
        XCTAssertEqual(visualValues.count, 3)
        for (actual, expected) in zip(visualValues, [0.2, 0.35, 0.8]) { XCTAssertEqual(actual, expected, accuracy: 1e-12) }
        XCTAssertEqual(try JSONDecoder().decode(EffectDefinition.self, from: JSONEncoder().encode(effect.asDefinition())), effect.asDefinition())
    }
}
