import AuroraEngine
import AuroraModel
import XCTest

final class EffectTimingTests: XCTestCase {
    private let fourFour = EffectMusicalMeter(numerator: 4, denominator: 4)

    func testCoordinatorSampleDrivesSemanticOutputAndVisualization() throws {
        let fixtureID = UUID()
        let source = EffectInstance(kind: .wave, rateHz: 99, size: 1, fixtureIDs: [fixtureID])
        let timing = EffectTimingCompiler.compile(.init(source: .musicEngine, rate: .musical(.init(unit: .note, noteDivision: .whole))))
        let compiled = CompiledPrismEffect(
            source: source,
            resolvedTargets: [.init(target: .init(fixtureID: fixtureID), orderIndex: 0, distributionPosition: 0)],
            timing: timing,
            parameterDescriptors: []
        )
        let coordinator = EffectTimingCoordinator()
        _ = coordinator.samples(for: [compiled], clocks: [.musicEngine: clock(q: 0)], monotonicTime: 0)
        let samples = coordinator.samples(for: [compiled], clocks: [.musicEngine: clock(q: 1, time: 1)], monotonicTime: 1)
        let result = PrismEffectEvaluator.evaluateOrdered(
            baseLook: .empty,
            context: .init(legacyTime: 123, timingSamples: samples),
            effects: [compiled]
        )

        XCTAssertEqual(try XCTUnwrap(samples[source.id]).phase, 0.25, accuracy: 1e-12)
        let semantic = try XCTUnwrap(result.semanticLook.fixtureAttributes[fixtureID]?["intensity"])
        let visual = try XCTUnwrap(result.visualizations[source.id]?.targets.first?.value)
        XCTAssertEqual(semantic, 1, accuracy: 1e-12)
        XCTAssertEqual(visual, semantic, accuracy: 1e-12)
    }

    func testWaitingAndStoppedSamplesDoNotModifySemanticLook() {
        let fixtureID = UUID()
        let source = EffectInstance(kind: .wave, rateHz: 1, size: 1, phase: 0.25, fixtureIDs: [fixtureID])
        let compiled = PrismEffectCompiler.compileLegacy(source)
        let base = ActiveLook(fixtureAttributes: [fixtureID: ["intensity": 0.2]])
        for status in [EffectTimingStatus.waitingForQuantization, .stopped] {
            let sample = EffectTimingSample(phase: 0.25, status: status, sourceID: "test", meter: fourFour)
            let result = PrismEffectEvaluator.evaluateOrdered(
                baseLook: base,
                context: .init(legacyTime: 0, timingSamples: [source.id: sample]),
                effects: [compiled]
            )
            XCTAssertEqual(result.semanticLook, base)
            XCTAssertNil(result.visualizations[source.id])
        }
    }

    func testPausedTransportHoldsAndDoesNotEnterInternalFallback() {
        var definition = EffectTimingDefinition(
            source: .musicEngine,
            rate: .musical(.init(unit: .note, noteDivision: .whole)),
            clockLossPolicy: .fallbackInternal
        )
        var runtime = EffectTimingRuntime()
        _ = runtime.sample(compiled: .init(definition: definition), clock: clock(q: 0))
        _ = runtime.sample(compiled: .init(definition: definition), clock: clock(q: 1, time: 1))
        var paused = clock(q: 1, time: 2)
        paused.transport = .paused
        let sample = runtime.sample(compiled: .init(definition: definition), clock: paused)
        XCTAssertEqual(sample.status, .holding)
        XCTAssertTrue(sample.isActive)
        XCTAssertEqual(sample.phase, 0.25, accuracy: 1e-12)
        definition.internalBPM = 240 // ensure fallback timing would have visibly advanced
    }

    func testRecoveryFromFallbackPreservesPhase() {
        var definition = EffectTimingDefinition(
            source: .midiClock,
            rate: .musical(.init(unit: .note, noteDivision: .whole)),
            sourceSwitchPolicy: .preservePhase,
            clockLossPolicy: .continueLastTempo
        )
        var runtime = EffectTimingRuntime()
        _ = runtime.sample(compiled: .init(definition: definition), clock: clock(q: 0, id: "midi"))
        let fallback = runtime.sample(compiled: .init(definition: definition), clock: lostClock(time: 1))
        let recovered = runtime.sample(compiled: .init(definition: definition), clock: clock(q: 100, time: 2, id: "midi"))
        XCTAssertEqual(fallback.phase, 0.5, accuracy: 1e-12)
        XCTAssertEqual(recovered.phase, fallback.phase, accuracy: 1e-12)
        definition.phase = 0.3
    }

