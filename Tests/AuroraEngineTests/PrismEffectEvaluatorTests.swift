import AuroraEngine
import AuroraModel
import XCTest

final class PrismEffectEvaluatorTests: XCTestCase {
    private let f1 = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    private let f2 = UUID(uuidString: "10000000-0000-4000-8000-000000000002")!

    func testStableParameterIDsRoundTripWithoutDisplayNames() throws {
        let id = EffectParameterID.gradientPosition
        let data = try JSONEncoder().encode(id)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "\"gradient.position\"")
        XCTAssertEqual(try JSONDecoder().decode(EffectParameterID.self, from: data), id)
    }

    func testLegacyCompilerPreservesFixtureOrderAndFrequency() {
        let source = EffectInstance(
            kind: .wave,
            rateHz: 1.75,
            size: 0.5,
            spread: 0.25,
            fixtureIDs: [f2, f1]
        )
        let compiled = PrismEffectCompiler.compileLegacy(source)
        XCTAssertEqual(compiled.source.rateHz, 1.75)
        XCTAssertEqual(compiled.targets.map(\.fixtureID), [f2, f1])
        XCTAssertTrue(compiled.parameterDescriptors.contains { $0.id == .speed })
        XCTAssertTrue(compiled.parameterDescriptors.contains { $0.id == .spread })
    }

    func testVisualizationMetadataMatchesEvaluatedSemanticValue() throws {
        let source = EffectInstance(
            kind: .wave,
            rateHz: 0,
            size: 1,
            phase: 0,
            spread: 0.25,
            attribute: "intensity",
            fixtureIDs: [f1, f2]
        )
        let result = PrismEffectEvaluator.evaluate(
            baseLook: .empty,
            time: 0,
            effects: [PrismEffectCompiler.compileLegacy(source)]
        )

        let visualization = try XCTUnwrap(result.visualizations[source.id])
        XCTAssertEqual(visualization.targets.count, 2)
        XCTAssertEqual(visualization.targets[0].distributionPosition, 0)
        XCTAssertEqual(visualization.targets[1].distributionPosition, 1)
        XCTAssertEqual(visualization.targets[1].phase, 0.25)
        let visualValue = try XCTUnwrap(visualization.targets[1].value)
        XCTAssertEqual(visualValue, 1, accuracy: 1e-9)
        XCTAssertEqual(
            result.semanticLook.fixtureAttributes[f2]?["intensity"] ?? -1,
            visualValue,
            accuracy: 1e-9
        )
    }

    func testCellChaseMetadataAndSemanticOutputShareOneEvaluation() throws {
        let source = EffectInstance(
            kind: .cellChase,
            rateHz: 0,
            size: 0.8,
            attribute: "colorR",
            fixtureIDs: [f1],
            cellCount: 4
        )
        let result = PrismEffectEvaluator.evaluate(
            baseLook: .empty,
            time: 0,
            effects: [PrismEffectCompiler.compileLegacy(source)]
        )

        XCTAssertEqual(result.semanticLook.fixtureAttributes[f1]?["colorR@0"], 0.8)
        XCTAssertEqual(result.semanticLook.fixtureAttributes[f1]?["colorR@1"], 0)
        XCTAssertEqual(try XCTUnwrap(result.visualizations[source.id]).targets[0].value, 0)
    }

    func testRunnerCompilesOnMutationAndRetainsStableSnapshotForFrames() {
        let runner = EffectRunner()
        var source = EffectInstance(id: f1, kind: .pulse, rateHz: 2, fixtureIDs: [f1])
        runner.upsert(source)
        XCTAssertEqual(runner.compiledSnapshot().first?.source.rateHz, 2)

        source.rateHz = 3
        runner.upsert(source)
        XCTAssertEqual(runner.compiledSnapshot().first?.source.rateHz, 3)
        XCTAssertEqual(runner.compiledSnapshot().first?.targets.map(\.fixtureID), [f1])
    }

    func testResolvedDistributionPositionDrivesSemanticPhase() throws {
        let source = EffectInstance(
            kind: .wave,
            rateHz: 0,
            size: 1,
            spread: 0.25,
            attribute: "intensity",
            fixtureIDs: [f1, f2]
        )
        let compiled = CompiledPrismEffect(
            source: source,
            resolvedTargets: [
                ResolvedEffectTarget(target: EffectTargetID(fixtureID: f1), orderIndex: 0, distributionPosition: 0),
                // Deliberately non-linear: index position would be 1, resolved fan position is 0.5.
                ResolvedEffectTarget(target: EffectTargetID(fixtureID: f2), orderIndex: 1, distributionPosition: 0.5),
            ],
            parameterDescriptors: []
        )
        let result = PrismEffectEvaluator.evaluateOrdered(baseLook: .empty, time: 0, effects: [compiled])
        let expected = sin(2 * Double.pi * 0.125)
        XCTAssertEqual(result.semanticLook.fixtureAttributes[f2]?["intensity"] ?? -1, expected, accuracy: 1e-9)
        XCTAssertEqual(
            try XCTUnwrap(result.visualizations[source.id]).targets[1].phase,
            0.125,
            accuracy: 1e-9
        )
    }

    func testCanonicalCellIdentityProducesExistingConcreteAttributeConvention() {
        let source = EffectInstance(
            kind: .wave,
            rateHz: 0,
            size: 1,
            phase: 0.25,
            attribute: "intensity",
            fixtureIDs: [f1]
        )
        let compiled = CompiledPrismEffect(
            source: source,
            resolvedTargets: [
                ResolvedEffectTarget(
                    target: EffectTargetID(FixtureTarget.cell(fixtureID: f1, index: 3)),
                    orderIndex: 0,
                    distributionPosition: 0
                ),
            ],
            parameterDescriptors: []
        )
        let result = PrismEffectEvaluator.evaluateOrdered(baseLook: .empty, time: 0, effects: [compiled])
        XCTAssertEqual(result.semanticLook.fixtureAttributes[f1]?["intensity@3"], 1)
        XCTAssertNil(result.semanticLook.fixtureAttributes[f1]?["intensity@cell-3"])
    }

    func testRunnerPublishesAuthoritativeVisualizationResult() throws {
        let runner = EffectRunner()
        let source = EffectInstance(kind: .wave, rateHz: 0, size: 1, phase: 0.25, fixtureIDs: [f1])
        runner.upsert(source)
        _ = runner.apply(on: .empty, time: 0)
        let result = try XCTUnwrap(runner.latestEvaluationResult())
        XCTAssertEqual(result.semanticLook.fixtureAttributes[f1]?["intensity"], 1)
        XCTAssertEqual(try XCTUnwrap(result.visualizations[source.id]).targets[0].value, 1)
    }

    func testDisabledEffectsAreRemovedFromCompiledFrameStack() {
        let runner = EffectRunner()
        let source = EffectInstance(id: f1, kind: .wave, fixtureIDs: [f1])
        runner.upsert(source)
        XCTAssertEqual(runner.compiledSnapshot().count, 1)
        runner.setEnabled(id: f1, enabled: false)
        XCTAssertTrue(runner.compiledSnapshot().isEmpty)
    }

    func testReverseSingleFixturePreservesLegacyZeroSpreadPosition() {
        let source = EffectInstance(
            kind: .wave,
            rateHz: 0,
            size: 1,
            spread: 0.25,
            fixtureIDs: [f1],
            direction: -1
        )
        let compiled = PrismEffectCompiler.compileLegacy(source)
        XCTAssertEqual(compiled.resolvedTargets.first?.distributionPosition, 0)
        let result = PrismEffectEvaluator.evaluateOrdered(baseLook: .empty, time: 0, effects: [compiled])
        XCTAssertEqual(result.semanticLook.fixtureAttributes[f1]?["intensity"], 0)
    }

    func testEmptyRunnerClearsStaleVisualizationSnapshot() throws {
        let runner = EffectRunner()
        let source = EffectInstance(kind: .wave, phase: 0.25, fixtureIDs: [f1])
        runner.upsert(source)
        _ = runner.apply(on: .empty, time: 0)
        runner.remove(id: source.id)
        _ = runner.apply(on: .empty, time: 0)
        XCTAssertTrue(try XCTUnwrap(runner.latestEvaluationResult()).visualizations.isEmpty)
    }
}
