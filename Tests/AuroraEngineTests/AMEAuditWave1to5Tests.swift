import AuroraEngine
import AuroraModel
import AuroraMusical
import XCTest

final class AMEAuditWave1to5Tests: XCTestCase {
    func testUIDSourceBindingMatch() {
        let binding = MIDISourceBinding(
            displayName: "Pad",
            lastCoreMIDIUniqueID: 12345
        )
        XCTAssertTrue(MIDISourceIdentity.matches(sourceID: "uid:12345", binding: binding))
        XCTAssertFalse(MIDISourceIdentity.matches(sourceID: "uid:12346", binding: binding))
        XCTAssertFalse(MIDISourceIdentity.matches(sourceID: "Pad", binding: binding), "UID required when configured")
    }

    func testInventoryResolveUID() {
        let binding = MIDISourceBinding(displayName: "Pad", lastCoreMIDIUniqueID: 99)
        let inventory = [
            MIDISourceIdentity.InventorySource(id: "uid:99", name: "Pad"),
            MIDISourceIdentity.InventorySource(id: "ep:1", name: "Other"),
        ]
        let r = MIDISourceIdentity.resolve(binding: binding, inventory: inventory)
        XCTAssertEqual(r, .resolved(canonicalSourceID: "uid:99"))
    }

    func testInventoryResolveNameToEndpointID() {
        let binding = MIDISourceBinding(
            displayName: "Nord Drum 3P",
            endpointNameHint: "Nord Drum 3P"
        )
        let inventory = [
            MIDISourceIdentity.InventorySource(id: "ep:4242", name: "Nord Drum 3P", manufacturer: "Clavia"),
        ]
        let r = MIDISourceIdentity.resolve(binding: binding, inventory: inventory)
        XCTAssertEqual(r, .resolved(canonicalSourceID: "ep:4242"))
    }

    func testInventoryResolveAmbiguousNames() {
        let binding = MIDISourceBinding(
            displayName: "Pad",
            endpointNameHint: "Pad"
        )
        let inventory = [
            MIDISourceIdentity.InventorySource(id: "ep:1", name: "Pad"),
            MIDISourceIdentity.InventorySource(id: "ep:2", name: "Pad"),
        ]
        let r = MIDISourceIdentity.resolve(binding: binding, inventory: inventory)
        if case .ambiguous(let ids) = r {
            XCTAssertEqual(Set(ids), Set(["ep:1", "ep:2"]))
        } else {
            XCTFail("expected ambiguous, got \(r)")
        }
    }

    func testInventoryResolveUnresolved() {
        let binding = MIDISourceBinding(displayName: "Missing", endpointNameHint: "Missing")
        let r = MIDISourceIdentity.resolve(binding: binding, inventory: [])
        XCTAssertEqual(r, .unresolved)
    }

