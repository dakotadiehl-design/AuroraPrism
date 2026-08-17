import AuroraEngine
import AuroraModel
import AuroraMusical
import XCTest

/// Phase F/G/H integration-level engine tests (headless; no SwiftUI).
final class AMEPhaseFGHTests: XCTestCase {

    // MARK: - Phase G quantization bridge

    func testQuantizationBridgeBoundaries() {
        XCTAssertEqual(AMEQuantizationBridge.musicalBoundary(from: nil), .immediate)
        XCTAssertEqual(AMEQuantizationBridge.musicalBoundary(from: .immediate), .immediate)
        XCTAssertEqual(AMEQuantizationBridge.musicalBoundary(from: .nextBar), .nextBar)
        XCTAssertEqual(AMEQuantizationBridge.musicalBoundary(from: .nextMetricalBeat), .nextMetricalBeat)
        if case .next(let d) = AMEQuantizationBridge.musicalBoundary(from: .nextEighth) {
            XCTAssertEqual(d.unit, .eighth)
        } else {
            XCTFail("expected next eighth")
        }
    }

    func testShouldScheduleOnlyWhenQuantizedExecutable() {
        let immediate = AMEActionEmission(
            latencyID: UUID(),
            mappingID: UUID(),
            action: .go,
            controlValue: 1,
            quantizeBoundary: .immediate,
            quantizationFailurePolicy: .cancel,
            executeImmediately: true,
            shouldExecute: true,
            ingressHostTime: HostTime(nanoseconds: 1)
        )
        XCTAssertFalse(AMEQuantizationBridge.shouldSchedule(immediate))

        let quantized = AMEActionEmission(
            latencyID: UUID(),
            mappingID: UUID(),
            action: .go,
            controlValue: 1,
            quantizeBoundary: .nextBar,
            quantizationFailurePolicy: .cancel,
            executeImmediately: false,
            shouldExecute: true,
            ingressHostTime: HostTime(nanoseconds: 1)
        )
        XCTAssertTrue(AMEQuantizationBridge.shouldSchedule(quantized))

        let safety = AMEActionEmission(
            latencyID: UUID(),
            mappingID: UUID(),
            action: .panic,
            controlValue: 1,
            quantizeBoundary: .nextBar,
            quantizationFailurePolicy: .cancel,
            executeImmediately: true,
            shouldExecute: true,
            ingressHostTime: HostTime(nanoseconds: 1)
        )
        XCTAssertFalse(AMEQuantizationBridge.shouldSchedule(safety))
    }

