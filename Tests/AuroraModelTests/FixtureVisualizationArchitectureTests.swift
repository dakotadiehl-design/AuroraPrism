import AuroraModel
import XCTest

final class FixtureVisualizationArchitectureTests: XCTestCase {
    func testPersonalitiesWithRadicallyDifferentDMXResolveIdenticalPhysicalTopology() {
        let physical = twelveEmitterBar()
        let personalities = [
            FixtureDefinition(
                manufacturer: "Synthetic",
                model: "Invariant Bar 12",
                modeName: "3 channel",
                channels: rgbChannels(count: 1),
                physicalFixtureID: physical.id
            ),
            FixtureDefinition(
                manufacturer: "Synthetic",
                model: "Invariant Bar 12",
                modeName: "6 channel",
                channels: rgbChannels(count: 1) + [
                    ChannelDef(offset: 4, name: "Dimmer", attribute: "intensity"),
                    ChannelDef(offset: 5, name: "Strobe", attribute: "strobe"),
                    ChannelDef(offset: 6, name: "Macro", attribute: "macro", semanticKind: .generic),
                ],
                physicalFixtureID: physical.id
            ),
            FixtureDefinition(
                manufacturer: "Synthetic",
                model: "Invariant Bar 12",
                modeName: "36 channel",
                channels: rgbChannels(count: 12, owned: true),
                physicalFixtureID: physical.id
            ),
            FixtureDefinition(
                manufacturer: "Synthetic",
                model: "Invariant Bar 12",
                modeName: "48 channel",
                channels: rgbaChannels(count: 12),
                physicalFixtureID: physical.id
            ),
        ]

        let descriptors = personalities.map { FixtureVisualizationResolver.resolve(definition: $0, physical: physical) }
        XCTAssertEqual(Set(descriptors.map(\.physicalTopologySignature)).count, 1)
        XCTAssertTrue(descriptors.allSatisfy { $0.emitters.count == 12 })
        XCTAssertTrue(descriptors.allSatisfy { $0.form == .linearBar })
    }

    func testPhysicalAndControlIdentitiesRemainIndependentAcrossMappingCardinalities() {
        let controls = ["zone-a", "zone-b", "zone-c"]
        let emitters = ["aperture-1", "aperture-2", "aperture-3"]
        let mappings = [
            FixtureEmitterMapping(id: "one-one", controlElementIDs: [controls[0]], physicalEmitterIDs: [emitters[0]]),
            FixtureEmitterMapping(id: "one-many", controlElementIDs: [controls[1]], physicalEmitterIDs: [emitters[1], emitters[2]]),
            FixtureEmitterMapping(id: "many-one", controlElementIDs: [controls[0], controls[2]], physicalEmitterIDs: [emitters[2]], combination: .additive),
            FixtureEmitterMapping(id: "many-many", controlElementIDs: Set(controls), physicalEmitterIDs: Set(emitters), combination: .maximum),
        ]

        XCTAssertTrue(Set(controls).isDisjoint(with: Set(emitters)))
        XCTAssertEqual(mappings[0].controlElementIDs.count, 1)
        XCTAssertEqual(mappings[0].physicalEmitterIDs.count, 1)
        XCTAssertEqual(mappings[1].controlElementIDs.count, 1)
        XCTAssertEqual(mappings[1].physicalEmitterIDs.count, 2)
        XCTAssertEqual(mappings[2].controlElementIDs.count, 2)
        XCTAssertEqual(mappings[2].physicalEmitterIDs.count, 1)
        XCTAssertEqual(mappings[3].controlElementIDs.count, 3)
        XCTAssertEqual(mappings[3].physicalEmitterIDs.count, 3)
    }

    func testExplicitPersonalityOverrideMayDeliberatelyBreakInvarianceAndExplainsWhy() {
        let physical = twelveEmitterBar()
        var definition = FixtureDefinition(
            manufacturer: "Synthetic",
            model: "Invariant Bar 12",
            channels: rgbChannels(count: 1),
            physicalFixtureID: physical.id
        )
        let automatic = FixtureVisualizationResolver.resolve(definition: definition, physical: physical)
        definition.visual = FixtureVisualDefinition(role: .matrixLight, bodyAspectRatio: 1, layout: .grid, provenance: .manuallyAuthored)
        let overridden = FixtureVisualizationResolver.resolve(definition: definition, physical: physical)

        XCTAssertNotEqual(automatic.physicalTopologySignature, overridden.physicalTopologySignature)
        XCTAssertEqual(overridden.confidence, .explicit)
        XCTAssertTrue(overridden.evidence.contains { $0.id == "visualization-override" })
    }

