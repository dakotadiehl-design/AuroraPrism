import AuroraEngine
import AuroraModel
import XCTest

final class EffectPatternTests: XCTestCase {
    private let fixtures = (0..<8).map { _ in UUID() }

    func testEveryPatternIsFiniteDeterministicAndBounded() {
        for kind in EffectPatternKind.allCases {
            let definition = EffectPatternDefinition(kind: kind, randomSeed: 42)
            let a = CompiledEffectPattern(definition: definition)
            let b = CompiledEffectPattern(definition: definition)
            XCTAssertEqual(a, b, "\(kind)")
            for index in 0..<64 {
                let sample = a.sample(position: Double(index) / 63, phase: 12.345)
                XCTAssertTrue(sample.value.isFinite, "\(kind)")
                XCTAssertTrue((0...1).contains(sample.value), "\(kind): \(sample.value)")
                XCTAssertTrue(sample.hue?.isFinite ?? true)
            }
        }
    }

    func testPatternUsesCompiledDistributionAndSemanticEvaluator() {
        let effect = EffectInstance(
            kind: .pattern,
            rateHz: 0,
            size: 1,
            fixtureIDs: fixtures,
            timing: .init(source: .freeRun, rate: .frequencyHz(0.001)),
            distribution: .init(order: .selection),
            pattern: .init(kind: .alternator)
        )
        let compiled = PrismEffectCompiler.compile(effect)
        let result = PrismEffectEvaluator.evaluate(baseLook: .empty, time: 0, effects: [compiled])
        let values = compiled.targets.map { result.semanticLook.fixtureAttributes[$0.fixtureID]?["intensity"] ?? -1 }
        XCTAssertTrue(values.contains(0))
        XCTAssertTrue(values.contains(1))
        XCTAssertEqual(result.visualizations[effect.id]?.targets.map(\.value), values.map(Optional.some))
    }

    func testColorPatternWritesSemanticRGB() {
        let effect = EffectInstance(kind: .pattern, rateHz: 0, fixtureIDs: [fixtures[0]], pattern: .init(kind: .colorRoll))
        let result = PrismEffectEvaluator.evaluate(baseLook: .empty, time: 0, effects: [PrismEffectCompiler.compile(effect)])
        XCTAssertNotNil(result.semanticLook.fixtureAttributes[fixtures[0]]?["colorR"])
        XCTAssertNotNil(result.semanticLook.fixtureAttributes[fixtures[0]]?["colorG"])
        XCTAssertNotNil(result.semanticLook.fixtureAttributes[fixtures[0]]?["colorB"])
    }

    func testPatternRoundTripsDurably() throws {
        let definition = EffectDefinition(kind: EffectKind.pattern.rawValue, fixtureIDs: fixtures, pattern: .init(kind: .meteor, randomSeed: 99))
        XCTAssertEqual(try JSONDecoder().decode(EffectDefinition.self, from: JSONEncoder().encode(definition)), definition)
    }
}
