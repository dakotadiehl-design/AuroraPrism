@testable import PrismACP
import Foundation
import XCTest

final class PrismACPMomentaryAuthorityTests: XCTestCase {
    func testBeginDuplicateRenewWrongLeaseEndAndCancel() async throws {
        let releases = ReleaseProbe()
        let authority = makeAuthority(probe: releases)
        await authority.start()
        let connection = UUID()
        let first = await authority.begin(
            controlID: "lease_test", activationID: "a", principalNodeID: "node",
            connectionID: connection, requestedLeaseMS: 500
        )
        let duplicate = await authority.begin(
            controlID: "lease_test", activationID: "a", principalNodeID: "node",
            connectionID: connection, requestedLeaseMS: 1_000
        )
        XCTAssertEqual(first.hold?.leaseID, duplicate.hold?.leaseID)
        let lease = try XCTUnwrap(first.hold?.leaseID)
        let wrong = await authority.renew(
            controlID: "lease_test", activationID: "a", leaseID: "wrong", principalNodeID: "node"
        )
        XCTAssertEqual(wrong.disposition, "rejected")
        let renewed = await authority.renew(
            controlID: "lease_test", activationID: "a", leaseID: lease, principalNodeID: "node"
        )
        XCTAssertEqual(renewed.disposition, "applied")
        let ended = await authority.end(activationID: "a", leaseID: lease, principalNodeID: "node", cancelled: false)
        XCTAssertEqual(ended.disposition, "applied")
        let emptyAfterEnd = await authority.snapshot().isEmpty
        XCTAssertTrue(emptyAfterEnd)

        let second = await authority.begin(
            controlID: "lease_test", activationID: "b", principalNodeID: "node",
            connectionID: connection, requestedLeaseMS: 500
        )
        let cancelled = await authority.end(
            activationID: "b", leaseID: try XCTUnwrap(second.hold?.leaseID), principalNodeID: "node", cancelled: true
        )
        XCTAssertEqual(cancelled.disposition, "applied")
        let normalReleaseCount = await releases.count()
        XCTAssertEqual(normalReleaseCount, 2)
        await authority.shutdown()
    }

    func testExpiryRunsWithoutInboundTraffic() async throws {
        let releases = ReleaseProbe()
        let authority = makeAuthority(probe: releases)
        await authority.start()
        _ = await authority.begin(
            controlID: "lease_test", activationID: "expiry", principalNodeID: "node",
            connectionID: UUID(), requestedLeaseMS: 100
        )
        try await Task.sleep(nanoseconds: 400_000_000)
        let emptyAfterExpiry = await authority.snapshot().isEmpty
        let expiryReleaseCount = await releases.count()
        XCTAssertTrue(emptyAfterExpiry)
        XCTAssertEqual(expiryReleaseCount, 1)
        await authority.shutdown()
    }

    func testDisconnectAuthorizationRemovalControlRemovalAndShutdownRelease() async {
        let releases = ReleaseProbe()
        let authority = makeAuthority(probe: releases)
        await authority.start()
        let connection = UUID()
        _ = await authority.begin(controlID: "lease_test", activationID: "disconnect", principalNodeID: "a", connectionID: connection, requestedLeaseMS: 2_000)
        await authority.releaseConnection(connection)
        _ = await authority.begin(controlID: "lease_test", activationID: "revoke", principalNodeID: "b", connectionID: UUID(), requestedLeaseMS: 2_000)
        await authority.revokePrincipal("b")
        _ = await authority.begin(controlID: "lease_test", activationID: "remove", principalNodeID: "c", connectionID: UUID(), requestedLeaseMS: 2_000)
        await authority.removeControl("lease_test")
        _ = await authority.begin(controlID: "lease_test", activationID: "shutdown", principalNodeID: "d", connectionID: UUID(), requestedLeaseMS: 2_000)
        await authority.shutdown()
        let emptyAfterTerminations = await authority.snapshot().isEmpty
        let terminationReleaseCount = await releases.count()
        XCTAssertTrue(emptyAfterTerminations)
        XCTAssertEqual(terminationReleaseCount, 4)
    }

    func testPersistedHoldRecoveryAndFailedReleaseStayUnsafe() async throws {
        let dir = temporaryDirectory()
        let store = dir.appendingPathComponent("holds.json")
        let failing = ReleaseProbe(fail: true)
        let first = PrismACPMomentaryAuthority(
            storeURL: store,
            releaseHandler: { hold in await failing.release(hold) }
        )
        await first.start()
        let begun = await first.begin(
            controlID: "lease_test", activationID: "persisted", principalNodeID: "node",
            connectionID: UUID(), requestedLeaseMS: 2_000
        )
        let failed = await first.end(
            activationID: "persisted", leaseID: try XCTUnwrap(begun.hold?.leaseID), principalNodeID: "node", cancelled: false
        )
        XCTAssertEqual(failed.disposition, "failed")
        XCTAssertEqual(failed.hold?.releasePending, true)
        XCTAssertEqual(failed.hold?.physicalActive, true)

        let recovered = ReleaseProbe()
        let second = PrismACPMomentaryAuthority(
            storeURL: store,
            releaseHandler: { hold in await recovered.release(hold) }
        )
        await second.start()
        let emptyAfterRecovery = await second.snapshot().isEmpty
        let recoveryCount = await recovered.count()
        XCTAssertTrue(emptyAfterRecovery)
        XCTAssertEqual(recoveryCount, 1)
        await second.shutdown()
        await first.shutdown()
    }

    private func makeAuthority(probe: ReleaseProbe) -> PrismACPMomentaryAuthority {
        PrismACPMomentaryAuthority(
            storeURL: temporaryDirectory().appendingPathComponent("holds.json"),
            releaseHandler: { hold in await probe.release(hold) }
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

private actor ReleaseProbe {
    private var releases = 0
    private let fail: Bool
    init(fail: Bool = false) { self.fail = fail }
    func release(_ hold: PrismACPMomentaryHold) -> (confirmedInactive: Bool, physicalActive: Bool?) {
        _ = hold
        releases += 1
        return fail ? (false, true) : (true, false)
    }
    func count() -> Int { releases }
}
