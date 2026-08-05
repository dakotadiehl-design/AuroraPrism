import AuroraModel
import XCTest

final class PaletteRecordTests: XCTestCase {
    func testCommonValuesOnly() {
        let a = UUID()
        let b = UUID()
        let values: [UUID: [String: Double]] = [
            a: ["colorR": 1, "colorG": 0, "intensity": 0.5],
            b: ["colorR": 1, "colorG": 0.5, "intensity": 0.5],
        ]
        let result = PaletteRecord.fromProgrammer(
            programmerValues: values,
            selectedFixtureIDs: [a, b],
            attributeKeys: ["colorR", "colorG", "intensity"]
        )
        XCTAssertEqual(result.values["colorR"], 1)
        XCTAssertEqual(result.values["intensity"], 0.5)
        XCTAssertNil(result.values["colorG"])
        XCTAssertTrue(result.mixedAttributes.contains("colorG"))
        XCTAssertTrue(result.isMixed)
    }

    func testEmptySelection() {
        let result = PaletteRecord.fromProgrammer(programmerValues: [:], selectedFixtureIDs: [])
        XCTAssertTrue(result.values.isEmpty)
    }
}
