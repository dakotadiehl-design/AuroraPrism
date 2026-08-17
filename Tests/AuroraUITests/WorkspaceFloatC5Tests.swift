import AuroraUI
import XCTest

@MainActor
final class WorkspaceFloatC5Tests: XCTestCase {
    func testDefaultAllDocked() {
        let state = WorkspaceFloatState.default
        for id in FloatSurfaceID.allCases {
            XCTAssertTrue(state.showsInMainWindow(id))
            XCTAssertFalse(state.isFloating(id))
        }
    }

    func testUndockRedockCycle() {
        var state = WorkspaceFloatState.default
        state.float(.programmer, frame: CGRect(x: 100, y: 100, width: 600, height: 400), screenID: "0")
        XCTAssertTrue(state.isFloating(.programmer))
        XCTAssertFalse(state.showsInMainWindow(.programmer))
        XCTAssertEqual(state.record(for: .programmer).frameW ?? 0, 600, accuracy: 0.1)

        state.dock(.programmer)
        XCTAssertFalse(state.isFloating(.programmer))
        XCTAssertTrue(state.showsInMainWindow(.programmer))
    }

    func testMultiSurfaceIndependence() {
        var state = WorkspaceFloatState.default
        state.float(.inspector)
        state.float(.stagePreview)
        XCTAssertTrue(state.isFloating(.inspector))
        XCTAssertTrue(state.isFloating(.stagePreview))
        XCTAssertTrue(state.showsInMainWindow(.browser))
        state.dock(.inspector)
        XCTAssertFalse(state.isFloating(.inspector))
        XCTAssertTrue(state.isFloating(.stagePreview))
    }

