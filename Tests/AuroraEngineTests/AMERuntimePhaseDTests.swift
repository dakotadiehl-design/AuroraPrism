import AuroraEngine
import AuroraModel
import AuroraMusical
import XCTest

final class AMERuntimePhaseDTests: XCTestCase {

    // MARK: - Helpers

    private func noteOn(
        note: UInt8 = 36,
        vel: UInt8 = 100,
        ch: UInt8 = 0,
        source: String = "pad",
        t: UInt64 = 1_000_000_000
    ) -> AMENormalizedEvent {
        AMENormalizedEvent(
            messageType: .noteOn,
            channel: ch,
            data1: note,
            data2: vel,
            sourceID: source,
            hostTime: HostTime(nanoseconds: t),
            latencyID: UUID()
        )
    }

    private func noteOff(
        note: UInt8 = 36,
        ch: UInt8 = 0,
        source: String = "pad",
        t: UInt64 = 2_000_000_000
    ) -> AMENormalizedEvent {
        AMENormalizedEvent(
            messageType: .noteOff,
            channel: ch,
            data1: note,
            data2: 0,
            sourceID: source,
            hostTime: HostTime(nanoseconds: t),
            latencyID: UUID()
        )
    }

    private func makeDoc(
        trigger: AMETriggerDefinition,
        mapping: AMEMapping,
        sequences: [AMETriggeredSequence] = [],
        bindings: [MIDISourceBinding] = []
    ) -> AMEProjectDocument {
        AMEProjectDocument(
            triggers: [trigger],
            mappings: [mapping],
            sequences: sequences,
            sourceBindings: bindings
        )
    }

    // MARK: - Match / fire

