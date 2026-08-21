import AuroraEngine
import AuroraModel
import XCTest

final class EffectMovementTests: XCTestCase {
    private let a = UUID(uuidString: "60000000-0000-4000-8000-000000000001")!
    private let b = UUID(uuidString: "60000000-0000-4000-8000-000000000002")!

    func testRelativeMovementOrbitsEachFixturesOwnFocus() {
        let movement = EffectMovementDefinition(template: .circle, coordinateMode: .relative, width: 0.2, height: 0.2)
        let effect = EffectInstance(kind: .movement, rateHz: 0, fixtureIDs: [a, b], movement: movement)
        var base = ActiveLook.empty
        base.set(fixtureID: a, attribute: "pan", value: 0.2)
        base.set(fixtureID: a, attribute: "tilt", value: 0.3)
        base.set(fixtureID: b, attribute: "pan", value: 0.7)
        base.set(fixtureID: b, attribute: "tilt", value: 0.8)
        let result = PrismEffectEvaluator.evaluate(baseLook: base, time: 0, effects: [PrismEffectCompiler.compile(effect)])
        XCTAssertEqual(result.semanticLook.fixtureAttributes[a]?["pan"] ?? -1, 0.3, accuracy: 1e-9)
        XCTAssertEqual(result.semanticLook.fixtureAttributes[b]?["pan"] ?? -1, 0.8, accuracy: 1e-9)
        XCTAssertEqual(result.semanticLook.fixtureAttributes[a]?["tilt"] ?? -1, 0.3, accuracy: 1e-9)
        XCTAssertEqual(result.semanticLook.fixtureAttributes[b]?["tilt"] ?? -1, 0.8, accuracy: 1e-9)
    }

    func testAbsoluteMovementUsesCommonConfiguredCenter() {
        let movement = EffectMovementDefinition(template: .verticalSweep, coordinateMode: .absolute, centerPan: 0.4, centerTilt: 0.6, width: 0, height: 0.2)
        let effect = EffectInstance(kind: .movement, rateHz: 0, fixtureIDs: [a], movement: movement)
        var base = ActiveLook.empty
        base.set(fixtureID: a, attribute: "pan", value: 0.9)
        base.set(fixtureID: a, attribute: "tilt", value: 0.9)
        let result = PrismEffectEvaluator.evaluate(baseLook: base, time: 0, effects: [PrismEffectCompiler.compile(effect)])
        XCTAssertEqual(result.semanticLook.fixtureAttributes[a]?["pan"] ?? -1, 0.4, accuracy: 1e-9)
        XCTAssertEqual(result.semanticLook.fixtureAttributes[a]?["tilt"] ?? -1, 0.5, accuracy: 1e-9)
    }

    func testMovementTemplatesAreFiniteAndBounded() {
        for template in EffectMovementTemplate.allCases where template != .customPath {
            let compiled = CompiledEffectMovement(definition: .init(template: template, randomSeed: 42))
            XCTAssertEqual(compiled.pathSamples.count, 129)
            XCTAssertTrue(compiled.pathSamples.allSatisfy { $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 0.5 && abs($0.y) <= 0.5 }, "\(template)")
        }
    }

    func testCustomPathInterpolationAndVisualizationUseCompiledPath() {
        let definition = EffectMovementDefinition(
            template: .customPath,
            interpolation: .linear,
            coordinateMode: .absolute,
            width: 1,
            height: 1,
            customPath: [.init(x: -1, y: 0), .init(x: 1, y: 0)]
        )
        let effect = EffectInstance(kind: .movement, rateHz: 1, fixtureIDs: [a], movement: definition)
        let compiled = PrismEffectCompiler.compile(effect)
        let result = PrismEffectEvaluator.evaluate(baseLook: .empty, time: 0.125, effects: [compiled])
        XCTAssertEqual(result.semanticLook.fixtureAttributes[a]?["pan"] ?? -1, 0.25, accuracy: 1e-9)
        XCTAssertEqual(result.visualizations[effect.id]?.movementPathSamples, compiled.movement?.pathSamples)
    }

    func testMovementDefinitionRoundTrips() throws {
        let definition = EffectDefinition(
            kind: EffectKind.movement.rawValue,
            fixtureIDs: [a],
            movement: .init(template: .figureEight, interpolation: .smooth, coordinateMode: .relative, rotation: 0.25, mirrorPan: true)
        )
        XCTAssertEqual(try JSONDecoder().decode(EffectDefinition.self, from: JSONEncoder().encode(definition)), definition)
    }

