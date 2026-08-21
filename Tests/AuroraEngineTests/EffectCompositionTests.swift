import AuroraEngine
import AuroraModel
import XCTest

final class EffectCompositionTests: XCTestCase {
    private let fixture = UUID()

    func testLightingBlendModesAndAmountComposeInStackOrder() {
        let base = ActiveLook(fixtureAttributes: [fixture: ["intensity": 0.4]])
        func effect(_ mode: EffectBlendMode, amount: Double = 1, value: Double) -> CompiledPrismEffect {
            PrismEffectCompiler.compile(.init(
                kind: .wave, rateHz: 0, size: 0, fixtureIDs: [fixture], generator: .init(shape: .square),
                base: value, blendMode: mode, blendAmount: amount
            ))
        }
        XCTAssertEqual(evaluate(base, [effect(.replace, value: 0.6)]), 0.6, accuracy: 0.0001)
        XCTAssertEqual(evaluate(base, [effect(.add, value: 0.6)]), 1, accuracy: 0.0001)
        XCTAssertEqual(evaluate(base, [effect(.multiply, value: 0.5)]), 0.2, accuracy: 0.0001)
        XCTAssertEqual(evaluate(base, [effect(.maximum, value: 0.7)]), 0.7, accuracy: 0.0001)
        XCTAssertEqual(evaluate(base, [effect(.minimum, value: 0.2)]), 0.2, accuracy: 0.0001)
        XCTAssertEqual(evaluate(base, [effect(.replace, amount: 0.5, value: 0.8)]), 0.6, accuracy: 0.0001)
    }

    func testMaskIsAppliedAfterDynamicOrdering() {
        let left = UUID(), middle = UUID(), right = UUID()
        let effect = EffectInstance(
            kind: .pattern, fixtureIDs: [right, left, middle],
            distribution: .init(order: .stageLeftToRight), pattern: .init(), mask: .init(kind: .edges)
        )
        let context = EffectDistributionContext(stagePlacements: [
            .init(fixtureID: left, x: -10, y: 0), .init(fixtureID: middle, x: 0, y: 0), .init(fixtureID: right, x: 10, y: 0),
        ])
        XCTAssertEqual(PrismEffectCompiler.compile(effect, context: context).targets, [.init(fixtureID: left), .init(fixtureID: right)])
    }

    func testLinkedInstanceResolvesCreativeValuesAndDetachFreezesThem() {
        let runner = EffectRunner()
        let template = EffectInstance(name: "Reusable", kind: .pattern, size: 0.73, fixtureIDs: [fixture], pattern: .init(kind: .meteor))
        runner.upsert(template)
        let linkedID = runner.createLinkedInstance(templateID: template.id, fixtureIDs: [fixture])!
        XCTAssertEqual(runner.compiledSnapshot().first { $0.id == linkedID }?.source.size, 0.73)

        var edited = template
        edited.size = 0.31
        runner.upsert(edited)
        XCTAssertEqual(runner.compiledSnapshot().first { $0.id == linkedID }?.source.size, 0.31)

        runner.detachTemplate(id: linkedID)
        edited.size = 0.9
        runner.upsert(edited)
        let detached = runner.snapshot().first { $0.id == linkedID }
        XCTAssertEqual(detached?.size, 0.31)
        XCTAssertEqual(detached?.templateLinkMode, .detached)
        XCTAssertNil(detached?.templateEffectID)
    }

    func testMissingAndCyclicTemplatesAreUnsupported() {
        let missingID = UUID()
        let linked = EffectInstance(templateEffectID: missingID, templateLinkMode: .linked)
        let missing = PrismEffectCompiler.compile(linked)
        XCTAssertTrue(missing.compatibilityIssues.contains { $0.id.hasPrefix("template.missing") })
        XCTAssertTrue(missing.targets.isEmpty, "Broken links must not silently evaluate their stale embedded snapshot")

        var a = EffectInstance(name: "A")
        var b = EffectInstance(name: "B")
        a.templateEffectID = b.id; a.templateLinkMode = .linked
        b.templateEffectID = a.id; b.templateLinkMode = .linked
        let context = EffectDistributionContext(templateEffects: [a.id: a, b.id: b])
        let cyclic = PrismEffectCompiler.compile(a, context: context)
        XCTAssertTrue(cyclic.compatibilityIssues.contains { $0.id == "template.cycle" })
        XCTAssertTrue(cyclic.targets.isEmpty)
    }

    func testCompositionMetadataRoundTrips() throws {
        let definition = EffectDefinition(
            blendMode: .multiply, blendAmount: 0.42, mask: .init(kind: .everyNth, everyNth: 3),
            templateEffectID: UUID(), templateLinkMode: .linked, isFavorite: true
        )
        XCTAssertEqual(try JSONDecoder().decode(EffectDefinition.self, from: JSONEncoder().encode(definition)), definition)
    }

    func testInvalidMaskPersistenceIsRejected() {
        let json = #"{"kind":"everyNth","everyNth":0,"selectedTargets":[],"minimumX":0,"maximumX":1,"minimumY":0,"maximumY":1}"#.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(EffectMaskDefinition.self, from: json))
    }

    func testFixtureGroupMaskResolvesAtCompilation() {
        let member = UUID(), excluded = UUID(), group = UUID()
        let effect = EffectInstance(
            kind: .pattern, fixtureIDs: [member, excluded], pattern: .init(),
            mask: .init(kind: .fixtureGroup, fixtureGroupID: group)
        )
        let compiled = PrismEffectCompiler.compile(effect, context: .init(fixtureGroups: [group: [member]]))
        XCTAssertEqual(compiled.targets, [.init(fixtureID: member)])
        XCTAssertFalse(compiled.compatibilityIssues.contains { $0.id == "mask.missing-group" })
    }

    private func evaluate(_ base: ActiveLook, _ effects: [CompiledPrismEffect]) -> Double {
        PrismEffectEvaluator.evaluate(baseLook: base, time: 0, effects: effects).semanticLook.fixtureAttributes[fixture]?["intensity"] ?? -1
    }
}
