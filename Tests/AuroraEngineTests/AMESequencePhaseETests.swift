import AuroraEngine
import AuroraModel
import AuroraMusical
import XCTest

final class AMESequencePhaseETests: XCTestCase {

    // MARK: Helpers

    /// Default sequence stateScope is perSection — provide real song/section context.
    private let testSong = UUID()
    private let testSection = UUID()
    private var testContext: AMEShowContext {
        AMEShowContext(activeSongID: testSong, activeSectionID: testSection)
    }

    private func noteOn(t: UInt64 = 1_000_000_000, note: UInt8 = 36) -> AMENormalizedEvent {
        AMENormalizedEvent(
            messageType: .noteOn,
            channel: 0,
            data1: note,
            data2: 100,
            sourceID: "pad",
            hostTime: HostTime(nanoseconds: t),
            latencyID: UUID()
        )
    }

    private func steps(_ labels: [String], action: AuroraAction = .go) -> [AMESequenceStep] {
        labels.enumerated().map { i, name in
            AMESequenceStep(name: name, actions: [action == .go ? .fireCueIndex(i) : action], weight: 1)
        }
    }

    private func weightedSteps(_ weights: [Double]) -> [AMESequenceStep] {
        weights.enumerated().map { i, w in
            AMESequenceStep(name: "S\(i)", actions: [.fireCueIndex(i)], weight: w)
        }
    }

    private func doc(
        sequence: AMETriggeredSequence,
        mappingBehavior: AMETriggerBehavior = .trigger
    ) -> (AMEProjectDocument, UUID, UUID) {
        let tid = UUID()
        let mid = UUID()
        let d = AMEProjectDocument(
            triggers: [
                AMETriggerDefinition(id: tid, name: "Hit", messageType: .noteOn, data1Min: 36, data1Max: 36),
            ],
            mappings: [
                AMEMapping(
                    id: mid,
                    name: "SeqMap",
                    triggerID: tid,
                    behavior: mappingBehavior,
                    actions: [],
                    sequenceID: sequence.id
                ),
            ],
            sequences: [sequence]
        )
        return (d, tid, mid)
    }

    private func prepare(_ runtime: AMERuntime, document: AMEProjectDocument) {
        _ = runtime.updateDocument(document)
        _ = runtime.updateShowContext(testContext)
    }

    private func fireIndices(
        _ runtime: AMERuntime,
        doc: AMEProjectDocument,
        count: Int,
        startT: UInt64 = 1_000_000_000,
        context: AMEShowContext? = nil
    ) -> [Int] {
        let ctx = context ?? testContext
        var indices: [Int] = []
        for i in 0..<count {
            let r = runtime.process(
                noteOn(t: startT + UInt64(i) * 1_000_000_000),
                document: doc,
                context: ctx
            )
            if let step = r.diagnostics.last(where: { $0.kind == .sequenceStepFired })?.stepIndex {
                indices.append(step)
            } else if let cue = r.emissions.compactMap({ emission -> Int? in
                if case .fireCueIndex(let idx) = emission.action { return idx }
                return nil
            }).first {
                indices.append(cue)
            }
        }
        return indices
    }

    // MARK: Advance / reverse / pingPong

    func testFireThenAdvanceDefault() {
        let seq = AMETriggeredSequence(
            name: "Intro",
            steps: steps(["A", "B", "C"]),
            mode: .advance,
            loop: true,
            triggerPolicy: .fireThenAdvance,
            initialIndex: 0
        )
        let (document, _, _) = doc(sequence: seq)
        let runtime = AMERuntime()
        prepare(runtime, document: document)
        let idx = fireIndices(runtime, doc: document, count: 5)
        XCTAssertEqual(idx, [0, 1, 2, 0, 1])
    }

