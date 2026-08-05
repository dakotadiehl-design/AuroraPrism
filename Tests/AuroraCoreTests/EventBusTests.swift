import AuroraCore
import AuroraModel
import Foundation
import XCTest

@MainActor
final class EventBusTests: XCTestCase {
    func testSubscribeReceivesProjectModified() throws {
        let session = DocumentSession(project: ShowProject.empty(name: "E"))
        var events: [AppEvent] = []
        let token = session.eventBus.subscribe { events.append($0) }

        try session.perform(RenameProjectCommand(newName: "E2"))
        XCTAssertEqual(events, [.projectModified])

        session.eventBus.unsubscribe(token)
        try session.perform(RenameProjectCommand(newName: "E3"))
        XCTAssertEqual(events, [.projectModified])
    }

    func testUnsubscribeStopsDelivery() throws {
        let bus = EventBus()
        var count = 0
        let token = bus.subscribe { _ in count += 1 }
        bus.publish(.projectModified)
        XCTAssertEqual(count, 1)
        bus.unsubscribe(token)
        bus.publish(.projectModified)
        XCTAssertEqual(count, 1)
    }

    func testMultipleSubscribers() {
        let bus = EventBus()
        var a = 0
        var b = 0
        _ = bus.subscribe { _ in a += 1 }
        _ = bus.subscribe { _ in b += 1 }
        bus.publish(.projectModified)
        XCTAssertEqual(a, 1)
        XCTAssertEqual(b, 1)
    }
}
