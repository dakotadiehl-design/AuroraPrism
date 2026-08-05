import AuroraDiagnostics
import AuroraEngine
import AuroraModel
import AuroraOutput
import XCTest

final class PerformanceScaleTests: XCTestCase {
    func testScaleMergeManyFixturesUnderBudget() {
        let output = OutputManager()
        output.register(NullOutputDriver())
        let engine = LightingEngine(output: output, clock: ManualEngineClock(time: 0))

        var project = ShowProject.empty()
        let universeID = UUID()
        project.universes = [Universe(id: universeID, number: 1, channelCount: 512)]
        let defID = UUID()
        project.fixtureDefinitions = [
            FixtureDefinition(
                id: defID,
                manufacturer: "G",
                model: "D",
                channels: [ChannelDef(offset: 1, name: "I", attribute: "intensity")]
            )
        ]
        // 200 single-channel fixtures packed on universe 1 (addresses 1…200).
        var fixtures: [PatchedFixture] = []
        var look = ActiveLook()
        for i in 0..<200 {
            let fid = UUID()
            fixtures.append(
                PatchedFixture(
                    id: fid,
                    name: "F\(i)",
                    definitionId: defID,
                    universeId: universeID,
                    address: UInt16(i + 1)
                )
            )
            look.set(fixtureID: fid, attribute: "intensity", value: Double(i % 10) / 10.0)
        }
        project.fixtures = fixtures
        engine.load(project: project)
        engine.setLook(look)
        engine.frameMetrics.reset()

        let iterations = 30
        for _ in 0..<iterations {
            engine.stepForTesting()
        }
        let metrics = engine.frameMetrics.snapshot()
        XCTAssertEqual(metrics.sampleCount, iterations)
        XCTAssertLessThan(
            metrics.meanFrameMs,
            PerformanceBudget.scaleTestMeanFrameMs,
            "mean frame \(metrics.meanFrameMs) ms exceeded budget"
        )
    }

    func testFrameMetricsRecorderBasics() {
        let rec = FrameMetricsRecorder(window: 10)
        rec.record(durationSeconds: 0.001)
        rec.record(durationSeconds: 0.002)
        let snap = rec.snapshot()
        XCTAssertEqual(snap.sampleCount, 2)
        XCTAssertEqual(snap.lastFrameMs, 2, accuracy: 0.001)
        XCTAssertEqual(snap.meanFrameMs, 1.5, accuracy: 0.001)
        XCTAssertEqual(snap.maxFrameMs, 2, accuracy: 0.001)
    }
}