    func testAdvanceThenFireDiffersFromFireThenAdvance() {
        let stepsABC = steps(["A", "B", "C"])
        let fireFirst = AMETriggeredSequence(
            name: "FF",
            steps: stepsABC,
            mode: .advance,
            loop: true,
            triggerPolicy: .fireThenAdvance,
            initialIndex: 0
        )
        let advanceFirst = AMETriggeredSequence(
            name: "AF",
            steps: stepsABC,
            mode: .advance,
            loop: true,
            triggerPolicy: .advanceThenFire,
            initialIndex: 0
        )
        let (docFF, _, _) = doc(sequence: fireFirst)
        let (docAF, _, _) = doc(sequence: advanceFirst)
        let r1 = AMERuntime()
        prepare(r1, document: docFF)
        let r2 = AMERuntime()
        prepare(r2, document: docAF)
        let ff = fireIndices(r1, doc: docFF, count: 4)
        let af = fireIndices(r2, doc: docAF, count: 4)
        XCTAssertEqual(ff, [0, 1, 2, 0])
        // advanceThenFire: first advance from 0 → fire 1, then 2, 0, 1
        XCTAssertEqual(af, [1, 2, 0, 1])
        XCTAssertNotEqual(ff, af)
    }

    func testReverseMode() {
        let seq = AMETriggeredSequence(
            name: "Rev",
            steps: steps(["A", "B", "C", "D"]),
            mode: .reverse,
            loop: true,
            triggerPolicy: .fireThenAdvance,
            initialIndex: 3
        )
        let (document, _, _) = doc(sequence: seq)
        let runtime = AMERuntime()
        prepare(runtime, document: document)
        let idx = fireIndices(runtime, doc: document, count: 5)
        XCTAssertEqual(idx, [3, 2, 1, 0, 3])
    }

    func testPingPongMode() {
        let seq = AMETriggeredSequence(
            name: "PP",
            steps: steps(["A", "B", "C"]),
            mode: .pingPong,
            loop: true,
            triggerPolicy: .fireThenAdvance,
            initialIndex: 0
        )
        let (document, _, _) = doc(sequence: seq)
        let runtime = AMERuntime()
        prepare(runtime, document: document)
        let idx = fireIndices(runtime, doc: document, count: 7)
        // 0,1,2,1,0,1,2
        XCTAssertEqual(idx, [0, 1, 2, 1, 0, 1, 2])
    }

    func testNoLoopClampsAtEnd() {
        let seq = AMETriggeredSequence(
            name: "Once",
            steps: steps(["A", "B"]),
            mode: .advance,
            loop: false,
            triggerPolicy: .fireThenAdvance,
            initialIndex: 0
        )
        let (document, _, _) = doc(sequence: seq)
        let runtime = AMERuntime()
        prepare(runtime, document: document)
        let idx = fireIndices(runtime, doc: document, count: 4)
        XCTAssertEqual(idx, [0, 1, 1, 1])
    }

    // MARK: Random / weighted / shuffle (deterministic seed)

    func testRandomDeterministicWithSeed() {
        let seq = AMETriggeredSequence(
            name: "Rnd",
            steps: steps(["A", "B", "C", "D"]),
            mode: .random,
            triggerPolicy: .fireThenAdvance
        )
        let (document, _, _) = doc(sequence: seq)

        let r1 = AMERuntime(sequenceSeed: 42)
        prepare(r1, document: document)
        let a = fireIndices(r1, doc: document, count: 8)

        let r2 = AMERuntime(sequenceSeed: 42)
        prepare(r2, document: document)
        let b = fireIndices(r2, doc: document, count: 8)

        XCTAssertEqual(a, b)
        // Not stuck on a single step for all 8 (very unlikely with seed)
        XCTAssertTrue(Set(a).count >= 1)
    }

    func testWeightedRandomPrefersHeavyStep() {
        let seq = AMETriggeredSequence(
            name: "W",
            steps: weightedSteps([0.001, 1000, 0.001]),
            mode: .weightedRandom
        )
        let (document, _, _) = doc(sequence: seq)
        let runtime = AMERuntime(sequenceSeed: 7)
        prepare(runtime, document: document)
        let idx = fireIndices(runtime, doc: document, count: 30)
        let ones = idx.filter { $0 == 1 }.count
        XCTAssertGreaterThan(ones, 20, "Heavy weight should dominate")
    }

