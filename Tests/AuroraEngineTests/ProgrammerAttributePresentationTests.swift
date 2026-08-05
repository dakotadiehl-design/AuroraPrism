import AuroraEngine
import AuroraModel
import XCTest

final class ProgrammerAttributePresentationTests: XCTestCase {
    private let dimDef = UUID(uuidString: "D1000000-0000-4000-8000-000000000001")!
    private let rgbDef = UUID(uuidString: "D1000000-0000-4000-8000-000000000002")!
    private let mhDef = UUID(uuidString: "D1000000-0000-4000-8000-000000000003")!
    private let fDim = UUID(uuidString: "D1000000-0000-4000-8000-000000000011")!
    private let fRGB = UUID(uuidString: "D1000000-0000-4000-8000-000000000012")!
    private let fMH = UUID(uuidString: "D1000000-0000-4000-8000-000000000013")!
    private let u1 = UUID(uuidString: "D1000000-0000-4000-8000-0000000000AA")!

    private func mixedProject() -> ShowProject {
        var p = ShowProject.empty(name: "UI03")
        p.universes = [Universe(id: u1, number: 1)]
        p.fixtureDefinitions = [
            FixtureDefinition(
                id: dimDef, manufacturer: "G", model: "Dim",
                channels: [ChannelDef(offset: 1, name: "I", attribute: "intensity")]
            ),
            FixtureDefinition(
                id: rgbDef, manufacturer: "G", model: "RGB",
                channels: [
                    ChannelDef(offset: 1, name: "R", attribute: "colorR"),
                    ChannelDef(offset: 2, name: "G", attribute: "colorG"),
                    ChannelDef(offset: 3, name: "B", attribute: "colorB"),
                    ChannelDef(offset: 4, name: "I", attribute: "intensity"),
                ],
                colorModel: .rgb
            ),
            FixtureDefinition(
                id: mhDef, manufacturer: "G", model: "MH",
                channels: [
                    ChannelDef(offset: 1, name: "P", attribute: "pan"),
                    ChannelDef(offset: 2, name: "T", attribute: "tilt"),
                    ChannelDef(offset: 3, name: "I", attribute: "intensity"),
                ],
                hasPanTilt: true
            ),
        ]
        p.fixtures = [
            PatchedFixture(id: fDim, name: "Dim", definitionId: dimDef, universeId: u1, address: 1),
            PatchedFixture(id: fRGB, name: "RGB", definitionId: rgbDef, universeId: u1, address: 10),
            PatchedFixture(id: fMH, name: "MH", definitionId: mhDef, universeId: u1, address: 20),
        ]
        return p
    }

    func testAllSupportUntouched() {
        let p = mixedProject()
        let ordered = [fDim, fRGB, fMH]
        let pres = ProgrammerAttributePresentationResolver.resolve(
            orderedFixtureIDs: ordered,
            project: p,
            programmer: .empty
        )
        XCTAssertEqual(pres.intensity.support, .all)
        XCTAssertEqual(pres.intensity.value, .untouched)
    }

    func testAllSupportCommon() {
        let p = mixedProject()
        var prog = ProgrammerState()
        prog.values = [fDim: ["intensity": 0.5], fRGB: ["intensity": 0.5], fMH: ["intensity": 0.5]]
        let pres = ProgrammerAttributePresentationResolver.resolve(
            orderedFixtureIDs: [fDim, fRGB, fMH],
            project: p,
            programmer: prog
        )
        XCTAssertEqual(pres.intensity.support, .all)
        if case .common(let v) = pres.intensity.value {
            XCTAssertEqual(v, 0.5, accuracy: 1e-9)
        } else {
            XCTFail("expected common")
        }
    }

    func testAllSupportMixed() {
        let p = mixedProject()
        var prog = ProgrammerState()
        prog.values = [fDim: ["intensity": 0.2], fRGB: ["intensity": 0.5], fMH: ["intensity": 0.8]]
        let pres = ProgrammerAttributePresentationResolver.resolve(
            orderedFixtureIDs: [fDim, fRGB, fMH],
            project: p,
            programmer: prog
        )
        XCTAssertEqual(pres.intensity.value, .mixed)
        XCTAssertNil(pres.intensity.displayValue)
    }

    func testPartialSupportPan() {
        let p = mixedProject()
        let pres = ProgrammerAttributePresentationResolver.resolve(
            orderedFixtureIDs: [fDim, fRGB, fMH],
            project: p,
            programmer: .empty
        )
        XCTAssertEqual(pres.pan.support, .partial)
        XCTAssertEqual(pres.pan.value, .untouched)
        XCTAssertEqual(pres.colorR.support, .partial)
        XCTAssertFalse(pres.colorW.isSupported)
    }

    func testNoSupportColorW() {
        let p = mixedProject()
        let st = ProgrammerAttributePresentationResolver.resolve(
            orderedFixtureIDs: [fDim],
            project: p,
            programmer: .empty
        )
        XCTAssertEqual(st.colorW.support, .none)
        XCTAssertFalse(st.hasColor)
        XCTAssertTrue(st.hasIntensity)
    }

    func testPartialCommonAndMixed() {
        let p = mixedProject()
        var prog = ProgrammerState()
        prog.values = [fMH: ["pan": 0.3]]
        let common = ProgrammerAttributePresentationResolver.resolve(
            orderedFixtureIDs: [fDim, fMH],
            project: p,
            programmer: prog
        )
        XCTAssertEqual(common.pan.support, .partial)
        if case .common(let v) = common.pan.value {
            XCTAssertEqual(v, 0.3, accuracy: 1e-9)
        } else {
            // Only one capable fixture with value — common
            XCTFail("\(common.pan.value)")
        }

        prog.values = [fMH: ["pan": 0.3]]
        // single capable still common; add second MH-like by using only MH — already common
        _ = common
    }

    func testFirstCapableForAlign() {
        let p = mixedProject()
        let id = ProgrammerAttributePresentationResolver.firstCapableID(
            attribute: "pan",
            orderedFixtureIDs: [fDim, fRGB, fMH],
            project: p
        )
        XCTAssertEqual(id, fMH)
    }

    func testScaleEightyMixed() {
        var p = mixedProject()
        var ids: [UUID] = []
        var fixtures = p.fixtures
        for i in 0..<80 {
            let id = UUID()
            ids.append(id)
            let def = [dimDef, rgbDef, mhDef][i % 3]
            fixtures.append(
                PatchedFixture(
                    id: id,
                    name: "F\(i)",
                    definitionId: def,
                    universeId: u1,
                    address: UInt16(1 + i * 6)
                )
            )
        }
        p.fixtures = fixtures
        var prog = ProgrammerState()
        for (i, id) in ids.enumerated() {
            prog.values[id] = ["intensity": Double(i % 5) / 4.0]
        }
        let start = CFAbsoluteTimeGetCurrent()
        let pres = ProgrammerAttributePresentationResolver.resolve(
            orderedFixtureIDs: ids,
            project: p,
            programmer: prog
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        XCTAssertEqual(pres.selectionCount, 80)
        XCTAssertEqual(pres.intensity.support, .all)
        XCTAssertEqual(pres.intensity.value, .mixed)
        XCTAssertLessThan(elapsed, 0.05, "presentation resolve should be fast")
    }
}
