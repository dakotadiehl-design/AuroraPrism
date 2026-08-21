import AuroraEngine
import AuroraModel
import AuroraOutput
import XCTest

final class EffectCurveIntensityTests: XCTestCase {
    private let fixture = UUID(uuidString: "40000000-0000-4000-8000-000000000001")!

    func testEveryFX4ShapeMapsGeneratorIntoIntensity() throws {
        let cases: [(EffectGeneratorShape, Double, Double)] = [
            (.sine, 0, 0.5),
            (.triangle, 0.5, 1),
            (.sawUp, 0.25, 0.25),
            (.sawDown, 0.25, 0.75),
            (.square, 0.25, 1),
            (.pulse, 0.75, 0),
        ]
        for (shape, phase, expected) in cases {
            let effect = curveEffect(shape: shape, phase: phase)
            let result = PrismEffectEvaluator.evaluate(baseLook: .empty, time: 0, effects: [PrismEffectCompiler.compile(effect)])
            XCTAssertEqual(try XCTUnwrap(result.semanticLook.fixtureAttributes[fixture]?["intensity"]), expected, accuracy: 1e-12, "shape: \(shape)")
            XCTAssertEqual(try XCTUnwrap(try XCTUnwrap(result.visualizations[effect.id]).targets.first?.value), expected, accuracy: 1e-12)
        }
    }

    func testBaseAndAmplitudeMapNormalizedGeneratorWithoutLegacyBipolarMath() {
        var effect = curveEffect(shape: .sawUp, phase: 0.5)
        effect.base = 0.2
        effect.size = 0.4
        let result = PrismEffectEvaluator.evaluate(baseLook: .empty, time: 0, effects: [PrismEffectCompiler.compile(effect)])
        XCTAssertEqual(try XCTUnwrap(result.semanticLook.fixtureAttributes[fixture]?["intensity"]), 0.4, accuracy: 1e-12)
    }

    func testCustomCurveCompilesOnceAndDrivesOutputAndWaveform() throws {
        var effect = curveEffect(shape: .customCurve, phase: 0.5)
        effect.generator?.customCurve = [
            .init(position: 0, value: 0.1),
            .init(position: 0.5, value: 0.8),
            .init(position: 1, value: 0.2),
        ]
        let compiled = PrismEffectCompiler.compile(effect)
        let result = PrismEffectEvaluator.evaluate(baseLook: .empty, time: 0, effects: [compiled])
        let metadata = try XCTUnwrap(result.visualizations[effect.id])
        XCTAssertEqual(try XCTUnwrap(result.semanticLook.fixtureAttributes[fixture]?["intensity"]), 0.8, accuracy: 1e-12)
        XCTAssertEqual(metadata.waveformSamples.count, 129)
        XCTAssertEqual(metadata.waveformSamples[64], 0.8, accuracy: 1e-12)
    }

    func testDistributionPhaseUsesCompiledGeneratorForEachFixture() throws {
        let second = UUID(uuidString: "40000000-0000-4000-8000-000000000002")!
        var effect = curveEffect(shape: .sawUp, phase: 0)
        effect.fixtureIDs = [fixture, second]
        effect.spread = 0.5
        let result = PrismEffectEvaluator.evaluate(baseLook: .empty, time: 0, effects: [PrismEffectCompiler.compile(effect)])
        XCTAssertEqual(try XCTUnwrap(result.semanticLook.fixtureAttributes[fixture]?["intensity"]), 0, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(result.semanticLook.fixtureAttributes[second]?["intensity"]), 0.5, accuracy: 1e-12)
    }

