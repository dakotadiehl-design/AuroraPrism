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

    func testEnabledServiceWithoutQualifiedProviderManifestFailsClosed() async {
        let service = PrismACPService(configuration: PrismACPConfiguration(enabled: true))
        do {
            try await service.start()
            XCTFail("Secure startup must not succeed without qualified provenance")
        } catch {
            XCTAssertEqual(error as? PrismACPBlocker, .providerManifestMissing)
        }
        let diagnostics = await service.diagnostics()
        XCTAssertEqual(diagnostics.listenerState, .blocked)
        XCTAssertEqual(diagnostics.blocker, .providerManifestMissing)
        let silent = await service.isNetworkSilent()
        XCTAssertTrue(silent)
    }

    func testRepeatedStopIsIdempotentAndNetworkSilent() async {
        let service = PrismACPService(configuration: PrismACPConfiguration(enabled: false))
        await service.stop()
        await service.stop()
        let silent = await service.isNetworkSilent()
        XCTAssertTrue(silent)
        let state = await service.enrollment.state
        XCTAssertEqual(state, .idle)
    }

    func testInvalidProviderManifestFailsClosedBeforeHostBootstrap() async {
        let service = PrismACPService(configuration: PrismACPConfiguration(
            enabled: true,
            providerProvenanceJSON: Data("{}".utf8),
            expectedProviderSourceRevision: String(repeating: "a", count: 40)))
        do {
            try await service.start()
            XCTFail("Malformed provenance must not reach host bootstrap")
        } catch {
            XCTAssertEqual(error as? PrismACPBlocker, .providerManifestInvalid)
        }
        let silent = await service.isNetworkSilent()
        XCTAssertTrue(silent)
    }

    func testQualifiedProviderRevisionMismatchFailsClosed() async {
        let manifest = """
        {"schema_version":"1.0","adapter_id":"apple-full","source_revision":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","provider":{"name":"Apple","version":"1"},"target_triple":"arm64-apple-macosx14.0","profiles":["full"],"key_storage_classes":["secure_enclave","keychain"],"qualification":{"status":"PASS","artifact_sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}}
        """
        let service = PrismACPService(configuration: PrismACPConfiguration(
            enabled: true,
            providerProvenanceJSON: Data(manifest.utf8),
            expectedProviderSourceRevision: String(repeating: "c", count: 40)))
        do {
            try await service.start()
            XCTFail("Mismatched qualification revision must fail closed")
        } catch {
            XCTAssertEqual(error as? PrismACPBlocker, .providerRevisionMismatch)
        }
        let silent = await service.isNetworkSilent()
        XCTAssertTrue(silent)
    }

    func testEveryRegisteredMessageHasDeterministicDisposition() {
        XCTAssertFalse(ACPRegistry.rows.isEmpty)
        for type in ACPRegistry.rows.keys {
            switch PrismACPService.disposition(for: type) {
            case .allowedReadOnly, .reject, .protocolInternal, .close: break
            }
        }
        XCTAssertEqual(PrismACPService.disposition(for: "future.unknown") == .close, true)
        let mutations = [
            "remote.control.invoke", "remote.momentary.begin",
            "remote.momentary.refresh", "remote.momentary.end",
            "remote.navigation.song", "remote.navigation.section",
            "remote.navigation.cue", "remote.transport", "remote.busking",
        ]
        for type in mutations where ACPRegistry.lookup(type) != nil {
            XCTAssertEqual(PrismACPService.disposition(for: type), .reject, type)
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
