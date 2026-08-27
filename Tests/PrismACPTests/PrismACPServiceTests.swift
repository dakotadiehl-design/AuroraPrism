import AuroraACP
@testable import PrismACP
import XCTest

final class PrismACPServiceTests: XCTestCase {
    func testDisabledServiceIsNetworkSilent() async {
        let service = PrismACPService(configuration: PrismACPConfiguration(enabled: false))
        try? await service.start()
        let diagnostics = await service.diagnostics()
        XCTAssertEqual(diagnostics.listenerState, .stopped)
        let silent = await service.isNetworkSilent()
        XCTAssertTrue(silent)
    }

    func testEnabledServiceWithoutACPProvisionedIdentityFailsClosed() async {
        let service = PrismACPService(configuration: PrismACPConfiguration(enabled: true))
        do {
            try await service.start()
            XCTFail("Secure startup must not succeed without ACP-owned identity material")
        } catch {
            XCTAssertEqual(error as? PrismACPBlocker, .secureIdentityUnavailable)
        }
        let diagnostics = await service.diagnostics()
        XCTAssertEqual(diagnostics.listenerState, .blocked)
        XCTAssertEqual(diagnostics.blocker, .secureIdentityUnavailable)
        let silent = await service.isNetworkSilent()
        XCTAssertTrue(silent)
    }

    func testRepeatedStopIsIdempotentAndClearsPendingEnrollment() async {
        let service = PrismACPService(configuration: PrismACPConfiguration(enabled: false))
        await service.stop()
        await service.stop()
        let silent = await service.isNetworkSilent()
        XCTAssertTrue(silent)
        let state = await service.enrollment.state
        XCTAssertEqual(state, .unavailable(.enrollmentBootstrapUnavailable))
    }

    func testEnrollmentCannotApproveOrRejectWithoutACPProtocolCoordinator() async {
        let model = PrismACPEnrollmentPresentationModel()
        do {
            try await model.approve(UUID())
            XCTFail("Approval must remain unavailable")
        } catch {
            XCTAssertEqual(error as? PrismACPBlocker, .enrollmentBootstrapUnavailable)
        }
        do {
            try await model.reject(UUID())
            XCTFail("Rejection must remain unavailable")
        } catch {
            XCTAssertEqual(error as? PrismACPBlocker, .enrollmentBootstrapUnavailable)
        }
    }

    func testDiagnosticSnapshotContainsNoLiveControlState() async {
        let state = PrismACPAuthoritativeState(
            authorityEpoch: 2,
            revision: 9,
            showID: "show-id",
            showName: "Qualification Show"
        )
        let payload = state.snapshotPayload(ownerNodeID: "host")
        guard case .array(let resources) = payload["resources"] else {
            return XCTFail("Expected resources")
        }
        let names = Set(resources.compactMap { resource -> String? in
            guard case .object(let value) = resource,
                  case .string(let name) = value["resource"] else { return nil }
            return name
        })
        XCTAssertEqual(names, ["show.project", "system.health"])
        XCTAssertFalse(names.contains("output.grand_master"))
        XCTAssertFalse(names.contains("output.blackout"))
    }

    func testProductionSourceHasNoPlaintextOrMutationBoundary() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let prismACP = root.appendingPathComponent("Sources/PrismACP")
        let files = try FileManager.default.contentsOfDirectory(at: prismACP, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        let source = try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")

        XCTAssertFalse(source.contains("allowPlaintext"))
        XCTAssertFalse(source.contains("ControlActionRouter"))
        XCTAssertFalse(source.contains("ShowControlController"))
        XCTAssertFalse(source.contains("import AuroraEngine"))
        XCTAssertFalse(source.contains("installHostExecutor"))
        XCTAssertFalse(source.contains("remote.control.invoke"))
        XCTAssertFalse(source.contains("cue.go"))
        XCTAssertFalse(source.contains("output.blackout"))
        XCTAssertFalse(source.contains("output.grand_master"))
    }

    func testLegacyRemotePortsAreAbsentFromShippingSources() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources")
        let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
        var shippingSource = ""
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            shippingSource += try String(contentsOf: url, encoding: .utf8)
        }
        XCTAssertFalse(shippingSource.contains("8742"))
        XCTAssertFalse(shippingSource.contains("8743"))
    }
}
