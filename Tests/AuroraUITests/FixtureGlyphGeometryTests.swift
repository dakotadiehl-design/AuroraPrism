import AuroraModel
import AuroraUI
import CoreGraphics
import XCTest

final class FixtureGlyphGeometryTests: XCTestCase {
    func testRendererStylesShareTheSameSemanticGeometryContract() {
        let descriptor = linearDescriptor(count: 4)
        let geometry = FixtureGlyphGeometryBuilder.build(descriptor: descriptor, baseHeight: 40, detailLevel: 2)
        for _ in StageGlyphStyle.allCases {
            XCTAssertEqual(geometry.interactionApertures.map(\.id), descriptor.emitters.map(\.id))
            XCTAssertEqual(geometry.opticalOrigins.count, descriptor.emitters.count)
            XCTAssertEqual(geometry.interactionApertures.map(\.center), descriptor.emitters.map {
                CGPoint(x: geometry.bodyBounds.width * $0.x, y: geometry.bodyBounds.height * $0.y)
            })
        }
    }

    func testBeamOriginsAreExactlyGlyphApertureCenters() {
        let descriptor = linearDescriptor(count: 12)
        let geometry = FixtureGlyphGeometryBuilder.build(descriptor: descriptor, baseHeight: 40, detailLevel: 2)
        XCTAssertEqual(geometry.apertures.count, 12)
        for aperture in geometry.apertures {
            XCTAssertEqual(geometry.opticalOrigins[aperture.id], aperture.center)
            XCTAssertTrue(geometry.bodyBounds.contains(aperture.center))
        }
        XCTAssertTrue(geometry.hitTestBounds.contains(geometry.bodyBounds))
    }

    func testRotationTransformsOpticalOriginAtRequiredAngles() {
        let descriptor = linearDescriptor(count: 2)
        let geometry = FixtureGlyphGeometryBuilder.build(descriptor: descriptor, baseHeight: 40, detailLevel: 2)
        let local = try! XCTUnwrap(geometry.opticalOrigins["e0"])
        let origin = CGPoint(x: 100, y: 100)
        for degrees in [0.0, 45, 90, 180, 31.75] {
            let radians = degrees * .pi / 180
            let transformed = geometry.stagePoint(localPoint: local, fixtureOrigin: origin, rotation: radians)
            let dx = Double(local.x - geometry.bodyBounds.midX)
            let dy = Double(local.y - geometry.bodyBounds.midY)
            XCTAssertEqual(Double(transformed.x), 100 + dx * cos(radians) - dy * sin(radians), accuracy: 0.0001)
            XCTAssertEqual(Double(transformed.y), 100 + dx * sin(radians) + dy * cos(radians), accuracy: 0.0001)
        }
    }

    func testSubElementHitTestingPrecedesFixtureBody() throws {
        let geometry = FixtureGlyphGeometryBuilder.build(descriptor: linearDescriptor(count: 4), baseHeight: 40, detailLevel: 2)
        let aperture = try XCTUnwrap(geometry.apertures.first)
        XCTAssertEqual(geometry.hitTest(localPoint: aperture.center), .physicalElement(aperture.id))
        XCTAssertEqual(geometry.hitTest(localPoint: CGPoint(x: geometry.bodyBounds.midX, y: geometry.bodyBounds.minY + 1)), .fixtureBody)
        XCTAssertNil(geometry.hitTest(localPoint: CGPoint(x: geometry.hitTestBounds.maxX + 10, y: geometry.hitTestBounds.maxY + 10)))
    }

    func testCanonicalGeometrySnapshots() {
        let snapshots: [(String, FixtureVisualizationDescriptor, String)] = [
            ("par", descriptor(form: .par, topology: .single, positions: [(0.5, 0.5)]), "40x40|a1|h0"),
            ("bar12", linearDescriptor(count: 12), "128x40|a12|h0"),
            ("blinder2x4", gridDescriptor(form: .blinder, rows: 2, columns: 4), "48x40|a8|h0"),
            ("variableRows", descriptor(form: .strobe, topology: .variableRows, positions: [(0.25,0.25),(0.75,0.25),(0.17,0.75),(0.5,0.75),(0.83,0.75)]), "48x40|a5|h0"),
            ("movingWash", descriptor(form: .movingHead, topology: .single, positions: [(0.5,0.42)], movement: .panTilt), "40x40|a1|h0"),
            ("movingSpot", descriptor(form: .movingHead, topology: .single, positions: [(0.5,0.42)], movement: .panTilt), "40x40|a1|h0"),
            ("scanner", descriptor(form: .scanner, topology: .single, positions: [(0.5,0.5)], movement: .scannerMirror), "50x40|a1|h0"),
            ("multiHead", multiHeadDescriptor(), "152x40|a4|h4"),
            ("ring", ringDescriptor(count: 12), "40x40|a12|h0"),
            ("hybrid", hybridDescriptor(), "40x40|a13|h0"),
            ("atmospheric", descriptor(form: .atmospheric, topology: .noBeam, positions: []), "40x40|a0|h0"),
        ]
        for (name, descriptor, expected) in snapshots {
            let geometry = FixtureGlyphGeometryBuilder.build(descriptor: descriptor, baseHeight: 40, detailLevel: 2)
            let actual = "\(Int(geometry.bodyBounds.width.rounded()))x\(Int(geometry.bodyBounds.height.rounded()))|a\(geometry.apertures.count)|h\(geometry.headCenters.count)"
            XCTAssertEqual(actual, expected, name)
        }
    }

