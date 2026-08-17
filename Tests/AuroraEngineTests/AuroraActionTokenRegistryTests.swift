import AuroraEngine
import AuroraModel
import AuroraMusical
import XCTest

final class AuroraActionTokenRegistryTests: XCTestCase {
    func testRegisterAndConsumeEphemeral() {
        let reg = AuroraActionTokenRegistry()
        let record = reg.registerEphemeral(.go)
        XCTAssertEqual(reg.count, 1)
        let consumed = reg.consume(record.token)
        XCTAssertEqual(consumed?.action, .go)
        XCTAssertEqual(reg.count, 0)
        XCTAssertNil(reg.consume(record.token))
    }

    func testSafetyDerivedOnRegister() throws {
        let reg = AuroraActionTokenRegistry()
        let record = reg.registerEphemeral(.compound([.go, .panic]))
        XCTAssertTrue(record.isSafetyCritical)
        let scheduled = try reg.schedulePayload(for: .compound([.panic]), targetBoundary: .nextBar)
        XCTAssertTrue(scheduled.isSafetyCritical)
        XCTAssertTrue(scheduled.targetBoundary.isImmediate)
    }

    func testDecorativeRemainsNonSafety() throws {
        let reg = AuroraActionTokenRegistry()
        let scheduled = try reg.schedulePayload(for: .go, targetBoundary: .nextMetricalBeat)
        XCTAssertFalse(scheduled.isSafetyCritical)
        if case .nextMetricalBeat = scheduled.targetBoundary {
            // ok
        } else {
            XCTFail("expected quantize boundary")
        }
    }

    func testMeterBridgeRoundTrip() throws {
        let show = ShowMusicalMeter.sevenEight_223
        let musical = try MusicalMeterBridge.musical(from: show)
        XCTAssertEqual(musical.beatGrouping, [2, 2, 3])
        XCTAssertEqual(musical.metricalBeatLengthsInQuarterNotes, [1.0, 1.0, 1.5])
        let back = MusicalMeterBridge.show(from: musical)
        XCTAssertEqual(back, show)
    }

    func testCancelPathCanConsumeToken() throws {
        let reg = AuroraActionTokenRegistry()
        let engine = MusicalEngine(clock: VirtualHostClock())
        engine.startTransport()
        let record = reg.registerEphemeral(.go)
        let scheduled = try ScheduledMusicalAction.actionToken(
            token: record.token,
            isSafetyCritical: record.isSafetyCritical,
            targetBoundary: .nextBar
        )
        XCTAssertEqual(engine.schedule(scheduled), .accepted(scheduled.id))
        XCTAssertEqual(reg.count, 1)
        if let removed = engine.cancelScheduled(id: scheduled.id),
           case .auroraActionToken(let token, _) = removed.command {
            _ = reg.consume(token)
        } else {
            XCTFail("expected canceled payload with token")
        }
        XCTAssertEqual(reg.count, 0)
    }

    func testFirePathConsumesToken() throws {
        let reg = AuroraActionTokenRegistry()
        let engine = MusicalEngine(clock: VirtualHostClock())
        engine.setScheduleFireHandler { action in
            if case .auroraActionToken(let token, _) = action.command {
                _ = reg.consume(token)
            }
        }
        let scheduled = try reg.schedulePayload(for: .panic, targetBoundary: .nextBar)
        XCTAssertEqual(reg.count, 1)
        _ = engine.schedule(scheduled)
        XCTAssertEqual(reg.count, 0)
    }
}
