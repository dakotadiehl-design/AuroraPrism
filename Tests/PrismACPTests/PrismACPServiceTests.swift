import AuroraACP
import CoreFoundation
import CryptoKit
@testable import PrismACP
import XCTest

final class PrismACPServiceTests: XCTestCase {
    private func uniquePort() -> UInt16 { UInt16.random(in: 28400...28999) }

    func testLiveEphemeralFreshnessRejectsMissingAndExpiredInvocations() {
        let now = Date()
        XCTAssertEqual(
            PrismACPInvocationFreshness.rejectionReason(payload: [:], now: now),
            "live_ephemeral_required"
        )
        let expired: [String: AnySendable] = [
            "delivery": .string("live_ephemeral"),
            "issued_at": .string(timestamp(date: now.addingTimeInterval(-10))),
            "expires_at": .string(timestamp(date: now.addingTimeInterval(-5))),
            "max_age_ms": .uint(5_000),
        ]
        XCTAssertEqual(
            PrismACPInvocationFreshness.rejectionReason(payload: expired, now: now),
            "command_expired"
        )
        let fresh: [String: AnySendable] = [
            "delivery": .string("live_ephemeral"),
            "issued_at": .string(timestamp(date: now)),
            "expires_at": .string(timestamp(date: now.addingTimeInterval(5))),
            "max_age_ms": .uint(5_000),
        ]
        XCTAssertNil(PrismACPInvocationFreshness.rejectionReason(payload: fresh, now: now))
        var invalidDelivery = fresh
        invalidDelivery["delivery"] = .string("latest_value_wins")
        XCTAssertEqual(
            PrismACPInvocationFreshness.rejectionReason(payload: invalidDelivery, now: now),
            "live_ephemeral_required"
        )
    }

    func testRemoteSurfaceUsesFrozenSemanticActionsAndPassesProductionValidation() {
        let state = authoritativeState(currentCueID: "cue-current")
        let layout = PrismACPRemoteProfile.layout(for: state, mutationsEnabled: true)
        guard case .array(let controls) = layout["controls"], controls.count == 3 else {
            return XCTFail("canonical production controls")
        }
        let actions = Set(controls.compactMap { item -> String? in
            guard case .object(let control) = item,
                  case .object(let binding) = control["binding"],
                  case .string(let action) = binding["action"] else { return nil }
            return action
        })
        XCTAssertEqual(actions, ["cue.go", "output.grand_master.set", "output.blackout.set"])

        guard case .object(let master) = controls.first(where: {
            guard case .object(let value) = $0 else { return false }
            return value["control_id"] == .string("grand_master")
        }) else { return XCTFail("missing grand master control") }
        XCTAssertEqual(master["permission"], .string("output.grand_master"))
        XCTAssertEqual(master["delivery"], .string("latest_value_wins"))
        XCTAssertEqual(master["update_mode"], .string("continuous"))
        XCTAssertEqual(master["min"], .double(0))
        XCTAssertEqual(master["max"], .double(1))
        guard case .object(let masterBinding) = master["binding"] else { return XCTFail("master binding") }
        XCTAssertEqual(masterBinding["action"], .string("output.grand_master.set"))

        guard case .object(let blackout) = controls.first(where: {
            guard case .object(let value) = $0 else { return false }
            return value["control_id"] == .string("blackout")
        }), case .object(let blackoutBinding) = blackout["binding"] else { return XCTFail("blackout control") }
        XCTAssertEqual(blackout["control_type"], .string("toggle"))
        XCTAssertEqual(blackoutBinding["action"], .string("output.blackout.set"))

        let typed = PrismACPRemoteProfile.executionLayout(for: state, mutationsEnabled: true)
        XCTAssertEqual(typed.control("cue_go")?.action, "cue.go")
        XCTAssertEqual(typed.control("grand_master")?.controlType, "fader")
        XCTAssertNil(typed.control("lease_test"))
        if case .rejected(let reason) = ACPRemoteSurfaceValidator.evaluate(layout) {
            XCTFail("production surface rejected: \(reason)")
        }
    }

    func testProductionSnapshotDoesNotExposeSyntheticMomentaryControl() {
        let snapshot = PrismACPRemoteProfile.controlSnapshot(
            for: authoritativeState(currentCueID: "cue-current"),
            mutationsEnabled: true
        )
        guard case .array(let controls) = snapshot["controls"] else { return XCTFail("controls") }
        XCTAssertFalse(controls.contains { item in
            guard case .object(let value) = item else { return false }
            return value["control_id"] == .string("lease_test")
        })
    }

    func testStartStopIsDeterministicAndSilentWhenDisabled() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let port = uniquePort()
        let service = PrismACPService(
            configuration: PrismACPConfiguration(
                enabled: true,
                discoveryEnabled: false,
                advertiseControl: false,
                webSocketPort: port,
                applicationSupportDirectory: dir
            )
        )
        try await service.start()
        var diag = await service.diagnostics()
        XCTAssertEqual(diag.listenerState, .ready)
        XCTAssertTrue(diag.advertisedCapabilities.isEmpty)
        XCTAssertFalse(diag.nodeID.isEmpty)
        let node = diag.nodeID
        await service.stop()
        diag = await service.diagnostics()
        XCTAssertEqual(diag.listenerState, .stopped)
        let silent = await service.isNetworkSilent()
        XCTAssertTrue(silent)