    func testVerifiedPhysicalMetadataPrecedesDMXAndNameHeuristics() {
        let physical = FixturePhysicalDefinition(manufacturer: "Synthetic", model: "Not A Bar", form: .panel, emitters: [.init(id: "p", name: "P", x: 0.5, y: 0.5)], source: .imported, sourceMetadata: ["beamLayoutClass": "LXArrayBeamLayout"])
        let definition = FixtureDefinition(manufacturer: "Synthetic", model: "BAR MOVING PAR", channels: rgbaChannels(count: 12), hasPanTilt: true, physicalFixtureID: physical.id)
        let result = FixtureVisualizationResolver.resolve(definition: definition, physical: physical)
        XCTAssertEqual(result.form, .panel)
        XCTAssertEqual(result.emitters.map(\.id), ["p"])
        XCTAssertTrue(result.evidence.contains { $0.id == "shared-physical" })
    }

    func testLowConfidenceNameHeuristicIsExplained() {
        let definition = FixtureDefinition(manufacturer: "Synthetic", model: "Mystery Laser", channels: [ChannelDef(offset: 1, name: "Function", attribute: "function", semanticKind: .generic)])
        let result = FixtureVisualizationResolver.resolve(definition: definition, physical: nil)
        XCTAssertEqual(result.form, .laser)
        XCTAssertEqual(result.confidence, .low)
        XCTAssertTrue(result.warnings.contains { $0.id == "missing-physical" })
    }

    func testMalformedGeometryIsClampedAndUnknownMetadataRetained() {
        let physical = FixturePhysicalDefinition(
            manufacturer: "Synthetic",
            model: "Malformed",
            form: .panel,
            aspectRatio: .infinity,
            emitters: [.init(id: "bad", name: "Bad", x: -3, y: 8, width: -1, height: .nan)],
            beamShape: 17,
            source: .imported,
            sourceMetadata: ["unknownVendorField": "opaque-value"]
        )
        let definition = FixtureDefinition(manufacturer: "Synthetic", model: "Malformed", channels: [ChannelDef(offset: 1, name: "I", attribute: "intensity")], physicalFixtureID: physical.id)
        let result = FixtureVisualizationResolver.resolve(definition: definition, physical: physical)
        XCTAssertEqual(result.aspectRatio, 1)
        XCTAssertEqual(result.emitters.first?.x, 0)
        XCTAssertEqual(result.emitters.first?.y, 1)
        XCTAssertEqual(result.emitters.first?.width, 0.01)
        XCTAssertEqual(result.emitters.first?.height, 0.1)
        XCTAssertTrue(result.warnings.contains { $0.id == "malformed-geometry" })
        XCTAssertTrue(result.warnings.contains { $0.id == "unknown-beam-shape" })
        XCTAssertEqual(physical.sourceMetadata["unknownVendorField"], "opaque-value")
    }

