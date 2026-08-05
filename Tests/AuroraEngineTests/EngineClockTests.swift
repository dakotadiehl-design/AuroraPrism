import AuroraEngine
import XCTest

final class EngineClockTests: XCTestCase {
    func testManualClockAdvance() {
        let clock = ManualEngineClock(time: 1)
        XCTAssertEqual(clock.now(), 1, accuracy: 0.0001)
        clock.advance(by: 0.5)
        XCTAssertEqual(clock.now(), 1.5, accuracy: 0.0001)
    }

    func testContinuousClockMovesForward() {
        let clock = ContinuousEngineClock()
        let a = clock.now()
        let b = clock.now()
        XCTAssertGreaterThanOrEqual(b, a)
    }

    func testFrameRateClamp() {
        XCTAssertEqual(EngineConfiguration.clampFrameRate(10), 20)
        XCTAssertEqual(EngineConfiguration.clampFrameRate(100), 44)
        XCTAssertEqual(EngineConfiguration(frameRateHz: 40).frameRateHz, 40)
    }
}