    func testFX4DefinitionRoundTripsAndLegacyDefinitionDefaultsRemainNil() throws {
        let effect = curveEffect(shape: .triangle, phase: 0.2)
        let definition = effect.asDefinition()
        let data = try JSONEncoder().encode(definition)
        let decoded = try JSONDecoder().decode(EffectDefinition.self, from: data)
        XCTAssertEqual(decoded, definition)
        XCTAssertEqual(EffectInstance(definition: decoded), effect)

        let legacyJSON = Data(#"{"id":"40000000-0000-4000-8000-000000000001","kind":"wave","fixtureIDs":[]}"#.utf8)
        let legacy = try JSONDecoder().decode(EffectDefinition.self, from: legacyJSON)
        XCTAssertNil(legacy.generator)
        XCTAssertNil(legacy.timing)
        XCTAssertNil(legacy.distribution)
        XCTAssertEqual(legacy.base, 0)
    }

    func testRunnerCompilesFX4DefinitionsOnLoad() {
        let effect = curveEffect(shape: .square, phase: 0.25)
        let runner = EffectRunner()
        runner.load(definitions: [effect.asDefinition()])
        XCTAssertEqual(runner.compiledSnapshot().first?.generator?.definition.shape, .square)
        XCTAssertEqual(runner.compiledSnapshot().first?.waveformSamples.count, 129)
    }

    func testFX2TimingSampleDrivesFX4GeneratorInsteadOfLegacyRate() throws {
        var effect = curveEffect(shape: .sawUp, phase: 0)
        effect.rateHz = 99
        effect.timing = EffectTimingDefinition(source: .freeRun, rate: .frequencyHz(1))
        let compiled = PrismEffectCompiler.compile(effect)
        let coordinator = EffectTimingCoordinator()
        _ = coordinator.samples(for: [compiled], clocks: [:], monotonicTime: 0)
        let timing = coordinator.samples(for: [compiled], clocks: [:], monotonicTime: 0.5)
        let result = PrismEffectEvaluator.evaluateOrdered(
            baseLook: .empty,
            context: .init(legacyTime: 10, timingSamples: timing),
            effects: [compiled]
        )
        XCTAssertEqual(try XCTUnwrap(result.semanticLook.fixtureAttributes[fixture]?["intensity"]), 0.5, accuracy: 1e-12)
    }

    func testInvalidPersistedGeneratorAndCurvePointAreRejected() {
        let invalidGenerator = Data(#"{"shape":"pulse","dutyCycle":0,"exponent":2,"randomSeed":0,"customCurve":[]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(EffectGeneratorDefinition.self, from: invalidGenerator))
        let invalidPoint = Data(#"{"id":"40000000-0000-4000-8000-000000000001","position":1.5,"value":0.5}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(EffectCurvePoint.self, from: invalidPoint))
    }

    func testDuplicateCurvePositionsMergeByDeterministicAverage() {
        let generator = CompiledEffectGenerator(definition: .init(shape: .customCurve, customCurve: [
            .init(id: UUID(uuidString: "40000000-0000-4000-8000-000000000001")!, position: 0.5, value: 0.2),
            .init(id: UUID(uuidString: "40000000-0000-4000-8000-000000000002")!, position: 0.5, value: 0.8),
        ]))
        XCTAssertEqual(generator.curvePoints.count, 1)
        XCTAssertEqual(generator.curvePoints[0].value, 0.5, accuracy: 1e-12)
    }

    func testUnsupportedFamilyAndPropertyDoNotWriteSemanticOutput() {
        var effect = curveEffect(shape: .sine, phase: 0.25)
        effect.kind = .rainbow
        effect.attribute = "gobo"
        let compiled = PrismEffectCompiler.compile(effect)
        XCTAssertTrue(compiled.compatibilityIssues.contains { $0.severity == .unsupported })
        let base = ActiveLook(fixtureAttributes: [fixture: ["intensity": 0.3]])
        let result = PrismEffectEvaluator.evaluate(baseLook: base, time: 0, effects: [compiled])
        XCTAssertEqual(result.semanticLook, base)
    }

    func testWaveformMetadataCarriesReverseDirectionAndPlayhead() throws {
        var effect = curveEffect(shape: .sawUp, phase: 0)
        effect.direction = -1
        let compiled = PrismEffectCompiler.compile(effect)
        let timing = EffectTimingSample(phase: 0.25, status: .running, sourceID: "test", meter: nil)
        let result = PrismEffectEvaluator.evaluateOrdered(
            baseLook: .empty,
            context: .init(legacyTime: 0, timingSamples: [effect.id: timing]),
            effects: [compiled]
        )
        let metadata = try XCTUnwrap(result.visualizations[effect.id])
        XCTAssertEqual(metadata.waveformDirection, -1)
        XCTAssertEqual(metadata.playheadPhase, 0.75, accuracy: 1e-12)
        XCTAssertEqual(metadata.timingStatus, .running)
    }

    func testPreviewUsesInjectedClockProviderAndMatchesSemanticTiming() throws {
        var effect = curveEffect(shape: .sawUp, phase: 0)
        effect.timing = EffectTimingDefinition(
            source: .musicEngine,
            rate: .musical(.init(unit: .note, noteDivision: .quarter))
        )
        let engine = LightingEngine(output: OutputManager())
        engine.setEffectClockSnapshotProvider { time in
            [.musicEngine: EffectClockSnapshot(
                source: .musicEngine,
                sourceID: "music",
                monotonicTime: time,
                tempoBPM: 120,
                quarterNotePosition: time,
                meter: EffectMusicalMeter(numerator: 4, denominator: 4)
            )]
        }
        _ = engine.evaluateEffectPreview(effect, time: 0)
        let result = engine.evaluateEffectPreview(effect, time: 0.5)
        XCTAssertEqual(try XCTUnwrap(result.semanticLook.fixtureAttributes[fixture]?["intensity"]), 0.5, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(result.visualizations[effect.id]).clockSourceID, "music")
    }

    func testRunnerEvaluatesExactCompiledFrameSnapshotAfterConcurrentEdit() throws {
        let runner = EffectRunner()
        var effect = curveEffect(shape: .sawUp, phase: 0)
        runner.upsert(effect)
        let frameStack = runner.compiledSnapshot()
        effect.generator = EffectGeneratorDefinition(shape: .square)
        runner.upsert(effect)
        let timing = EffectTimingSample(phase: 0.25, status: .running, sourceID: "frame", meter: nil)
        let look = runner.apply(
            on: .empty,
            context: .init(legacyTime: 0, timingSamples: [effect.id: timing]),
            compiledEffects: frameStack
        )
        XCTAssertEqual(try XCTUnwrap(look.fixtureAttributes[fixture]?["intensity"]), 0.25, accuracy: 1e-12)
    }

    private func curveEffect(shape: EffectGeneratorShape, phase: Double) -> EffectInstance {
        EffectInstance(
            name: "FX-4 Test",
            kind: .wave,
            rateHz: 0,
            size: 1,
            phase: phase,
            spread: 0,
            attribute: "intensity",
            fixtureIDs: [fixture],
            generator: EffectGeneratorDefinition(shape: shape),
            timing: EffectTimingDefinition(source: .freeRun, rate: .frequencyHz(0)),
            distribution: FixtureDistributionDefinition(order: .selection),
            base: 0
        )
    }
}