    func testRuntimeEmitsNonImmediateWhenMusicalTimeAvailable() {
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
                    quantizationFailurePolicy: .cancel
                ),
            ]
        )
        let event = AMENormalizedEvent(
            messageType: .noteOn,
            channel: 0,
            data1: 36,
            data2: 100,
            sourceID: "pad",
            hostTime: HostTime(nanoseconds: 1_000_000_000)
        )
        let result = runtime.process(
            event,
            document: doc,
            timing: AMETimingSnapshot(musicalTimeAvailable: true, transportRunning: true, externalSyncLocked: false)
        )
        XCTAssertEqual(result.emissions.count, 1)
        XCTAssertFalse(result.emissions[0].executeImmediately)
        XCTAssertTrue(result.emissions[0].shouldExecute)
        XCTAssertTrue(result.diagnostics.contains { $0.kind == .quantizeDeferred })
    }

    func testSafetyStillImmediateDespiteQuantizeBoundary() {
        let runtime = AMERuntime()
        let tid = UUID()
        let doc = AMEProjectDocument(
            triggers: [AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36)],
            mappings: [
                AMEMapping(
                    name: "Panic",
                    triggerID: tid,
                    actions: [.panic],
                    quantizeBoundary: .nextBar,
                    quantizationFailurePolicy: .cancel
                ),
            ]
        )
        let event = AMENormalizedEvent(
            messageType: .noteOn,
            channel: 0,
            data1: 36,
            data2: 100,
            sourceID: "pad",
            hostTime: HostTime(nanoseconds: 1)
        )
        let result = runtime.process(
            event,
            document: doc,
            timing: AMETimingSnapshot(musicalTimeAvailable: true, transportRunning: true, externalSyncLocked: true)
        )
        XCTAssertTrue(result.emissions[0].executeImmediately)
        XCTAssertFalse(AMEQuantizationBridge.shouldSchedule(result.emissions[0]))
    }

    func testQuantizeScheduleAndFireViaMusicalEngine() throws {
        let clock = VirtualHostClock()
        let engine = MusicalEngine(clock: clock)
        engine.startTransport()
        engine.setTempoBPM(120)

        let registry = AuroraActionTokenRegistry()
        var fired: [AuroraAction] = []
        engine.setScheduleFireHandler { scheduled in
            if case .auroraActionToken(let token, _) = scheduled.command,
               let record = registry.consume(token) {
                fired.append(record.action)
            }
        }

        let scheduled = try registry.schedulePayload(
            for: .go,
            targetBoundary: .nextBar,
            origin: .ameMapping(UUID()),
            failurePolicy: .cancel
        )
        let result = engine.schedule(scheduled)
        guard case .accepted = result else {
            XCTFail("schedule rejected")
            return
        }
        XCTAssertTrue(fired.isEmpty, "should not fire before boundary")

        // Advance musical time enough to pass a bar at 120 BPM (4 quarters ≈ 2s).
        for _ in 0..<40 {
            clock.advance(nanoseconds: 100_000_000) // 100ms
            engine.tick()
        }
        XCTAssertEqual(fired, [.go])
    }

    // MARK: - Phase H section transition

    func testSectionTransitionOrderExitThenEnter() {
        let songID = UUID()
        let secA = UUID()
        let secB = UUID()
        var project = ShowProject.empty()
        project.songs = [
            Song(
                id: songID,
                title: "Test",
                sections: [
                    SongSection(
                        id: secA,
                        name: "Intro",
                        order: 0,
                        onEnterActions: [.go],
                        onExitActions: [.stop]
                    ),
                    SongSection(
                        id: secB,
                        name: "Chorus",
                        order: 1,
                        onEnterActions: [.back],
                        onExitActions: []
                    ),
                ]
            ),
        ]
        let plan = AMESectionTransition.plan(
            .init(
                previousSongID: songID,
                previousSectionID: secA,
                nextSongID: songID,
                nextSectionID: secB,
                project: project
            )
        )
        XCTAssertEqual(plan.exitActions, [.stop])
        XCTAssertEqual(plan.enterActions, [.back])
        XCTAssertEqual(plan.orderedLifecycleActions, [.stop, .back])
        XCTAssertTrue(plan.sectionChanged)
        XCTAssertFalse(plan.songChanged)
        XCTAssertEqual(plan.nextContext.activeSectionID, secB)
    }

    func testSongMusicalDefaultsProvenance() {
        let songID = UUID()
        var project = ShowProject.empty()
        project.ame.musicalSettings.defaultTempoBPM = 100
        project.songs = [
            Song(id: songID, title: "S", defaultTempoBPM: 128),
        ]
        let defaults = AMESectionTransition.musicalDefaults(forSongID: songID, project: project)
        XCTAssertEqual(defaults.tempoBPM, 128)
        XCTAssertEqual(defaults.tempoProvenance, "songDefault")

        let projectDefaults = AMESectionTransition.musicalDefaults(forSongID: nil, project: project)
        XCTAssertEqual(projectDefaults.tempoBPM, 100)
        XCTAssertEqual(projectDefaults.tempoProvenance, "projectDefault")
    }

    func testSectionTransitionResetsSequenceOnEntry() {
        let sectionA = UUID()
        let sectionB = UUID()
        let songID = UUID()
        let tid = UUID()
        let seq = AMETriggeredSequence(
            name: "SecSeq",
            steps: [
                AMESequenceStep(name: "0", actions: [.fireCueIndex(0)]),
                AMESequenceStep(name: "1", actions: [.fireCueIndex(1)]),
                AMESequenceStep(name: "2", actions: [.fireCueIndex(2)]),
            ],
            mode: .advance,
            resetPolicy: .onSectionEntry,
            stateScope: .perSection
        )
        let doc = AMEProjectDocument(
            triggers: [AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36)],
            mappings: [AMEMapping(name: "M", triggerID: tid, sequenceID: seq.id)],
            sequences: [seq]
        )
        let runtime = AMERuntime()
        _ = runtime.updateDocument(doc)
        let ctxA = AMEShowContext(activeSongID: songID, activeSectionID: sectionA)
        _ = runtime.updateShowContext(ctxA)

        func fire(_ t: UInt64, ctx: AMEShowContext) -> Int? {
            let r = runtime.process(
                AMENormalizedEvent(
                    messageType: .noteOn, channel: 0, data1: 36, data2: 100,
                    sourceID: "pad", hostTime: HostTime(nanoseconds: t)
                ),
                document: doc,
                context: ctx
            )
            return r.diagnostics.first(where: { $0.kind == .sequenceStepFired })?.stepIndex
        }

        XCTAssertEqual(fire(1_000_000_000, ctx: ctxA), 0)
        XCTAssertEqual(fire(2_000_000_000, ctx: ctxA), 1)

        let ctxB = AMEShowContext(activeSongID: songID, activeSectionID: sectionB)
        _ = runtime.updateShowContext(ctxB)
        XCTAssertEqual(fire(3_000_000_000, ctx: ctxB), 0)
    }

    // MARK: - Phase I reliability-style deterministic smoke

    func testDenseDrumSequenceNoCoalesce() {
        let tid = UUID()
        let seq = AMETriggeredSequence(
            name: "Dense",
            steps: (0..<8).map { AMESequenceStep(name: "\($0)", actions: [.fireCueIndex($0)]) },
            mode: .advance,
            loop: true
        )
        let doc = AMEProjectDocument(
            triggers: [AMETriggerDefinition(id: tid, name: "Any", messageType: .noteOn)],
            mappings: [AMEMapping(name: "M", triggerID: tid, sequenceID: seq.id)],
            sequences: [seq]
        )
        let runtime = AMERuntime()
        _ = runtime.updateDocument(doc)
        let ctx = AMEShowContext(activeSongID: UUID(), activeSectionID: UUID())
        _ = runtime.updateShowContext(ctx)

        var steps: [Int] = []
        for i in 0..<16 {
            let r = runtime.process(
                AMENormalizedEvent(
                    messageType: .noteOn, channel: 0, data1: UInt8(36 + (i % 4)), data2: 100,
                    sourceID: "kit", hostTime: HostTime(nanoseconds: UInt64(i + 1) * 50_000_000)
                ),
                document: doc,
                context: ctx
            )
            if let s = r.diagnostics.first(where: { $0.kind == .sequenceStepFired })?.stepIndex {
                steps.append(s)
            }
        }
        XCTAssertEqual(steps.count, 16)
        XCTAssertEqual(steps, [0, 1, 2, 3, 4, 5, 6, 7, 0, 1, 2, 3, 4, 5, 6, 7])
    }

    func testTimingLossCancelsQuantizedButNotSafety() {
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
                    quantizationFailurePolicy: .cancel
                ),
            ]
        )
        let lost = AMETimingSnapshot(musicalTimeAvailable: false, transportRunning: false, externalSyncLocked: false)
        let r = runtime.process(
            AMENormalizedEvent(
                messageType: .noteOn, channel: 0, data1: 36, data2: 100,
                sourceID: "x", hostTime: HostTime(nanoseconds: 1)
            ),
            document: doc,
            timing: lost
        )
        XCTAssertTrue(r.emissions.isEmpty)
        XCTAssertTrue(r.diagnostics.contains { $0.kind == .quantizeCancelled })
    }
}
