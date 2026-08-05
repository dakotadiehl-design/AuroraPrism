import AuroraEngine
import AuroraModel
import AuroraOutput
import XCTest

/// Post-UI-02 gate G1: updateProject preserves active cue UUID, not array index.
final class PlaybackCueIdentityOnUpdateTests: XCTestCase {
    private let listID = UUID(uuidString: "C1000000-0000-4000-8000-000000000001")!
    private let cue1 = UUID(uuidString: "C1000000-0000-4000-8000-000000000011")!
    private let cue2 = UUID(uuidString: "C1000000-0000-4000-8000-000000000012")!
    private let cue3 = UUID(uuidString: "C1000000-0000-4000-8000-000000000013")!
    private let cueNew = UUID(uuidString: "C1000000-0000-4000-8000-000000000014")!

    private func project(cues: [Cue]) -> ShowProject {
        var project = ShowProject.empty(name: "Identity")
        project.cueLists = [CueList(id: listID, name: "Main", cues: cues)]
        return project
    }

    private func baseCues() -> [Cue] {
        [
            Cue(id: cue1, number: 1, name: "One", fadeIn: 0),
            Cue(id: cue2, number: 2, name: "Two", fadeIn: 0),
            Cue(id: cue3, number: 3, name: "Three", fadeIn: 0),
        ]
    }

    private func engineOnCue3() throws -> (LightingEngine, ShowProject) {
        let project = project(cues: baseCues())
        let engine = LightingEngine(output: OutputManager())
        engine.load(project: project)
        engine.fire(cueID: cue3)
        engine.stepForTesting()
        let snap = engine.currentSnapshot().playback
        XCTAssertEqual(snap.cueID, cue3)
        XCTAssertEqual(snap.cueIndex, 2)
        return (engine, project)
    }

    func testInsertBeforeCurrentPreservesCueID() throws {
        var (engine, project) = try engineOnCue3()
        var list = project.cueLists[0]
        // Insert before cue3 (index 2)
        list.cues.insert(Cue(id: cueNew, number: Decimal(string: "2.5")!, name: "Inserted", fadeIn: 0), at: 2)
        project.cueLists = [list]
        engine.updateProject(project)
        engine.stepForTesting()

        let snap = engine.currentSnapshot().playback
        XCTAssertEqual(snap.cueID, cue3, "semantic CURRENT must stay cue3")
        XCTAssertEqual(snap.cueIndex, 3, "index should move after insert")
        XCTAssertEqual(snap.listID, listID)
        XCTAssertEqual(snap.phase, .active)
    }

    func testReorderPreservesCueID() throws {
        var (engine, project) = try engineOnCue3()
        var list = project.cueLists[0]
        // Move cue3 to front
        let three = list.cues.remove(at: 2)
        list.cues.insert(three, at: 0)
        project.cueLists = [list]
        engine.updateProject(project)
        engine.stepForTesting()

        let snap = engine.currentSnapshot().playback
        XCTAssertEqual(snap.cueID, cue3)
        XCTAssertEqual(snap.cueIndex, 0)
    }

    func testDeleteActiveCueDetachesWithoutSubstitute() throws {
        var (engine, project) = try engineOnCue3()
        var list = project.cueLists[0]
        list.cues.removeAll { $0.id == cue3 }
        project.cueLists = [list]
        engine.updateProject(project)
        engine.stepForTesting()

        let snap = engine.currentSnapshot().playback
        XCTAssertEqual(snap.cueIndex, -1)
        XCTAssertNil(snap.cueID)
        XCTAssertEqual(snap.phase, .idle)
        XCTAssertEqual(snap.listID, listID, "list remains loaded")

        // Presentation must not invent CURRENT from remaining cues via wrong index
        let (current, _) = PerformanceCuePresentation.resolveCues(
            project: project,
            playback: snap,
            song: .empty
        )
        XCTAssertEqual(current, .empty)
    }

    func testDeleteActiveListDetaches() throws {
        var (engine, project) = try engineOnCue3()
        project.cueLists = [
            CueList(
                id: UUID(),
                name: "Other",
                cues: [Cue(id: UUID(), number: 1, name: "Unrelated", fadeIn: 0)]
            )
        ]
        engine.updateProject(project)
        engine.stepForTesting()

        let snap = engine.currentSnapshot().playback
        XCTAssertNil(snap.listID)
        XCTAssertEqual(snap.cueIndex, -1)
        XCTAssertEqual(snap.phase, .idle)

        let (current, _) = PerformanceCuePresentation.resolveCues(
            project: project,
            playback: snap,
            song: .empty
        )
        XCTAssertEqual(current.cueID, nil)
        XCTAssertNotEqual(current.name, "Unrelated")
    }
}