    func testMeterChangeReanchorsWithoutPhaseJump() {
        let definition = EffectTimingDefinition(source: .musicEngine, rate: .musical(.init(unit: .bar)))
        var runtime = EffectTimingRuntime()
        _ = runtime.sample(compiled: .init(definition: definition), clock: clock(q: 0))
        let before = runtime.sample(compiled: .init(definition: definition), clock: clock(q: 1, time: 1))
        let sevenEight = EffectMusicalMeter(numerator: 7, denominator: 8, beatGrouping: [2, 2, 3])
        let changed = runtime.sample(compiled: .init(definition: definition), clock: clock(q: 1, time: 2, meter: sevenEight))
        XCTAssertEqual(changed.phase, before.phase, accuracy: 1e-12)
    }

    func testCoordinatorInvalidatesRuntimeWhenDefinitionChanges() throws {
        let fixtureID = UUID()
        let source = EffectInstance(kind: .wave, fixtureIDs: [fixtureID])
        func compiled(_ timing: EffectTimingDefinition) -> CompiledPrismEffect {
            .init(source: source, resolvedTargets: [.init(target: .init(fixtureID: fixtureID), orderIndex: 0, distributionPosition: 0)], timing: .init(definition: timing), parameterDescriptors: [])
        }
        let coordinator = EffectTimingCoordinator()
        let first = EffectTimingDefinition(source: .musicEngine, rate: .musical(.init(unit: .note, noteDivision: .whole)))
        _ = coordinator.samples(for: [compiled(first)], clocks: [.musicEngine: clock(q: 0)], monotonicTime: 0)
        _ = coordinator.samples(for: [compiled(first)], clocks: [.musicEngine: clock(q: 1, time: 1)], monotonicTime: 1)
        let edited = EffectTimingDefinition(source: .musicEngine, rate: .musical(.init(unit: .note, noteDivision: .quarter)), phase: 0.3)
        let samples = coordinator.samples(for: [compiled(edited)], clocks: [.musicEngine: clock(q: 1, time: 2)], monotonicTime: 2)
        XCTAssertEqual(try XCTUnwrap(samples[source.id]).phase, 0.3, accuracy: 1e-12)
    }

