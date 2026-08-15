import Foundation

/// Network listener lifecycle for truthful Remote runtime status (REM-01).
public enum RemoteListenerState: Equatable, Sendable {
    case stopped
    case starting
    case ready(boundEndpoint: String)
    case failed(String)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    public var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}
