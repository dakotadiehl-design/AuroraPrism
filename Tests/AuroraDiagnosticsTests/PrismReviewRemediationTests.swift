import AuroraDiagnostics
import XCTest

final class PrismReviewRemediationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PrismLog.resetForTests()
        PrismLogConfigurationStore.shared.replace(.verboseAll)
    }

    func testSupportSummaryOmitsTechnicalAndRedactsSecrets() {
        let report = PrismErrorReport(
            code: "project.open.decode_failed",
            userTitle: "Prism Couldn't Open the Show",
            userMessage: "Couldn't open /Users/dakota/Shows/Tour.prism from 10.0.0.8 pin=998877",
            recoverySuggestion: "Try another file.",
            technicalDescription: "DecodingError.dataCorrupted path=/Users/dakota/secret.json {\"cue\":\"Verse\"}",
            underlyingChain: ["NSCocoaErrorDomain#260 /Users/dakota/Shows/Tour.prism"],
            category: .projectDocument,
            severity: .error
        )
        let summary = PrismLogSanitizer.supportSummary(for: report)
        XCTAssertTrue(summary.contains("project.open.decode_failed"))
        XCTAssertTrue(summary.contains("reference="))
        XCTAssertFalse(summary.contains("DecodingError"))
        XCTAssertFalse(summary.contains("NSCocoaErrorDomain"))
        XCTAssertFalse(summary.contains("/Users/dakota"))
        XCTAssertFalse(summary.contains("10.0.0.8"))
        XCTAssertFalse(summary.contains("998877"))
        XCTAssertFalse(summary.contains("{\"cue\""))
        XCTAssertFalse(summary.contains("Couldn't open"))
        XCTAssertFalse(summary.contains("Try another file"))
    }

    func testRedactFreeTextCoversHostSerialAndPayload() {
        let text = "host=192.168.1.20 serial=ABC123 token: supersecret {\"fixture\":\"wash\"}"
        let redacted = PrismLogSanitizer.redactFreeText(text)
        XCTAssertFalse(redacted.contains("192.168.1.20"))
        XCTAssertFalse(redacted.contains("supersecret"))
        XCTAssertFalse(redacted.contains("{\"fixture\""))
    }

    func testSupportSummaryExcludesArbitraryNamesAndEndpointDetails() {
        let sensitive = [
            "Summer Tour", "Verse Cue", "Finale Song", "MegaWash Fixture",
            "lighting-console.local", "SN-A1B2C3", "stage-left endpoint",
            "2001:db8::1", #"C:\\Users\\Dakota\\Shows\\Tour.prism"#,
            "PIN 123456", "token is quoted-secret", "password \"hunter2\"",
        ].joined(separator: " | ")
        let report = PrismErrorReport(
            code: "output.failed",
            userTitle: sensitive,
            userMessage: sensitive,
            recoverySuggestion: sensitive,
            technicalDescription: sensitive,
            underlyingChain: [sensitive],
            category: .outputArtnet,
            severity: .error
        )
        let summary = report.supportSummary
        for fragment in ["Summer Tour", "Verse Cue", "lighting-console", "SN-A1B2C3", "2001:db8", "123456", "hunter2"] {
            XCTAssertFalse(summary.contains(fragment))
        }
        XCTAssertEqual(summary.components(separatedBy: "\n").count, 5)
    }

    func testUnifiedRecordIsIndependentlyJoinable() {
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let event = PrismLogEvent(
            level: .error,
            category: .projectDocument,
            code: "project.document.save_failed",
            humanMessage: "Prism couldn't save the show.",
            technicalMessage: "writeFailed replace_item",
            metadata: ["count": .count(1)],
            correlationID: id
        )
        let record = UnifiedPrismLogger.makeRecord(from: event)
        XCTAssertEqual(record.code, "project.document.save_failed")
        XCTAssertEqual(record.reference, "AAAAAAAA")
        XCTAssertTrue(record.independentlyJoinableText.contains("code=project.document.save_failed"))
        XCTAssertTrue(record.independentlyJoinableText.contains("ref=AAAAAAAA"))
        XCTAssertEqual(record.humanMessage, "Prism couldn't save the show.")
        XCTAssertEqual(record.technicalMessage, "writeFailed replace_item")
    }

    func testConcurrentUnifiedRecordsStayJoinable() {
        let unified = UnifiedPrismLogger(configuration: { .verboseAll }, captureLimit: 32)
        let group = DispatchGroup()
        for i in 0..<20 {
            group.enter()
            DispatchQueue.global().async {
                unified.log(
                    PrismLogEvent(
                        level: .error,
                        category: .outputArtnet,
                        code: "output.artnet.failed",
                        humanMessage: "Art-Net failed \(i).",
                        technicalMessage: "technical-\(i)",
                        correlationID: UUID()
                    )
                )
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 2), .success)
        let records = unified.capturedRecords()
        XCTAssertEqual(records.count, 20)
        for record in records {
            XCTAssertEqual(record.code, "output.artnet.failed")
            XCTAssertFalse(record.reference.isEmpty)
            XCTAssertTrue(record.independentlyJoinableText.contains("ref=\(record.reference)"))
            XCTAssertTrue(record.technicalMessage.hasPrefix("technical-"))
        }
    }

    func testRateLimitSummaryUsesOriginalLevel() {
        let memory = InMemoryPrismLogSink()
        var now = Date(timeIntervalSince1970: 100)
        let composite = CompositePrismLogger(
            sinks: [memory],
            configuration: { .productionDefaults },
            now: { now }
        )
        let event = PrismLogEvent(
            level: .error,
            category: .outputLocalDMX,
            code: "output.localDMX.failed",
            humanMessage: "Local DMX write failed.",
            ratePolicy: .oncePerSecond
        )
        composite.log(event)
        composite.log(event)
        now = now.addingTimeInterval(1.1)
        composite.log(event)
        let events = memory.snapshot()
        XCTAssertEqual(events.map(\.code), ["output.localDMX.failed", "output.localDMX.failed", "log.rate_limited"])
        let summary = try! XCTUnwrap(events.last)
        XCTAssertEqual(summary.level, .error)
        XCTAssertEqual(summary.category, .outputLocalDMX)
        XCTAssertEqual(summary.metadata["count"], .count(1))
        XCTAssertEqual(summary.metadata["code"], .public("output.localDMX.failed"))
    }

    func testUnifiedCaptureIsDisabledByDefault() {
        let unified = UnifiedPrismLogger(configuration: { .verboseAll })
        unified.log(PrismLogEvent(level: .error, category: .appLifecycle, code: "test", humanMessage: "private"))
        XCTAssertTrue(unified.capturedRecords().isEmpty)
    }

    func testOneLogicalEventIsOneUnifiedRecord() {
        let unified = UnifiedPrismLogger(configuration: { .verboseAll }, captureLimit: 8)
        unified.log(
            PrismLogEvent(
                level: .error,
                category: .remoteHost,
                code: "remote.host.failed",
                humanMessage: "Remote failed.",
                technicalMessage: "bind failed",
                metadata: [
                    "count": .count(2),
                    "profile": .public("troubleshooting"),
                ],
                correlationID: UUID()
            )
        )
        XCTAssertEqual(unified.capturedRecords().count, 1)
    }
}