    func testUnknownFutureVisualizationEnumValuesDegradeSafely() throws {
        let visualJSON = Data(#"{"schemaVersion":99,"role":"futureQuantumLight","layout":"futureSpiral","elements":[{"id":"e","name":"E","x":0.5,"y":0.5,"width":0.2,"height":0.2,"shape":"futureShape"}]}"#.utf8)
        let visual = try JSONDecoder().decode(FixtureVisualDefinition.self, from: visualJSON)
        XCTAssertEqual(visual.role, .generic)
        XCTAssertEqual(visual.layout, .row)
        XCTAssertEqual(visual.elements.first?.shape, .circle)

        let id = UUID()
        let physicalJSON = Data("""
        {"schemaVersion":99,"id":"\(id.uuidString)","manufacturer":"Future","model":"Fixture","form":"futureForm","movement":"teleport","emitters":[],"componentGroups":[{"id":"g","role":"other","topology":"futureTopology","emitterIDs":[]}],"sourceMetadata":{"futureKey":"preserved"}}
        """.utf8)
        let physical = try JSONDecoder().decode(FixturePhysicalDefinition.self, from: physicalJSON)
        XCTAssertEqual(physical.form, .generic)
        XCTAssertEqual(physical.movement, .unknown)
        XCTAssertEqual(physical.componentGroups.first?.topology, .unknown)
        XCTAssertEqual(physical.sourceMetadata["futureKey"], "preserved")
    }

    func testFingerprintIgnoresDefinitionIdentityButChangesWithPhysicalContent() {
        let physical = twelveEmitterBar()
        let a = FixtureDefinition(manufacturer: "Synthetic", model: "Bar", channels: rgbChannels(count: 1))
        var b = a
        b.id = UUID()
        XCTAssertEqual(
            FixtureVisualizationResolver.visualizationFingerprint(definition: a, physical: physical),
            FixtureVisualizationResolver.visualizationFingerprint(definition: b, physical: physical)
        )
        var changed = physical
        changed.emitters[0].x += 0.01
        XCTAssertNotEqual(
            FixtureVisualizationResolver.visualizationFingerprint(definition: a, physical: physical),
            FixtureVisualizationResolver.visualizationFingerprint(definition: a, physical: changed)
        )
    }

    func testResolvedDescriptorIsCachedByContentNotPerFrame() {
        let physical = twelveEmitterBar()
        let definition = FixtureDefinition(manufacturer: "Synthetic", model: "Bar", channels: rgbChannels(count: 1), physicalFixtureID: physical.id)
        FixtureVisualizationResolver.resetCacheForTesting()
        for _ in 0..<10_000 {
            _ = FixtureVisualizationResolver.resolveCached(definition: definition, physical: physical)
        }
        XCTAssertEqual(FixtureVisualizationResolver.cacheResolutionCount, 1)
    }

    func testLegacyExplicitPodsBecomeSharedPhysicalHeadsAcrossPersonalities() throws {
        let pixel = FixtureDefinition(
            manufacturer: "Synthetic", model: "Four Head Bar", modeName: "Pixel", channels: [],
            cellBlock: FixtureCellBlock(channels: [ChannelDef(offset: 1, name: "Red", attribute: "colorR")], cellCount: 4, cellLabelPrefix: "Pod")
        )
        let basic = FixtureDefinition(manufacturer: "Synthetic", model: "Four Head Bar", modeName: "Basic", channels: [ChannelDef(offset: 1, name: "Dimmer", attribute: "intensity")])
        let project = ShowProject(metadata: ProjectMetadata(name: "Physical adaptation"), fixtureDefinitions: [pixel, basic])
        let pixelPhysical = try XCTUnwrap(project.physicalFixture(for: pixel))
        let basicPhysical = try XCTUnwrap(project.physicalFixture(for: basic))
        XCTAssertEqual(pixelPhysical.id, basicPhysical.id)
        XCTAssertEqual(pixelPhysical.emitters.count, 4)
        XCTAssertEqual(pixelPhysical.form, .multiHeadBar)
        XCTAssertEqual(pixelPhysical.componentGroups.first?.topology, .multiHead)
        XCTAssertTrue(pixel.channels.allSatisfy { $0.elementID == nil }, "Visualization adaptation must not rewrite DMX ownership")
    }

    func testLegacyLinearProductSharesExplicitOwnedElementTopologyWithoutUsingChannelCount() throws {
        let basic = FixtureDefinition(manufacturer: "Synthetic", model: "Photon Band", modeName: "Basic", channels: [ChannelDef(offset: 1, name: "Red", attribute: "colorR")])
        let extendedChannels = (0..<3).flatMap { index in
            ["colorR", "colorG", "colorB"].enumerated().map { offset, attribute in
                ChannelDef(offset: UInt16(index * 3 + offset + 1), name: attribute, attribute: attribute, elementID: "zone-\(index)")
            }
        }
        let extended = FixtureDefinition(manufacturer: "Synthetic", model: "Photon Band", modeName: "Extended", channels: extendedChannels)
        let project = ShowProject(metadata: ProjectMetadata(name: "Legacy linear"), fixtureDefinitions: [basic, extended])
        let basicPhysical = try XCTUnwrap(project.physicalFixture(for: basic))
        let extendedPhysical = try XCTUnwrap(project.physicalFixture(for: extended))
        XCTAssertEqual(basicPhysical.id, extendedPhysical.id)
        XCTAssertEqual(basicPhysical.form, .linearBar)
        XCTAssertEqual(basicPhysical.emitters.count, 3)
        XCTAssertEqual(basicPhysical.componentGroups.first?.topology, .linear)
        XCTAssertTrue(basic.channels.allSatisfy { $0.elementID == nil })

        let unrelated = FixtureDefinition(manufacturer: "Synthetic", model: "Mystery Fixture", channels: extendedChannels)
        let unrelatedProject = ShowProject(metadata: ProjectMetadata(name: "No guessed topology"), fixtureDefinitions: [unrelated])
        XCTAssertNil(unrelatedProject.physicalFixture(for: unrelated), "Explicit controls without physical form evidence must not invent a layout")
    }

    func testIncompleteImportedStripIsCompletedFromRGBPixelPersonalityForEveryMode() throws {
        let physical = FixturePhysicalDefinition(
            manufacturer: "Synthetic", model: "Photon Array", form: .generic,
            source: .imported, sourceMetadata: ["beamLayoutClass": "LXStripBeamLayout"]
        )
        let basic = FixtureDefinition(
            manufacturer: "Synthetic", model: "Photon Array", modeName: "Basic",
            channels: rgbChannels(count: 1), physicalFixtureID: physical.id
        )
        let hsic = FixtureDefinition(
            manufacturer: "Synthetic", model: "Photon Array", modeName: "HSIC",
            channels: [
                ChannelDef(offset: 1, name: "Hue", attribute: "hue"),
                ChannelDef(offset: 2, name: "Saturation", attribute: "saturation"),
            ], physicalFixtureID: physical.id
        )
        let pixels = FixtureDefinition(
            manufacturer: "Synthetic", model: "Photon Array", modeName: "RGBW Pixels",
            channels: rgbaChannels(count: 15), physicalFixtureID: physical.id
        )
        var project = ShowProject(metadata: ProjectMetadata(name: "Imported pixels"), fixtureDefinitions: [basic, hsic, pixels])
        project.physicalFixtureDefinitions = [physical]

        let resolved = try [basic, hsic, pixels].map { try XCTUnwrap(project.physicalFixture(for: $0)) }
        XCTAssertEqual(Set(resolved.map(\.id)), [physical.id])
        XCTAssertTrue(resolved.allSatisfy { $0.form == .linearBar && $0.emitters.count == 15 })
        XCTAssertEqual(Set(resolved.map { $0.emitters.map(\.id) }).count, 1)
        XCTAssertGreaterThan(try XCTUnwrap(resolved.first?.aspectRatio), 3)

        let descriptor = project.visualizationDescriptor(for: pixels)
        let first = FixturePhysicalControlMapper.resolve(physicalEmitterID: "physical-pixel-0", descriptor: descriptor, definition: pixels)
        let last = FixturePhysicalControlMapper.resolve(physicalEmitterID: "physical-pixel-14", descriptor: descriptor, definition: pixels)
        XCTAssertEqual(first.disposition, .controls(["zone-0"]))
        XCTAssertEqual(last.disposition, .controls(["zone-14"]))

        let deferredHSIC = FixturePhysicalControlMapper.resolve(physicalEmitterID: "physical-pixel-4", descriptor: project.visualizationDescriptor(for: hsic), definition: hsic)
        XCTAssertEqual(deferredHSIC.disposition, .wholeFixture, "HSIC pixel interpretation remains deliberately out of scope")
    }

    func testPhysicalControlMapperHandlesIndependentGroupedAndUnmappedPersonalities() {
        let physical = twelveEmitterBar()
        let descriptor = FixtureVisualizationResolver.resolve(definition: FixtureDefinition(manufacturer: "Synthetic", model: "Bar"), physical: physical)
        var independent = FixtureDefinition(manufacturer: "Synthetic", model: "Bar", controlElements: physical.emitters.enumerated().map { .init(id: "c\($0.offset)", name: "Cell") })
        independent.emitterMappings = physical.emitters.enumerated().map { .init(id: "m\($0.offset)", controlElementIDs: ["c\($0.offset)"], physicalEmitterIDs: [$0.element.id]) }
        XCTAssertTrue(FixturePhysicalControlMapper.resolve(physicalEmitterID: "aperture-1", descriptor: descriptor, definition: independent).independentlyControllable)

        var grouped = FixtureDefinition(manufacturer: "Synthetic", model: "Bar", channels: [ChannelDef(offset: 1, name: "Dimmer", attribute: "intensity")], controlElements: [.init(id: "all", name: "All")])
        grouped.emitterMappings = [.init(id: "all-map", controlElementIDs: ["all"], physicalEmitterIDs: Set(physical.emitters.map(\.id)))]
        let groupedResult = FixturePhysicalControlMapper.resolve(physicalEmitterID: "aperture-3", descriptor: descriptor, definition: grouped)
        XCTAssertFalse(groupedResult.independentlyControllable)
        XCTAssertEqual(groupedResult.affectedPhysicalEmitterIDs.count, 12)

        let unmapped = FixtureDefinition(manufacturer: "Synthetic", model: "Display Only")
        XCTAssertEqual(FixturePhysicalControlMapper.resolve(physicalEmitterID: "aperture-1", descriptor: descriptor, definition: unmapped).disposition, .inspectionOnly)
    }

    func testUndefinedImportedLinearLayoutUsesMatchingDeclaredBeamAndOwnedElementCounts() throws {
        let physical = FixturePhysicalDefinition(
            manufacturer: "Synthetic",
            model: "Four Pod Bar",
            form: .linearBar,
            aspectRatio: 2.5,
            emitters: [],
            source: .imported,
            sourceMetadata: ["beamLayoutClass": "LXUndefinedBeamLayout", "numberOfBeams": "4"]
        )
        let definition = FixtureDefinition(
            manufacturer: "Synthetic",
            model: "Four Pod Bar",
            channels: rgbChannels(count: 4, owned: true),
            physicalFixtureID: physical.id
        )
        var project = ShowProject(metadata: ProjectMetadata(name: "Four pods"), fixtureDefinitions: [definition])
        project.physicalFixtureDefinitions = [physical]

        let completed = try XCTUnwrap(project.physicalFixture(for: definition))
        XCTAssertEqual(completed.emitters.count, 4)
        XCTAssertEqual(completed.componentGroups.first?.topology, .linear)
        XCTAssertEqual(completed.sourceMetadata["topologyCompletedFrom"], "declared-beam-count+explicit-rgb-element-ownership")

        let descriptor = project.visualizationDescriptor(for: definition)
        XCTAssertEqual(descriptor.emitters.count, 4)
        XCTAssertEqual(
            FixturePhysicalControlMapper.resolve(
                physicalEmitterID: descriptor.emitters[2].id,
                descriptor: descriptor,
                definition: definition
            ).disposition,
            .controls(["zone-2"])
        )
    }

    func testUndefinedImportedLayoutDoesNotInventEmittersWhenCountsDisagree() {
        let physical = FixturePhysicalDefinition(
            manufacturer: "Synthetic",
            model: "Ambiguous Bar",
            form: .linearBar,
            emitters: [],
            source: .imported,
            sourceMetadata: ["beamLayoutClass": "LXUndefinedBeamLayout", "numberOfBeams": "4"]
        )
        let definition = FixtureDefinition(
            manufacturer: "Synthetic",
            model: "Ambiguous Bar",
            channels: rgbChannels(count: 3, owned: true),
            physicalFixtureID: physical.id
        )
        var project = ShowProject(metadata: ProjectMetadata(name: "Mismatch"), fixtureDefinitions: [definition])
        project.physicalFixtureDefinitions = [physical]

        XCTAssertTrue(project.physicalFixture(for: definition)?.emitters.isEmpty == true)
    }

    private func twelveEmitterBar() -> FixturePhysicalDefinition {
        let emitters = (0..<12).map { index in
            FixturePhysicalEmitter(
                id: "aperture-\(index + 1)",
                name: "Aperture \(index + 1)",
                x: (Double(index) + 0.5) / 12,
                y: 0.5,
                width: 0.055,
                height: 0.55
            )
        }
        return FixturePhysicalDefinition(
            manufacturer: "Synthetic",
            model: "Invariant Bar 12",
            form: .linearBar,
            aspectRatio: 8,
            emitters: emitters,
            componentGroups: [.init(id: "row", role: .emitterArray, topology: .linear, emitterIDs: emitters.map(\.id))],
            opticalBehaviors: [.wash, .pixel],
            movement: .static
        )
    }

    private func rgbChannels(count: Int, owned: Bool = false) -> [ChannelDef] {
        (0..<count).flatMap { element in
            ["colorR", "colorG", "colorB"].enumerated().map { index, attribute in
                ChannelDef(offset: UInt16(element * 3 + index + 1), name: attribute, attribute: attribute, elementID: owned ? "zone-\(element)" : nil)
            }
        }
    }

    private func rgbaChannels(count: Int) -> [ChannelDef] {
        (0..<count).flatMap { element in
            ["colorR", "colorG", "colorB", "colorA"].enumerated().map { index, attribute in
                ChannelDef(offset: UInt16(element * 4 + index + 1), name: attribute, attribute: attribute, elementID: "zone-\(element)")
            }
        }
    }
}
