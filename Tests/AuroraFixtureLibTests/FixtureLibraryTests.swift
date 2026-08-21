import AuroraFixtureLib
import AuroraModel
import XCTest

final class FixtureLibraryTests: XCTestCase {
    func testAtmosphericCreationTemplatesHaveUsefulChannelsAndNoLightEmitter() throws {
        for template in [FixtureCreationTemplate.fogger, .hazer, .snowMachine, .bubbleMachine, .fan] {
            let definition = FixtureDefinitionFactory.make(template: template)
            try FixtureDefinitionValidation.validate(definition)
            XCTAssertFalse(definition.channels.isEmpty)
            XCTAssertEqual(definition.portablePhysicalDefinition?.form, .atmospheric)
            XCTAssertTrue(definition.portablePhysicalDefinition?.emitters.isEmpty == true)
            XCTAssertNil(definition.colorModel)
        }
    }

    func testFogTemplateDefinesOffAndOutputRanges() throws {
        let definition = FixtureDefinitionFactory.make(template: .fogger)
        let functions = try XCTUnwrap(definition.channels.first?.dmxFunctions)
        XCTAssertEqual(functions.count, 2)
        XCTAssertEqual(functions[0].name, "Off")
        XCTAssertEqual(functions[0].dmxMin, 0)
        XCTAssertEqual(functions[0].dmxMax, 5)
        XCTAssertEqual(functions[1].name, "Fog Output")
        XCTAssertEqual(functions[1].dmxMin, 6)
        XCTAssertEqual(functions[1].dmxMax, 255)
        XCTAssertEqual(functions[1].attribute, "fogOutput")
        XCTAssertEqual(functions[1].semantic, .attribute)
    }

    func testFunctionRangesSurviveJSONRoundTrip() throws {
        let original = FixtureDefinitionFactory.make(template: .fogger)
        let decoded = try JSONDecoder().decode(FixtureDefinition.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.channels.first?.dmxFunctions, original.channels.first?.dmxFunctions)
    }

    func testOverlappingFunctionRangesAreRejected() {
        let definition = FixtureDefinition(
            manufacturer: "Test",
            model: "Overlap",
            channels: [ChannelDef(
                offset: 1,
                name: "Output",
                attribute: "output",
                semanticKind: .generic,
                dmxFunctions: [
                    DMXFunctionRange(name: "Off", dmxMin: 0, dmxMax: 10),
                    DMXFunctionRange(name: "On", dmxMin: 10, dmxMax: 255),
                ]
            )]
        )
        XCTAssertNoThrow(try FixtureDefinitionValidation.validate(definition))
        XCTAssertThrowsError(try FixtureDefinitionValidation.validateAuthoredFunctionRanges(definition)) { error in
            XCTAssertTrue(error.localizedDescription.contains("overlapping DMX function ranges"))
        }
    }

    func testFlameTemplateUsesSafeDefaultsAndProtectedActivation() throws {
        let definition = FixtureDefinitionFactory.make(template: .flameEffect)
        try FixtureDefinitionValidation.validate(definition)
        XCTAssertEqual(definition.category, "safety-effect")
        XCTAssertTrue(FixtureDefinitionFactory.isSafetySensitive(definition))
        XCTAssertEqual(definition.channels.first?.defaultValue, 0)
        XCTAssertEqual(definition.channels.first?.highlightValue, 0)
        XCTAssertEqual(definition.channels.first?.dmxFunctions.first?.semantic, .protectedCommand)
        XCTAssertEqual(definition.channels.first?.dmxFunctions.first?.requiresConfirmation, true)
        XCTAssertEqual(definition.channels.first?.dmxFunctions.first?.holdDurationMilliseconds, 1_000)
    }

    func testLightingTemplatesRetainPhysicalEmitters() throws {
        for template in [FixtureCreationTemplate.dimmer, .rgb, .rgbw, .movingHead, .laser, .strobe] {
            let definition = FixtureDefinitionFactory.make(template: template)
            try FixtureDefinitionValidation.validate(definition)
            XCTAssertFalse(definition.portablePhysicalDefinition?.emitters.isEmpty == true)
        }
    }

    func testLoadBundledSeed() throws {
        let library = try FixtureLibrary.loadBundledSeed()
        XCTAssertGreaterThanOrEqual(library.definitions.count, 4)
        XCTAssertTrue(library.manufacturers.contains("Generic"))
    }

    func testLookupDimmer() throws {
        let library = try FixtureLibrary.loadBundledSeed()
        let dimmer = library.lookup(manufacturer: "Generic", model: "Dimmer", modeName: "1-channel")
        XCTAssertNotNil(dimmer)
        XCTAssertEqual(dimmer?.channelCount, 1)
        XCTAssertEqual(dimmer?.channels.first?.attribute, "intensity")
    }

    func testLookupMissing() throws {
        let library = try FixtureLibrary.loadBundledSeed()
        XCTAssertNil(library.lookup(manufacturer: "NoSuch", model: "Thing", modeName: "x"))
    }

    func testSearchRGB() throws {
        let library = try FixtureLibrary.loadBundledSeed()
        let hits = library.search("rgb")
        XCTAssertTrue(hits.contains { $0.model.localizedCaseInsensitiveContains("RGB") })
        XCTAssertGreaterThanOrEqual(hits.count, 2)
    }

    func testDefinitionByStableID() throws {
        let library = try FixtureLibrary.loadBundledSeed()
        let id = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
        let def = library.definition(id: id)
        XCTAssertEqual(def?.model, "Dimmer")
    }

    func testEmbeddableCopyGetsNewIDs() throws {
        let library = try FixtureLibrary.loadBundledSeed()
        let original = try XCTUnwrap(library.lookup(manufacturer: "Generic", model: "Dimmer", modeName: "1-channel"))
        let copy = library.makeEmbeddableCopy(original)
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.manufacturer, original.manufacturer)
        XCTAssertEqual(copy.channels.count, original.channels.count)
        XCTAssertNotEqual(copy.channels[0].id, original.channels[0].id)
    }

    func testInvalidDefinitionRejected() {
        let bad = FixtureDefinition(
            manufacturer: "",
            model: "X",
            channelCount: 1,
            channels: [ChannelDef(offset: 1, name: "A", attribute: "intensity")]
        )
        XCTAssertThrowsError(try FixtureLibrary(definitions: [bad]))
    }

    func testDuplicateOffsetRejected() {
        let bad = FixtureDefinition(
            manufacturer: "G",
            model: "X",
            channelCount: 2,
            channels: [
                ChannelDef(offset: 1, name: "A", attribute: "intensity"),
                ChannelDef(offset: 1, name: "B", attribute: "pan"),
            ]
        )
        XCTAssertThrowsError(try FixtureDefinitionValidation.validate(bad))
    }

    func testMovingHeadHasPanTilt() throws {
        let library = try FixtureLibrary.loadBundledSeed()
        let mh = library.lookup(manufacturer: "Generic", model: "Moving Head", modeName: "16-channel")
        XCTAssertEqual(mh?.channelCount, 16)
        XCTAssertEqual(mh?.hasPanTilt, true)
        XCTAssertFalse(mh?.wheels.isEmpty ?? true)
    }
}
