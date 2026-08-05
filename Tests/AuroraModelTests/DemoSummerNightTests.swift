import AuroraModel
import XCTest

final class DemoSummerNightTests: XCTestCase {
    func testDemoDoesNotSurpriseRouteArtNet() {
        let demo = ShowProject.demoSummerNight()
        for universe in demo.universes {
            XCTAssertEqual(universe.protocolHint, .none, "Demo universe must default to .none")
        }
    }

    func testDemoCueIDsAreDeterministic() {
        let a = ShowProject.demoSummerNight()
        let b = ShowProject.demoSummerNight()
        XCTAssertEqual(a.cueLists.count, 1)
        XCTAssertEqual(a.cueLists[0].cues.count, 18)
        let idsA = a.cueLists[0].cues.map(\.id)
        let idsB = b.cueLists[0].cues.map(\.id)
        XCTAssertEqual(idsA, idsB)
        // Fixed prefix used by demo builder
        XCTAssertEqual(
            idsA[0],
            UUID(uuidString: "A1000000-0000-4000-8000-000000000601")
        )
    }

    func testDemoSongEntriesReferenceStableCueIDs() {
        let demo = ShowProject.demoSummerNight()
        guard let song = demo.songs.first,
              let list = demo.cueLists.first
        else {
            return XCTFail("missing song/list")
        }
        let cueIDs = Set(list.cues.map(\.id))
        for entry in song.entries {
            if case .cue(_, let cueId) = entry.target {
                XCTAssertTrue(cueIDs.contains(cueId), "song entry must reference demo cue")
            }
        }
    }

    func testDemoCueNumbersAreRealNotIndexOnly() {
        let demo = ShowProject.demoSummerNight()
        let cues = demo.cueLists[0].cues
        XCTAssertEqual(cues[0].number, Decimal(string: "1.0"))
        XCTAssertEqual(cues[9].number, Decimal(string: "10.0"))
        XCTAssertEqual(cues[9].name, "Audience Sweep")
    }
}