    func testDenseLODGeometryPreservesTopologyHintAndFullOpticalOrigins() {
        let descriptor = linearDescriptor(count: 100)
        let small = FixtureGlyphGeometryBuilder.build(descriptor: descriptor, baseHeight: 20, detailLevel: 0)
        let medium = FixtureGlyphGeometryBuilder.build(descriptor: descriptor, baseHeight: 40, detailLevel: 1)
        let large = FixtureGlyphGeometryBuilder.build(descriptor: descriptor, baseHeight: 80, detailLevel: 2)
        XCTAssertEqual(small.apertures.count, 8)
        XCTAssertEqual(medium.apertures.count, 24)
        XCTAssertEqual(large.apertures.count, 100)
        XCTAssertEqual(small.opticalOrigins.count, 100, "LOD must not discard physical beam origins")
        XCTAssertEqual(small.interactionApertures.count, 100, "LOD must not discard selectable physical emitters")
        for aperture in small.interactionApertures {
            XCTAssertEqual(small.hitTest(localPoint: aperture.center), .physicalElement(aperture.id))
        }
    }

    func testLargeStageReusesStaticGeometryInsteadOfRecomputingPerFrame() {
        let descriptor = linearDescriptor(count: 100)
        FixtureGlyphGeometryBuilder.resetCacheForTesting()
        for _ in 0..<10_000 {
            _ = FixtureGlyphGeometryBuilder.build(descriptor: descriptor, baseHeight: 40, detailLevel: 1)
        }
        XCTAssertEqual(FixtureGlyphGeometryBuilder.cacheBuildCount, 1)
    }

