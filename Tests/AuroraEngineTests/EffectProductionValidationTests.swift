import AuroraEngine
import AuroraModel
import AuroraOutput
import XCTest

final class EffectProductionValidationTests: XCTestCase {
    func testSemanticFixtureMatrixCoversDimmerRGBMoverAndMultiCell() {
        let dimmer = UUID(), rgb = UUID(), mover = UUID(), pixel = UUID()
        let effects: [EffectInstance] = [
            .init(kind: .wave, rateHz: 0, size: 0, fixtureIDs: [dimmer], generator: .init(shape: .square), base: 0.7),
            .init(kind: .colorGradient, rateHz: 0, size: 1, fixtureIDs: [rgb], colorGradient: .init(stops: [
                .init(position: 0, color: .init(red: 0.2, green: 0.4, blue: 0.8)),
            ])),
            .init(kind: .movement, rateHz: 0, fixtureIDs: [mover], movement: .init(template: .circle, width: 0.2, height: 0.2)),
            .init(kind: .pattern, rateHz: 0, fixtureIDs: [pixel], pattern: .init(kind: .alternator), cellTargeting: .init(mode: .allCells)),
        ]
        let context = EffectDistributionContext(fixtureElementIDs: [pixel: ["cell-0", "cell-1", "cell-2", "cell-3"]])
        let result = PrismEffectEvaluator.evaluate(baseLook: .empty, time: 0, effects: effects.map { PrismEffectCompiler.compile($0, context: context) })
        XCTAssertEqual(result.semanticLook.fixtureAttributes[dimmer]?["intensity"] ?? -1, 0.7, accuracy: 0.0001)
        XCTAssertEqual(result.semanticLook.fixtureAttributes[rgb]?["colorR"] ?? -1, 0.2, accuracy: 0.0001)
        XCTAssertEqual(result.semanticLook.fixtureAttributes[rgb]?["colorG"] ?? -1, 0.4, accuracy: 0.0001)
        XCTAssertEqual(result.semanticLook.fixtureAttributes[rgb]?["colorB"] ?? -1, 0.8, accuracy: 0.0001)
        XCTAssertNotNil(result.semanticLook.fixtureAttributes[mover]?["pan"])
        XCTAssertNotNil(result.semanticLook.fixtureAttributes[mover]?["tilt"])
        for cell in 0..<4 { XCTAssertNotNil(result.semanticLook.fixtureAttributes[pixel]?["intensity@\(cell)"]) }
        XCTAssertEqual(Set(result.visualizations.keys), Set(effects.map(\.id)))
    }

    func testPrivatePreviewCannotMutateLiveEffectStack() {
        let engine = LightingEngine(output: OutputManager())
        engine.load(project: .empty(name: "Preview Safety"))
        let fixture = UUID()
        let live = EffectInstance(name: "Live", kind: .wave, fixtureIDs: [fixture])
        engine.effects.upsert(live)
        let before = engine.effects.exportDefinitions()
        let draft = EffectInstance(name: "Draft", kind: .pattern, fixtureIDs: [fixture], pattern: .init(kind: .fire))

        let result = engine.evaluateEffectPreview(draft, time: 42)

        XCTAssertFalse(result.semanticLook.fixtureAttributes.isEmpty)
        XCTAssertEqual(engine.effects.exportDefinitions(), before)
        XCTAssertNil(engine.effects.latestEvaluationResult(), "Private evaluation must not publish itself as a live frame")
    }

    func testLongRunDeterminismAndPhaseStability() {
        let fixtures = (0..<256).map { _ in UUID() }
        let effect = EffectInstance(
            kind: .pattern, rateHz: 7.25, size: 1, phase: 0.137, spread: 1,
            fixtureIDs: fixtures, distribution: .init(order: .random, randomSeed: 0xA0_70_2A),
            pattern: .init(kind: .sparkle, density: 0.3, randomSeed: 0xFACADE)
        )
        let compiled = PrismEffectCompiler.compile(effect)
        let requestedMinutes = ProcessInfo.processInfo.environment["PRISM_EFFECT_SOAK_MINUTES"].flatMap(Double.init) ?? 0
        let deadline = Date().addingTimeInterval(requestedMinutes * 60)
        let minimumFrames = requestedMinutes > 0 ? 0 : 10_000
        var frame = 0
        var checksum = 0.0
        repeat {
            let time = Double(frame) / 44.0
            let first = PrismEffectEvaluator.evaluate(baseLook: .empty, time: time, effects: [compiled])
            let second = PrismEffectEvaluator.evaluate(baseLook: .empty, time: time, effects: [compiled])
            XCTAssertEqual(first, second)
            for attributes in first.semanticLook.fixtureAttributes.values {
                for value in attributes.values { XCTAssertTrue(value.isFinite); checksum += value }
            }
            frame += 1
        } while frame < minimumFrames || Date() < deadline
        XCTAssertGreaterThan(checksum, 0)
    }
}
