import Foundation

public enum PlaybackPhase: String, Sendable, Equatable, Codable {
    case idle
    case delay
    case fade
    case active
}

public struct PlaybackSnapshot: Sendable, Equatable {
    public var listID: UUID?
    public var cueIndex: Int
    public var cueID: UUID?
    public var phase: PlaybackPhase
    public var fadeProgress: Double
    public var cueName: String

    public init(
        listID: UUID? = nil,
        cueIndex: Int = -1,
        cueID: UUID? = nil,
        phase: PlaybackPhase = .idle,
        fadeProgress: Double = 0,
        cueName: String = ""
    ) {
        self.listID = listID
        self.cueIndex = cueIndex
        self.cueID = cueID
        self.phase = phase
        self.fadeProgress = fadeProgress
        self.cueName = cueName
    }

    public static let idle = PlaybackSnapshot()
}
