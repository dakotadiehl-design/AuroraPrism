import AuroraEngine
import AuroraModel
import AuroraOutput
import XCTest

final class LightingEngineFrameSerializationTests: XCTestCase {

    func testConcurrentPanicAndClearDoNotOverlapFrames() throws {
        let mock = MockOutputDriver()
        let output = OutputManager()
        output.register(mock)
        let engine = LightingEngine(
            output: output,
            configuration: EngineConfiguration(frameRateHz: 120, channelCount: 16, snapshotThrottleHz: 60)
        )
        engine.resetConcurrentFrameStatsForTesting()
        try engine.start()

        let group = DispatchGroup()
        let iterations = 40
        for _ in 0..<iterations {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                engine.panic()
                group.leave()
            }
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                engine.clearOverrides()
                group.leave()
            }
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                engine.setFreeze(true)
                engine.setFreeze(false)
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)
        engine.stop()

        XCTAssertEqual(
            engine.maxConcurrentFramesObserved,
            1,
            "Frame pipeline must never execute two bodies concurrently"
        )
        XCTAssertGreaterThan(engine.currentSnapshot().frameIndex, 0)
    }

    func testFrameIndexIsMonotonicUnderConcurrentForceFrames() throws {
        let mock = MockOutputDriver()
        let output = OutputManager()
        output.register(mock)
        let engine = LightingEngine(
            output: output,
            configuration: EngineConfiguration(frameRateHz: 80, channelCount: 8, snapshotThrottleHz: 80)
        )
        try engine.start()

        var indices: [UInt64] = []
        let lock = NSLock()
        let group = DispatchGroup()
        for _ in 0..<30 {
            group.enter()
            DispatchQueue.global().async {
                engine.panic()
                let idx = engine.currentSnapshot().frameIndex
                lock.lock()
                indices.append(idx)
                lock.unlock()
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        engine.stop()

        let sorted = indices.sorted()
        // Each observed snapshot index should be non-decreasing when sorted sample is unique path;
        // final index must be >= max sampled.
        XCTAssertEqual(engine.currentSnapshot().frameIndex, sorted.last)
        XCTAssertEqual(engine.maxConcurrentFramesObserved, 1)
    }

    func testStopPreventsFurtherFlush() throws {
        let mock = MockOutputDriver()
        let output = OutputManager()
        output.register(mock)
        let engine = LightingEngine(output: output)
        try engine.start()
        engine.stepForTesting()
        let framesBefore = mock.frames.count
        engine.stop()
        // Forced panic after stop must not flush (frames disabled).
        engine.panic()
        XCTAssertEqual(mock.frames.count, framesBefore, "No post-stop physical flush")
        XCTAssertEqual(engine.maxConcurrentFramesObserved, 1)
    }
}
