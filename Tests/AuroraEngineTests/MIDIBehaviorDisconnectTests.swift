import AuroraEngine
import AuroraModel
import XCTest

final class MIDIBehaviorDisconnectTests: XCTestCase {
    private func makeDef(id: UUID = UUID(), attribute: String = "intensity") -> MIDIBehaviorDefinition {
        MIDIBehaviorDefinition(
            id: id,
            name: "Flash",
            enabled: true,
            messageType: "noteOn",
            data1Min: 36,
            data1Max: 36,
            attribute: attribute,
            peakLevel: 1,
            velocityScale: false,
            envelope: MIDIEnvelopeSpec(attack: 0, hold: 0, decay: 0, sustain: 1.0, release: 0.05),
            maxConcurrent: 8
        )
    }

    func testReleaseAllForDeviceIDOnlyThatSource() {
        let runtime = MIDIBehaviorRuntime()
        runtime.load(definitions: [makeDef()], drums: [])
        let fx = UUID()
        runtime.noteOn(
            note: 36, velocity: 100, channel: 0, deviceID: "uid:A",
            songSection: nil, time: 1.0, selection: [fx]
        )
        runtime.noteOn(
            note: 36, velocity: 100, channel: 0, deviceID: "uid:B",
            songSection: nil, time: 1.0, selection: [fx]
        )
        XCTAssertEqual(runtime.liveCount, 2)
        let n = runtime.releaseAll(forDeviceID: "uid:A", at: 2.0)
        XCTAssertEqual(n, 1)
        // Both still live until envelope finishes, but A is marked released.
        XCTAssertEqual(runtime.liveCount, 2)
        // Advance past release envelope.
        _ = runtime.apply(on: ActiveLook(), time: 3.0)
        XCTAssertEqual(runtime.liveCount, 1, "only B should remain after A finishes release")
    }

    func testNoteOffReleasesMatchingKey() {
        let runtime = MIDIBehaviorRuntime()
        runtime.load(definitions: [makeDef()], drums: [])
        let fx = UUID()
        runtime.noteOn(
            note: 36, velocity: 100, channel: 0, deviceID: "pad",
            songSection: nil, time: 0, selection: [fx]
        )
        runtime.noteOff(note: 36, channel: 0, deviceID: "pad", time: 0.1)
        _ = runtime.apply(on: ActiveLook(), time: 1.0)
        XCTAssertEqual(runtime.liveCount, 0)
    }
}