        let again = PrismACPService(
            configuration: PrismACPConfiguration(
                enabled: true,
                webSocketPort: uniquePort(),
                applicationSupportDirectory: dir
            )
        )
        try await again.start()
        let againDiag = await again.diagnostics()
        XCTAssertEqual(againDiag.nodeID, node)
        await again.stop()
    }

    func testAuthoritativeSnapshotProjectsStableDomains() throws {
        let state = PrismACPAuthoritativeState(
            authorityEpoch: 4,
            revision: 12,
            showID: "show",
            showName: "Haywire",
            engineRunning: true,
            currentCueID: "cue-a",
            currentCueName: "Opening",
            nextCueID: "cue-b",
            nextCueName: "Verse",
            outputStatus: "sACN",
            masterIntensity: 0.8,
            blackout: false
        )
        let payload = state.snapshotPayload(ownerNodeID: "0193f8d8-4c4e-7d8b-a2ab-000000000001")
        XCTAssertEqual(payload["authority_epoch"], .uint(4))
        XCTAssertEqual(payload["revision"], .uint(12))
        guard case .array(let resources) = payload["resources"] else {
            return XCTFail("resources")
        }
        let names = resources.compactMap { item -> String? in
            guard case .object(let obj) = item, case .string(let name) = obj["resource"] else { return nil }
            return name
        }
        XCTAssertTrue(Set(ACPRemoteStateStore.namespaces).isSubset(of: Set(names)))
        XCTAssertFalse(names.contains(where: { $0.hasPrefix("prism.") }))
        guard let cue = resources.first(where: { item in
            guard case .object(let object) = item else { return false }
            return object["resource"] == .string("show.current_section")
        }), case .object(let cueResource) = cue, case .object(let cueValue) = cueResource["value"] else {
            return XCTFail("cue resource")
        }
        XCTAssertEqual(cueValue["section_id"], .string("cue-a"))
        XCTAssertEqual(cueValue["name"], .string("Opening"))
        let next = try ACPStateRevision.applyDelta(
            localEpoch: 4,
            localRevision: 12,
            payload: ACPStateRevision.deltaPayload(authorityEpoch: 4, baseRevision: 12, revision: 13, changes: [])
        )
        XCTAssertEqual(next.1, 13)
    }

    func testBonjourTXTContainsNoCredentials() {
        let txt = ACPDiscoveryTXT(
            name: "Prism",
            port: 27421,
            nodeID: "0193f8d8-4c4e-7d8b-a2ab-000000000001",
            instanceID: "0193f8d8-4c4e-7d8b-a2ab-000000000002",
            endpointURL: "ws://127.0.0.1:27421/acp"
        ).txtRecord
        XCTAssertNil(txt["pin"])
        XCTAssertNil(txt["token"])
        XCTAssertEqual(txt["url"], "ws://127.0.0.1:27421/acp")
        XCTAssertEqual(txt["prf"], "core,remote,aurora.remote.prism.v1")
        XCTAssertEqual(txt["enc"], "cbor,json")
        XCTAssertEqual(txt["name"], "Prism")
        XCTAssertNotNil(txt["cap"])
    }

    func testMutationsAreNotAdvertised() async {
        let router = PrismACPActionRouter(advertiseControl: false)
        XCTAssertTrue(router.advertisedCapabilities().isEmpty)
        XCTAssertThrowsError(try router.submit(PrismACPAction(name: "performance.go")))
        XCTAssertEqual(PrismACPActionRouter.showActionStorageKey(for: PrismACPAction(name: "performance.go")), "go")
        XCTAssertNil(PrismACPActionRouter.showActionStorageKey(for: PrismACPAction(name: "programmer.attribute")))
    }

    func testAdmitGoIsOnceOnlyAndStaleCueFails() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let service = PrismACPService(
            configuration: PrismACPConfiguration(
                enabled: true,
                advertiseControl: true,
                operatorNodeIDs: ["remote-a"],
                webSocketPort: uniquePort(),
                applicationSupportDirectory: dir
            )
        )
        try await service.start()
        await service.noteAuthoritativeState(PrismACPAuthoritativeState(
            authorityEpoch: 1,
            revision: 4,
            showID: "show",
            showName: "Haywire",
            engineRunning: true,
            currentCueID: "cue-b",
            nextCueID: "cue-c",
            outputStatus: "Null",
            masterIntensity: 1,
            blackout: false
        ))
        let box = DispatchBox()
        await installAppliedExecutor(service: service, box: box, currentCueID: "cue-b")
        let stale = PrismACPAction(
            name: "performance.go",
            commandID: "0193f8d8-4c4e-7d8b-a2ab-000000000010",
            originNodeID: "0193f8d8-4c4e-7d8b-a2ab-000000000001",
            originInstanceID: "0193f8d8-4c4e-7d8b-a2ab-000000000001",
            originPrincipal: "remote-a",
            preconditions: [
                ACPPrecondition(op: "equals", field: "authority_epoch", value: .uint(2)),
                ACPPrecondition(op: "equals", field: "current_cue_id", value: .string("cue-a")),
            ]
        )
        let staleResult = try await service.admit(stale)
        XCTAssertEqual(staleResult.disposition, "precondition_failed")
        XCTAssertEqual(box.snapshot(), [])
        let command = "0193f8d8-4c4e-7d8b-a2ab-000000000011"
        let go = PrismACPAction(
            name: "performance.go",
            commandID: command,
            originNodeID: "0193f8d8-4c4e-7d8b-a2ab-000000000001",
            originInstanceID: "0193f8d8-4c4e-7d8b-a2ab-000000000001",
            originPrincipal: "remote-a",
            preconditions: [
                ACPPrecondition(op: "equals", field: "authority_epoch", value: .uint(2)),
                ACPPrecondition(op: "equals", field: "current_cue_id", value: .string("cue-b")),
            ]
        )
        let first = try await service.admit(go)
        let second = try await service.admit(go)
        XCTAssertEqual(first.disposition, "applied")
        XCTAssertEqual(second.disposition, "applied")
        XCTAssertEqual(box.snapshot(), ["go"])
        for unavailable in ["performance.back", "performance.stop"] {
            XCTAssertThrowsError(try PrismACPActionRouter(advertiseControl: true).submit(PrismACPAction(name: unavailable)))
        }
        for blackout in ["blackoutOn", "blackoutOff"] {
            XCTAssertNoThrow(try PrismACPActionRouter(advertiseControl: true).submit(PrismACPAction(
                name: blackout,
                preconditions: [ACPPrecondition(op: "equals", field: "authority_epoch", value: .uint(2))]
            )))
        }
        XCTAssertNoThrow(try PrismACPActionRouter(advertiseControl: true).submit(PrismACPAction(
            name: "output.master",
            value: 0.5,
            preconditions: [ACPPrecondition(op: "equals", field: "authority_epoch", value: .uint(2))]
        )))
        XCTAssertThrowsError(try PrismACPActionRouter(advertiseControl: true).submit(PrismACPAction(
            name: "output.master",
            value: 1.5,
            preconditions: [ACPPrecondition(op: "equals", field: "authority_epoch", value: .uint(2))]
        )))
        XCTAssertThrowsError(try PrismACPActionRouter(advertiseControl: true).submit(PrismACPAction(
            name: "performance.fire_cue",
            parameter: "not-a-uuid",
            preconditions: [
                ACPPrecondition(op: "equals", field: "authority_epoch", value: .uint(2)),
                ACPPrecondition(op: "equals", field: "current_cue_id", value: .string("cue-b")),
            ]
        )))
        await service.stop()
    }

    func testBlackoutCommandsAreExplicitOnceOnlyAndClearIsSeparatelyAuthorized() async throws {
        let node = "0193f8d8-4c4e-7d8b-a2ab-000000000071"
        let state = authoritativeState(currentCueID: "cue-current")
        let deniedClear = PrismACPService(configuration: PrismACPConfiguration(
            enabled: false,
            advertiseControl: true,
            operatorNodeIDs: [node],
            blackoutClearNodeIDs: [],
            applicationSupportDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        ))
        await deniedClear.noteAuthoritativeState(state)
        let deniedBox = DispatchBox()
        await installAppliedExecutor(service: deniedClear, box: deniedBox, currentCueID: "cue-current")
        let on = PrismACPAction(
            name: "blackoutOn",
            commandID: "0193f8d8-4c4e-7d8b-a2ab-000000000072",
            originNodeID: node,
            originInstanceID: "0193f8d8-4c4e-7d8b-a2ab-000000000073",
            originPrincipal: node,
            idempotencyKey: "0193f8d8-4c4e-7d8b-a2ab-000000000072",
            preconditions: [ACPPrecondition(op: "equals", field: "authority_epoch", value: .uint(2))]
        )
        let firstOn = try await deniedClear.admit(on)
        let duplicateOn = try await deniedClear.admit(on)
        XCTAssertEqual(firstOn.disposition, "applied")
        XCTAssertEqual(duplicateOn.disposition, "applied")
        XCTAssertEqual(deniedBox.snapshot(), ["blackout"])

        let off = PrismACPAction(
            name: "blackoutOff",
            commandID: "0193f8d8-4c4e-7d8b-a2ab-000000000074",
            originNodeID: node,
            originInstanceID: "0193f8d8-4c4e-7d8b-a2ab-000000000073",
            originPrincipal: node,
            idempotencyKey: "0193f8d8-4c4e-7d8b-a2ab-000000000074",
            preconditions: [ACPPrecondition(op: "equals", field: "authority_epoch", value: .uint(2))]
        )
        do {
            _ = try await deniedClear.admit(off)
            XCTFail("blackout clear must require its separate authorization")
        } catch PrismACPActionRouterError.rejected(let reason) {
            XCTAssertEqual(reason, "blackout_clear_not_authorized")
        }
        XCTAssertEqual(deniedBox.snapshot(), ["blackout"])
        let deniedEvents = await deniedClear.audit.snapshot()
        XCTAssertEqual(deniedEvents.last?.operation, "blackoutOff")
        XCTAssertEqual(deniedEvents.last?.safetyOutcome, "safety_state_unchanged")

        let authorized = PrismACPService(configuration: PrismACPConfiguration(
            enabled: false,
            advertiseControl: true,
            operatorNodeIDs: [node],
            blackoutClearNodeIDs: [node],
            applicationSupportDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        ))
        await authorized.noteAuthoritativeState(state)
        let authorizedBox = DispatchBox()
        await installAppliedExecutor(service: authorized, box: authorizedBox, currentCueID: "cue-current")
        let firstOff = try await authorized.admit(off)
        let duplicateOff = try await authorized.admit(off)
        XCTAssertEqual(firstOff.disposition, "applied")
        XCTAssertEqual(duplicateOff.disposition, "applied")
        XCTAssertEqual(authorizedBox.snapshot(), ["blackoutOff"])
        let events = await authorized.audit.snapshot()
        XCTAssertEqual(events.last?.operation, "blackoutOff")
        XCTAssertEqual(events.last?.safetyOutcome, "blackout_cleared")

        var conflictingOn = on
        conflictingOn.commandID = off.commandID
        conflictingOn.idempotencyKey = off.idempotencyKey
        let conflict = try await authorized.admit(conflictingOn)
        XCTAssertEqual(conflict.disposition, "conflict")
        XCTAssertEqual(authorizedBox.snapshot(), ["blackoutOff"])
    }

    func testACPReconnectAndServiceRestartDoNotClearAuthoritativeBlackout() async throws {
        let node = UUID().uuidString.lowercased()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = PrismACPService(configuration: PrismACPConfiguration(
            enabled: true,
            advertiseControl: true,
            operatorNodeIDs: [node],
            blackoutClearNodeIDs: [node],
            webSocketPort: uniquePort(),
            applicationSupportDirectory: dir
        ))
        var state = authoritativeState(currentCueID: "cue-current")
        state.blackout = true
        await service.noteAuthoritativeState(state)
        try await service.start()
        let first = try await connectedClient(
            service: service,
            role: "remote",
            profiles: ["core", "remote", "aurora.remote.prism.v1"],
            nodeID: node
        )
        await first.goodbye()
        try await Task.sleep(nanoseconds: 30_000_000)
        let afterDisconnect = await service.lastState?.blackout
        XCTAssertEqual(afterDisconnect, true)

        await service.stop()
        let afterStop = await service.lastState?.blackout
        XCTAssertEqual(afterStop, true)
        try await service.start()
        let afterRestart = await service.lastState?.blackout
        XCTAssertEqual(afterRestart, true)
        await service.stop()
    }

    func testExplicitCueFireIsValidatedAndOnceOnly() async throws {
        let target = "0193f8d8-4c4e-7d8b-a2ab-000000000099"
        let node = "0193f8d8-4c4e-7d8b-a2ab-000000000001"
        let command = "0193f8d8-4c4e-7d8b-a2ab-000000000012"
        let service = PrismACPService(configuration: PrismACPConfiguration(
            enabled: false,
            advertiseControl: true,
            operatorNodeIDs: [node],
            applicationSupportDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        ))
        await service.noteAuthoritativeState(authoritativeState(currentCueID: "cue-current"))
        let box = DispatchBox()
        await service.installHostExecutor { request in
            do {
                try request.evaluatePreconditions(
                    authorityEpoch: 2,
                    revision: 7,
                    showID: "show",
                    currentCueID: "cue-current"
                )
            } catch {
                return PrismACPControlResult(disposition: "precondition_failed", reason: "precondition_failed")
            }
            box.record("\(request.action.name):\(request.action.parameter ?? "")")
            return PrismACPControlResult(disposition: "applied", resultingEpoch: 2, resultingRevision: 8)
        }
        let action = PrismACPAction(
            name: "performance.fire_cue",
            commandID: command,
            originNodeID: node,
            originInstanceID: node,
            originPrincipal: node,
            idempotencyKey: command,
            parameter: target,
            preconditions: [
                ACPPrecondition(op: "equals", field: "authority_epoch", value: .uint(2)),
                ACPPrecondition(op: "equals", field: "current_cue_id", value: .string("cue-current")),
            ]
        )
        let first = try await service.admit(action)
        let duplicate = try await service.admit(action)
        XCTAssertEqual(first.disposition, "applied")
        XCTAssertEqual(duplicate.disposition, "applied")
        XCTAssertEqual(box.snapshot(), ["performance.fire_cue:\(target)"])
        var expired = action
        expired.commandID = "0193f8d8-4c4e-7d8b-a2ab-000000000013"
        expired.idempotencyKey = expired.commandID
        expired.freshnessRejection = "command_expired"
        let expiredFirst = try await service.admit(expired)
        let expiredReplay = try await service.admit(expired)
        XCTAssertEqual(expiredFirst.disposition, "expired")
        XCTAssertEqual(expiredReplay.disposition, "expired")
        XCTAssertEqual(box.snapshot(), ["performance.fire_cue:\(target)"])
    }

    func testMasterIntensityCoalescesToLatestValueAndRetainsDisposition() async throws {
        let node = UUID().uuidString.lowercased()
        let service = PrismACPService(configuration: PrismACPConfiguration(
            enabled: false,
            advertiseControl: true,
            operatorNodeIDs: [node],
            applicationSupportDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        ))
        await service.noteAuthoritativeState(authoritativeState(currentCueID: "cue-current"))
        let values = DispatchBox()
        await service.installHostExecutor { request in
            values.record(String(request.action.value ?? -1))
            return PrismACPControlResult(disposition: "applied", resultingEpoch: 2, resultingRevision: 8)
        }
        @Sendable func action(_ value: Double, command: String) -> PrismACPAction {
            PrismACPAction(
                name: "output.master",
                commandID: command,
                originNodeID: node,
                originInstanceID: "instance",
                originPrincipal: node,
                idempotencyKey: command,
                value: value,
                preconditions: [ACPPrecondition(op: "equals", field: "authority_epoch", value: .uint(2))]
            )
        }
        let firstID = UUID().uuidString.lowercased()
        let secondID = UUID().uuidString.lowercased()
        async let first = service.admit(action(0.25, command: firstID))
        try await Task.sleep(nanoseconds: 1_000_000)
        async let second = service.admit(action(0.75, command: secondID))
        let results = try await [first, second]
        XCTAssertEqual(Set(results.map(\.disposition)), Set(["completed", "applied"]))
        XCTAssertEqual(values.snapshot(), ["0.75"])
        let replay = try await service.admit(action(0.25, command: firstID))
        XCTAssertEqual(replay.disposition, "completed")
        XCTAssertEqual(values.snapshot(), ["0.75"])
    }

    func testApplyConfigurationRebuildsAuthorizationPolicy() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let service = PrismACPService(
            configuration: PrismACPConfiguration(
                enabled: true,
                advertiseControl: false,
                webSocketPort: 28111,
                applicationSupportDirectory: dir
            )
        )
        try await service.start()
        await installAppliedExecutor(service: service, currentCueID: "cue-a")
        await service.noteAuthoritativeState(PrismACPAuthoritativeState(
            authorityEpoch: 1,
            revision: 1,
            showID: "show",
            showName: "Haywire",
            engineRunning: false,
            currentCueID: "cue-a",
            nextCueID: "",
            outputStatus: "Null",
            masterIntensity: 1,
            blackout: false
        ))
        do {
            _ = try await service.admit(PrismACPAction(name: "performance.go"))
            XCTFail("read-only should reject")
        } catch PrismACPActionRouterError.mutationsNotAdvertised {}
        try await service.applyConfiguration(PrismACPConfiguration(
            enabled: true,
            advertiseControl: true,
            operatorNodeIDs: ["operator-node"],
            webSocketPort: 28111,
            applicationSupportDirectory: dir
        ))
        await installAppliedExecutor(service: service, currentCueID: "cue-a")
        await service.noteAuthoritativeState(PrismACPAuthoritativeState(
            authorityEpoch: 1,
            revision: 1,
            showID: "show",
            showName: "Haywire",
            engineRunning: false,
            currentCueID: "cue-a",
            nextCueID: "",
            outputStatus: "Null",
            masterIntensity: 1,
            blackout: false
        ))
        let result = try await service.admit(PrismACPAction(
            name: "performance.go",
            originNodeID: "operator-node",
            originInstanceID: "operator-instance",
            originPrincipal: "operator-node",
            preconditions: [
                ACPPrecondition(op: "equals", field: "authority_epoch", value: .uint(2)),
                ACPPrecondition(op: "equals", field: "current_cue_id", value: .string("cue-a")),
            ]
        ))
        XCTAssertEqual(result.disposition, "applied")
        await service.stop()
    }

    func testLoopbackAdvertisementURLIsLocalOnly() {
        XCTAssertEqual(ACPDiscoveryTXT.advertisementURL(port: 27421, loopbackOnly: true), "ws://127.0.0.1:27421/acp")
        let lan = ACPDiscoveryTXT.advertisementURL(port: 27421, loopbackOnly: false)
        XCTAssertFalse(lan.contains("127.0.0.1"))
    }

    func testWebSocketClientReceivesAuthoritativeSnapshot() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let port = UInt16.random(in: 28200...28399)
        let service = PrismACPService(
            configuration: PrismACPConfiguration(
                enabled: true,
                webSocketPort: port,
                loopbackOnly: true,
                applicationSupportDirectory: dir
            )
        )
        try await service.start()
        await service.noteAuthoritativeState(PrismACPAuthoritativeState(
            authorityEpoch: 9,
            revision: 3,
            showID: "show",
            showName: "Haywire",
            engineRunning: true,
            currentCueID: "cue-live",
            nextCueID: "cue-next",
            outputStatus: "Null",
            masterIntensity: 1,
            blackout: false
        ))
        // Restart must not wipe the last authoritative snapshot.
        await service.stop()
        try await service.start()
        let bound = await service.boundPort ?? port
        let clientTransport = try await ACPWebSocketConnection.connect(host: "127.0.0.1", port: bound, timeout: 8)
        let client = ACPSession(
            transport: clientTransport,
            local: ACPIdentity(role: "remote", name: "test-client"),
            isServer: false,
            allowPlaintext: true
        )
        await client.setHandshakeTimeout(8)
        _ = try await client.handshake()
        let snap = try await client.request(
            ACPEnvelope(
                acp: "1.2",
                messageID: UUID().uuidString.lowercased(),
                type: "state.request",
                source: ACPEndpoint(nodeID: client.local.nodeID),
                timestampUTC: "2026-08-17T16:42:15.231Z",
                qos: .reliable,
                payload: ["resources": .array([])]
            ),
            timeout: 3
        )
        XCTAssertEqual(snap.type, "state.snapshot")
        switch snap.payload["authority_epoch"] {
        case .int(9), .uint(9): break
        default: XCTFail("expected epoch 9, got \(String(describing: snap.payload["authority_epoch"]))")
        }
        await client.goodbye()
        await service.stop()
    }

    func testWebSocketCommandPreservesPreconditions() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let service = PrismACPService(configuration: PrismACPConfiguration(
            enabled: true,
            advertiseControl: true,
            webSocketPort: uniquePort(),
            loopbackOnly: true,
            applicationSupportDirectory: dir
        ))
        let box = DispatchBox()
        await installAppliedExecutor(service: service, box: box, currentCueID: "cue-current")
        try await service.start()
        await service.noteAuthoritativeState(authoritativeState(currentCueID: "cue-current"))

        let client = try await connectedClient(service: service, role: "tool", profiles: ["core"])
        let stale = try await client.request(commandEnvelope(
            source: client.local.nodeID,
            preconditions: [[
                "op": .string("equals"),
                "field": .string("current_cue_id"),
                "value": .string("cue-stale"),
            ]]
        ), timeout: 3)
        XCTAssertEqual(stale.payload["status"], .string("rejected"))
        XCTAssertEqual(box.snapshot(), [])

        let current = try await client.request(commandEnvelope(
            source: client.local.nodeID,
            preconditions: [[
                "op": .string("equals"),
                "field": .string("current_cue_id"),
                "value": .string("cue-current"),
            ]]
        ), timeout: 3)
        XCTAssertEqual(current.payload["status"], .string("rejected"))
        XCTAssertEqual(box.snapshot(), [])
        await client.goodbye()
        await service.stop()
    }

    func testRemoteControlInvokeReceivesAckAndDispatches() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let service = PrismACPService(configuration: PrismACPConfiguration(
            enabled: true,
            advertiseControl: true,
            webSocketPort: uniquePort(),
            loopbackOnly: true,
            applicationSupportDirectory: dir
        ))
        let box = DispatchBox()
        await installAppliedExecutor(service: service, box: box, currentCueID: "cue-current")
        try await service.start()
        await service.noteAuthoritativeState(authoritativeState(currentCueID: "cue-current"))

        let client = try await connectedClient(
            service: service,
            role: "remote",
            profiles: ["core", "remote", "aurora.remote.prism.v1"]
        )
        await service.setOperatorNodeIDs([client.local.nodeID])
        do {
            try await synchronizeRemote(client: client, service: service, showID: "show", revision: 7)
        } catch {
            let serverError = await service.lastSessionError ?? "none"
            XCTFail("sync error \(error); server error \(serverError)")
            throw error
        }
        let invocationID = UUID().uuidString.lowercased()
        let issuedAt = timestamp(offset: 0)
        let ack: ACPEnvelope
        do {
            ack = try await client.request(ACPEnvelope(
            acp: "1.2",
            messageID: UUID().uuidString.lowercased(),
            type: "remote.control.invoke",
            source: ACPEndpoint(nodeID: client.local.nodeID),
            timestampUTC: "2026-08-17T16:42:15.231Z",
            qos: .reliable,
            payload: [
                "control_id": .string("cue_go"),
                "invocation_id": .string(invocationID),
                "interaction": .string("activate"),
                "idempotency_key": .string(invocationID),
                "delivery": .string("live_ephemeral"),
                "issued_at": .string(issuedAt),
                "expires_at": .string(timestamp(offset: 5)),
                "max_age_ms": .uint(5_000),
                "preconditions": .array([
                    .object(["op": .string("equals"), "field": .string("authority_epoch"), "value": .uint(2)]),
                    .object(["op": .string("equals"), "field": .string("current_cue_id"), "value": .string("cue-current")]),
                ]),
            ]
            ), timeout: 3)
        } catch {
            let serverError = await service.lastSessionError ?? "none"
            XCTFail("client error \(error); server error \(serverError)")
            throw error
        }
        XCTAssertEqual(ack.type, "command.ack")
        XCTAssertEqual(ack.payload["status"], .string("applied"))
        guard case .object(let result) = ack.payload["result"] else {
            return XCTFail("missing command result")
        }
        switch result["authority_epoch"] {
        case .int(2), .uint(2): break
        default: XCTFail("missing resulting epoch")
        }
        switch result["snapshot_revision"] {
        case .int(8), .uint(8): break
        default: XCTFail("missing resulting revision")
        }
        XCTAssertEqual(box.snapshot(), ["go"])
        let status = try await client.request(remoteEnvelope(
            type: "command.status_request",
            source: client.local.nodeID,
            payload: ["command_id": .string(invocationID)]
        ), timeout: 3)
        XCTAssertEqual(status.type, "command.status_report")
        XCTAssertEqual(status.payload["disposition"], .string("applied"))
        XCTAssertEqual(status.payload["resulting_revision"], .int(8))
        let masterID = UUID().uuidString.lowercased()
        let masterAck = try await client.request(ACPEnvelope(
            acp: "1.2",
            messageID: UUID().uuidString.lowercased(),
            type: "remote.control.invoke",
            source: ACPEndpoint(nodeID: client.local.nodeID),
            timestampUTC: "2026-08-17T16:42:15.231Z",
            qos: .reliable,
            payload: [
                "control_id": .string("grand_master"),
                "invocation_id": .string(masterID),
                "interaction": .string("set"),
                "idempotency_key": .string(masterID),
                "value": .double(0.42),
                "preconditions": .array([
                    .object(["op": .string("equals"), "field": .string("authority_epoch"), "value": .uint(2)]),
                ]),
            ]
        ), timeout: 3)
        XCTAssertEqual(masterAck.type, "command.ack")
        XCTAssertEqual(masterAck.payload["status"], .string("applied"))
        XCTAssertEqual(box.snapshot(), ["go", "masterIntensity"])
        await service.noteAuthoritativeState(PrismACPAuthoritativeState(
            authorityEpoch: 2,
            revision: 8,
            showID: "show",
            showName: "Haywire",
            engineRunning: true,
            currentCueID: "cue-next",
            nextCueID: "cue-after-next",
            outputStatus: "Null",
            masterIntensity: 1,
            blackout: false
        ))
        let delta = try await client.pumpOnce(deadline: Date().addingTimeInterval(3))
        XCTAssertEqual(delta?.type, "state.delta")
        switch delta?.payload["revision"] {
        case .int(8), .uint(8): break
        default: XCTFail("missing authoritative delta revision")
        }
        await client.goodbye()
        await service.stop()
    }

    func testConcurrentDuplicateGoCrossesExecutorOnce() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let node = UUID().uuidString.lowercased()
        let service = PrismACPService(configuration: PrismACPConfiguration(
            enabled: true,
            advertiseControl: true,
            operatorNodeIDs: [node],
            webSocketPort: uniquePort(),
            applicationSupportDirectory: dir
        ))
        try await service.start()
        await service.noteAuthoritativeState(authoritativeState(currentCueID: "cue-current"))
        let box = DispatchBox()
        await service.installHostExecutor { request in
            box.record(request.action.name)
            try? await Task.sleep(nanoseconds: 50_000_000)
            return PrismACPControlResult(disposition: "applied", resultingEpoch: 2, resultingRevision: 8)
        }
        let command = UUID().uuidString.lowercased()
        let action = PrismACPAction(
            name: "performance.go",
            commandID: command,
            originNodeID: node,
            originInstanceID: UUID().uuidString.lowercased(),
            originPrincipal: node,
            idempotencyKey: command,
            preconditions: [
                ACPPrecondition(op: "equals", field: "authority_epoch", value: .uint(2)),
                ACPPrecondition(op: "equals", field: "current_cue_id", value: .string("cue-current")),
            ]
        )
        async let first = service.admit(action)
        async let second = service.admit(action)
        let results = try await [first, second]
        XCTAssertEqual(Set(results.map(\.disposition)), Set(["in_flight", "applied"]))
        XCTAssertEqual(box.snapshot(), ["performance.go"])
        let replay = try await service.admit(action)
        XCTAssertEqual(replay.disposition, "applied")
        XCTAssertEqual(box.snapshot(), ["performance.go"])
        await service.stop()
    }

    func testReadOnlyHandshakeAdvertisesInvokeSupportWithoutMutationAuthority() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let service = PrismACPService(configuration: PrismACPConfiguration(
            enabled: true,
            advertiseControl: false,
            webSocketPort: uniquePort(),
            loopbackOnly: true,
            applicationSupportDirectory: dir
        ))
        try await service.start()
        let client = try await connectedClient(service: service, role: "remote", profiles: ["core", "remote"])
        let capabilities = await client.negotiatedCapabilities
        XCTAssertFalse(capabilities.contains("prism.cue_control"))
        XCTAssertFalse(capabilities.contains("bridge.blackout"))
        XCTAssertTrue(ACPCapabilitySet.prismRemoteRequiredIDs.isSubset(of: capabilities))
        await client.goodbye()
        await service.stop()
    }

    func testRemoteWorkbenchObservationFlowBecomesReadyWithViewerPermissions() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let service = PrismACPService(configuration: PrismACPConfiguration(
            enabled: true,
            advertiseControl: false,
            webSocketPort: uniquePort(),
            loopbackOnly: true,
            applicationSupportDirectory: dir
        ))
        try await service.start()
        let showID = UUID().uuidString.lowercased()
        await service.noteAuthoritativeState(PrismACPAuthoritativeState(
            authorityEpoch: 3,
            revision: 11,
            showID: showID,
            showName: "HaywireFullRig",
            engineRunning: true,
            currentCueID: "cue-live",
            nextCueID: "cue-next",
            outputStatus: "sACN",
            masterIntensity: 0.75,
            blackout: false
        ))

        let client = try await connectedClient(
            service: service,
            role: "remote",
            profiles: ["core", "remote", "aurora.remote.prism.v1"]
        )
        let remoteID = UUID().uuidString.lowercased()
        let hello = try await client.request(remoteEnvelope(
            type: "remote.hello",
            source: client.local.nodeID,
            payload: [
                "remote": .object([
                    "node_id": .string(client.local.nodeID),
                    "instance_id": .string(client.local.instanceID),
                    "device_id": .string(UUID().uuidString.lowercased()),
                    "remote_id": .string(remoteID),
                    "device_name": .string("ACP Workbench"),
                    "platform": .string("macos"),
                    "app_version": .string("0.1.0"),
                ]),
                "roles": .array([.string("remote.viewer"), .string("remote.admin")]),
                "capabilities": .array([]),
            ]
        ), timeout: 3)
        XCTAssertEqual(hello.type, "remote.hello_ack")
        XCTAssertEqual(hello.payload["accepted"], .bool(true))
        guard case .string(let endpointShowID) = hello.payload["show_id"] else {
            return XCTFail("missing show id")
        }
        XCTAssertEqual(hello.payload["show_id"], .string(showID))
        guard case .object(let permissions) = hello.payload["permissions"] else {
            return XCTFail("missing server-owned permissions")
        }
        XCTAssertEqual(permissions["roles"], .array([.string("remote.viewer")]))

        let surface = try await transferAndActivateSurface(client: client, showID: endpointShowID)
        let layout = surface.layout
        let layoutHash = surface.hash
        XCTAssertEqual(layout["name"], .string("HaywireFullRig Remote"))
        XCTAssertEqual(layout["show_id"], .string(showID))
        guard case .array(let controls) = layout["controls"] else { return XCTFail("missing controls") }
        XCTAssertFalse(controls.isEmpty)
        for control in controls {
            guard case .object(let definition) = control else { return XCTFail("invalid control") }
            XCTAssertEqual(definition["enabled"], .bool(false))
        }

        let snapshot = try await client.request(remoteEnvelope(
            type: "state.request",
            source: client.local.nodeID,
            payload: ["resources": .array([])]
        ), timeout: 3)
        XCTAssertEqual(snapshot.type, "state.snapshot")
        switch snapshot.payload["revision"] {
        case .int(11), .uint(11): break
        default: XCTFail("expected authoritative revision 11")
        }

        let ready = try await client.request(remoteEnvelope(
            type: "remote.readiness",
            source: client.local.nodeID,
            payload: [
                "state": .string("ready"),
                "layout_revision": .uint(PrismACPRemoteProfile.surfaceRevision),
                "layout_hash": .string(layoutHash),
                "snapshot_revision": .uint(11),
            ]
        ), timeout: 3)
        XCTAssertEqual(ready.type, "remote.readiness.changed")
        XCTAssertEqual(ready.payload["state"], .string("ready"))

        let stale = try await client.request(remoteEnvelope(
            type: "remote.readiness",
            source: client.local.nodeID,
            payload: [
                "state": .string("ready"),
                "layout_revision": .uint(PrismACPRemoteProfile.surfaceRevision + 1),
                "layout_hash": .string(layoutHash),
                "snapshot_revision": .uint(11),
            ]
        ), timeout: 3)
        XCTAssertEqual(stale.payload["state"], .string("syncing_state"))
        await client.goodbye()
        await service.stop()
    }

    func testProductionRemoteStateStoreConsumesPrismSnapshot() async throws {
        let service = PrismACPService(configuration: PrismACPConfiguration(
            enabled: true,
            advertiseControl: false,
            webSocketPort: uniquePort(),
            loopbackOnly: true,
            applicationSupportDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        ))
        try await service.start()
        await service.noteAuthoritativeState(authoritativeState(currentCueID: "cue-current"))
        let session = try await connectedClient(
            service: service,
            role: "remote",
            profiles: ["core", "remote", "aurora.remote.prism.v1"]
        )
        let localIdentity = await session.local
        let identity = ACPRemoteIdentity(
            nodeID: localIdentity.nodeID,
            instanceID: localIdentity.instanceID,
            deviceID: UUID().uuidString.lowercased(),
            remoteID: UUID().uuidString.lowercased(),
            deviceName: "Production Contract Test",
            platform: "macos",
            appVersion: "1.0.0"
        )
        let remote = ACPRemoteClient(session: session, identity: identity)
        try await remote.verifyNegotiated()
        let hello = try await session.request(remoteEnvelope(
            type: "remote.hello",
            source: session.local.nodeID,
            payload: [
                "remote": .object([
                    "node_id": .string(identity.nodeID),
                    "instance_id": .string(identity.instanceID),
                    "device_id": .string(identity.deviceID),
                    "remote_id": .string(identity.remoteID),
                    "device_name": .string(identity.deviceName),
                    "platform": .string(identity.platform),
                    "app_version": .string(identity.appVersion),
                ]),
                "roles": .array([.string("remote.viewer")]),
                "capabilities": .array(ACPCapabilitySet.prismRemoteClient.map {
                    .object(["id": .string($0.id), "version": .string($0.version)])
                }),
            ]
        ), timeout: 3)
        guard case .string(let showID) = hello.payload["show_id"] else { return XCTFail("show id") }
        _ = try await transferAndActivateSurface(client: session, showID: showID)
        let snapshot = try await session.request(remoteEnvelope(
            type: "state.request",
            source: session.local.nodeID,
            payload: ["resources": .array(ACPRemoteStateStore.namespaces.map(AnySendable.string))]
        ), timeout: 3)
        try await remote.resyncFromSnapshot(snapshot)
        let state = await remote.state
        XCTAssertEqual(state.currentSection, "cue-current")
        XCTAssertEqual(state.nextSection, "cue-next")
        XCTAssertEqual(state.grandMaster, 1)
        XCTAssertEqual(state.blackout, false)
        XCTAssertNotNil(state.resource("system.health"))
        await session.goodbye()
        await service.stop()
    }

    func testProductionSurfaceTransferRequiresVerificationAndActivation() async throws {
        let service = PrismACPService(configuration: PrismACPConfiguration(
            enabled: true,
            advertiseControl: false,
            webSocketPort: uniquePort(),
            loopbackOnly: true,
            applicationSupportDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        ))
        try await service.start()
        await service.noteAuthoritativeState(authoritativeState(currentCueID: "cue-current"))
        let client = try await connectedClient(
            service: service,
            role: "remote",
            profiles: ["core", "remote", "aurora.remote.prism.v1"]
        )
        _ = try await client.request(remoteEnvelope(
            type: "remote.hello",
            source: client.local.nodeID,
            payload: [
                "remote": .object([
                    "node_id": .string(client.local.nodeID),
                    "instance_id": .string(client.local.instanceID),
                    "device_id": .string(UUID().uuidString.lowercased()),
                    "remote_id": .string(UUID().uuidString.lowercased()),
                    "device_name": .string("Transfer Client"),
                    "platform": .string("macos"),
                    "app_version": .string("0.1.0"),
                ]),
                "roles": .array([.string("remote.viewer")]),
                "capabilities": .array([.object([
                    "id": .string("resource.transfer"), "version": .string("1.2"),
                ])]),
            ]
        ), timeout: 3)
        let report = try await client.request(remoteEnvelope(
            type: "remote.layout.request",
            source: client.local.nodeID,
            payload: [:]
        ), timeout: 3)
        XCTAssertNil(report.payload["layout"])
        guard case .string(let digest) = report.payload["sha256"] else { return XCTFail("missing digest") }
        let offered = try await client.pumpOnce(deadline: Date().addingTimeInterval(3))
        let offer = try XCTUnwrap(offered)
        XCTAssertEqual(offer.type, "resource.offer")
        guard case .string(let transferID) = offer.payload["transfer_id"] else { return XCTFail("missing transfer") }
        _ = try await client.send(ACPEnvelope(
            acp: "1.2",
            messageID: UUID().uuidString.lowercased(),
            type: "resource.accept",
            source: ACPEndpoint(nodeID: client.local.nodeID),
            timestampUTC: timestamp(offset: 0),
            correlationID: offer.messageID,
            causationID: offer.messageID,
            qos: .reliable,
            payload: ["transfer_id": .string(transferID), "max_chunk_bytes": .uint(1024)]
        ))
        var received = Data()
        var complete: ACPEnvelope?
        while complete == nil {
            let inbound = try await client.pumpOnce(deadline: Date().addingTimeInterval(3))
            let event = try XCTUnwrap(inbound)
            if event.type == "remote.control.snapshot" { continue }
            if event.type == "resource.chunk", case .string(let encoded) = event.payload["data"] {
                received.append(try XCTUnwrap(Data(base64Encoded: encoded)))
            } else if event.type == "resource.chunk", case .bytes(let data) = event.payload["data"] {
                received.append(data)
            } else if event.type == "resource.complete" {
                complete = event
            }
        }
        XCTAssertFalse(received.isEmpty)
        XCTAssertEqual(SHA256.hash(data: received).map { String(format: "%02x", $0) }.joined(), digest)
        _ = try await client.send(ACPEnvelope(
            acp: "1.2",
            messageID: UUID().uuidString.lowercased(),
            type: "resource.transfer_result",
            source: ACPEndpoint(nodeID: client.local.nodeID),
            timestampUTC: timestamp(offset: 0),
            correlationID: complete?.messageID,
            causationID: complete?.messageID,
            qos: .reliable,
            payload: ["transfer_id": .string(transferID), "status": .string("verified")]
        ))
        let receivedActivation = try await client.pumpOnce(deadline: Date().addingTimeInterval(3))
        let activation = try XCTUnwrap(receivedActivation)
        XCTAssertEqual(activation.type, "resource.activate")
        XCTAssertEqual(activation.payload["transfer_id"], .string(transferID))
        _ = try await client.send(remoteEnvelope(
            type: "resource.activation_result",
            source: client.local.nodeID,
            payload: ["transfer_id": .string(transferID), "status": .string("applied")]
        ))
        await client.goodbye()
        await service.stop()
    }

    func testSyntheticMomentaryControlIsNotPublishedInProduction() {
        let state = authoritativeState(currentCueID: "cue-current")
        let layout = PrismACPRemoteProfile.executionLayout(for: state, mutationsEnabled: true)
        XCTAssertNil(layout.control("lease_test"))
        XCTAssertFalse(layout.controls.contains { $0.action == "system.test_hold" })
    }

    func testIdentityPersistsAcrossLaunches() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = PrismACPIdentityStore()
        let first = try store.loadOrCreate(in: dir)
        let second = try store.loadOrCreate(in: dir)
        XCTAssertEqual(first.nodeID, second.nodeID)
        XCTAssertNotEqual(first.instanceID, second.instanceID)
    }

    private func installAppliedExecutor(
        service: PrismACPService,
        box: DispatchBox? = nil,
        currentCueID: String
    ) async {
        await service.installHostExecutor { request in
            do {
                try request.evaluatePreconditions(
                    authorityEpoch: 2,
                    revision: 7,
                    showID: "show",
                    currentCueID: currentCueID
                )
            } catch {
                return PrismACPControlResult(
                    disposition: "precondition_failed",
                    reason: "precondition_failed",
                    resultingEpoch: 2,
                    resultingRevision: 7
                )
            }
            if let key = PrismACPActionRouter.showActionStorageKey(for: request.action) {
                box?.record(key)
            }
            return PrismACPControlResult(
                disposition: "applied",
                resultingEpoch: 2,
                resultingRevision: 8
            )
        }
    }

    private func synchronizeRemote(
        client: ACPSession,
        service: PrismACPService,
        showID: String,
        revision: UInt64
    ) async throws {
        let hello = try await client.request(remoteEnvelope(
            type: "remote.hello",
            source: client.local.nodeID,
            payload: [
                "remote": .object([
                    "node_id": .string(client.local.nodeID),
                    "instance_id": .string(client.local.instanceID),
                    "device_id": .string(UUID().uuidString.lowercased()),
                    "remote_id": .string(UUID().uuidString.lowercased()),
                    "device_name": .string("Test Operator"),
                    "platform": .string("macos"),
                    "app_version": .string("0.1.0"),
                ]),
                "roles": .array([.string("remote.operator")]),
                "capabilities": .array([]),
            ]
        ), timeout: 3)
        XCTAssertEqual(hello.payload["accepted"], .bool(true))
        guard case .string(let endpointShowID) = hello.payload["show_id"] else {
            return XCTFail("missing show id")
        }
        guard case .object(let permissions) = hello.payload["permissions"] else {
            return XCTFail("missing permissions")
        }
        XCTAssertEqual(
            permissions["roles"],
            .array([.string("remote.viewer"), .string("remote.operator")])
        )

        let surface = try await transferAndActivateSurface(client: client, showID: endpointShowID)
        let layoutHash = surface.hash

        _ = try await client.request(remoteEnvelope(
            type: "state.request",
            source: client.local.nodeID,
            payload: ["resources": .array([])]
        ), timeout: 3)
        let ready = try await client.request(remoteEnvelope(
            type: "remote.readiness",
            source: client.local.nodeID,
            payload: [
                "state": .string("ready"),
                "layout_revision": .uint(PrismACPRemoteProfile.surfaceRevision),
                "layout_hash": .string(layoutHash),
                "snapshot_revision": .uint(revision),
            ]
        ), timeout: 3)
        XCTAssertEqual(ready.payload["state"], .string("ready"))
        _ = service
        _ = showID
    }

    private func transferAndActivateSurface(
        client: ACPSession,
        showID: String
    ) async throws -> (layout: [String: AnySendable], hash: String) {
        let report = try await client.request(remoteEnvelope(
            type: "remote.layout.request",
            source: client.local.nodeID,
            payload: ["show_id": .string(showID)]
        ), timeout: 3)
        guard case .string(let digest) = report.payload["sha256"] else {
            throw ACPSessionError("invalid_type", "missing surface digest")
        }
        var transferID: String?
        var received = Data()
        while transferID == nil {
            guard let event = try await client.pumpOnce(deadline: Date().addingTimeInterval(3)) else { continue }
            if event.type == "resource.offer", case .string(let id) = event.payload["transfer_id"] {
                transferID = id
                _ = try await client.send(remoteEnvelope(
                    type: "resource.accept",
                    source: client.local.nodeID,
                    payload: ["transfer_id": .string(id), "max_chunk_bytes": .uint(32_768)]
                ))
            }
        }
        let id = try XCTUnwrap(transferID)
        var complete = false
        while !complete {
            guard let event = try await client.pumpOnce(deadline: Date().addingTimeInterval(3)) else { continue }
            if event.type == "resource.chunk" {
                if case .bytes(let data) = event.payload["data"] { received.append(data) }
                else if case .string(let encoded) = event.payload["data"], let data = Data(base64Encoded: encoded) { received.append(data) }
            } else if event.type == "resource.complete" {
                complete = true
            }
        }
        XCTAssertEqual(SHA256.hash(data: received).map { String(format: "%02x", $0) }.joined(), digest)
        guard let raw = try JSONSerialization.jsonObject(with: received) as? [String: Any] else {
            throw ACPSessionError("invalid_type", "surface JSON")
        }
        let layout = raw.mapValues(anySendable)
        if case .rejected(let reason) = ACPRemoteSurfaceValidator.evaluate(layout) {
            throw ACPSessionError("remote.layout.incompatible", reason)
        }
        _ = try await client.send(remoteEnvelope(
            type: "resource.transfer_result",
            source: client.local.nodeID,
            payload: ["transfer_id": .string(id), "status": .string("verified")]
        ))
        var activation: ACPEnvelope?
        while activation == nil {
            let event = try await client.pumpOnce(deadline: Date().addingTimeInterval(3))
            if event?.type == "resource.activate" { activation = event }
        }
        _ = try await client.send(remoteEnvelope(
            type: "resource.activation_result",
            source: client.local.nodeID,
            payload: ["transfer_id": .string(id), "status": .string("applied")]
        ))
        return (layout, digest)
    }

    private func authoritativeState(currentCueID: String) -> PrismACPAuthoritativeState {
        PrismACPAuthoritativeState(
            authorityEpoch: 2,
            revision: 7,
            showID: "show",
            showName: "Haywire",
            engineRunning: true,
            currentCueID: currentCueID,
            nextCueID: "cue-next",
            outputStatus: "Null",
            masterIntensity: 1,
            blackout: false
        )
    }

    private func connectedClient(
        service: PrismACPService,
        role: String,
        profiles: [String],
        nodeID: String? = nil
    ) async throws -> ACPSession {
        let port = await service.boundPort!
        let transport = try await ACPWebSocketConnection.connect(host: "127.0.0.1", port: port, timeout: 8)
        let identity = nodeID.map { ACPIdentity(nodeID: $0, role: role, name: "test-client") }
            ?? ACPIdentity(role: role, name: "test-client")
        let client = ACPSession(
            transport: transport,
            local: identity,
            isServer: false,
            allowPlaintext: true
        )
        await client.setProfiles(profiles)
        if profiles.contains("remote") {
            await client.setCapabilities(ACPCapabilitySet.prismRemoteClient)
        }
        await client.setHandshakeTimeout(8)
        _ = try await client.handshake()
        return client
    }

    private func anySendable(_ value: Any) -> AnySendable {
        switch value {
        case is NSNull: return .null
        case let value as String: return .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() { return .bool(value.boolValue) }
            let number = value.doubleValue
            if number.rounded() == number, number >= 0 { return .uint(UInt64(number)) }
            if number.rounded() == number { return .int(Int64(number)) }
            return .double(number)
        case let value as [Any]: return .array(value.map(anySendable))
        case let value as [String: Any]: return .object(value.mapValues(anySendable))
        default: return .null
        }
    }

    private func commandEnvelope(
        source: String,
        preconditions: [[String: AnySendable]]
    ) -> ACPEnvelope {
        ACPEnvelope(
            acp: "1.2",
            messageID: UUID().uuidString.lowercased(),
            type: "command.execute",
            source: ACPEndpoint(nodeID: source),
            timestampUTC: "2026-08-17T16:42:15.231Z",
            qos: .reliable,
            payload: [
                "name": .string("performance.go"),
                "idempotency_key": .string(UUID().uuidString.lowercased()),
                "preconditions": .array(preconditions.map(AnySendable.object)),
            ]
        )
    }

    private func remoteEnvelope(type: String, source: String, payload: [String: AnySendable]) -> ACPEnvelope {
        ACPEnvelope(
            acp: "1.2",
            messageID: UUID().uuidString.lowercased(),
            type: type,
            source: ACPEndpoint(nodeID: source),
            timestampUTC: "2026-08-17T16:42:15.231Z",
            qos: .reliable,
            payload: payload
        )
    }

    private func timestamp(offset: TimeInterval) -> String {
        timestamp(date: Date().addingTimeInterval(offset))
    }

    private func timestamp(date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

private final class DispatchBox: @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [String] = []
    func record(_ key: String) {
        lock.lock()
        keys.append(key)
        lock.unlock()
    }
    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return keys
    }
}