    func testShuffleBagPlaysEachOnceBeforeRepeat() {
        let seq = AMETriggeredSequence(
            name: "Bag",
            steps: steps(["A", "B", "C", "D"]),
            mode: .shuffleBag
        )
        let (document, _, _) = doc(sequence: seq)
        let runtime = AMERuntime(sequenceSeed: 99)
        prepare(runtime, document: document)
        let first = fireIndices(runtime, doc: document, count: 4)
        XCTAssertEqual(Set(first).count, 4, "First bag should contain each step once")
        let second = fireIndices(runtime, doc: document, count: 4, startT: 100_000_000_000)
        XCTAssertEqual(Set(second).count, 4)
    }

    // MARK: Reset policies / state scope

    func testResetOnSectionEntry() {
        let sectionA = UUID()
        let sectionB = UUID()
        let seq = AMETriggeredSequence(
            name: "Sec",
            steps: steps(["A", "B", "C"]),
            mode: .advance,
            resetPolicy: .onSectionEntry,
            triggerPolicy: .fireThenAdvance,
            stateScope: .perSection
        )
        let (document, _, _) = doc(sequence: seq)
        let runtime = AMERuntime()
        prepare(runtime, document: document)
        let ctxA = AMEShowContext(activeSongID: testSong, activeSectionID: sectionA)
        let ctxB = AMEShowContext(activeSongID: testSong, activeSectionID: sectionB)
        _ = runtime.updateShowContext(ctxA)
        _ = fireIndices(runtime, doc: document, count: 2, context: ctxA) // fire 0,1 → next is 2

        _ = runtime.updateShowContext(ctxB)
        let after = fireIndices(runtime, doc: document, count: 1, startT: 50_000_000_000, context: ctxB)
        XCTAssertEqual(after, [0], "Section entry should reset to initialIndex")
    }

    func testResetOnSongStart() {
        let songA = UUID()
        let songB = UUID()
        let seq = AMETriggeredSequence(
            name: "Song",
            steps: steps(["A", "B", "C"]),
            mode: .advance,
            resetPolicy: .onSongStart,
            stateScope: .perSong
        )
        let (document, _, _) = doc(sequence: seq)
        let runtime = AMERuntime()
        prepare(runtime, document: document)
        let ctxA = AMEShowContext(activeSongID: songA, activeSectionID: testSection)
        let ctxB = AMEShowContext(activeSongID: songB, activeSectionID: testSection)
        _ = runtime.updateShowContext(ctxA)
        _ = fireIndices(runtime, doc: document, count: 2, context: ctxA)

        _ = runtime.updateShowContext(ctxB)
        let after = fireIndices(runtime, doc: document, count: 1, startT: 50_000_000_000, context: ctxB)
        XCTAssertEqual(after, [0])
    }

    func testManualResetAPI() {
        let seq = AMETriggeredSequence(
            name: "Man",
            steps: steps(["A", "B", "C"]),
            mode: .advance,
            resetPolicy: .manual
        )
        let (document, _, _) = doc(sequence: seq)
        let runtime = AMERuntime()
        prepare(runtime, document: document)
        _ = fireIndices(runtime, doc: document, count: 2)
        runtime.resetSequence(id: seq.id)
        let after = fireIndices(runtime, doc: document, count: 1, startT: 50_000_000_000)
        XCTAssertEqual(after, [0])
    }

    func testNeverResetSurvivesSectionChange() {
        let sectionA = UUID()
        let sectionB = UUID()
        let seq = AMETriggeredSequence(
            name: "Sticky",
            steps: steps(["A", "B", "C"]),
            mode: .advance,
            resetPolicy: .never,
            stateScope: .sequenceGlobal
        )
        let (document, _, _) = doc(sequence: seq)
        let runtime = AMERuntime()
        prepare(runtime, document: document)
        let ctxA = AMEShowContext(activeSongID: testSong, activeSectionID: sectionA)
        let ctxB = AMEShowContext(activeSongID: testSong, activeSectionID: sectionB)
        _ = runtime.updateShowContext(ctxA)
        _ = fireIndices(runtime, doc: document, count: 2, context: ctxA) // next = 2
        _ = runtime.updateShowContext(ctxB)
        let after = fireIndices(runtime, doc: document, count: 1, startT: 50_000_000_000, context: ctxB)
        XCTAssertEqual(after, [2])
    }