    func testHoldUntilTimingAvailableEmitsForScheduler() {
        let runtime = AMERuntime()
        let tid = UUID()
        let doc = AMEProjectDocument(
            triggers: [AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36)],
            mappings: [
                AMEMapping(
                    name: "Q",
                    triggerID: tid,
                    actions: [.go],
                    quantizeBoundary: .nextBar,
                    quantizationFailurePolicy: .holdUntilTimingAvailable
                ),
            ]
        )
        let r = runtime.process(
            AMENormalizedEvent(
                messageType: .noteOn, channel: 0, data1: 36, data2: 100,
                sourceID: "uid:1", hostTime: HostTime(nanoseconds: 1)
            ),
            document: doc,
            timing: AMETimingSnapshot(musicalTimeAvailable: false, transportRunning: false, externalSyncLocked: false)
        )
        XCTAssertEqual(r.emissions.count, 1)
        XCTAssertFalse(r.emissions[0].executeImmediately)
        XCTAssertTrue(AMEQuantizationBridge.shouldSchedule(r.emissions[0]))
        XCTAssertTrue(r.diagnostics.contains { $0.kind == .quantizeHeld })
    }

    func testEffectiveMappingIncludesLocalIDs() {
        let mid = UUID()
        let setID = UUID()
        let m = AMEMapping(id: mid, name: "Local", scope: .project, actions: [.go])
        let doc = AMEProjectDocument(
            mappings: [m],
            mappingSets: [AMEMappingSet(id: setID, name: "S", mappingIDs: [mid])]
        )
        let ctx = AMEShowContext(activeSectionID: UUID())
        let ids = AMERuntime.effectiveMappingIDs(
            document: doc,
            context: ctx,
            localMappingIDs: [],
            mappingSetIDs: [setID]
        )
        XCTAssertTrue(ids.contains(mid))
    }

    func testReleaseHeldForSourceOnly() {
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
        let batch = runtime.releaseHeld(forSourceID: "uid:A")
        XCTAssertEqual(batch.releasedEntries.count, 1)
        XCTAssertEqual(runtime.liveHeldSnapshot().count, 0)
        XCTAssertTrue(batch.emissions.contains { $0.action == .blindOff })
        XCTAssertTrue(batch.diagnostics.contains { $0.kind == .heldReleasedBySourceDisconnect })
    }

    func testToggleUnwindsOnSourceDisconnect() {
        let runtime = AMERuntime()
        let tidA = UUID()
        let tidB = UUID()
        let midA = UUID()
        let midB = UUID()
        let doc = AMEProjectDocument(
            triggers: [
                AMETriggerDefinition(id: tidA, name: "A", messageType: .noteOn, data1Min: 36, data1Max: 36),
                AMETriggerDefinition(id: tidB, name: "B", messageType: .noteOn, data1Min: 37, data1Max: 37),
            ],
            mappings: [
                AMEMapping(
                    id: midA,
                    name: "ToggleA",
                    triggerID: tidA,
                    behavior: .toggle,
                    actions: [.blind],
                    releaseActions: [.blindOff]
                ),
                AMEMapping(
                    id: midB,
                    name: "ToggleB",
                    triggerID: tidB,
                    behavior: .toggle,
                    actions: [.freeze],
                    releaseActions: [.freezeOff]
                ),
            ]
        )
        _ = runtime.updateDocument(doc)
        // Toggle A ON from source A
        _ = runtime.process(
            AMENormalizedEvent(
                messageType: .noteOn, channel: 0, data1: 36, data2: 100,
                sourceID: "uid:A", hostTime: HostTime(nanoseconds: 1)
            ),
            document: doc
        )
        // Toggle B ON from source B
        _ = runtime.process(
            AMENormalizedEvent(
                messageType: .noteOn, channel: 0, data1: 37, data2: 100,
                sourceID: "uid:B", hostTime: HostTime(nanoseconds: 2)
            ),
            document: doc
        )
        let batch = runtime.releaseHeld(forSourceID: "uid:A")
        XCTAssertTrue(batch.emissions.contains { $0.action == .blindOff })
        XCTAssertFalse(batch.emissions.contains { $0.action == .freezeOff }, "source B toggle must remain")
        // Idempotent second disconnect
        let batch2 = runtime.releaseHeld(forSourceID: "uid:A")
        XCTAssertTrue(batch2.emissions.isEmpty)
        // B still releases on its own disconnect
        let batchB = runtime.releaseHeld(forSourceID: "uid:B")
        XCTAssertTrue(batchB.emissions.contains { $0.action == .freezeOff })
    }

    func testDryRunToggleDisconnectDoesNotLiveExecute() {
        let runtime = AMERuntime()
        _ = runtime.setPerformanceMode(.dryRun)
        let tid = UUID()
        let doc = AMEProjectDocument(
            triggers: [AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36)],
            mappings: [
                AMEMapping(
                    name: "Tog",
                    triggerID: tid,
                    behavior: .toggle,
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
        let batch = runtime.releaseHeld(forSourceID: "uid:A")
        // Dry-run sim domain forceExecute false — release emissions should not execute live.
        for emission in batch.emissions where emission.action == .blindOff {
            XCTAssertFalse(emission.shouldExecute)
        }
    }

    func testScheduledPayloadPreservesControlValue() throws {
        let reg = AuroraActionTokenRegistry()
        let scheduled = try reg.schedulePayload(
            for: .masterIntensity,
            targetBoundary: .immediate,
            controlValue: 0.75,
            latencyID: UUID(),
            orderedFixtureIDs: [UUID()]
        )
        if case .auroraActionToken(let token, _) = scheduled.command {
            let rec = reg.consume(token)
            XCTAssertEqual(rec?.payload.controlValue, 0.75)
        } else {
            XCTFail("expected token")
        }
    }

    func testMusicalEngineProvenanceSongOverrideThenProjectFallback() {
        let engine = MusicalEngine()
        engine.setProjectDefaults(tempoBPM: 96, meter: .fourFour)
        let songA = UUID()
        let songB = UUID()
        engine.setShowContext(ShowMusicalContext(
            activeSongID: songA,
            songDefaultTempoBPM: 110
        ))
        XCTAssertEqual(engine.state.timing.tempoBPM ?? -1, 110, accuracy: 0.001)
        engine.setShowContext(ShowMusicalContext(
            activeSongID: songB,
            songDefaultTempoBPM: nil
        ))
        XCTAssertEqual(engine.state.timing.tempoBPM ?? -1, 96, accuracy: 0.001)
    }

    func testMusicalEngineProvenanceCustomMeterSurvivesNilSong() throws {
        let engine = MusicalEngine()
        let projectMeter = try MusicalMeter(numerator: 7, denominator: 8, beatGrouping: [2, 2, 3])
        engine.setProjectDefaults(tempoBPM: 100, meter: projectMeter)
        let songA = UUID()
        engine.setShowContext(ShowMusicalContext(
            activeSongID: songA,
            songDefaultMeter: .fourFour
        ))
        XCTAssertEqual(engine.state.timing.meter?.numerator, 4)
        engine.setShowContext(ShowMusicalContext(
            activeSongID: UUID(),
            songDefaultMeter: nil
        ))
        XCTAssertEqual(engine.state.timing.meter?.numerator, 7)
        XCTAssertEqual(engine.state.timing.meter?.beatGrouping, [2, 2, 3])
    }

    func testRuntimeDriverFixedCadenceStarts() {
        let engine = MusicalEngine()
        let driver = MusicalEngineRuntimeDriver(engine: engine, intervalSeconds: 0.01)
        driver.start()
        XCTAssertTrue(driver.isRunning)
        driver.stop()
        XCTAssertFalse(driver.isRunning)
    }
}
