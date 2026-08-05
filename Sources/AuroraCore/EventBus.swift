import Foundation

/// Opaque token for unsubscribing from the event bus.
public struct EventSubscriptionToken: Hashable, Sendable {
    public let id: UUID

    public init(id: UUID = UUID()) {
        self.id = id
    }
}

/// Synchronous in-process event fan-out. Handlers must not block; engine never waits on the bus.
@MainActor
public final class EventBus {
    private var handlers: [UUID: (AppEvent) -> Void] = [:]

    public init() {}

    @discardableResult
    public func subscribe(_ handler: @escaping @MainActor (AppEvent) -> Void) -> EventSubscriptionToken {
        let token = EventSubscriptionToken()
        handlers[token.id] = handler
        return token
    }

    public func unsubscribe(_ token: EventSubscriptionToken) {
        handlers.removeValue(forKey: token.id)
    }

    public func publish(_ event: AppEvent) {
        // Snapshot keys so handlers may unsubscribe during delivery.
        let current = handlers
        for (_, handler) in current {
            handler(event)
        }
    }

    public var subscriberCount: Int { handlers.count }
}