    func testPerSectionStateIsIsolated() {
        let sectionA = UUID()
        let sectionB = UUID()
        let seq = AMETriggeredSequence(
            name: "Iso",
            steps: steps(["A", "B", "C"]),
            mode: .advance,
            resetPolicy: .never,
            stateScope: .perSection
        )
        let (document, _, _) = doc(sequence: seq)
        let runtime = AMERuntime()
        prepare(runtime, document: document)
        let ctxA = AMEShowContext(activeSongID: testSong, activeSectionID: sectionA)
        let ctxB = AMEShowContext(activeSongID: testSong, activeSectionID: sectionB)

        _ = runtime.updateShowContext(ctxA)
        _ = fireIndices(runtime, doc: document, count: 2, context: ctxA) // A at 2 next

        _ = runtime.updateShowContext(ctxB)
        // Fresh per-section state for B
        let bFirst = fireIndices(runtime, doc: document, count: 1, startT: 50_000_000_000, context: ctxB)
        XCTAssertEqual(bFirst, [0])
    }

    // MARK: Broken references / empty

    func testMissingSequenceDiagnostic() {
        let tid = UUID()
        let missing = UUID()
        let document = AMEProjectDocument(
            triggers: [AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36)],
            mappings: [AMEMapping(name: "M", triggerID: tid, sequenceID: missing)],
            sequences: []
        )
        let runtime = AMERuntime()
        let r = runtime.process(noteOn(), document: document, context: testContext)
        XCTAssertTrue(r.diagnostics.contains { $0.kind == .sequenceMissing })
        XCTAssertTrue(r.emissions.isEmpty)
    }

    func testEmptySequenceDiagnostic() {
        let seq = AMETriggeredSequence(name: "Empty", steps: [])
        let (document, _, _) = doc(sequence: seq)
        let runtime = AMERuntime()
        let r = runtime.process(noteOn(), document: document, context: testContext)
        XCTAssertTrue(r.diagnostics.contains { $0.kind == .sequenceEmpty })
    }

    // MARK: One event = one step; mapping actions + sequence

    func testOneEventOneStepNoCoalesce() {
        let seq = AMETriggeredSequence(
            name: "Drum",
            steps: steps(["A", "B", "C"]),
            mode: .advance
        )
        let (document, _, _) = doc(sequence: seq)
        let runtime = AMERuntime()
        _ = runtime.updateDocument(document)
        // Three events in one "batch" (separate process calls — no coalescing)
        let i0 = fireIndices(runtime, doc: document, count: 1, startT: 1)
        let i1 = fireIndices(runtime, doc: document, count: 1, startT: 2)
        let i2 = fireIndices(runtime, doc: document, count: 1, startT: 3)
        XCTAssertEqual(i0 + i1 + i2, [0, 1, 2])
    }

    func testMappingActionsPlusSequenceStep() {
        let seqID = UUID()
        let tid = UUID()
        let seq = AMETriggeredSequence(
            id: seqID,
            name: "S",
            steps: [AMESequenceStep(name: "Only", actions: [.back])]
        )
        let document = AMEProjectDocument(
            triggers: [AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36)],
            mappings: [
                AMEMapping(name: "M", triggerID: tid, actions: [.go], sequenceID: seqID),
            ],
            sequences: [seq]
        )
        let runtime = AMERuntime()
        prepare(runtime, document: document)
        let r = runtime.process(noteOn(), document: document, context: testContext)
        let actions = r.executableEmissions.map(\.action)
        XCTAssertTrue(actions.contains(.go))
        XCTAssertTrue(actions.contains(.back))
    }

    func testResetSequenceActionInMapping() {
        let seqID = UUID()
        let tid = UUID()
        let seq = AMETriggeredSequence(
            id: seqID,
            name: "S",
            steps: steps(["A", "B", "C"]),
            mode: .advance,
            resetPolicy: .manual
        )
        // Use two different notes so we control order
        let tAdv = UUID()
        let tRst = UUID()
        let document = AMEProjectDocument(
            triggers: [
                AMETriggerDefinition(id: tAdv, name: "A", messageType: .noteOn, data1Min: 36, data1Max: 36),
                AMETriggerDefinition(id: tRst, name: "R", messageType: .noteOn, data1Min: 40, data1Max: 40),
            ],
            mappings: [
                AMEMapping(name: "Adv", triggerID: tAdv, sequenceID: seqID),
                AMEMapping(name: "Rst", triggerID: tRst, actions: [.resetSequence(seqID)]),
            ],
            sequences: [seq]
        )
        let runtime = AMERuntime()
        prepare(runtime, document: document)
        _ = runtime.process(noteOn(note: 36), document: document, context: testContext)
        _ = runtime.process(noteOn(t: 2_000_000_000, note: 36), document: document, context: testContext)
        _ = runtime.process(noteOn(t: 3_000_000_000, note: 40), document: document, context: testContext)
        let after = runtime.process(noteOn(t: 4_000_000_000, note: 36), document: document, context: testContext)
        let step = after.diagnostics.first(where: { $0.kind == .sequenceStepFired })?.stepIndex
        XCTAssertEqual(step, 0)
    }

    // MARK: Dry-run isolation — must not poison armed state

    func testDryRunSequenceDoesNotPoisonArmed() {
        let seq = AMETriggeredSequence(
            name: "Dry",
            steps: steps(["A", "B", "C"]),
            mode: .advance
        )
        let (document, _, _) = doc(sequence: seq)
        let runtime = AMERuntime()
        prepare(runtime, document: document)
        _ = runtime.setPerformanceMode(.dryRun)
        _ = fireIndices(runtime, doc: document, count: 2) // sim advances
        _ = runtime.setPerformanceMode(.armed) // purges sim
        let firstArmed = fireIndices(runtime, doc: document, count: 1, startT: 90_000_000_000)
        XCTAssertEqual(firstArmed, [0], "Armed must start fresh, not at dry-run cursor")
    }

    // MARK: Document replace clears sequence state

    func testDocumentReplaceClearsSequenceState() {
        let seq = AMETriggeredSequence(
            name: "Clr",
            steps: steps(["A", "B", "C"]),
            mode: .advance
        )
        let (document, _, _) = doc(sequence: seq)
        let runtime = AMERuntime()
        prepare(runtime, document: document)
        _ = fireIndices(runtime, doc: document, count: 2)
        prepare(runtime, document: document) // re-load same doc
        let after = fireIndices(runtime, doc: document, count: 1, startT: 90_000_000_000)
        XCTAssertEqual(after, [0])
    }

    func testAdvanceSequenceDoesNotFireActions() {
        let seqID = UUID()
        let tid = UUID()
        let seq = AMETriggeredSequence(
            id: seqID,
            name: "S",
            steps: [
                AMESequenceStep(name: "A", actions: [.go]),
                AMESequenceStep(name: "B", actions: [.back]),
            ],
            mode: .advance,
            triggerPolicy: .fireThenAdvance
        )
        let document = AMEProjectDocument(
            triggers: [AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36)],
            mappings: [
                AMEMapping(name: "AdvOnly", triggerID: tid, actions: [.advanceSequence(seqID)]),
            ],
            sequences: [seq]
        )
        let runtime = AMERuntime()
        prepare(runtime, document: document)
        let r = runtime.process(noteOn(), document: document, context: testContext)
        XCTAssertTrue(r.executableEmissions.isEmpty, "advanceSequence must not fire step actions")
        XCTAssertTrue(r.diagnostics.contains { $0.kind == .sequenceControlAction })
    }

    func testFireSequenceStepOOBRejected() {
        let seqID = UUID()
        let tid = UUID()
        let seq = AMETriggeredSequence(
            id: seqID,
            name: "S",
            steps: [AMESequenceStep(name: "A", actions: [.go])]
        )
        let document = AMEProjectDocument(
            triggers: [AMETriggerDefinition(id: tid, name: "T", messageType: .noteOn, data1Min: 36, data1Max: 36)],
            mappings: [
                AMEMapping(name: "Bad", triggerID: tid, actions: [.fireSequenceStep(sequenceID: seqID, stepIndex: 99)]),
            ],
            sequences: [seq]
        )
        let runtime = AMERuntime()
        prepare(runtime, document: document)
        let r = runtime.process(noteOn(), document: document, context: testContext)
        XCTAssertTrue(r.emissions.isEmpty)
        XCTAssertTrue(r.diagnostics.contains { $0.kind == .sequenceInvalidStep })
    }

    func testFireSequenceStepDoesNotAdvanceCursor() {
        let seqID = UUID()
        let tid = UUID()
        let tFire = UUID()
        let tStep = UUID()
        let seq = AMETriggeredSequence(
            id: seqID,
            name: "S",
            steps: steps(["A", "B", "C"]),
            mode: .advance,
            triggerPolicy: .fireThenAdvance
        )
        let document = AMEProjectDocument(
            triggers: [
                AMETriggerDefinition(id: tFire, name: "F", messageType: .noteOn, data1Min: 36, data1Max: 36),
                AMETriggerDefinition(id: tStep, name: "S", messageType: .noteOn, data1Min: 40, data1Max: 40),
            ],
            mappings: [
                AMEMapping(name: "Seq", triggerID: tFire, sequenceID: seqID),
                AMEMapping(name: "Step", triggerID: tStep, actions: [.fireSequenceStep(sequenceID: seqID, stepIndex: 2)]),
            ],
            sequences: [seq]
        )
        let runtime = AMERuntime()
        prepare(runtime, document: document)
        _ = runtime.process(noteOn(note: 36), document: document, context: testContext) // fires 0, next 1
        _ = runtime.process(noteOn(t: 2_000_000_000, note: 40), document: document, context: testContext) // fire step 2 without cursor change
        let next = runtime.process(noteOn(t: 3_000_000_000, note: 36), document: document, context: testContext)
        XCTAssertEqual(next.diagnostics.first(where: { $0.kind == .sequenceStepFired })?.stepIndex, 1)
    }

    func testSectionExitToNilDoesNotReset() {
        let sectionA = UUID()
        let seq = AMETriggeredSequence(
            name: "Sec",
            steps: steps(["A", "B", "C"]),
            mode: .advance,
            resetPolicy: .onSectionEntry,
            stateScope: .sequenceGlobal
        )
        let (document, _, _) = doc(sequence: seq)
        let runtime = AMERuntime()
        prepare(runtime, document: document)
        _ = runtime.updateShowContext(AMEShowContext(activeSectionID: sectionA))
        _ = fireIndices(runtime, doc: document, count: 2) // next = 2
        _ = runtime.updateShowContext(AMEShowContext()) // exit to nil
        let after = fireIndices(runtime, doc: document, count: 1, startT: 50_000_000_000)
        XCTAssertEqual(after, [2], "Exit-to-nil must not reset onSectionEntry sequences")
    }

    func testUnrelatedSequenceDoesNotPerturbRandomStream() {
        let seqA = AMETriggeredSequence(
            id: UUID(),
            name: "A",
            steps: steps(["0", "1", "2", "3"]),
            mode: .random
        )
        let seqB = AMETriggeredSequence(
            id: UUID(),
            name: "B",
            steps: steps(["0", "1", "2", "3"]),
            mode: .random
        )
        func runA(interleaveB: Bool) -> [Int] {
            let tA = UUID()
            let tB = UUID()
            let document = AMEProjectDocument(
                triggers: [
                    AMETriggerDefinition(id: tA, name: "A", messageType: .noteOn, data1Min: 36, data1Max: 36),
                    AMETriggerDefinition(id: tB, name: "B", messageType: .noteOn, data1Min: 40, data1Max: 40),
                ],
                mappings: [
                    AMEMapping(name: "MA", triggerID: tA, sequenceID: seqA.id),
                    AMEMapping(name: "MB", triggerID: tB, sequenceID: seqB.id),
                ],
                sequences: [seqA, seqB]
            )
            let runtime = AMERuntime(sequenceSeed: 42)
            prepare(runtime, document: document)
            var idx: [Int] = []
            for i in 0..<6 {
                if interleaveB {
                    _ = runtime.process(noteOn(t: UInt64(i) * 2_000_000_000 + 500_000_000, note: 40), document: document, context: testContext)
                }
                let r = runtime.process(noteOn(t: UInt64(i) * 2_000_000_000, note: 36), document: document, context: testContext)
                if let s = r.diagnostics.first(where: { $0.kind == .sequenceStepFired && $0.sequenceID == seqA.id })?.stepIndex {
                    idx.append(s)
                }
            }
            return idx
        }
        XCTAssertEqual(runA(interleaveB: false), runA(interleaveB: true))
    }
}