    func testEmptyCustomPathIsUnsupportedAndDoesNotWritePanTilt() {
        let effect = EffectInstance(
            kind: .movement,
            fixtureIDs: [a],
            movement: .init(template: .customPath, coordinateMode: .absolute, customPath: [])
        )
        let compiled = PrismEffectCompiler.compile(effect)
        XCTAssertNil(compiled.movement)
        XCTAssertNil(compiled.propertyMapping)
        XCTAssertTrue(compiled.compatibilityIssues.contains { $0.id == "movement.empty-path" })
        let result = PrismEffectEvaluator.evaluate(baseLook: .empty, time: 0, effects: [compiled])
        XCTAssertNil(result.semanticLook.fixtureAttributes[a]?["pan"])
        XCTAssertNil(result.semanticLook.fixtureAttributes[a]?["tilt"])
    }

    func testCompiledPathsCloseAtRuntimeLoopBoundary() {
        for template in EffectMovementTemplate.allCases where template != .customPath {
            let movement = CompiledEffectMovement(definition: .init(template: template, randomSeed: 7))
            XCTAssertEqual(movement.pathSamples.first, movement.pathSamples.last, "\(template)")
            XCTAssertEqual(movement.point(at: 0), movement.point(at: 1), "\(template)")
        }
        let custom = CompiledEffectMovement(definition: .init(
            template: .customPath,
            customPath: [.init(x: -1, y: 0), .init(x: 1, y: 0)]
        ))
        XCTAssertEqual(custom.pathSamples.first, custom.pathSamples.last)
    }

    func testArcIsContinuousAcrossLoopBoundary() {
        let movement = CompiledEffectMovement(definition: .init(template: .arc, width: 1, height: 1))
        let beforeWrap = movement.point(at: 1 - 1e-6)
        let afterWrap = movement.point(at: 1e-6)
        XCTAssertEqual(beforeWrap.x, afterWrap.x, accuracy: 1e-4)
        XCTAssertEqual(beforeWrap.y, afterWrap.y, accuracy: 1e-4)
    }

    func testVisualizationPublishesActualEvaluatedPanTilt() {
        let effect = EffectInstance(
            kind: .movement,
            rateHz: 0,
            fixtureIDs: [a],
            movement: .init(template: .circle, coordinateMode: .absolute, centerPan: 0.4, centerTilt: 0.6, width: 0.2, height: 0.2)
        )
        let result = PrismEffectEvaluator.evaluate(baseLook: .empty, time: 0, effects: [PrismEffectCompiler.compile(effect)])
        let target = result.visualizations[effect.id]?.targets.first
        XCTAssertEqual(target?.pan, result.semanticLook.fixtureAttributes[a]?["pan"])
        XCTAssertEqual(target?.tilt, result.semanticLook.fixtureAttributes[a]?["tilt"])
    }

    func testMovementHasStableAutomationParameterDescriptors() {
        let effect = EffectInstance(kind: .movement, fixtureIDs: [a], movement: .init())
        let ids = Set(PrismEffectCompiler.compile(effect).parameterDescriptors.map(\.id))
        XCTAssertTrue(ids.isSuperset(of: [.movementSize, .movementWidth, .movementHeight, .movementRotation, .movementCenterPan, .movementCenterTilt]))
    }

    func testRelativeCellMovementUsesThatCellsSemanticBase() {
        let target = EffectTargetID(fixtureID: a, elementID: "cell-1")
        let effect = EffectInstance(
            kind: .movement, rateHz: 0, fixtureIDs: [a],
            movement: .init(template: .horizontalSweep, coordinateMode: .relative, width: 0.2, height: 0),
            cellTargeting: .init(mode: .selectedCells, selectedTargets: [target])
        )
        let base = ActiveLook(fixtureAttributes: [a: ["pan@1": 0.25, "tilt@1": 0.75]])
        let result = PrismEffectEvaluator.evaluate(baseLook: base, time: 0, effects: [PrismEffectCompiler.compile(effect)])
        XCTAssertEqual(result.semanticLook.fixtureAttributes[a]?["pan@1"] ?? -1, 0.15, accuracy: 1e-12)
        XCTAssertEqual(result.semanticLook.fixtureAttributes[a]?["tilt@1"] ?? -1, 0.75, accuracy: 1e-12)
    }

    func testInvalidPersistedMovementCoordinatesAreRejected() throws {
        let point = EffectMovementPoint(x: 0, y: 0)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(point)) as? [String: Any])
        object["x"] = 2.0
        XCTAssertThrowsError(try JSONDecoder().decode(EffectMovementPoint.self, from: JSONSerialization.data(withJSONObject: object)))
    }
}
