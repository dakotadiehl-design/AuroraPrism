import AuroraEngine
import XCTest

final class FrameMetricsPercentileTests: XCTestCase {
    func testPercentilesAndOverruns() {
        let rec = FrameMetricsRecorder(window: 100, targetPeriodMs: 10)
        for i in 1...100 {
            rec.record(durationSeconds: Double(i) / 1000.0) // 1…100 ms
        }
        let snap = rec.snapshot()
        XCTAssertEqual(snap.sampleCount, 100)
        XCTAssertGreaterThan(snap.p95FrameMs, snap.meanFrameMs)
        XCTAssertGreaterThanOrEqual(snap.p99FrameMs, snap.p95FrameMs)
        XCTAssertGreaterThan(snap.overrunCount, 0)
        XCTAssertGreaterThan(snap.jitterMs, 0)
    }
}
