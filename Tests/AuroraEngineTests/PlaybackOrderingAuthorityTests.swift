import AuroraEngine
import AuroraModel
import XCTest

/// UI-05 A4: Playback order is CueList array order; Cue.number is display metadata only.
final class PlaybackOrderingAuthorityTests: XCTestCase {
    private let fixtureID = UUID(uuidString: "B1000000-0000-4000-8000-000000000001")!

    private func project(with list: CueList) -> ShowProject {
        var p = ShowProject.empty(name: "Order")
        p.cueLists = [list]
        p.universes = [Universe(id: UUID(), number: 1, channelCount: 512)]
        p.fixtures = [
            PatchedFixture(
                id: fixtureID,
                name: "F1",
                definitionId: UUID(),
                universeId: p.universes[0].id,
                address: 1
            )
        ]
        return p
    }

    private func levelCue(id: UUID, number: Decimal, name: String, intensity: Double) -> Cue {
        Cue(
            id: id,
            number: number,
            name: name,
            fadeIn: 0,
            levels: CueLevelData(fixtures: [
                FixtureCueLevels(fixtureId: fixtureID, attributes: ["intensity": intensity])
            ])
        )
    }

    func testGOAdvancesByArrayIndexNotNumberSort() {
        // Array order: A(number 3), B(number 1), C(number 2) — numbers out of sequence.
        let idA = UUID()
        let idB = UUID()
        let idC = UUID()
        let list = CueList(
            name: "Main",
            cues: [
                levelCue(id: idA, number: 3, name: "Third-label", intensity: 0.3),
                levelCue(id: idB, number: 1, name: "First-label", intensity: 0.1),
                levelCue(id: idC, number: 2, name: "Second-label", intensity: 0.2),
            ]
        )
        let pb = PlaybackController()
        pb.load(list: list, project: project(with: list))

        pb.go(at: 0)
        XCTAssertEqual(pb.snapshot().cueIndex, 0)
        XCTAssertEqual(pb.snapshot().cueID, idA, "GO must follow array[0], not lowest Cue.number")

        pb.go(at: 1)
        XCTAssertEqual(pb.snapshot().cueIndex, 1)
        XCTAssertEqual(pb.snapshot().cueID, idB)

        pb.go(at: 2)
        XCTAssertEqual(pb.snapshot().cueIndex, 2)
        XCTAssertEqual(pb.snapshot().cueID, idC)
    }

    func testFireUsesArrayFirstIndexMatchingID() {
        let idA = UUID()
        let idB = UUID()
        let list = CueList(
            name: "Main",
            cues: [
                levelCue(id: idA, number: 10, name: "A", intensity: 0.5),
                levelCue(id: idB, number: 1, name: "B", intensity: 1.0),
            ]
        )
        let pb = PlaybackController()
        pb.load(list: list, project: project(with: list))
        pb.fire(cueID: idB, at: 0)
        XCTAssertEqual(pb.snapshot().cueIndex, 1)
        XCTAssertEqual(pb.snapshot().cueID, idB)
        XCTAssertEqual(pb.snapshot().cueName, "B")
    }

    func testDecimalDisplayNumbersDoNotReorderPlayback() {
        let c1 = UUID()
        let c25 = UUID()
        let c3 = UUID()
        let list = CueList(
            name: "Main",
            cues: [
                levelCue(id: c1, number: 1, name: "One", intensity: 0.1),
                levelCue(id: c25, number: Decimal(string: "2.5")!, name: "Two-five", intensity: 0.25),
                levelCue(id: c3, number: 3, name: "Three", intensity: 0.3),
            ]
        )
        let pb = PlaybackController()
        pb.load(list: list, project: project(with: list))
        pb.go(at: 0)
        pb.go(at: 1)
        XCTAssertEqual(pb.snapshot().cueID, c25)
        XCTAssertEqual(pb.snapshot().cueIndex, 1)
        pb.go(at: 2)
        XCTAssertEqual(pb.snapshot().cueID, c3)
    }

    func testCueResolverUsesArrayIndexNotNumber() {
        let list = CueList(
            name: "Main",
            cues: [
                levelCue(id: UUID(), number: 99, name: "Hi", intensity: 0.99),
                levelCue(id: UUID(), number: 1, name: "Lo", intensity: 0.11),
            ]
        )
        let project = project(with: list)
        let look0 = CueResolver.resolveLook(list: list, index: 0, project: project)
        let look1 = CueResolver.resolveLook(list: list, index: 1, project: project)
        XCTAssertEqual(look0.fixtureAttributes[fixtureID]?["intensity"], 0.99)
        XCTAssertEqual(look1.fixtureAttributes[fixtureID]?["intensity"], 0.11)
    }
}
