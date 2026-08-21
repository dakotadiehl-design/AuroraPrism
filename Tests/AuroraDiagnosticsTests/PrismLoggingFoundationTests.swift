import AuroraDiagnostics
import XCTest

final class PrismLoggingFoundationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PrismLog.resetForTests()
        PrismLogConfigurationStore.shared.replace(.productionDefaults)
    }

    func testLevelOrderingAndOffSemantics() {
        XCTAssertTrue(PrismLogLevel.debug < PrismLogLevel.info)
        XCTAssertTrue(PrismLogLevel.info < PrismLogLevel.notice)
        XCTAssertTrue(PrismLogLevel.notice < PrismLogLevel.warning)
        XCTAssertTrue(PrismLogLevel.warning < PrismLogLevel.error)
        XCTAssertTrue(PrismLogLevel.error < PrismLogLevel.fault)

        XCTAssertFalse(PrismLogLevel.off.accepts(.debug))
        XCTAssertFalse(PrismLogLevel.off.accepts(.notice))
        XCTAssertTrue(PrismLogLevel.off.accepts(.error))
        XCTAssertTrue(PrismLogLevel.off.accepts(.fault))

        XCTAssertTrue(PrismLogLevel.error.accepts(.error))
        XCTAssertFalse(PrismLogLevel.error.accepts(.notice))
        XCTAssertTrue(PrismLogLevel.notice.accepts(.warning))
        XCTAssertTrue(PrismLogLevel.debug.accepts(.info))
    }

    func testLegacySuppressionFieldCannotDisableProductionErrors() throws {
        let data = Data(#"{"version":1,"profile":"custom","thresholds":{"output.artnet":"off"},"allowFaultSuppression":true}"#.utf8)
        let decoded = try JSONDecoder().decode(PrismLogConfiguration.self, from: data)
        XCTAssertTrue(decoded.accepts(.error, category: .outputArtnet))
        XCTAssertTrue(decoded.accepts(.fault, category: .outputArtnet))
        let reencoded = String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self)
        XCTAssertFalse(reencoded.contains("allowFaultSuppression"))
    }

    func testConfigurationVersionMigrationAndFutureRejection() throws {
        let legacy = try JSONDecoder().decode(
            PrismLogConfiguration.self,
            from: Data(#"{"profile":"custom","thresholds":{"music.transport":"debug"}}"#.utf8)
        )
        XCTAssertEqual(legacy.version, PrismLogConfiguration.currentVersion)
        XCTAssertEqual(legacy.level(for: .musicTransport), .debug)

        let future = Data(#"{"version":999,"profile":"custom","thresholds":{}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(PrismLogConfiguration.self, from: future))
    }

    func testCategoryDefaultsAndUnknownFallback() {
        XCTAssertEqual(PrismLogCategory.ameIngress.defaultLevel, .notice)
        XCTAssertEqual(PrismLogCategory.musicTransport.defaultLevel, .notice)
        XCTAssertEqual(PrismLogCategory.uiStage.defaultLevel, .error)
        XCTAssertEqual(PrismLogCategory.enginePerformance.defaultLevel, .error)

        let encoded = try! JSONEncoder().encode(PrismLogConfiguration.productionDefaults)
        var json = try! JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        var thresholds = json["thresholds"] as! [String: String]
        thresholds["future.unknown"] = "debug"
        json["thresholds"] = thresholds
        let data = try! JSONSerialization.data(withJSONObject: json)
        let decoded = try! JSONDecoder().decode(PrismLogConfiguration.self, from: data)
        XCTAssertEqual(decoded.level(for: .ameIngress), .notice)
        XCTAssertEqual(decoded.level(for: .uiStage), .error)
    }

    func testCorruptConfigurationFallsBackViaDecodeDefaults() {
        let data = Data("{\"version\":1}".utf8)
        let decoded = try! JSONDecoder().decode(PrismLogConfiguration.self, from: data)
        XCTAssertEqual(decoded.level(for: .ameMatching), .notice)
        XCTAssertEqual(decoded.level(for: .uiWorkspace), .error)
    }

    func testIndependentAMEAndMusicThresholds() {
        var config = PrismLogConfiguration.productionDefaults
        config = config.setting(.ameMatching, to: .debug)
        config = config.setting(.musicTransport, to: .notice)
        XCTAssertTrue(config.accepts(.debug, category: .ameMatching))
        XCTAssertFalse(config.accepts(.debug, category: .musicTransport))
        XCTAssertTrue(config.accepts(.notice, category: .musicTransport))
    }

    func testAutoclosureLazinessBelowThreshold() {
        PrismLogConfigurationStore.shared.replace(.productionDefaults)
        let memory = InMemoryPrismLogSink()
        PrismLog.shared = memory
        var evaluated = false
        func expensive() -> String {
            evaluated = true
            return "should not build"
        }
        PrismLog.debug(.uiStage, "ui.stage.should_not_run", expensive())
        XCTAssertFalse(evaluated)
        XCTAssertEqual(memory.count, 0)
    }

    func testAutoclosureRunsWhenEnabled() {
        PrismLogConfigurationStore.shared.replace(.verboseAll)
        let memory = InMemoryPrismLogSink()
        PrismLog.shared = memory
        var evaluated = false
        func expensive() -> String {
            evaluated = true
            return "built"
        }
        PrismLog.debug(.uiStage, "ui.stage.layout_commit_failed", expensive())
        XCTAssertTrue(evaluated)
        XCTAssertEqual(memory.snapshot().first?.humanMessage, "built")
    }

    func testCompositeFanOutAndSanitizer() {
        let a = InMemoryPrismLogSink()
        let b = InMemoryPrismLogSink()
        let composite = CompositePrismLogger(sinks: [a, b])
        PrismLogConfigurationStore.shared.replace(.verboseAll)
        composite.log(
            PrismLogEvent(
                level: .error,
                category: .remoteSession,
                code: "remote.session.auth_failed",
                humanMessage: "A remote client could not be authenticated.",
                metadata: [
                    "pin": .string("1234", privacy: .public),
                    "count": .count(1),
                ]
            )
        )
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(b.count, 1)
        XCTAssertEqual(a.snapshot()[0].metadata["pin"]?.privacy, .private)
        XCTAssertEqual(a.snapshot()[0].metadata["count"]?.privacy, .public)
    }

    func testMetadataKeysAreSorted() {
        let event = PrismLogEvent(
            level: .info,
            category: .appLifecycle,
            code: "app.lifecycle.launch",
            humanMessage: "Prism is ready.",
            metadata: [
                "profile": .public("productionDefaults"),
                "count": .count(3),
                "ok": .flag(true),
            ]
        )
        XCTAssertEqual(event.metadata.keys.sorted(), ["count", "ok", "profile"])
        XCTAssertTrue(event.publicMetadataDescription.contains("count=3"))
    }

    func testRateLimiterFirstPlusSummary() {
        let limiter = PrismLogRateLimiter()
        let policy = PrismLogRatePolicy(interval: 1, maxPerInterval: 1)
        let start = Date()
        XCTAssertEqual(limiter.accept(key: "k", policy: policy, now: start), .allow)
        XCTAssertEqual(limiter.accept(key: "k", policy: policy, now: start.addingTimeInterval(0.1)), .suppress)
        XCTAssertEqual(limiter.accept(key: "k", policy: policy, now: start.addingTimeInterval(0.2)), .suppress)
        XCTAssertEqual(
            limiter.accept(key: "k", policy: policy, now: start.addingTimeInterval(1.1)),
            .allowAndSummarize(suppressed: 2)
        )
    }

    func testRingEvictsByCountAndBytes() {
        let sink = InMemoryPrismLogSink(capacity: 3, byteBudget: 80)
        for i in 0..<6 {
            sink.log(
                PrismLogEvent(
                    level: .error,
                    category: .appLifecycle,
                    code: "app.lifecycle.launch",
                    humanMessage: String(repeating: "x", count: 20) + "\(i)"
                )
            )
        }
        XCTAssertLessThanOrEqual(sink.count, 3)
        XCTAssertTrue(sink.snapshot().last?.humanMessage.hasSuffix("5") == true)
    }

    func testNoOpNeverEnables() {
        let noop = PrismNoOpLogger()
        XCTAssertFalse(noop.isEnabled(.fault, category: .appLifecycle))
    }

    func testConcurrentConfigurationSwap() {
        let store = PrismLogConfigurationStore(initial: .productionDefaults)
        let group = DispatchGroup()
        for i in 0..<50 {
            group.enter()
            DispatchQueue.global().async {
                if i % 2 == 0 {
                    store.replace(.verboseAll)
                } else {
                    store.replace(.productionDefaults)
                }
                _ = store.current().accepts(.debug, category: .ameMatching)
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 2), .success)
        _ = store.current()
    }

    func testExactlyOnceErrorReporting() {
        let memory = InMemoryPrismLogSink()
        PrismLog.shared = memory
        PrismLogConfigurationStore.shared.replace(.productionDefaults)
        let error = SampleDiagnosableError()
        let first = PrismErrorReporting.report(
            error: error,
            context: .projectOpen(objectLabel: "Tour Show")
        )
        XCTAssertEqual(memory.count, 1)
        XCTAssertEqual(first.code, "project.open.decode_failed")
        XCTAssertEqual(first.userMessage, "Prism couldn't open this show because part of the file is damaged.")
        XCTAssertTrue(first.technicalDescription.contains("SampleDiagnosableError"))
        XCTAssertFalse(first.userMessage.contains("DecodingError"))
        XCTAssertNotNil(first.correlationID)
    }

    func testUnknownErrorFallbackOmitsTechnicalTokensFromUserCopy() {
        let ns = NSError(domain: "NSCocoaErrorDomain", code: 260, userInfo: [
            NSLocalizedDescriptionKey: "The file couldn’t be opened.",
        ])
        let report = PrismErrorReporting.makeReport(
            error: ns,
            context: .projectOpen()
        )
        XCTAssertEqual(report.code, "project.document.open_failed")
        XCTAssertEqual(report.userTitle, "Prism Couldn't Open the Show")
        XCTAssertFalse(report.userMessage.contains("NSCocoaErrorDomain"))
        XCTAssertTrue(report.technicalDescription.contains("NSCocoaErrorDomain"))
    }

    func testUnknownErrorWithoutEventCodeUsesFallback() {
        let ns = NSError(domain: "NSCocoaErrorDomain", code: 260, userInfo: [
            NSLocalizedDescriptionKey: "The file couldn’t be opened.",
        ])
        let report = PrismErrorReporting.makeReport(
            error: ns,
            context: PrismErrorContext(
                operation: "unclassified",
                fallbackTitle: "Prism Couldn't Complete That Action",
                fallbackMessage: "Something went wrong."
            )
        )
        XCTAssertEqual(report.code, "error.unknown")
        XCTAssertFalse(report.userMessage.contains("NSCocoaErrorDomain"))
        XCTAssertTrue(report.technicalDescription.contains("NSCocoaErrorDomain"))
    }
}

private struct SampleDiagnosableError: PrismDiagnosableError {
    var prismErrorCode: String { "project.open.decode_failed" }
    var userTitle: String { "Prism Couldn't Open the Show" }
    var userMessage: String { "Prism couldn't open this show because part of the file is damaged." }
    var recoverySuggestion: String? { "Choose another file." }
    var technicalDetails: String { "SampleDiagnosableError; DecodingError.dataCorrupted" }
    var prismCategory: PrismLogCategory { .projectDocument }
    var prismSeverity: PrismLogLevel { .error }
}
