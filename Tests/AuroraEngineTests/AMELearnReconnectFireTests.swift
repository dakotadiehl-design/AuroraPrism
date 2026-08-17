import AuroraEngine
import AuroraModel
import AuroraMusical
import XCTest

/// Pass 3 post-impl: reconnect resolution fires AME; orphan Learn path is rejected at identity layer.
final class AMELearnReconnectFireTests: XCTestCase {
    func testResolvedNameBindingFiresAfterEndpointRefChange() {
        let runtime = AMERuntime()
        let bid = UUID()
        let tid = UUID()
        // Learned in session 1 with durable name (never ep: as hint).
        let binding = MIDISourceBinding(
            id: bid,
            displayName: "Network Session 1",
            endpointNameHint: "Network Session 1"
        )
        let doc = AMEProjectDocument(
            triggers: [
                AMETriggerDefinition(
                    id: tid,
                    name: "Snare",
                    sourceBindingID: bid,
                    messageType: .noteOn,
                    data1Min: 36,
                    data1Max: 36
                ),
            ],
            mappings: [AMEMapping(name: "M", triggerID: tid, actions: [.go])],
            sourceBindings: [binding]
        )
        _ = runtime.updateDocument(doc)
        // Session 2: same name, new ep:
        runtime.setResolvedSourceBindings([bid: ["ep:900"]])
        let r = runtime.process(
            AMENormalizedEvent(
                messageType: .noteOn, channel: 0, data1: 36, data2: 100,
                sourceID: "ep:900", hostTime: HostTime(nanoseconds: 1)
            ),
            document: doc
        )
        XCTAssertFalse(r.emissions.isEmpty)
        XCTAssertTrue(r.emissions.contains { $0.action == .go })
    }

    func testAmbiguousResolvedBindingDoesNotFire() {
        let runtime = AMERuntime()
        let bid = UUID()
        let tid = UUID()
        let binding = MIDISourceBinding(
            id: bid,
            displayName: "Pad",
            endpointNameHint: "Pad"
        )
        let doc = AMEProjectDocument(
            triggers: [
                AMETriggerDefinition(
                    id: tid, name: "T", sourceBindingID: bid,
                    messageType: .noteOn, data1Min: 36, data1Max: 36
                ),
            ],
            mappings: [AMEMapping(name: "M", triggerID: tid, actions: [.go])],
            sourceBindings: [binding]
        )
        _ = runtime.updateDocument(doc)
        runtime.setResolvedSourceBindings([bid: []]) // fail closed
        let r = runtime.process(
            AMENormalizedEvent(
                messageType: .noteOn, channel: 0, data1: 36, data2: 100,
                sourceID: "ep:1", hostTime: HostTime(nanoseconds: 1)
            ),
            document: doc
        )
        XCTAssertTrue(r.emissions.isEmpty)
    }

    func testMakeDurableBindingUnavailableMeansNoBindingForProposal() {
        // Confirms the identity-layer contract Learn uses before commit.
        switch MIDISourceIdentity.makeDurableBinding(runtimeSourceID: "ep:42", inventory: nil) {
        case .binding:
            XCTFail("must not commit orphan")
        case .unavailable:
            break
        }
    }
}
