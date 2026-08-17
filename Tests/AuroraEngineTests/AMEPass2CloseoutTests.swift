import AuroraEngine
import AuroraModel
import AuroraMusical
import XCTest

/// Code Review Pass 2 closeout: idempotency, truthful support, binding resolution.
final class AMEPass2CloseoutTests: XCTestCase {

    // MARK: - P0-1 MusicalEngine idempotency

    func testSetTimingPolicyIdempotentDoesNotDropAuthority() {
        let engine = MusicalEngine()
        engine.setTimingPolicy(.externalMIDI)
        engine.selectExternalTimingSource("uid:1")
        // Simulate lock by replacing timing for test harness when available, or just re-apply.
        engine.setTimingPolicy(.externalMIDI) // must no-op
        XCTAssertEqual(engine.state.timing.timingPolicy, .externalMIDI)
        XCTAssertEqual(engine.state.timing.selectedSourceID, "uid:1")
    }

    func testSetProjectDefaultsIdempotentNoTempoJump() {
        let engine = MusicalEngine()
        engine.setProjectDefaults(tempoBPM: 96, meter: .fourFour)
        let before = engine.state.timing.tempoBPM
        engine.setProjectDefaults(tempoBPM: 96, meter: .fourFour)
        XCTAssertEqual(engine.state.timing.tempoBPM, before)
    }

    func testSetClockEstimatorConfigIdempotent() {
        let engine = MusicalEngine()
        var cfg = engine.clockEstimatorConfig
        cfg.freewheelSeconds = 1.5
        engine.setClockEstimatorConfig(cfg)
        engine.setClockEstimatorConfig(cfg) // no-op
        XCTAssertEqual(engine.clockEstimatorConfig.freewheelSeconds, 1.5, accuracy: 0.001)
    }

    func testIntentionalDocumentReplaceStillReleasesHeld() {
        let runtime = AMERuntime()
        let tid = UUID()
        let doc = AMEProjectDocument(
            triggers: [AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36)],
            mappings: [
                AMEMapping(
                    name: "H",
                    triggerID: tid,
                    behavior: .whileHeld,
                    actions: [.blind],
                    releaseActions: [.blindOff]
                ),
            ]
        )
        _ = runtime.updateDocument(doc)
        _ = runtime.process(
            AMENormalizedEvent(
                messageType: .noteOn, channel: 0, data1: 36, data2: 100,
                sourceID: "uid:A", hostTime: HostTime(nanoseconds: 1)
            ),
            document: doc
        )
        XCTAssertEqual(runtime.liveHeldSnapshot().count, 1)
        // Explicit AME document replacement (host only calls this when AME changed or reload).
        var doc2 = doc
        doc2.mappings[0].name = "Renamed"
        let batch = runtime.updateDocument(doc2)
        XCTAssertEqual(batch.releasedEntries.count, 1)
        XCTAssertEqual(runtime.liveHeldSnapshot().count, 0)
    }

    func testAMEDocumentEquatableDetectsChange() {
        var a = AMEProjectDocument()
        var b = AMEProjectDocument()
        XCTAssertEqual(a, b)
        a.mappings.append(AMEMapping(name: "X", actions: [.go]))
        XCTAssertNotEqual(a, b)
        b.mappings = a.mappings
        XCTAssertEqual(a, b)
    }

    // MARK: - P0-2 Truthful support

    func testEffectsAreNotLiveSupported() {
        XCTAssertFalse(AMELiveActionSupport.isLiveSupported(.firePreset(UUID())))
        XCTAssertFalse(AMELiveActionSupport.isLiveSupported(.firePalette(UUID())))
        XCTAssertFalse(AMELiveActionSupport.isLiveSupported(.triggerEffect(UUID())))
        XCTAssertFalse(AMELiveActionSupport.isLiveSupported(.runBehavior(UUID())))
    }

    func testSequenceControlIsLiveSupported() {
        XCTAssertTrue(AMELiveActionSupport.isLiveSupported(.advanceSequence(UUID())))
        XCTAssertTrue(AMELiveActionSupport.isLiveSupported(.fireSequenceStep(sequenceID: UUID(), stepIndex: 0)))
        XCTAssertTrue(AMELiveActionSupport.isLiveSupported(.resetSequence(UUID())))
    }

    func testAdvanceSequenceAPIOutsideMappingPath() {
        let runtime = AMERuntime()
        let seqID = UUID()
        let seq = AMETriggeredSequence(
            id: seqID,
            name: "S",
            steps: [
                AMESequenceStep(name: "0", actions: [.go]),
                AMESequenceStep(name: "1", actions: [.stop]),
            ],
            mode: .advance,
            triggerPolicy: .fireThenAdvance,
            stateScope: .sequenceGlobal
        )
        let doc = AMEProjectDocument(sequences: [seq])
        _ = runtime.updateDocument(doc)
        XCTAssertTrue(runtime.advanceSequence(id: seqID))
        let snap = runtime.sequenceState(sequenceID: seqID)
        XCTAssertNotNil(snap)
    }

    func testFireSequenceStepAPIReturnsActions() {
        let runtime = AMERuntime()
        let seqID = UUID()
        let seq = AMETriggeredSequence(
            id: seqID,
            name: "S",
            steps: [
                AMESequenceStep(name: "0", actions: [.blind]),
                AMESequenceStep(name: "1", actions: [.go]),
            ]
        )
        _ = runtime.updateDocument(AMEProjectDocument(sequences: [seq]))
        let actions = runtime.fireSequenceStepActions(sequenceID: seqID, stepIndex: 0)
        XCTAssertEqual(actions, [.blind])
        XCTAssertNil(runtime.fireSequenceStepActions(sequenceID: seqID, stepIndex: 99))
    }

    // MARK: - P1-3 Resolved binding matching

    func testResolvedNameBindingMatchesCanonicalEndpoint() {
        let runtime = AMERuntime()
        let bid = UUID()
        let binding = MIDISourceBinding(id: bid, displayName: "Nord", endpointNameHint: "Nord")
        let tid = UUID()
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
        // Without resolution, ep: live ID would not match name hint.
        runtime.setResolvedSourceBindings([bid: ["ep:4242"]])
        let r = runtime.process(
            AMENormalizedEvent(
                messageType: .noteOn, channel: 0, data1: 36, data2: 100,
                sourceID: "ep:4242", hostTime: HostTime(nanoseconds: 1)
            ),
            document: doc
        )
        XCTAssertFalse(r.emissions.isEmpty, "resolved binding must match canonical ep: ID")
    }

    func testAmbiguousResolvedBindingFailsClosed() {
        let runtime = AMERuntime()
        let bid = UUID()
        let binding = MIDISourceBinding(id: bid, displayName: "Pad", endpointNameHint: "Pad")
        let tid = UUID()
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
        runtime.setResolvedSourceBindings([bid: []]) // ambiguous fail-closed
        let r = runtime.process(
            AMENormalizedEvent(
                messageType: .noteOn, channel: 0, data1: 36, data2: 100,
                sourceID: "ep:1", hostTime: HostTime(nanoseconds: 1)
            ),
            document: doc
        )
        XCTAssertTrue(r.emissions.isEmpty)
    }

    func testInventoryResolveNameToCanonical() {
        let binding = MIDISourceBinding(displayName: "Nord Drum 3P", endpointNameHint: "Nord Drum 3P")
        let inv = [MIDISourceIdentity.InventorySource(id: "ep:99", name: "Nord Drum 3P")]
        XCTAssertEqual(
            MIDISourceIdentity.resolve(binding: binding, inventory: inv),
            .resolved(canonicalSourceID: "ep:99")
        )
    }
}
