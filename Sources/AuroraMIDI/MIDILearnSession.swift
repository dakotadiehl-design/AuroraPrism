import AuroraModel
import Foundation

/// Arms a single action to capture the next MIDI message.
public final class MIDILearnSession: @unchecked Sendable {
    private let lock = NSLock()
    private var armed: ShowAction?

    public init() {}

    public var isLearning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return armed != nil
    }

    public var armedAction: ShowAction? {
        lock.lock()
        defer { lock.unlock() }
        return armed
    }

    public func arm(_ action: ShowAction) {
        lock.lock()
        armed = action
        lock.unlock()
    }

    public func cancel() {
        lock.lock()
        armed = nil
        lock.unlock()
    }

    /// If learning, consumes the event and returns a mapping; otherwise nil.
    public func completeIfArmed(event: MIDIEvent) -> (mapping: MIDIMapping, action: ShowAction)? {
        lock.lock()
        guard let action = armed else {
            lock.unlock()
            return nil
        }
        // Prefer noteOn / cc for learn.
        switch event {
        case .noteOff:
            lock.unlock()
            return nil
        default:
            break
        }
        armed = nil
        lock.unlock()
        let mapping = MIDIActionResolver.mapping(from: event, action: action)
        return (mapping, action)
    }
}
