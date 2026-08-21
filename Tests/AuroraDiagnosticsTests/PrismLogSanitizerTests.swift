import AuroraDiagnostics
import XCTest

final class PrismLogSanitizerTests: XCTestCase {
    func testDowngradesDisallowedPublicFields() {
        let event = PrismLogEvent(
            level: .error,
            category: .remoteHost,
            code: "remote.host.failed",
            humanMessage: "Prism couldn't start remote access.",
            metadata: [
                "pin": .string("998877", privacy: .public),
                "path": .string("/Users/dakota/Shows/Tour.prism", privacy: .public),
                "host": .string("192.168.1.20", privacy: .public),
                "count": .count(2),
                "profile": .public("troubleshooting"),
            ]
        )
        let sanitized = PrismLogSanitizer.sanitize(event)
        XCTAssertEqual(sanitized.metadata["pin"]?.privacy, .private)
        XCTAssertEqual(sanitized.metadata["path"]?.privacy, .private)
        XCTAssertEqual(sanitized.metadata["host"]?.privacy, .private)
        XCTAssertEqual(sanitized.metadata["count"]?.privacy, .public)
        XCTAssertEqual(sanitized.metadata["profile"]?.privacy, .public)
        XCTAssertEqual(sanitized.metadata["pin"]?.publicDescription, "<private>")
        XCTAssertEqual(sanitized.metadata["count"]?.publicDescription, "2")
    }

    func testSupportSummaryContainsCodeAndReferenceNotPIN() {
        let report = PrismErrorReport(
            code: "remote.session.auth_failed",
            userTitle: "Prism Couldn't Start Remote Access",
            userMessage: "A remote client could not be authenticated.",
            recoverySuggestion: "Check the PIN in Settings.",
            technicalDescription: "auth failed",
            underlyingChain: [],
            category: .remoteSession,
            severity: .warning,
            correlationID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        )
        let summary = report.supportSummary
        XCTAssertTrue(summary.contains("remote.session.auth_failed"))
        XCTAssertTrue(summary.contains("reference=AAAAAAAA"))
        XCTAssertFalse(summary.contains("998877"))
        XCTAssertFalse(summary.contains("technical="))
    }
}
