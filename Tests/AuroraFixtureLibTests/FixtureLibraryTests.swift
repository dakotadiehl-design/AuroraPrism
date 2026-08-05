import AuroraFixtureLib
import AuroraModel
import XCTest

final class FixtureLibraryTests: XCTestCase {
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
