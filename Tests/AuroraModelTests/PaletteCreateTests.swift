import AuroraModel
import XCTest

final class PaletteCreateTests: XCTestCase {
    func testCommonColorCreates() {
        let a = UUID()
        let b = UUID()
        let values: [UUID: [String: Double]] = [
            a: ["colorR": 1, "colorG": 0.2, "colorB": 0],
            b: ["colorR": 1, "colorG": 0.2, "colorB": 0],
        ]
        let outcome = PaletteCreate.fromProgrammer(
            kind: .color,
            programmerValues: values,
            selectedFixtureIDs: [a, b],
            existingPaletteCount: 0
        )
        guard case .created(let palette, let mixed) = outcome else {
            return XCTFail("expected created")
        }
        XCTAssertEqual(palette.type, .color)
        XCTAssertEqual(palette.values["colorR"], 1)
        XCTAssertEqual(palette.values["colorG"], 0.2)
        XCTAssertTrue(mixed.isEmpty)
        XCTAssertEqual(PaletteCreate.statusMessage(for: outcome), "Created \(palette.name)")
    }

    func testMixedAttributesNeverSilentAndNotStored() {
        let a = UUID()
        let b = UUID()
        let values: [UUID: [String: Double]] = [
            a: ["colorR": 1, "colorG": 0.2, "colorB": 0],
            b: ["colorR": 1, "colorG": 0.7, "colorB": 0],
        ]
        let outcome = PaletteCreate.fromProgrammer(
            kind: .color,
            programmerValues: values,
            selectedFixtureIDs: [a, b],
            existingPaletteCount: 2
        )
        guard case .created(let palette, let mixed) = outcome else {
            return XCTFail("expected created with commons")
        }
        XCTAssertEqual(palette.values["colorR"], 1)
        XCTAssertEqual(palette.values["colorB"], 0)
        XCTAssertNil(palette.values["colorG"], "mixed Green must not be stored")
        XCTAssertEqual(mixed, ["colorG"])
        let status = PaletteCreate.statusMessage(for: outcome)
        XCTAssertTrue(status.contains("Skipped mixed"), status)
        XCTAssertTrue(status.contains("Green"), status)
        XCTAssertFalse(status.contains("fabricat"), status)
    }

    func testAllMixedRefusesEmpty() {
        let a = UUID()
        let b = UUID()
        let values: [UUID: [String: Double]] = [
            a: ["colorR": 1, "colorG": 0.2],
            b: ["colorR": 0.5, "colorG": 0.7],
        ]
        let outcome = PaletteCreate.fromProgrammer(
            kind: .color,
            programmerValues: values,
            selectedFixtureIDs: [a, b],
            existingPaletteCount: 0
        )
        XCTAssertEqual(outcome, .refusedEmpty)
        XCTAssertTrue(PaletteCreate.statusMessage(for: outcome).contains("mixed"))
    }

    func testNoProgrammerDataRefused() {
        let outcome = PaletteCreate.fromProgrammer(
            kind: .position,
            programmerValues: [:],
            selectedFixtureIDs: [UUID()],
            existingPaletteCount: 0
        )
        XCTAssertEqual(outcome, .refusedNoProgrammerData)
    }

    func testDoesNotFabricateDefaults() {
        let a = UUID()
        let values: [UUID: [String: Double]] = [
            a: ["intensity": 0.5],
        ]
        let outcome = PaletteCreate.fromProgrammer(
            kind: .color,
            programmerValues: values,
            selectedFixtureIDs: [a],
            existingPaletteCount: 0
        )
        XCTAssertEqual(outcome, .refusedNoProgrammerData)
    }