    func testMalformedDurableMeterIsRejected() {
        let json = Data(#"{"numerator":7,"denominator":0,"beatGrouping":[2,2,3]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(EffectMusicalMeter.self, from: json))
    }

    func testTwoBarsUsesSevenEightBarLength() {
        let meter = EffectMusicalMeter(numerator: 7, denominator: 8, beatGrouping: [2, 2, 3])
        let definition = EffectTimingDefinition(
            source: .musicEngine,
            rate: .musical(.init(unit: .bar, count: 2))
        )
        var runtime = EffectTimingRuntime()

        _ = runtime.sample(compiled: .init(definition: definition), clock: clock(q: 0, meter: meter))
        let halfway = runtime.sample(compiled: .init(definition: definition), clock: clock(q: 3.5, time: 1, meter: meter))

        XCTAssertEqual(halfway.phase, 0.5, accuracy: 1e-12)
        XCTAssertEqual(halfway.meter?.beatsPerBar, 3)
        XCTAssertEqual(halfway.meter?.beatUnit, 8)
    }

    func testAsymmetricMetricalBeatsHaveContinuousPhase() {
        let meter = EffectMusicalMeter(numerator: 7, denominator: 8, beatGrouping: [2, 2, 3])
        let definition = EffectTimingDefinition(
            source: .musicEngine,
            rate: .musical(.init(unit: .metricalBeat, count: 3))
        )
        var runtime = EffectTimingRuntime()
        _ = runtime.sample(compiled: .init(definition: definition), clock: clock(q: 0, meter: meter))

        XCTAssertEqual(runtime.sample(compiled: .init(definition: definition), clock: clock(q: 1, time: 1, meter: meter)).phase, 1.0 / 3.0, accuracy: 1e-12)
        XCTAssertEqual(runtime.sample(compiled: .init(definition: definition), clock: clock(q: 2, time: 2, meter: meter)).phase, 2.0 / 3.0, accuracy: 1e-12)
        XCTAssertEqual(runtime.sample(compiled: .init(definition: definition), clock: clock(q: 3.5, time: 3, meter: meter)).phase, 0, accuracy: 1e-12)
    }

    func testPreservePhaseAcrossSourceSwitch() {
        let definition = EffectTimingDefinition(
            source: .midiClock,
            rate: .musical(.init(unit: .note, noteDivision: .whole)),
            sourceSwitchPolicy: .preservePhase
        )
        var runtime = EffectTimingRuntime()
        _ = runtime.sample(compiled: .init(definition: definition), clock: clock(q: 0, id: "midi-a"))
        let before = runtime.sample(compiled: .init(definition: definition), clock: clock(q: 1, time: 1, id: "midi-a"))
        let after = runtime.sample(compiled: .init(definition: definition), clock: clock(q: 99, time: 2, id: "midi-b"))

        XCTAssertEqual(before.phase, 0.25, accuracy: 1e-12)
        XCTAssertEqual(after.phase, before.phase, accuracy: 1e-12)
    }

    func testRestartAcrossSourceSwitchUsesConfiguredPhase() {
        let definition = EffectTimingDefinition(
            source: .midiClock,
            rate: .musical(.init(unit: .note, noteDivision: .whole)),
            phase: 0.4,
            sourceSwitchPolicy: .restart
        )
        var runtime = EffectTimingRuntime()
        _ = runtime.sample(compiled: .init(definition: definition), clock: clock(q: 0, id: "a"))
        _ = runtime.sample(compiled: .init(definition: definition), clock: clock(q: 1, time: 1, id: "a"))
        let restarted = runtime.sample(compiled: .init(definition: definition), clock: clock(q: 50, time: 2, id: "b"))

        XCTAssertEqual(restarted.phase, 0.4, accuracy: 1e-12)
    }

    func testNextBarStartWaitsThenRuns() {
        let definition = EffectTimingDefinition(
            source: .musicEngine,
            rate: .musical(.init(unit: .note, noteDivision: .whole)),
            startQuantization: .nextBar
        )
        var runtime = EffectTimingRuntime()
        let waiting = runtime.sample(compiled: .init(definition: definition), clock: clock(q: 1))
        let starts = runtime.sample(compiled: .init(definition: definition), clock: clock(q: 4, time: 1))
        let advanced = runtime.sample(compiled: .init(definition: definition), clock: clock(q: 5, time: 2))

        XCTAssertEqual(waiting.status, .waitingForQuantization)
        XCTAssertEqual(starts.phase, 0, accuracy: 1e-12)
        XCTAssertEqual(advanced.phase, 0.25, accuracy: 1e-12)
    }

    func testClockLossPoliciesHoldContinueAndFallback() {
        let base = EffectTimingDefinition(
            source: .midiClock,
            rate: .musical(.init(unit: .note, noteDivision: .whole)),
            internalBPM: 60
        )
        var holdRuntime = EffectTimingRuntime()
        var hold = base
        hold.clockLossPolicy = .holdPhase
        _ = holdRuntime.sample(compiled: .init(definition: hold), clock: clock(q: 0))
        let held = holdRuntime.sample(compiled: .init(definition: hold), clock: lostClock(time: 2))
        XCTAssertEqual(held.status, .holding)
        XCTAssertEqual(held.phase, 0, accuracy: 1e-12)

        var continueRuntime = EffectTimingRuntime()
        var continuing = base
        continuing.clockLossPolicy = .continueLastTempo
        _ = continueRuntime.sample(compiled: .init(definition: continuing), clock: clock(q: 0, bpm: 120))
        let continued = continueRuntime.sample(compiled: .init(definition: continuing), clock: lostClock(time: 1))
        XCTAssertEqual(continued.status, .fallback)
        XCTAssertEqual(continued.phase, 0.5, accuracy: 1e-12)

        var fallbackRuntime = EffectTimingRuntime()
        var fallback = base
        fallback.clockLossPolicy = .fallbackInternal
        _ = fallbackRuntime.sample(compiled: .init(definition: fallback), clock: clock(q: 0))
        let internalSample = fallbackRuntime.sample(compiled: .init(definition: fallback), clock: lostClock(time: 1))
        XCTAssertEqual(internalSample.status, .fallback)
        XCTAssertEqual(internalSample.phase, 0.25, accuracy: 1e-12)
    }

    func testCoordinatorPreservesRuntimeAcrossDefinitionSourceSwitch() {
        let id = UUID(), fixture = UUID()
        let coordinator = EffectTimingCoordinator()
        func compiled(source: EffectClockSource, policy: EffectClockSwitchPolicy) -> CompiledPrismEffect {
            PrismEffectCompiler.compile(.init(
                id: id, kind: .wave, fixtureIDs: [fixture], generator: .init(),
                timing: .init(source: source, rate: .musical(.init(unit: .note, noteDivision: .whole)), sourceSwitchPolicy: policy)
            ))
        }
        let music0 = EffectClockSnapshot(source: .musicEngine, sourceID: "music", monotonicTime: 0, tempoBPM: 120, quarterNotePosition: 0, meter: fourFour)
        let music1 = EffectClockSnapshot(source: .musicEngine, sourceID: "music", monotonicTime: 1, tempoBPM: 120, quarterNotePosition: 1, meter: fourFour)
        _ = coordinator.samples(for: [compiled(source: .musicEngine, policy: .preservePhase)], clocks: [.musicEngine: music0], monotonicTime: 0)
        let before = coordinator.samples(for: [compiled(source: .musicEngine, policy: .preservePhase)], clocks: [.musicEngine: music1], monotonicTime: 1)[id]!
        XCTAssertEqual(before.phase, 0.25, accuracy: 1e-12)

        let midi = EffectClockSnapshot(source: .midiClock, sourceID: "midi", monotonicTime: 2, tempoBPM: 120, quarterNotePosition: 100, meter: fourFour)
        let preserved = coordinator.samples(for: [compiled(source: .midiClock, policy: .preservePhase)], clocks: [.midiClock: midi], monotonicTime: 2)[id]!
        XCTAssertEqual(preserved.phase, before.phase, accuracy: 1e-12)
    }

    func testCoordinatorExecutesRequantizePolicyInsteadOfResettingRuntime() {
        let id = UUID(), fixture = UUID()
        let coordinator = EffectTimingCoordinator()
        func compiled(source: EffectClockSource, policy: EffectClockSwitchPolicy) -> CompiledPrismEffect {
            PrismEffectCompiler.compile(.init(
                id: id, kind: .wave, fixtureIDs: [fixture], generator: .init(),
                timing: .init(
                    source: source, rate: .musical(.init(unit: .note, noteDivision: .quarter)),
                    startQuantization: .nextBar, sourceSwitchPolicy: policy
                )
            ))
        }
        let music = EffectClockSnapshot(source: .musicEngine, sourceID: "music", monotonicTime: 0, tempoBPM: 120, quarterNotePosition: 4, meter: fourFour)
        _ = coordinator.samples(for: [compiled(source: .musicEngine, policy: .preservePhase)], clocks: [.musicEngine: music], monotonicTime: 0)
        let midi = EffectClockSnapshot(source: .midiClock, sourceID: "midi", monotonicTime: 1, tempoBPM: 120, quarterNotePosition: 5, meter: fourFour)
        let waiting = coordinator.samples(for: [compiled(source: .midiClock, policy: .requantize)], clocks: [.midiClock: midi], monotonicTime: 1)[id]!
        XCTAssertEqual(waiting.status, .waitingForQuantization)
        XCTAssertFalse(waiting.isActive)
    }

    private func clock(
        q: Double,
        time: TimeInterval = 0,
        id: String = "music",
        bpm: Double = 120,
        meter: EffectMusicalMeter? = nil
    ) -> EffectClockSnapshot {
        .init(
            source: .musicEngine,
            sourceID: id,
            monotonicTime: time,
            tempoBPM: bpm,
            quarterNotePosition: q,
            meter: meter ?? fourFour
        )
    }

    private func lostClock(time: TimeInterval) -> EffectClockSnapshot {
        .init(
            source: .midiClock,
            sourceID: "lost",
            monotonicTime: time,
            meter: fourFour,
            transport: .stopped,
            quality: .unavailable
        )
    }
}
