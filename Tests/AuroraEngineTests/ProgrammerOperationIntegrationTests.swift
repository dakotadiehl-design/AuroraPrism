import AuroraEngine
import AuroraModel
import XCTest

/// Ordered selection → capable filter → Fan/Align (UI-03 CR-07).
final class ProgrammerOperationIntegrationTests: XCTestCase {
    private let dimDef = UUID(uuidString: "F1000000-0000-4000-8000-000000000001")!
    private let mhDef = UUID(uuidString: "F1000000-0000-4000-8000-000000000002")!
    private let a = UUID(uuidString: "F1000000-0000-4000-8000-0000000000A1")!
    private let b = UUID(uuidString: "F1000000-0000-4000-8000-0000000000B1")!
    private let c = UUID(uuidString: "F1000000-0000-4000-8000-0000000000C1")!
    private let u1 = UUID(uuidString: "F1000000-0000-4000-8000-0000000000AA")!

    private func project() -> ShowProject {
        var p = ShowProject.empty(name: "Ops")
        p.universes = [Universe(id: u1, number: 1)]
        p.fixtureDefinitions = [
            FixtureDefinition(
                id: dimDef, manufacturer: "G", model: "Dim",
                channels: [ChannelDef(offset: 1, name: "I", attribute: "intensity")]
            ),
            FixtureDefinition(
                id: mhDef, manufacturer: "G", model: "MH",
                channels: [
                    ChannelDef(offset: 1, name: "P", attribute: "pan"),
                    ChannelDef(offset: 2, name: "I", attribute: "intensity"),
                ],
                hasPanTilt: true
            ),
        ]
        // A,C = MH (pan+I); B = dimmer (I only)
        p.fixtures = [
            PatchedFixture(id: a, name: "A", definitionId: mhDef, universeId: u1, address: 1),
            PatchedFixture(id: b, name: "B", definitionId: dimDef, universeId: u1, address: 10),
            PatchedFixture(id: c, name: "C", definitionId: mhDef, universeId: u1, address: 20),
        ]
        return p
    }

    func testFanUsesOrderedCapablePhase() {
        let p = project()
        let ordered = [a, b, c]
        let capable = ProgrammerAttributePresentationResolver.capableFixtureIDs(
            attribute: "pan",
            orderedFixtureIDs: ordered,
            project: p
        )
        XCTAssertEqual(capable, [a, c], "dimmer mid-list skipped; relative capable order preserved")

        let map = ProgrammerGeometry.fan(fixtureIDs: capable, center: 0.5, spread: 0.5)
        XCTAssertEqual(map[a]!, 0.0, accuracy: 1e-9) // first of capable
        XCTAssertEqual(map[c]!, 1.0, accuracy: 1e-9) // last of capable
        XCTAssertNil(map[b])
    }

    func testFanReverseOrderedSelection() {
        let p = project()
        let capable = ProgrammerAttributePresentationResolver.capableFixtureIDs(
            attribute: "pan",
            orderedFixtureIDs: [c, b, a],
            project: p
        )
        XCTAssertEqual(capable, [c, a])
        let map = ProgrammerGeometry.fan(fixtureIDs: capable, center: 0.5, spread: 0.5)
        XCTAssertEqual(map[c]!, 0.0, accuracy: 1e-9)
        XCTAssertEqual(map[a]!, 1.0, accuracy: 1e-9)
    }

    func testAlignSkipsUnsupportedLeaderUsesFirstCapableOwned() {
        let p = project()
        // order: dimmer first, then MH with pan value
        let ordered = [b, a, c]
        let capable = ProgrammerAttributePresentationResolver.capableFixtureIDs(
            attribute: "pan",
            orderedFixtureIDs: ordered,
            project: p
        )
        XCTAssertEqual(capable.first, a)

        let values: [UUID: Double] = [a: 0.33, c: 0.9]
        let map = ProgrammerGeometry.alignToFirst(fixtureIDs: capable, values: values)
        XCTAssertNotNil(map)
        XCTAssertEqual(map![a]!, 0.33, accuracy: 1e-9)
        XCTAssertEqual(map![c]!, 0.33, accuracy: 1e-9)
    }

    func testPartialTwoCapableMixed() {
        let p = project()
        var prog = ProgrammerState()
        prog.values = [a: ["pan": 0.2], c: ["pan": 0.8]]
        let st = ProgrammerAttributePresentationResolver.resolve(
            orderedFixtureIDs: [a, b, c],
            project: p,
            programmer: prog
        )
        XCTAssertEqual(st.pan.support, .partial)
        XCTAssertEqual(st.pan.value, .mixed)
    }

    func testPartialTwoCapableCommon() {
        let p = project()
        var prog = ProgrammerState()
        prog.values = [a: ["pan": 0.4], c: ["pan": 0.4]]
        let st = ProgrammerAttributePresentationResolver.resolve(
            orderedFixtureIDs: [a, b, c],
            project: p,
            programmer: prog
        )
        XCTAssertEqual(st.pan.support, .partial)
        if case .common(let v) = st.pan.value {
            XCTAssertEqual(v, 0.4, accuracy: 1e-9)
        } else {
            XCTFail("\(st.pan.value)")
        }
    }

    func testAllSupportOwnedPlusUntouchedIsMixed() {
        let p = project()
        var prog = ProgrammerState()
        prog.values = [a: ["intensity": 0.5]] // b,c capable intensity but untouched
        let st = ProgrammerAttributePresentationResolver.resolve(
            orderedFixtureIDs: [a, b, c],
            project: p,
            programmer: prog
        )
        XCTAssertEqual(st.intensity.support, .all)
        XCTAssertEqual(st.intensity.value, .mixed)
    }
}