    func testIntensityAndPositionKinds() {
        let a = UUID()
        let values: [UUID: [String: Double]] = [
            a: ["intensity": 0.8, "pan": 0.3, "tilt": 0.6],
        ]
        let intOutcome = PaletteCreate.fromProgrammer(
            kind: .intensity,
            programmerValues: values,
            selectedFixtureIDs: [a],
            existingPaletteCount: 0
        )
        guard case .created(let intPal, _) = intOutcome else {
            return XCTFail("intensity")
        }
        XCTAssertEqual(intPal.type, .intensity)
        XCTAssertEqual(intPal.values["intensity"], 0.8)
        XCTAssertNil(intPal.values["pan"])

        let posOutcome = PaletteCreate.fromProgrammer(
            kind: .position,
            programmerValues: values,
            selectedFixtureIDs: [a],
            existingPaletteCount: 0
        )
        guard case .created(let posPal, _) = posOutcome else {
            return XCTFail("position")
        }
        XCTAssertEqual(posPal.type, .position)
        XCTAssertEqual(posPal.values["pan"], 0.3)
        XCTAssertEqual(posPal.values["tilt"], 0.6)
    }

    func testFallsBackToProgrammerKeysWhenSelectionEmpty() {
        let a = UUID()
        let values: [UUID: [String: Double]] = [
            a: ["colorR": 0.1, "colorG": 0.2, "colorB": 0.3],
        ]
        let outcome = PaletteCreate.fromProgrammer(
            kind: .color,
            programmerValues: values,
            selectedFixtureIDs: [],
            existingPaletteCount: 0
        )
        guard case .created(let palette, _) = outcome else {
            return XCTFail("expected create from programmer keys")
        }
        XCTAssertEqual(palette.values["colorR"], 0.1)
    }

    // MARK: CR-03 capability-aware create

    func testCapableUntouchedBlocksFalseCommon() {
        let a = UUID()
        let b = UUID()
        let values: [UUID: [String: Double]] = [
            a: ["colorR": 1.0],
            // b supports red but untouched
        ]
        let caps: [UUID: Set<String>] = [
            a: ["colorR", "colorG", "colorB"],
            b: ["colorR", "colorG", "colorB"],
        ]
        let outcome = PaletteCreate.fromProgrammer(
            kind: .color,
            programmerValues: values,
            selectedFixtureIDs: [a, b],
            existingPaletteCount: 0,
            capabilityMap: caps
        )
        // Not common — capable+untouched → refused empty or only if other commons exist
        XCTAssertEqual(outcome, .refusedEmpty)
    }

    func testUnsupportedDoesNotPoisonCommon() {
        let rgb = UUID()
        let dimmer = UUID()
        let values: [UUID: [String: Double]] = [
            rgb: ["colorR": 0.5, "colorG": 0.2, "colorB": 0.1],
        ]
        let caps: [UUID: Set<String>] = [
            rgb: ["colorR", "colorG", "colorB"],
            dimmer: ["intensity"],
        ]
        let outcome = PaletteCreate.fromProgrammer(
            kind: .color,
            programmerValues: values,
            selectedFixtureIDs: [rgb, dimmer],
            existingPaletteCount: 0,
            capabilityMap: caps
        )
        guard case .created(let palette, let mixed) = outcome else {
            return XCTFail("expected create ignoring unsupported dimmer")
        }
        XCTAssertEqual(palette.values["colorR"], 0.5)
        XCTAssertTrue(mixed.isEmpty)
    }

    func testFilterValuesAndCompatibleIDs() {
        let mover = UUID()
        let par = UUID()
        let values = ["pan": 0.25, "tilt": 0.7]
        let caps: [UUID: Set<String>] = [
            mover: ["pan", "tilt", "intensity"],
            par: ["colorR", "colorG", "colorB"],
        ]
        XCTAssertEqual(PaletteCreate.filterValues(values, supported: caps[mover]!).count, 2)
        XCTAssertTrue(PaletteCreate.filterValues(values, supported: caps[par]!).isEmpty)
        let compatible = PaletteCreate.compatibleFixtureIDs(
            selection: [mover, par],
            values: values,
            capabilityMap: caps
        )
        XCTAssertEqual(compatible, [mover])
    }
}
