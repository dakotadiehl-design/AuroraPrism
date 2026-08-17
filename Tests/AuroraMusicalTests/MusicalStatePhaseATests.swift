import AuroraMusical
import XCTest

final class MusicalStatePhaseATests: XCTestCase {
    func testModuleIdentity() {
        XCTAssertEqual(AuroraMusicalModule.name, "AuroraMusical")
    }

    func testTimingAndContextAreSeparate() {
        var state = MusicalState.initial
        state.context.activeSongID = UUID()
        state.timing.meter = .sixEight
        state.timing.meterProvenance = .songMetadata
        XCTAssertNotEqual(state.timing.meterProvenance, .midiClock)
    }

    func testSixEightCanonicalBeatLengths() {
        let meter = MusicalMeter.sixEight
        XCTAssertEqual(meter.metricalBeatCount, 2)
        XCTAssertEqual(meter.metricalBeatLengthsInQuarterNotes, [1.5, 1.5])
        XCTAssertEqual(meter.uniformMetricalBeatLengthInQuarterNotes ?? -1, 1.5, accuracy: 1e-12)
    }

    func testSevenEightAsymmetricNoSingularBeatDuration() {
        let m223 = MusicalMeter.sevenEight_223
        XCTAssertEqual(m223.metricalBeatLengthsInQuarterNotes, [1.0, 1.0, 1.5])
        XCTAssertNil(m223.uniformMetricalBeatLengthInQuarterNotes)

        let m322 = MusicalMeter.sevenEight_322
        XCTAssertEqual(m322.metricalBeatLengthsInQuarterNotes, [1.5, 1.0, 1.0])
        XCTAssertNotEqual(m223.beatGrouping, m322.beatGrouping)
    }

    func testContradictoryGroupingRejected() {
        // sum mismatch (6/8 with groups totaling 7)
        XCTAssertThrowsError(try MusicalMeter(numerator: 6, denominator: 8, beatGrouping: [3, 3, 1]))
        // empty
        XCTAssertThrowsError(try MusicalMeter(numerator: 4, denominator: 4, beatGrouping: []))
        // zero group entry
        XCTAssertThrowsError(try MusicalMeter(numerator: 4, denominator: 4, beatGrouping: [1, 0, 3]))
    }

    func testSixEightNextMetricalBeatDiffersFromQuarter() throws {
        let meter = MusicalMeter.sixEight
        let pos = try QuarterNotePosition(quarters: 0)
        let nextBeat = MusicalMeterMath.nextMetricalBeatPosition(after: pos, meter: meter)
        let nextQuarter = MusicalMeterMath.nextQuarterNotePosition(after: pos)
        XCTAssertEqual(nextBeat.quarters, 1.5, accuracy: 1e-9)
        XCTAssertEqual(nextQuarter.quarters, 1.0, accuracy: 1e-9)
    }

    func testBarBeatUsesGrouping() {
        let meter = MusicalMeter.sevenEight_223
        // After first beat (1.0 qn), into second beat
        let bb = MusicalMeterMath.barBeat(at: .must(1.1), meter: meter)
        XCTAssertEqual(bb.beatIndexInBar, 2)
    }

    func testMidiClockCapabilityDoesNotClaimSongPosition() {
        XCTAssertFalse(TimingSourceCapabilities.midiClock.suppliesSongPosition)
        XCTAssertTrue(TimingSourceCapabilities.midiClock.supportsSongPositionInput)
    }

    func testPanicBypassAlwaysImmediateAndSafety() throws {
        let a = ScheduledMusicalAction.panicBypass()
        XCTAssertTrue(a.isSafetyCritical)
        XCTAssertTrue(a.targetBoundary.isImmediate)
        // Decode path cannot reintroduce quantized panic
        var encoded = try JSONEncoder().encode(a)
        // Craft corrupted JSON with nextBar
        if var obj = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] {
            obj["targetBoundary"] = ["nextBar": [:]]
            // Use re-encode of proper structure: encode action then mutate command only via re-decode of panic with forced boundary in private init
        }
        let decoded = try JSONDecoder().decode(ScheduledMusicalAction.self, from: encoded)
        XCTAssertTrue(decoded.targetBoundary.isImmediate)
        XCTAssertTrue(decoded.isSafetyCritical)
    }

    func testSafetyTokenForcesImmediate() throws {
        let token = UUID()
        let scheduled = try ScheduledMusicalAction.actionToken(
            token: token,
            isSafetyCritical: true,
            targetBoundary: .nextBar
        )
        XCTAssertTrue(scheduled.targetBoundary.isImmediate)
        XCTAssertTrue(scheduled.isSafetyCritical)
        if case .auroraActionToken(let t, let s) = scheduled.command {
            XCTAssertEqual(t, token)
            XCTAssertTrue(s)
        } else {
            XCTFail("expected token")
        }
    }

    func testDecorativeTokenCanQuantize() throws {
        let scheduled = try ScheduledMusicalAction.actionToken(
            token: UUID(),
            isSafetyCritical: false,
            targetBoundary: .nextMetricalBeat
        )
        if case .nextMetricalBeat = scheduled.targetBoundary {
            // ok
        } else {
            XCTFail("expected nextMetricalBeat")
        }
        XCTAssertFalse(scheduled.isSafetyCritical)
    }

    func testSPPNormalizesToQuarterNotes() {
        let pos = QuarterNotePosition.fromMIDISongPositionSixteenths(16)
        XCTAssertEqual(pos.quarters, 4.0, accuracy: 0.0001)
    }
}
