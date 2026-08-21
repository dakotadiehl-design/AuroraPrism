import AuroraEngine
import AuroraModel
import XCTest

final class EffectCellTargetingTests: XCTestCase {
    private let multi = UUID()
    private let single = UUID()

    func testAllCellsExpandsMultiCellAndPreservesFixtureFallbackInMixedSelection() {
        let context = EffectDistributionContext(fixtureElementIDs: [multi: ["cell-0", "cell-1", "cell-2"]])
        let effect = EffectInstance(
            kind: .pattern, rateHz: 0, fixtureIDs: [multi, single], pattern: .init(kind: .alternator),
            cellTargeting: .init(mode: .allCells)
        )
        let compiled = PrismEffectCompiler.compile(effect, context: context)
        XCTAssertEqual(compiled.targets, [
            .init(fixtureID: multi, elementID: "cell-0"), .init(fixtureID: multi, elementID: "cell-1"),
            .init(fixtureID: multi, elementID: "cell-2"), .init(fixtureID: single),
        ])
        let result = PrismEffectEvaluator.evaluate(baseLook: .empty, time: 0, effects: [compiled])
        XCTAssertNotNil(result.semanticLook.fixtureAttributes[multi]?["intensity@0"])
        XCTAssertNotNil(result.semanticLook.fixtureAttributes[multi]?["intensity@1"])
        XCTAssertNotNil(result.semanticLook.fixtureAttributes[multi]?["intensity@2"])
        XCTAssertNotNil(result.semanticLook.fixtureAttributes[single]?["intensity"])
        XCTAssertEqual(result.visualizations[effect.id]?.targets.map(\.target), compiled.targets)
    }

    func testReverseCellOrderAndGroupingCompileBeforeFrameEvaluation() {
        let context = EffectDistributionContext(fixtureElementIDs: [multi: ["cell-0", "cell-1", "cell-2", "cell-3"]])
        let effect = EffectInstance(
            kind: .pattern, fixtureIDs: [multi], distribution: .init(), pattern: .init(),
            cellTargeting: .init(mode: .allCells, order: .reverse, grouping: 2)
        )
        let compiled = PrismEffectCompiler.compile(effect, context: context)
        XCTAssertEqual(compiled.targets.map(\.elementID), ["cell-3", "cell-2", "cell-1", "cell-0"])
        XCTAssertEqual(compiled.resolvedTargets.map(\.distributionPosition), [0, 0, 1, 1])
    }

    func testSelectedCellsFiltersTargetsOutsideFixtureSelection() {
        let foreign = UUID()
        let selected = [EffectTargetID(fixtureID: multi, elementID: "cell-2"), EffectTargetID(fixtureID: foreign, elementID: "cell-0")]
        let effect = EffectInstance(kind: .pattern, fixtureIDs: [multi], pattern: .init(), cellTargeting: .init(mode: .selectedCells, selectedTargets: selected))
        XCTAssertEqual(PrismEffectCompiler.compile(effect).targets, [selected[0]])
    }

    func testCellTargetingRoundTripsDurably() throws {
        let definition = EffectDefinition(
            kind: EffectKind.pattern.rawValue, fixtureIDs: [multi], pattern: .init(kind: .meteor),
            cellTargeting: .init(mode: .selectedCells, order: .reverse, grouping: 4, selectedTargets: [.init(fixtureID: multi, elementID: "cell-1")])
        )
        XCTAssertEqual(try JSONDecoder().decode(EffectDefinition.self, from: JSONEncoder().encode(definition)), definition)
    }

    func testInvalidKnownCellIsIgnoredAndReported() {
        let target = EffectTargetID(fixtureID: multi, elementID: "removed-cell")
        let effect = EffectInstance(
            kind: .pattern, fixtureIDs: [multi], pattern: .init(),
            cellTargeting: .init(mode: .selectedCells, selectedTargets: [target])
        )
        let compiled = PrismEffectCompiler.compile(
            effect,
            context: .init(fixtureElementIDs: [multi: ["cell-0"]])
        )
        XCTAssertTrue(compiled.targets.isEmpty)
        XCTAssertTrue(compiled.compatibilityIssues.contains { $0.id == "cells.empty-selection" && $0.severity == .unsupported })
        XCTAssertTrue(compiled.compatibilityIssues.contains { $0.target == target })
    }

    func testDecodedGroupingMustBePositive() {
        let json = #"{"mode":"allCells","order":"forward","grouping":0,"selectedTargets":[]}"#.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(EffectCellTargetingDefinition.self, from: json))
    }
}
