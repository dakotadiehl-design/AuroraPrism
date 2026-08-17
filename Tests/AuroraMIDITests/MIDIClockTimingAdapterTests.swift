import AuroraMIDI
import AuroraMusical
import XCTest

private final class RecordingSink: MusicalTimingSink, @unchecked Sendable {
    private let lock = NSLock()
    var pulses: [(String, HostTime)] = []
    var starts: [String] = []
    var stops: [String] = []
    var continues: [String] = []
    var spp: [(QuarterNotePosition, String)] = []

    func receiveClockPulse(from sourceID: String, at hostTime: HostTime) {
        lock.lock(); pulses.append((sourceID, hostTime)); lock.unlock()
    }
    func receiveTransportStart(from sourceID: String, at hostTime: HostTime) {
        lock.lock(); starts.append(sourceID); lock.unlock()
    }
    func receiveTransportStop(from sourceID: String, at hostTime: HostTime) {
        lock.lock(); stops.append(sourceID); lock.unlock()
    }
    func receiveTransportContinue(from sourceID: String, at hostTime: HostTime) {
        lock.lock(); continues.append(sourceID); lock.unlock()
    }
    func receiveSongPosition(_ position: QuarterNotePosition, from sourceID: String, at hostTime: HostTime) {
        lock.lock(); spp.append((position, sourceID)); lock.unlock()
    }
}

final class MIDIClockTimingAdapterTests: XCTestCase {
    func testForwardsClockStartStopContinueAndSPP() {
        let sink = RecordingSink()
        let adapter = MIDIClockTimingAdapter(sink: sink)
        let t = HostTime(nanoseconds: 42)
        let events: [MIDIIngressEvent] = [
            .systemRealtime(.start, sourceID: "d", hostTime: t),
            .systemRealtime(.timingClock, sourceID: "d", hostTime: t),
            .systemRealtime(.timingClock, sourceID: "d", hostTime: t),
            .systemCommon(.songPositionPointer(sixteenths: 16), sourceID: "d", hostTime: t),
            .systemRealtime(.stop, sourceID: "d", hostTime: t),
            .systemRealtime(.continue, sourceID: "d", hostTime: t),
            .channelVoice(MIDIChannelVoiceEvent(
                event: .noteOn(channel: 0, note: 38, velocity: 100, sourceID: "d", timestamp: 0),
                hostTime: t
            )),
        ]
        adapter.handle(ingress: events)
        XCTAssertEqual(sink.starts, ["d"])
        XCTAssertEqual(sink.pulses.count, 2)
        XCTAssertEqual(sink.spp.count, 1)
        XCTAssertEqual(sink.spp[0].0.quarters, 4, accuracy: 1e-9)
        XCTAssertEqual(sink.stops, ["d"])
        XCTAssertEqual(sink.continues, ["d"])
    }

    func testPreferredSourceFilter() {
        let sink = RecordingSink()
        let adapter = MIDIClockTimingAdapter(sink: sink)
        adapter.setPreferredSourceID("keep")
        let t = HostTime(nanoseconds: 1)
        adapter.handle(ingress: [
            .systemRealtime(.timingClock, sourceID: "drop", hostTime: t),
            .systemRealtime(.timingClock, sourceID: "keep", hostTime: t),
        ])
        XCTAssertEqual(sink.pulses.count, 1)
        XCTAssertEqual(sink.pulses[0].0, "keep")
    }

    func testAdapterDrivesMusicalEngineLock() {
        let clock = VirtualHostClock()
        let engine = MusicalEngine(
            clock: clock,
            clockEstimatorConfig: .init(lockPulseCount: 8)
        )
        engine.setTimingPolicy(.externalMIDI)
        engine.selectExternalTimingSource("kit")
        let adapter = MIDIClockTimingAdapter(sink: engine)

        let interval = 60.0 / (120.0 * 24.0)
        // Start
        adapter.handle(ingress: [
            .systemRealtime(.start, sourceID: "kit", hostTime: clock.now()),
        ])
        for _ in 0..<40 {
            clock.advance(seconds: interval)
            adapter.handle(ingress: [
                .systemRealtime(.timingClock, sourceID: "kit", hostTime: clock.now()),
            ])
        }
        XCTAssertEqual(engine.state.timing.sync, .locked)
        XCTAssertGreaterThanOrEqual(engine.state.timing.quarterNotePosition?.quarters ?? 0, 0.9)
    }
}