    func testSuppliedPrismCorpusResolvesToSemanticallyDistinctGlyphs() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let project = try ProjectPackage.load(from: repository.appendingPathComponent("smoketest files/Test Show.prism"))
        let expected: [String: FixturePhysicalForm] = [
            "COLORado PXL Curve 12": .linearBar,
            "COLORband Q3BT ILS": .linearBar,
            "Jolt Bar FX": .strobe,
            "4Bar Hex ILS": .multiHeadBar,
            "Intimidator Scan 360": .scanner,
            "Rogue R1X Wash": .movingHead,
            "Rogue R1 FX-B": .multiHeadBar,
        ]
        for (model, form) in expected {
            let definition = try XCTUnwrap(project.fixtureDefinitions.first(where: { $0.model == model }), model)
            let descriptor = definition.resolvedVisualization(physical: project.physicalFixture(for: definition))
            XCTAssertEqual(descriptor.form, form, model)
            let geometry = FixtureGlyphGeometryBuilder.build(descriptor: descriptor, baseHeight: 40, detailLevel: 2)
            if [.linearBar, .multiHeadBar].contains(form) { XCTAssertGreaterThan(geometry.bodyBounds.width, geometry.bodyBounds.height * 3, model) }
            if model == "4Bar Hex ILS" { XCTAssertEqual(geometry.apertures.count, 4) }
            if model == "COLORband Q3BT ILS" { XCTAssertEqual(geometry.apertures.count, 12) }
        }
    }

    func testSuppliedFourBarPersonalitiesResolvePhysicalClicksHonestly() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let project = try ProjectPackage.load(from: repository.appendingPathComponent("smoketest files/Test Show.prism"))
        let modes = project.fixtureDefinitions.filter { $0.model == "4Bar Hex ILS" }
        let pixel = try XCTUnwrap(modes.first { $0.modeName == "27 Channel" })
        let basic = try XCTUnwrap(modes.first { $0.modeName == "6 Channel" })
        let descriptor = project.visualizationDescriptor(for: pixel)
        let emitterID = try XCTUnwrap(descriptor.emitters.first?.id)
        XCTAssertEqual(
            FixturePhysicalControlMapper.resolve(physicalEmitterID: emitterID, descriptor: descriptor, definition: pixel).disposition,
            .controls(["cell-0"])
        )
        XCTAssertEqual(
            FixturePhysicalControlMapper.resolve(physicalEmitterID: emitterID, descriptor: project.visualizationDescriptor(for: basic), definition: basic).disposition,
            .wholeFixture
        )

        let grouped = try XCTUnwrap(project.fixtureDefinitions.first { $0.model == "4Bar Flex Q" })
        let groupedDescriptor = project.visualizationDescriptor(for: grouped)
        let groupedID = try XCTUnwrap(groupedDescriptor.emitters.first?.id)
        let groupedResult = FixturePhysicalControlMapper.resolve(physicalEmitterID: groupedID, descriptor: groupedDescriptor, definition: grouped)
        XCTAssertEqual(groupedResult.affectedPhysicalEmitterIDs.count, 4)
        XCTAssertFalse(groupedResult.independentlyControllable)
    }

    func testEveryPlacedControllableArrayInTestShowHasSelectablePhysicalTargets() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let project = try ProjectPackage.load(from: repository.appendingPathComponent("smoketest files/Test Show.prism"))
        for placement in project.stageLayout.fixtures {
            guard let fixture = project.fixtures.first(where: { $0.id == placement.fixtureID }),
                  let definition = project.definition(id: fixture.definitionId)
            else { continue }
            let descriptor = project.visualizationDescriptor(for: definition)
            guard descriptor.emitters.count > 1,
                  !definition.controlElements.isEmpty || definition.elements.count > 1
            else { continue }
            let geometry = FixtureGlyphGeometryBuilder.build(descriptor: descriptor, baseHeight: 36, detailLevel: 2)
            XCTAssertEqual(geometry.interactionApertures.count, descriptor.emitters.count, fixture.name)
            let controlled = descriptor.emitters.filter { emitter in
                if case .controls(let ids) = FixturePhysicalControlMapper.resolve(
                    physicalEmitterID: emitter.id,
                    descriptor: descriptor,
                    definition: definition
                ).disposition { return !ids.isEmpty }
                return false
            }
            XCTAssertFalse(controlled.isEmpty, "\(fixture.name) has control elements but no selectable physical aperture")
            for aperture in geometry.interactionApertures {
                XCTAssertEqual(geometry.hitTest(localPoint: aperture.center), .physicalElement(aperture.id), fixture.name)
            }
        }
    }

    private func descriptor(form: FixturePhysicalForm, topology: FixturePhysicalTopologyKind, positions: [(Double, Double)], movement: FixtureMovementKind = .static) -> FixtureVisualizationDescriptor {
        let emitters = positions.enumerated().map { index, p in FixturePhysicalEmitter(id: "e\(index)", name: "E\(index)", x: p.0, y: p.1, width: 0.1, height: 0.2) }
        return FixtureVisualizationDescriptor(physicalFixtureID: UUID(), form: form, aspectRatio: 1, emitters: emitters, componentGroups: [.init(id: "g", role: .emitterArray, topology: topology, emitterIDs: emitters.map(\.id))], opticalBehaviors: [.wash], movement: movement, indicators: [], confidence: .explicit, evidence: [], warnings: [])
    }

    private func linearDescriptor(count: Int) -> FixtureVisualizationDescriptor {
        descriptor(form: .linearBar, topology: .linear, positions: (0..<count).map { ((Double($0) + 0.5) / Double(count), 0.5) })
    }

    private func gridDescriptor(form: FixturePhysicalForm, rows: Int, columns: Int) -> FixtureVisualizationDescriptor {
        let positions: [(Double, Double)] = (0..<(rows * columns)).map { index in
            let x = (Double(index % columns) + 0.5) / Double(columns)
            let y = (Double(index / columns) + 0.5) / Double(rows)
            return (x, y)
        }
        return descriptor(form: form, topology: .grid, positions: positions)
    }

    private func ringDescriptor(count: Int) -> FixtureVisualizationDescriptor {
        descriptor(form: .par, topology: .ring, positions: (0..<count).map { index in let a = -.pi / 2 + 2 * .pi * Double(index) / Double(count); return (0.5 + cos(a) * 0.34, 0.5 + sin(a) * 0.34) })
    }

    private func multiHeadDescriptor() -> FixtureVisualizationDescriptor {
        var value = descriptor(form: .multiHeadBar, topology: .multiHead, positions: (0..<4).map { ((Double($0) + 0.5) / 4, 0.42) }, movement: .multiHead)
        value.aspectRatio = 3.8
        value.componentGroups = [.init(id: "heads", role: .movingHead, topology: .multiHead, emitterIDs: value.emitters.map(\.id), movement: .multiHead)]
        return value
    }

    private func hybridDescriptor() -> FixtureVisualizationDescriptor {
        var centerAndRing = [(0.5, 0.5)]
        centerAndRing += (0..<12).map { index in let a = -.pi / 2 + 2 * .pi * Double(index) / 12; return (0.5 + cos(a) * 0.35, 0.5 + sin(a) * 0.35) }
        var value = descriptor(form: .movingHead, topology: .compositional, positions: centerAndRing, movement: .panTilt)
        value.componentGroups = [
            .init(id: "beam", role: .primaryOptic, topology: .single, emitterIDs: ["e0"]),
            .init(id: "ring", role: .pixelRing, topology: .ring, emitterIDs: Array(value.emitters.dropFirst().map(\.id))),
        ]
        return value
    }
}
