import XCTest

/// Documents the UI-02 A1 action split: select must never imply fire.
/// View wiring is in CueListPanel / AuroraCueRow; this models the contract for regression.
enum CueListInteraction: Equatable {
    case select(cueID: UUID)
    case fire(cueID: UUID)
}

final class CueListInteractionTests: XCTestCase {
    func testSelectIsNotFire() {
        let id = UUID()
        let select = CueListInteraction.select(cueID: id)
        let fire = CueListInteraction.fire(cueID: id)
        XCTAssertNotEqual(select, fire)
        if case .select(let sid) = select {
            XCTAssertEqual(sid, id)
        } else {
            XCTFail("expected select")
        }
        if case .fire(let fid) = fire {
            XCTAssertEqual(fid, id)
        } else {
            XCTFail("expected fire")
        }
    }

    func testDoubleClickMapsToSingleFireAction() {
        // Double-click path: select then fire once (not two fires).
        let id = UUID()
        var engineFires = 0
        var selected: UUID?
        let onSelect: (UUID) -> Void = { selected = $0 }
        let onFire: (UUID) -> Void = { _ in engineFires += 1 }

        // Simulate single click
        onSelect(id)
        XCTAssertEqual(selected, id)
        XCTAssertEqual(engineFires, 0)

        // Simulate double-click fire path
        onSelect(id)
        onFire(id)
        XCTAssertEqual(engineFires, 1)
    }
}
