import AuroraEngine
import AuroraModel
import XCTest

final class EffectDistributionResolverTests: XCTestCase {
    private let a = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
    private let b = UUID(uuidString: "20000000-0000-4000-8000-000000000002")!
    private let c = UUID(uuidString: "20000000-0000-4000-8000-000000000003")!
    private let d = UUID(uuidString: "20000000-0000-4000-8000-000000000004")!

    private var targets: [EffectTargetID] { [a, b, c, d].map { EffectTargetID(fixtureID: $0) } }
    private var placements: [StageFixturePlacement] {
        [
            StageFixturePlacement(fixtureID: a, x: 30, y: 0),
            StageFixturePlacement(fixtureID: b, x: -30, y: 30),
            StageFixturePlacement(fixtureID: c, x: 10, y: -20),
            StageFixturePlacement(fixtureID: d, x: -10, y: 10),
        ]
    }

    func testStageLeftToRightUsesCoordinatesNotSelectionOrder() {
        let result = EffectDistributionResolver.resolve(
            targets: targets,
            definition: FixtureDistributionDefinition(order: .stageLeftToRight),
            stagePlacements: placements
        )
        XCTAssertEqual(result.map(\.target.fixtureID), [b, d, c, a])
        XCTAssertEqual(result.map(\.distributionPosition), [0, 1.0 / 3.0, 2.0 / 3.0, 1])
    }

    func testFreezeCurrentSpatialOrderSurvivesLaterStageMoves() {
        let dynamic = FixtureDistributionDefinition(order: .stageLeftToRight)
        let frozen = EffectDistributionResolver.freezeCurrentSpatialOrder(
            targets: targets,
            definition: dynamic,
            stagePlacements: placements
        )
        let moved = placements.map { placement -> StageFixturePlacement in
            var copy = placement
            copy.x = -copy.x
            return copy
        }
        let result = EffectDistributionResolver.resolve(targets: targets, definition: frozen, stagePlacements: moved)
        XCTAssertEqual(result.map(\.target.fixtureID), [b, d, c, a])
    }

    func testCenterOutAndOutsideInAreDeterministicForEvenCounts() {
        let center = EffectDistributionResolver.resolve(
            targets: targets,
            definition: FixtureDistributionDefinition(order: .centerOut),
            stagePlacements: placements
        )
        let outside = EffectDistributionResolver.resolve(
            targets: targets,
            definition: FixtureDistributionDefinition(order: .outsideIn),
            stagePlacements: placements
        )
        XCTAssertEqual(center.map(\.target.fixtureID), [d, c, b, a])
        XCTAssertEqual(outside.map(\.target.fixtureID), [b, a, d, c])
    }

    func testGroupingAndMirrorProduceSharedSymmetricPositions() {
        let result = EffectDistributionResolver.resolve(
            targets: targets,
            definition: FixtureDistributionDefinition(grouping: 2, symmetry: .mirror),
            stagePlacements: []
        )
        XCTAssertEqual(result.map(\.distributionPosition), [1, 1, 1, 1])

        let ungrouped = EffectDistributionResolver.resolve(
            targets: targets,
            definition: FixtureDistributionDefinition(symmetry: .mirror),
            stagePlacements: []
        )
        XCTAssertEqual(ungrouped[0].distributionPosition, 1)
        XCTAssertEqual(ungrouped[1].distributionPosition, 1.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(ungrouped[2].distributionPosition, 1.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(ungrouped[3].distributionPosition, 1)
    }

    func testRandomOrderIsSeededAndIncludesCellsIndependently() {
        let cellTargets = targets + [EffectTargetID(fixtureID: a, cellID: "1")]
        let definition = FixtureDistributionDefinition(order: .random, randomSeed: 42)
        let first = EffectDistributionResolver.resolve(targets: cellTargets, definition: definition, stagePlacements: [])
        let second = EffectDistributionResolver.resolve(targets: cellTargets, definition: definition, stagePlacements: [])
        XCTAssertEqual(first, second)
        XCTAssertEqual(Set(first.map(\.target)), Set(cellTargets))
    }

    func testCustomOrderAppendsNewEligibleTargetsWithoutLosingIntent() {
        let definition = FixtureDistributionDefinition(
            order: .custom,
            customOrder: [EffectTargetID(fixtureID: c), EffectTargetID(fixtureID: a)]
        )
        let result = EffectDistributionResolver.resolve(targets: targets, definition: definition, stagePlacements: [])
        XCTAssertEqual(result.map(\.target.fixtureID), [c, a, b, d])
    }
}