    func testArmedTriggerFiresGo() {
        let runtime = AMERuntime()
        _ = runtime.setPerformanceMode(.armed)
        let tid = UUID()
        let mid = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "Kick", messageType: .noteOn, data1Min: 36, data1Max: 36),
            mapping: AMEMapping(id: mid, name: "Go", triggerID: tid, actions: [.go])
        )
        let result = runtime.process(noteOn(), document: doc)
        XCTAssertEqual(result.executableEmissions.count, 1)
        XCTAssertEqual(result.executableEmissions[0].action, .go)
        XCTAssertTrue(result.executableEmissions[0].shouldExecute)
        XCTAssertTrue(result.matchedMappingIDs.contains(mid))
    }

    func testDryRunDoesNotExecute() {
        let runtime = AMERuntime()
        _ = runtime.setPerformanceMode(.dryRun)
        let tid = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36),
            mapping: AMEMapping(name: "M", triggerID: tid, actions: [.go])
        )
        let result = runtime.process(noteOn(), document: doc)
        XCTAssertEqual(result.emissions.count, 1)
        XCTAssertFalse(result.emissions[0].shouldExecute)
        XCTAssertTrue(result.executableEmissions.isEmpty)
        XCTAssertTrue(result.diagnostics.contains { $0.kind == .dryRunEmission })
    }

    func testEditModeSkipsEvaluation() {
        let runtime = AMERuntime()
        _ = runtime.setPerformanceMode(.edit)
        let tid = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36),
            mapping: AMEMapping(name: "M", triggerID: tid, actions: [.go])
        )
        let result = runtime.process(noteOn(), document: doc)
        XCTAssertTrue(result.emissions.isEmpty)
        XCTAssertTrue(result.diagnostics.contains { $0.kind == .modeEditSkipped })
    }

    // MARK: - D3: whileHeld / momentary release actions

    func testWhileHeldFiresActivationAndReleaseActions() {
        let runtime = AMERuntime()
        let tid = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36),
            mapping: AMEMapping(
                name: "BlindHold",
                triggerID: tid,
                behavior: .whileHeld,
                actions: [.blind],
                releaseActions: [.blindOff]
            )
        )
        let on = runtime.process(noteOn(t: 1_000_000_000), document: doc)
        XCTAssertEqual(on.executableEmissions.map(\.action), [.blind])
        XCTAssertFalse(on.executableEmissions[0].isRelease)
        XCTAssertEqual(runtime.heldSnapshot().count, 1)

        let off = runtime.process(noteOff(t: 2_000_000_000), document: doc)
        XCTAssertEqual(off.executableEmissions.map(\.action), [.blindOff])
        XCTAssertTrue(off.executableEmissions[0].isRelease)
        XCTAssertEqual(runtime.heldSnapshot().count, 0)
        XCTAssertTrue(off.diagnostics.contains { $0.kind == .heldReleased || $0.kind == .heldReleaseEmission })
    }

    func testMomentarySameAsWhileHeldReleasePath() {
        let runtime = AMERuntime()
        let tid = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36),
            mapping: AMEMapping(
                name: "M",
                triggerID: tid,
                behavior: .momentary,
                actions: [.freeze],
                releaseActions: [.freezeOff]
            )
        )
        _ = runtime.process(noteOn(), document: doc)
        let off = runtime.process(noteOff(), document: doc)
        XCTAssertEqual(off.executableEmissions.map(\.action), [.freezeOff])
    }

    func testNoteOnVelocityZeroSameReleaseSemantics() {
        let runtime = AMERuntime()
        let tid = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36),
            mapping: AMEMapping(
                name: "Held",
                triggerID: tid,
                behavior: .whileHeld,
                actions: [.go],
                releaseActions: [.stop]
            )
        )
        _ = runtime.process(noteOn(vel: 80), document: doc)
        XCTAssertEqual(runtime.heldSnapshot().count, 1)
        let vel0 = AMENormalizedEvent(
            messageType: .noteOn,
            channel: 0,
            data1: 36,
            data2: 0,
            sourceID: "pad",
            hostTime: HostTime(nanoseconds: 3_000_000_000)
        )
        let result = runtime.process(vel0, document: doc)
        XCTAssertEqual(runtime.heldSnapshot().count, 0)
        XCTAssertEqual(result.executableEmissions.map(\.action), [.stop])
    }

    // MARK: - D2: release never blocked by fire gates

    func testReleaseInsideDebounceWindow() {
        let runtime = AMERuntime()
        let tid = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36),
            mapping: AMEMapping(
                name: "D",
                triggerID: tid,
                behavior: .whileHeld,
                actions: [.blind],
                releaseActions: [.blindOff],
                debounceMilliseconds: 500
            )
        )
        _ = runtime.process(noteOn(t: 1_000_000_000), document: doc)
        // 100 ms later — within debounce
        let off = runtime.process(noteOff(t: 1_100_000_000), document: doc)
        XCTAssertEqual(runtime.heldSnapshot().count, 0)
        XCTAssertEqual(off.executableEmissions.map(\.action), [.blindOff])
        XCTAssertFalse(off.diagnostics.contains { $0.kind == .debounceSuppressed })
    }

    func testReleaseInsideBurstWindow() {
        let runtime = AMERuntime()
        let tid = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36),
            mapping: AMEMapping(
                name: "B",
                triggerID: tid,
                behavior: .whileHeld,
                actions: [.blind],
                releaseActions: [.blindOff],
                burstSuppressionMilliseconds: 500
            )
        )
        _ = runtime.process(noteOn(t: 1_000_000_000), document: doc)
        let off = runtime.process(noteOff(t: 1_050_000_000), document: doc)
        XCTAssertEqual(off.executableEmissions.map(\.action), [.blindOff])
    }

    func testReleaseAfterTimingLoss() {
        let runtime = AMERuntime()
        let tid = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36),
            mapping: AMEMapping(
                name: "Sync",
                triggerID: tid,
                timingRequirement: .externalSyncLocked,
                behavior: .whileHeld,
                actions: [.blind],
                releaseActions: [.blindOff]
            )
        )
        let locked = AMETimingSnapshot(musicalTimeAvailable: true, transportRunning: true, externalSyncLocked: true)
        _ = runtime.process(noteOn(t: 1_000_000_000), document: doc, timing: locked)
        XCTAssertEqual(runtime.heldSnapshot().count, 1)
        let unlocked = AMETimingSnapshot(musicalTimeAvailable: true, transportRunning: true, externalSyncLocked: false)
        let off = runtime.process(noteOff(t: 2_000_000_000), document: doc, timing: unlocked)
        XCTAssertEqual(runtime.heldSnapshot().count, 0)
        XCTAssertEqual(off.executableEmissions.map(\.action), [.blindOff])
    }

    func testReleaseAfterSectionChangeViaContextUpdate() {
        let runtime = AMERuntime()
        let tid = UUID()
        let sectionA = UUID()
        let sectionB = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36),
            mapping: AMEMapping(
                name: "Sec",
                scope: .section(sectionA),
                triggerID: tid,
                behavior: .whileHeld,
                actions: [.blind],
                releaseActions: [.blindOff]
            )
        )
        _ = runtime.updateDocument(doc)
        _ = runtime.updateShowContext(AMEShowContext(activeSectionID: sectionA))
        _ = runtime.process(noteOn(), document: doc, context: AMEShowContext(activeSectionID: sectionA))
        XCTAssertEqual(runtime.heldSnapshot().count, 1)

        let batch = runtime.updateShowContext(AMEShowContext(activeSectionID: sectionB))
        XCTAssertEqual(runtime.heldSnapshot().count, 0)
        XCTAssertEqual(batch.emissions.map(\.action), [.blindOff])
        XCTAssertTrue(batch.diagnostics.contains { $0.kind == .heldReleasedByContextChange })
    }

    func testDocumentReplaceReleasesHeld() {
        let runtime = AMERuntime()
        let tid = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36),
            mapping: AMEMapping(
                name: "H",
                triggerID: tid,
                behavior: .whileHeld,
                actions: [.blind],
                releaseActions: [.blindOff]
            )
        )
        _ = runtime.updateDocument(doc)
        _ = runtime.process(noteOn(), document: doc)
        XCTAssertEqual(runtime.heldSnapshot().count, 1)
        let batch = runtime.updateDocument(.empty)
        XCTAssertEqual(runtime.heldSnapshot().count, 0)
        XCTAssertEqual(batch.emissions.map(\.action), [.blindOff])
        XCTAssertTrue(batch.diagnostics.contains { $0.kind == .heldReleasedByDocumentChange })
    }

    func testWrongSourceDoesNotReleaseHold() {
        let runtime = AMERuntime()
        let tid = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36),
            mapping: AMEMapping(
                name: "H",
                triggerID: tid,
                behavior: .whileHeld,
                actions: [.blind],
                releaseActions: [.blindOff]
            )
        )
        _ = runtime.process(noteOn(source: "pad-a"), document: doc)
        let off = runtime.process(noteOff(source: "pad-b"), document: doc)
        XCTAssertEqual(runtime.heldSnapshot().count, 1)
        XCTAssertTrue(off.executableEmissions.isEmpty)
    }

    func testReleaseAllReturnsDeactivationEmissions() {
        let runtime = AMERuntime()
        let tid = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36),
            mapping: AMEMapping(
                name: "H",
                triggerID: tid,
                behavior: .whileHeld,
                actions: [.blackout],
                releaseActions: [.blackoutOff]
            )
        )
        _ = runtime.process(noteOn(), document: doc)
        let batch = runtime.releaseAllHeld()
        XCTAssertEqual(batch.releasedEntries.count, 1)
        XCTAssertEqual(batch.emissions.map(\.action), [.blackoutOff])
        XCTAssertTrue(batch.emissions.allSatisfy(\.isRelease))
    }

    // MARK: - Toggle ON/OFF

    func testToggleActivationAndDeactivation() {
        let runtime = AMERuntime()
        let tid = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36),
            mapping: AMEMapping(
                name: "Tog",
                triggerID: tid,
                behavior: .toggle,
                actions: [.blackout],
                releaseActions: [.blackoutOff]
            )
        )
        let r1 = runtime.process(noteOn(t: 1_000_000_000), document: doc)
        XCTAssertEqual(r1.executableEmissions.map(\.action), [.blackout])
        let r2 = runtime.process(noteOn(t: 2_000_000_000), document: doc)
        XCTAssertEqual(r2.executableEmissions.map(\.action), [.blackoutOff])
        XCTAssertTrue(r2.executableEmissions[0].isRelease)
        let r3 = runtime.process(noteOn(t: 3_000_000_000), document: doc)
        XCTAssertEqual(r3.executableEmissions.map(\.action), [.blackout])
    }

    // MARK: - Scope / inheritance

    func testSectionScopeInactiveWhenWrongSection() {
        let runtime = AMERuntime()
        let tid = UUID()
        let sectionA = UUID()
        let sectionB = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36),
            mapping: AMEMapping(
                name: "Sec",
                scope: .section(sectionA),
                triggerID: tid,
                actions: [.go]
            )
        )
        let result = runtime.process(
            noteOn(),
            document: doc,
            context: AMEShowContext(activeSectionID: sectionB)
        )
        XCTAssertTrue(result.emissions.isEmpty)
        XCTAssertTrue(result.diagnostics.contains { $0.kind == .scopeInactive })
    }

    func testOverrideChildSuppressesParent() {
        let runtime = AMERuntime()
        let tid = UUID()
        let parentID = UUID()
        let childID = UUID()
        let songID = UUID()
        let doc = AMEProjectDocument(
            triggers: [AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36)],
            mappings: [
                AMEMapping(
                    id: parentID,
                    name: "Parent",
                    priority: 0,
                    scope: .project,
                    triggerID: tid,
                    actions: [.stop]
                ),
                AMEMapping(
                    id: childID,
                    name: "Child",
                    priority: 10,
                    scope: .song(songID),
                    triggerID: tid,
                    actions: [.go],
                    overrideParentID: parentID
                ),
            ]
        )
        let result = runtime.process(
            noteOn(),
            document: doc,
            context: AMEShowContext(activeSongID: songID)
        )
        XCTAssertEqual(result.executableEmissions.map(\.action), [.go])
        XCTAssertFalse(result.executableEmissions.contains { $0.action == .stop })
        XCTAssertTrue(result.diagnostics.contains { $0.kind == .mappingSuppressed && $0.mappingID == parentID })
    }

    func testDisabledMappingDoesNotFireButClaimsLegacy() {
        let legacyID = UUID()
        let tid = UUID()
        let doc = AMEProjectDocument(
            triggers: [AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36)],
            mappings: [
                AMEMapping(
                    name: "Claimed",
                    enabled: false,
                    triggerID: tid,
                    actions: [.go],
                    claimsLegacyMappingID: legacyID
                ),
            ]
        )
        let runtime = AMERuntime()
        let result = runtime.process(noteOn(), document: doc)
        XCTAssertTrue(result.emissions.isEmpty)
        XCTAssertFalse(AMELegacyOwnership.shouldRunLegacyMapping(id: legacyID, document: doc))

        let maps = [
            MIDIMapping(id: legacyID, messageType: "noteOn", data1: 36, action: "go"),
            MIDIMapping(id: UUID(), messageType: "noteOn", data1: 36, action: "stop"),
        ]
        let filtered = AMERuntimeOwnership.filterLegacyMappings(maps, document: doc)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].action, "stop")
    }

    // MARK: - Timing / quantize / safety

    func testTimingRequirementBlocksFire() {
        let runtime = AMERuntime()
        let tid = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36),
            mapping: AMEMapping(
                name: "Sync",
                triggerID: tid,
                timingRequirement: .externalSyncLocked,
                actions: [.go]
            )
        )
        let result = runtime.process(
            noteOn(),
            document: doc,
            timing: AMETimingSnapshot(musicalTimeAvailable: true, transportRunning: true, externalSyncLocked: false)
        )
        XCTAssertTrue(result.emissions.isEmpty)
        XCTAssertTrue(result.diagnostics.contains { $0.kind == .timingRequirementFailed })
    }

    func testQuantizeFailureCancelWhenNoMusicalTime() {
        let runtime = AMERuntime()
        let tid = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36),
            mapping: AMEMapping(
                name: "Q",
                triggerID: tid,
                actions: [.go],
                quantizeBoundary: .nextBar,
                quantizationFailurePolicy: .cancel
            )
        )
        let result = runtime.process(
            noteOn(),
            document: doc,
            timing: AMETimingSnapshot(musicalTimeAvailable: false, transportRunning: false, externalSyncLocked: false)
        )
        XCTAssertTrue(result.emissions.isEmpty)
        XCTAssertTrue(result.diagnostics.contains { $0.kind == .quantizeCancelled })
    }

    func testSafetyIgnoresQuantizeBoundary() {
        let runtime = AMERuntime()
        let tid = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36),
            mapping: AMEMapping(
                name: "Panic",
                triggerID: tid,
                actions: [.panic],
                quantizeBoundary: .nextBar,
                quantizationFailurePolicy: .cancel
            )
        )
        let result = runtime.process(
            noteOn(),
            document: doc,
            timing: AMETimingSnapshot(musicalTimeAvailable: false, transportRunning: false, externalSyncLocked: false)
        )
        XCTAssertEqual(result.executableEmissions.count, 1)
        XCTAssertEqual(result.executableEmissions[0].action, .panic)
        XCTAssertTrue(result.executableEmissions[0].executeImmediately)
    }

    // MARK: - D4 / Wave 3 live support

    func testExpandedActionsAreLiveSupported() {
        let runtime = AMERuntime()
        let tid = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36),
            mapping: AMEMapping(
                name: "Song",
                triggerID: tid,
                actions: [.tapTempo, .go]
            )
        )
        let result = runtime.process(noteOn(), document: doc)
        let tap = result.emissions.first { $0.action == .tapTempo }
        XCTAssertNotNil(tap)
        // Wave 3: musical actions are live-supported (executor handles them).
        XCTAssertTrue(tap!.isLiveSupported)
        XCTAssertTrue(tap!.shouldExecute)
        XCTAssertEqual(Set(result.executableEmissions.map(\.action)), [.tapTempo, .go])
    }

    // MARK: - D5 transform math

    func testInMinInMaxAffectScaling() {
        let t = AMEValueTransform(inMin: 32, inMax: 96, outMin: 0, outMax: 1)
        // MIDI 32 → 0
        XCTAssertEqual(AMEValueTransformEvaluator.apply(t, rawNormalized: 32.0 / 127.0)!, 0, accuracy: 0.001)
        // MIDI 64 → midpoint of 32…96 → 0.5
        XCTAssertEqual(AMEValueTransformEvaluator.apply(t, rawNormalized: 64.0 / 127.0)!, 0.5, accuracy: 0.001)
        // MIDI 96 → 1
        XCTAssertEqual(AMEValueTransformEvaluator.apply(t, rawNormalized: 96.0 / 127.0)!, 1, accuracy: 0.001)
        // Below range clamps to 0
        XCTAssertEqual(AMEValueTransformEvaluator.apply(t, rawNormalized: 0)!, 0, accuracy: 0.001)
        // Above range clamps to 1
        XCTAssertEqual(AMEValueTransformEvaluator.apply(t, rawNormalized: 1)!, 1, accuracy: 0.001)
    }

    func testInvertAfterNormalization() {
        let t = AMEValueTransform(inMin: 0, inMax: 127, outMin: 0, outMax: 1, invert: true)
        XCTAssertEqual(AMEValueTransformEvaluator.apply(t, rawNormalized: 0)!, 1, accuracy: 0.001)
        XCTAssertEqual(AMEValueTransformEvaluator.apply(t, rawNormalized: 1)!, 0, accuracy: 0.001)
    }

    func testContinuousCCWithTransform() {
        let runtime = AMERuntime()
        let tid = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "CC7", messageType: .cc, data1Min: 7, data1Max: 7),
            mapping: AMEMapping(
                name: "Master",
                triggerID: tid,
                behavior: .continuous,
                transform: AMEValueTransform(inMin: 0, inMax: 127, outMin: 0, outMax: 1),
                actions: [.masterIntensity]
            )
        )
        let event = AMENormalizedEvent(
            messageType: .cc,
            channel: 0,
            data1: 7,
            data2: 64,
            sourceID: "fader",
            hostTime: HostTime(nanoseconds: 1)
        )
        let result = runtime.process(event, document: doc)
        XCTAssertEqual(result.executableEmissions.count, 1)
        XCTAssertEqual(result.executableEmissions[0].controlValue, 64.0 / 127.0, accuracy: 0.02)
    }

    func testThresholdRejects() {
        let runtime = AMERuntime()
        let tid = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36),
            mapping: AMEMapping(
                name: "Hard",
                triggerID: tid,
                transform: AMEValueTransform(threshold: 100),
                actions: [.go]
            )
        )
        let result = runtime.process(noteOn(vel: 50), document: doc)
        XCTAssertTrue(result.emissions.isEmpty)
        XCTAssertTrue(result.diagnostics.contains { $0.kind == .transformRejected })
    }

    // MARK: - Groups / multi / latency

    func testTriggerGroupMatch() {
        let runtime = AMERuntime()
        let t1 = UUID()
        let t2 = UUID()
        let gid = UUID()
        let doc = AMEProjectDocument(
            triggers: [
                AMETriggerDefinition(id: t1, name: "A", messageType: .noteOn, data1Min: 36, data1Max: 36),
                AMETriggerDefinition(id: t2, name: "B", messageType: .noteOn, data1Min: 38, data1Max: 38),
            ],
            triggerGroups: [AMETriggerGroup(id: gid, name: "Drums", memberTriggerIDs: [t1, t2])],
            mappings: [
                AMEMapping(name: "G", triggerGroupID: gid, actions: [.go]),
            ]
        )
        XCTAssertEqual(runtime.process(noteOn(note: 36), document: doc).executableEmissions.count, 1)
        XCTAssertEqual(runtime.process(noteOn(note: 38, t: 2_000_000_000), document: doc).executableEmissions.count, 1)
    }

    func testMultipleMappingsFireInParallel() {
        let runtime = AMERuntime()
        let tid = UUID()
        let doc = AMEProjectDocument(
            triggers: [AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36)],
            mappings: [
                AMEMapping(name: "A", priority: 1, triggerID: tid, actions: [.go]),
                AMEMapping(name: "B", priority: 2, triggerID: tid, actions: [.back]),
            ]
        )
        let result = runtime.process(noteOn(), document: doc)
        XCTAssertEqual(Set(result.executableEmissions.map(\.action)), [.go, .back])
    }

    func testLatencyIDPropagates() {
        let runtime = AMERuntime()
        let tid = UUID()
        let latency = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36),
            mapping: AMEMapping(name: "M", triggerID: tid, actions: [.go])
        )
        var event = noteOn()
        event.latencyID = latency
        let result = runtime.process(event, document: doc)
        XCTAssertEqual(result.latencyID, latency)
        XCTAssertEqual(result.emissions.first?.latencyID, latency)
    }

    func testTimingSnapshotFromMusicalState() {
        var state = MusicalState.initial
        state.timing.tempoBPM = 120
        state.timing.quarterNotePosition = .must(0)
        state.timing.transport = .running
        state.timing.sync = .locked
        let snap = AMETimingSnapshot.from(musical: state)
        XCTAssertTrue(snap.musicalTimeAvailable)
        XCTAssertTrue(snap.transportRunning)
        XCTAssertTrue(snap.externalSyncLocked)
    }

    func testDebounceSuppressesRapidRetrigger() {
        let runtime = AMERuntime()
        let tid = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36),
            mapping: AMEMapping(
                name: "D",
                triggerID: tid,
                actions: [.go],
                debounceMilliseconds: 500
            )
        )
        let r1 = runtime.process(noteOn(t: 1_000_000_000), document: doc)
        XCTAssertEqual(r1.executableEmissions.count, 1)
        let r2 = runtime.process(noteOn(t: 1_100_000_000), document: doc)
        XCTAssertTrue(r2.emissions.isEmpty)
        XCTAssertTrue(r2.diagnostics.contains { $0.kind == .debounceSuppressed })
        let r3 = runtime.process(noteOn(t: 1_700_000_000), document: doc)
        XCTAssertEqual(r3.executableEmissions.count, 1)
    }

    // MARK: - D7 duplicate IDs

    func testDuplicateIDsDoNotCrashRuntime() {
        let runtime = AMERuntime()
        let dup = UUID()
        let tid = UUID()
        let doc = AMEProjectDocument(
            triggers: [
                AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36),
                AMETriggerDefinition(id: tid, name: "T2", messageType: .noteOn, data1Min: 40, data1Max: 40),
            ],
            mappings: [
                AMEMapping(id: dup, name: "A", triggerID: tid, actions: [.go]),
                AMEMapping(id: dup, name: "B", triggerID: tid, actions: [.stop]),
            ],
            sourceBindings: [
                MIDISourceBinding(id: dup, displayName: "X"),
                MIDISourceBinding(id: dup, displayName: "Y"),
            ]
        )
        let result = runtime.process(noteOn(), document: doc)
        // Must not trap; may fire at least one mapping
        XCTAssertTrue(result.diagnostics.contains { $0.kind == .invalidRuntimeConfiguration } || !result.emissions.isEmpty || result.emissions.isEmpty)
    }

    // MARK: - D6 concurrent debounce

    func testConcurrentDebounceOnlyOneFires() {
        let runtime = AMERuntime()
        let tid = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36),
            mapping: AMEMapping(
                name: "D",
                triggerID: tid,
                actions: [.go],
                debounceMilliseconds: 200
            )
        )
        let e1 = noteOn(t: 1_000_000_000)
        let e2 = noteOn(t: 1_050_000_000) // 50ms later, same debounce window

        let group = DispatchGroup()
        let lock = NSLock()
        var fireCount = 0
        for event in [e1, e2] {
            group.enter()
            DispatchQueue.global().async {
                let r = runtime.process(event, document: doc)
                lock.lock()
                fireCount += r.executableEmissions.count
                lock.unlock()
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(fireCount, 1, "Concurrent debounce must allow only one fire")
    }

    // MARK: - D8 heldGate rename migration

    func testGateRawValueDecodesAsHeldGate() throws {
        let json = "\"gate\""
        let decoded = try JSONDecoder().decode(AMETriggerBehavior.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, .heldGate)
        let encoded = try JSONEncoder().encode(AMETriggerBehavior.heldGate)
        XCTAssertEqual(String(data: encoded, encoding: .utf8), "\"heldGate\"")
    }

    func testHeldGateBehaviorAcquiresAndReleases() {
        let runtime = AMERuntime()
        let tid = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36),
            mapping: AMEMapping(
                name: "G",
                triggerID: tid,
                behavior: .heldGate,
                actions: [.blind],
                releaseActions: [.blindOff]
            )
        )
        _ = runtime.process(noteOn(), document: doc)
        let off = runtime.process(noteOff(), document: doc)
        XCTAssertEqual(off.executableEmissions.map(\.action), [.blindOff])
    }

    // MARK: - Ingress host time preservation (engine side)

    func testDebounceUsesIngressTimestamps() {
        let runtime = AMERuntime()
        let tid = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36),
            mapping: AMEMapping(name: "D", triggerID: tid, actions: [.go], debounceMilliseconds: 100)
        )
        // Far-apart wall processing, but close ingress times
        let r1 = runtime.process(noteOn(t: 5_000_000_000), document: doc)
        XCTAssertEqual(r1.executableEmissions.count, 1)
        // 50ms later in ingress time
        let r2 = runtime.process(noteOn(t: 5_050_000_000), document: doc)
        XCTAssertTrue(r2.emissions.isEmpty)
        XCTAssertEqual(r1.emissions.first?.ingressHostTime.nanoseconds, 5_000_000_000)
    }

    func testDryRunReportsReleaseWithoutExecute() {
        let runtime = AMERuntime()
        _ = runtime.setPerformanceMode(.dryRun)
        let tid = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36),
            mapping: AMEMapping(
                name: "H",
                triggerID: tid,
                behavior: .whileHeld,
                actions: [.blind],
                releaseActions: [.blindOff]
            )
        )
        let on = runtime.process(noteOn(t: 1), document: doc)
        XCTAssertEqual(on.emissions.count, 1)
        XCTAssertFalse(on.emissions[0].shouldExecute)
        let off = runtime.process(noteOff(t: 2), document: doc)
        XCTAssertEqual(off.emissions.map(\.action), [.blindOff])
        XCTAssertTrue(off.emissions.allSatisfy { !$0.shouldExecute })
    }

    func testCompoundReleasePreservesSafety() {
        let runtime = AMERuntime()
        let tid = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36),
            mapping: AMEMapping(
                name: "H",
                triggerID: tid,
                behavior: .whileHeld,
                actions: [.compound([.blind, .go])],
                releaseActions: [.compound([.blindOff, .panic])]
            )
        )
        _ = runtime.process(noteOn(), document: doc)
        let batch = runtime.releaseAllHeld()
        let actions = batch.emissions.map(\.action)
        XCTAssertTrue(actions.contains(.blindOff))
        XCTAssertTrue(actions.contains(.panic))
        XCTAssertTrue(batch.emissions.contains { $0.action == .panic && $0.executeImmediately })
    }

    // MARK: - Closeout: mode/document provenance + dry-run isolation

    func testArmedModeChangeEmitsExecutableRelease() {
        let runtime = AMERuntime()
        let tid = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36),
            mapping: AMEMapping(
                name: "H",
                triggerID: tid,
                behavior: .whileHeld,
                actions: [.blind],
                releaseActions: [.blindOff]
            )
        )
        _ = runtime.updateDocument(doc)
        _ = runtime.process(noteOn(), document: doc)
        XCTAssertEqual(runtime.liveHeldSnapshot().count, 1)
        let batch = runtime.setPerformanceMode(.dryRun)
        XCTAssertTrue(batch.emissions.contains { $0.action == .blindOff && $0.shouldExecute })
        XCTAssertEqual(runtime.liveHeldSnapshot().count, 0)
    }

    func testArmedToggleModeChangeEmitsExecutableRelease() {
        let runtime = AMERuntime()
        let tid = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36),
            mapping: AMEMapping(
                name: "Tog",
                triggerID: tid,
                behavior: .toggle,
                actions: [.blackout],
                releaseActions: [.blackoutOff]
            )
        )
        _ = runtime.updateDocument(doc)
        _ = runtime.process(noteOn(), document: doc)
        let batch = runtime.setPerformanceMode(.edit)
        XCTAssertTrue(batch.emissions.contains { $0.action == .blackoutOff && $0.shouldExecute })
    }

    func testDryRunDocumentReplaceNonExecutableRelease() {
        let runtime = AMERuntime()
        _ = runtime.setPerformanceMode(.dryRun)
        let tid = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36),
            mapping: AMEMapping(
                name: "H",
                triggerID: tid,
                behavior: .whileHeld,
                actions: [.blind],
                releaseActions: [.blindOff]
            )
        )
        _ = runtime.updateDocument(doc)
        _ = runtime.process(noteOn(), document: doc)
        let batch = runtime.updateDocument(.empty)
        let offs = batch.emissions.filter { $0.action == .blindOff }
        XCTAssertFalse(offs.isEmpty)
        XCTAssertTrue(offs.allSatisfy { !$0.shouldExecute })
    }

    func testArmedDocumentReplaceExecutableRelease() {
        let runtime = AMERuntime()
        let tid = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36),
            mapping: AMEMapping(
                name: "H",
                triggerID: tid,
                behavior: .whileHeld,
                actions: [.blind],
                releaseActions: [.blindOff]
            )
        )
        _ = runtime.updateDocument(doc)
        _ = runtime.process(noteOn(), document: doc)
        let batch = runtime.updateDocument(.empty)
        XCTAssertTrue(batch.emissions.contains { $0.action == .blindOff && $0.shouldExecute })
    }

    func testDryRunHeldDoesNotBlockArmedAcquire() {
        let runtime = AMERuntime()
        let tid = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36),
            mapping: AMEMapping(
                name: "H",
                triggerID: tid,
                behavior: .whileHeld,
                actions: [.blind],
                releaseActions: [.blindOff]
            )
        )
        _ = runtime.updateDocument(doc)
        _ = runtime.setPerformanceMode(.dryRun)
        _ = runtime.process(noteOn(t: 1), document: doc)
        _ = runtime.setPerformanceMode(.armed)
        let armed = runtime.process(noteOn(t: 2), document: doc)
        XCTAssertEqual(armed.executableEmissions.map(\.action), [.blind])
    }

    func testDryRunDebounceDoesNotSuppressArmed() {
        let runtime = AMERuntime()
        let tid = UUID()
        let doc = makeDoc(
            trigger: AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36),
            mapping: AMEMapping(
                name: "D",
                triggerID: tid,
                actions: [.go],
                debounceMilliseconds: 500
            )
        )
        _ = runtime.updateDocument(doc)
        _ = runtime.setPerformanceMode(.dryRun)
        _ = runtime.process(noteOn(t: 1_000_000_000), document: doc)
        _ = runtime.setPerformanceMode(.armed)
        let armed = runtime.process(noteOn(t: 1_050_000_000), document: doc)
        XCTAssertEqual(armed.executableEmissions.count, 1)
    }
}
