import AuroraEngine
import AuroraModel
import XCTest

final class EffectGeneratorEvaluatorTests: XCTestCase {
    func testCoreWaveformsAtKnownPhases() {
        XCTAssertEqual(value(.sine, 0), 0.5, accuracy: 1e-9)
        XCTAssertEqual(value(.sine, 0.25), 1, accuracy: 1e-9)
        XCTAssertEqual(value(.triangle, 0.5), 1, accuracy: 1e-9)
        XCTAssertEqual(value(.sawUp, 0.75), 0.75, accuracy: 1e-9)
        XCTAssertEqual(value(.sawDown, 0.75), 0.25, accuracy: 1e-9)
        XCTAssertEqual(value(.square, 0.49), 1)
        XCTAssertEqual(value(.square, 0.5), 0)
        XCTAssertEqual(value(.smoothstep, 0.5), 0.5, accuracy: 1e-9)
    }

    func testPulseDutyCycleAndNegativePhaseWrap() {
        let generator = CompiledEffectGenerator(
            definition: EffectGeneratorDefinition(shape: .pulse, dutyCycle: 0.25)
        )
        XCTAssertEqual(EffectGeneratorEvaluator.value(generator: generator, phase: 0.2), 1)
        XCTAssertEqual(EffectGeneratorEvaluator.value(generator: generator, phase: 0.3), 0)
        XCTAssertEqual(EffectGeneratorEvaluator.value(generator: generator, phase: -0.8), 1)
    }

    func testRandomAndNoiseAreDeterministicAcrossRecompilation() {
        let definition = EffectGeneratorDefinition(shape: .random, randomSeed: 9)
        let a = CompiledEffectGenerator(definition: definition)
        let b = CompiledEffectGenerator(definition: definition)
        XCTAssertEqual(
            EffectGeneratorEvaluator.samples(generator: a, count: 16, startingPhase: -2),
            EffectGeneratorEvaluator.samples(generator: b, count: 16, startingPhase: -2)
        )
        XCTAssertNotEqual(
            EffectGeneratorEvaluator.value(generator: a, phase: 0.2),
            EffectGeneratorEvaluator.value(generator: a, phase: 1.2)
        )

        let noise = CompiledEffectGenerator(definition: EffectGeneratorDefinition(shape: .smoothNoise, randomSeed: 9))
        XCTAssertEqual(
            EffectGeneratorEvaluator.value(generator: noise, phase: 1),
            EffectGeneratorEvaluator.value(generator: noise, phase: 0.999999),
            accuracy: 0.00001
        )
    }

    func testCustomCurveSortsAndInterpolatesAtCompileBoundary() {
        let generator = CompiledEffectGenerator(
            definition: EffectGeneratorDefinition(
                shape: .customCurve,
                customCurve: [
                    EffectCurvePoint(position: 1, value: 0),
                    EffectCurvePoint(position: 0, value: 0.2),
                    EffectCurvePoint(position: 0.5, value: 1),
                ]
            )
        )
        XCTAssertEqual(generator.curvePoints.map(\.position), [0, 0.5, 1])
        XCTAssertEqual(EffectGeneratorEvaluator.value(generator: generator, phase: 0.25), 0.6, accuracy: 1e-9)
        // Phase 1 begins a new cycle and therefore samples the first point.
        XCTAssertEqual(EffectGeneratorEvaluator.value(generator: generator, phase: 1), 0.2, accuracy: 1e-9)
    }

    func testVisualizationSamplesUseTheSameGeneratorFunction() {
        let generator = CompiledEffectGenerator(definition: EffectGeneratorDefinition(shape: .triangle))
        let samples = EffectGeneratorEvaluator.samples(generator: generator, count: 5)
        XCTAssertEqual(samples, [0, 0.5, 1, 0.5, 0])
    }

    private func value(_ shape: EffectGeneratorShape, _ phase: Double) -> Double {
        EffectGeneratorEvaluator.value(
            generator: CompiledEffectGenerator(definition: EffectGeneratorDefinition(shape: shape)),
            phase: phase
        )
    }
}