    func testRecoverOffscreenFrame() {
        var state = WorkspaceFloatState.default
        state.float(.inspector, frame: CGRect(x: -5000, y: -5000, width: 300, height: 500))
        let screens = [ScreenVisibleRecord(id: "main", visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))]
        _ = state.recoverFrames(to: screens)
        let f = state.record(for: .inspector).frame!
        XCTAssertTrue(screens[0].visibleFrame.intersects(f))
        XCTAssertGreaterThan(f.minX, -1)
        XCTAssertGreaterThan(f.minY, -1)
    }

    func testRoundTripPersistence() throws {
        var state = WorkspaceFloatState.default
        state.float(.lowerShelf, frame: CGRect(x: 10, y: 20, width: 800, height: 300), screenID: "main")
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WorkspaceFloatState.self, from: data)
        XCTAssertTrue(decoded.isFloating(.lowerShelf))
        XCTAssertEqual(decoded.record(for: .lowerShelf).screenID, "main")
        XCTAssertEqual(decoded.record(for: .lowerShelf).frameW ?? 0, 800, accuracy: 0.1)
    }

    func testSurfaceCatalogComplete() {
        let required: Set<FloatSurfaceID> = [
            .browser, .stagePreview, .programmer, .inspector, .lowerShelf, .diagnostics
        ]
        XCTAssertEqual(Set(FloatSurfaceID.allCases), required)
    }

    // MARK: - C5.1 additions

    func testFrameUpdateReflectsInState() {
        var state = WorkspaceFloatState.default
        let frameA = CGRect(x: 50, y: 60, width: 400, height: 300)
        state.float(.programmer, frame: frameA, screenID: "display-1")
        XCTAssertEqual(state.record(for: .programmer).frame, frameA)

        let frameB = CGRect(x: 200, y: 150, width: 720, height: 480)
        var rec = state.record(for: .programmer)
        rec.setFrame(frameB)
        rec.screenID = "display-2"
        state.setRecord(rec, for: .programmer)

        XCTAssertEqual(state.record(for: .programmer).frame, frameB)
        XCTAssertEqual(state.record(for: .programmer).screenID, "display-2")
    }

    func testRecoveryAcrossMonitorGap() {
        // Two monitors with a gap between them — frame entirely in the gap.
        let screens = [
            ScreenVisibleRecord(id: "A", visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)),
            ScreenVisibleRecord(id: "B", visibleFrame: CGRect(x: 2000, y: 0, width: 1920, height: 1080)),
        ]
        let gapFrame = CGRect(x: 1500, y: 200, width: 400, height: 300)
        let result = WorkspaceFloatState.recoverFrame(gapFrame, preferredScreenID: nil, screens: screens)
        XCTAssertTrue(
            screens.contains { $0.visibleFrame.intersects(result.frame) },
            "Recovered frame must intersect a real screen, not sit in the gap"
        )
        // Must not remain fully in the gap.
        let stillInGapOnly = !screens[0].visibleFrame.intersects(result.frame)
            && !screens[1].visibleFrame.intersects(result.frame)
        XCTAssertFalse(stillInGapOnly)
    }

    func testRecoveryRemovedMonitorUsesPreferredFallback() {
        let screens = [
            ScreenVisibleRecord(id: "A", visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)),
        ]
        // Frame was on removed monitor B.
        let external = CGRect(x: 2000, y: 100, width: 500, height: 400)
        let result = WorkspaceFloatState.recoverFrame(external, preferredScreenID: "B", screens: screens)
        XCTAssertEqual(result.screenID, "A")
        XCTAssertTrue(screens[0].visibleFrame.intersects(result.frame))
    }

    func testRecoveryPreferredScreenPreservedWhenPresent() {
        let screens = [
            ScreenVisibleRecord(id: "A", visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)),
            ScreenVisibleRecord(id: "B", visibleFrame: CGRect(x: 2000, y: 0, width: 1920, height: 1080)),
        ]
        let onB = CGRect(x: 2100, y: 100, width: 400, height: 300)
        let result = WorkspaceFloatState.recoverFrame(onB, preferredScreenID: "B", screens: screens)
        XCTAssertEqual(result.screenID, "B")
        XCTAssertTrue(screens[1].visibleFrame.intersects(result.frame))
    }

    func testRecoveryShrinksOversizedWindow() {
        let screens = [
            ScreenVisibleRecord(id: "A", visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600)),
        ]
        let huge = CGRect(x: 0, y: 0, width: 3000, height: 2000)
        let result = WorkspaceFloatState.recoverFrame(huge, preferredScreenID: "A", screens: screens)
        XCTAssertLessThanOrEqual(result.frame.width, screens[0].visibleFrame.width)
        XCTAssertLessThanOrEqual(result.frame.height, screens[0].visibleFrame.height)
        XCTAssertTrue(screens[0].visibleFrame.intersects(result.frame))
    }

    func testRecoveryPartiallyVisibleClamped() {
        let screens = [
            ScreenVisibleRecord(id: "A", visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)),
        ]
        // Mostly off the left edge.
        let partial = CGRect(x: -200, y: 100, width: 400, height: 300)
        let result = WorkspaceFloatState.recoverFrame(partial, preferredScreenID: "A", screens: screens)
        XCTAssertGreaterThanOrEqual(result.frame.minX, screens[0].visibleFrame.minX - 0.5)
        XCTAssertTrue(screens[0].visibleFrame.intersects(result.frame))
    }

    func testBrowserAndShelfSurfaceContracts() {
        XCTAssertEqual(FloatSurfaceID.browserSubtools, ["Browser", "Groups"])
        XCTAssertEqual(
            FloatSurfaceID.creativeShelfSubtools,
            ["Palettes", "Cues", "Song", "Diagnostics"]
        )
    }

    func testHiddenDoesNotReportFloating() {
        var state = WorkspaceFloatState.default
        state.hide(.diagnostics)
        XCTAssertFalse(state.isFloating(.diagnostics))
        XCTAssertFalse(state.showsInMainWindow(.diagnostics))
        XCTAssertEqual(state.record(for: .diagnostics).kind, .hidden)
    }

    func testQuitPreservesFloatingConceptually() {
        // Application termination must leave kind == .floating (coordinator skips redock).
        var state = WorkspaceFloatState.default
        state.float(.inspector, frame: CGRect(x: 10, y: 10, width: 300, height: 500), screenID: "A")
        // Simulate: no dock on quit — only user close docks.
        XCTAssertTrue(state.isFloating(.inspector))
        // User close policy:
        state.dock(.inspector)
        XCTAssertFalse(state.isFloating(.inspector))
    }

    func testFloatStoreRoundTripMainActor() {
        var state = WorkspaceFloatState.default
        state.float(.stagePreview, frame: CGRect(x: 1, y: 2, width: 900, height: 640), screenID: "display-9")
        let suite = "aurora.float.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        WorkspaceFloatStore.save(state, to: defaults)
        let loaded = WorkspaceFloatStore.load(from: defaults)
        XCTAssertTrue(loaded.isFloating(.stagePreview))
        XCTAssertEqual(loaded.record(for: .stagePreview).screenID, "display-9")
        defaults.removePersistentDomain(forName: suite)
    }
}
