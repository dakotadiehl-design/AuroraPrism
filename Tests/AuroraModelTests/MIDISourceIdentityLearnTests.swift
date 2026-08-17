import AuroraModel
import XCTest

final class MIDISourceIdentityLearnTests: XCTestCase {
    func testLearnUIDPersistsUIDAndFriendlyName() {
        let meta = MIDISourceIdentity.InventorySource(
            id: "uid:12345",
            name: "Nord Drum 3P",
            manufacturer: "Clavia"
        )
        switch MIDISourceIdentity.makeDurableBinding(
            runtimeSourceID: "uid:12345",
            inventory: meta
        ) {
        case .binding(let binding):
            XCTAssertEqual(binding.lastCoreMIDIUniqueID, 12345)
            XCTAssertEqual(binding.displayName, "Nord Drum 3P")
            XCTAssertEqual(binding.endpointNameHint, "Nord Drum 3P")
            XCTAssertEqual(binding.manufacturerHint, "Clavia")
            XCTAssertFalse(binding.endpointNameHint?.hasPrefix("uid:") == true)
        case .unavailable(let reason):
            XCTFail("expected binding, got unavailable: \(reason)")
        }
    }

    func testLearnUIDWithoutInventoryStillDurableViaUID() {
        switch MIDISourceIdentity.makeDurableBinding(
            runtimeSourceID: "uid:99",
            inventory: nil
        ) {
        case .binding(let binding):
            XCTAssertEqual(binding.lastCoreMIDIUniqueID, 99)
            XCTAssertNil(binding.endpointNameHint)
        case .unavailable:
            XCTFail("UID alone must be durable")
        }
    }

    func testLearnNonUIDPersistsEndpointNameNotEpRef() {
        let meta = MIDISourceIdentity.InventorySource(
            id: "ep:4242",
            name: "Network Session 1",
            manufacturer: "Apple"
        )
        switch MIDISourceIdentity.makeDurableBinding(
            runtimeSourceID: "ep:4242",
            inventory: meta
        ) {
        case .binding(let binding):
            XCTAssertNil(binding.lastCoreMIDIUniqueID)
            XCTAssertEqual(binding.displayName, "Network Session 1")
            XCTAssertEqual(binding.endpointNameHint, "Network Session 1")
            XCTAssertNotEqual(binding.endpointNameHint, "ep:4242")
        case .unavailable(let reason):
            XCTFail("expected binding: \(reason)")
        }
    }

    func testNonUIDWithoutInventoryDoesNotCreateOrphanBinding() {
        switch MIDISourceIdentity.makeDurableBinding(
            runtimeSourceID: "ep:777",
            inventory: nil
        ) {
        case .binding:
            XCTFail("must not invent a generic binding without durable identity")
        case .unavailable(let reason):
            XCTAssertTrue(reason.contains("inventory") || reason.contains("ep:"))
        }
    }

    func testNonUIDEmptyInventoryNameIsUnavailable() {
        let meta = MIDISourceIdentity.InventorySource(id: "ep:1", name: "", manufacturer: "")
        switch MIDISourceIdentity.makeDurableBinding(runtimeSourceID: "ep:1", inventory: meta) {
        case .binding:
            XCTFail("empty name is not durable")
        case .unavailable:
            break
        }
    }

    func testReconnectResolvesNameHintToNewEndpointRef() {
        let binding = MIDISourceBinding(
            displayName: "Network Session 1",
            endpointNameHint: "Network Session 1"
        )
        let inv = [
            MIDISourceIdentity.InventorySource(id: "ep:900", name: "Network Session 1"),
        ]
        let r = MIDISourceIdentity.resolve(binding: binding, inventory: inv)
        XCTAssertEqual(r, .resolved(canonicalSourceID: "ep:900"))
    }

    func testAmbiguousSameNameFailsClosedForResolve() {
        let binding = MIDISourceBinding(
            displayName: "Pad",
            endpointNameHint: "Pad"
        )
        let inv = [
            MIDISourceIdentity.InventorySource(id: "ep:1", name: "Pad"),
            MIDISourceIdentity.InventorySource(id: "ep:2", name: "Pad"),
        ]
        if case .ambiguous(let ids) = MIDISourceIdentity.resolve(binding: binding, inventory: inv) {
            XCTAssertEqual(Set(ids), Set(["ep:1", "ep:2"]))
        } else {
            XCTFail("expected ambiguous")
        }
    }
}
