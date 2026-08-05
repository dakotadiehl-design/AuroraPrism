import AuroraModel
import Foundation

/// Single-list cue playback: delay, linear fade, follow, stop/back.
public final class PlaybackController: @unchecked Sendable {
    private let lock = NSLock()

    private var list: CueList?
    private var project: ShowProject = .empty()
    private var index: Int = -1
    private var phase: PlaybackPhase = .idle
    private var phaseStart: TimeInterval = 0
    private var fromLook: ActiveLook = .empty
    private var toLook: ActiveLook = .empty
    private var currentLook: ActiveLook = .empty
    private var fadeDuration: TimeInterval = 0
    private var delayDuration: TimeInterval = 0
    private var pendingFollowAt: TimeInterval?
    private var pendingFollowIsGo = false
    private var frozen = false

    public init() {}

    public func load(list: CueList?, project: ShowProject = .empty()) {
        lock.lock()
        self.list = list
        self.project = project
        index = -1
        phase = .idle
        phaseStart = 0
        fromLook = .empty
        toLook = .empty
        currentLook = .empty
        fadeDuration = 0
        delayDuration = 0
        pendingFollowAt = nil
        frozen = false
        lock.unlock()
    }

    public func snapshot() -> PlaybackSnapshot {
        lock.lock()
        defer { lock.unlock() }
        let cue = (index >= 0 && index < (list?.cues.count ?? 0)) ? list?.cues[index] : nil
        let progress: Double
        switch phase {
        case .fade where fadeDuration > 0:
            // approximate — real progress needs now; store last progress
            progress = lastFadeProgress
        case .fade:
            progress = 1
        default:
            progress = phase == .active ? 1 : 0
        }
        return PlaybackSnapshot(
            listID: list?.id,
            cueIndex: index,
            cueID: cue?.id,
            phase: phase,
            fadeProgress: progress,
            cueName: cue?.name ?? ""
        )
    }

    private var lastFadeProgress: Double = 0

    public func look(at now: TimeInterval) -> ActiveLook {
        lock.lock()
        defer { lock.unlock() }
        tickLocked(now: now)
        return currentLook
    }

    public func go(at now: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        guard let list, !list.cues.isEmpty else { return }
        frozen = false
        pendingFollowAt = nil

        let nextIndex = index + 1
        guard nextIndex < list.cues.count else {
            // Stay on last cue.
            return
        }
        beginTransition(to: nextIndex, at: now, list: list)
    }

    public func back(at now: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        guard let list, !list.cues.isEmpty else { return }
        frozen = false
        pendingFollowAt = nil
        let prev = max(0, index - 1)
        if index < 0 {
            beginTransition(to: 0, at: now, list: list)
        } else {
            beginTransition(to: prev, at: now, list: list)
        }
    }

    public func stop(at now: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        _ = now
        frozen = true
        pendingFollowAt = nil
        phase = .idle
        lastFadeProgress = 0
    }

    public func fire(cueID: UUID, at now: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        guard let list, let idx = list.cues.firstIndex(where: { $0.id == cueID }) else { return }
        frozen = false
        pendingFollowAt = nil
        beginTransition(to: idx, at: now, list: list)
    }

    private func beginTransition(to newIndex: Int, at now: TimeInterval, list: CueList) {
        let cue = list.cues[newIndex]
        fromLook = currentLook
        toLook = CueResolver.resolveLook(cues: list.cues, index: newIndex, project: project)
        index = newIndex
        delayDuration = max(0, cue.delay)
        fadeDuration = max(0, cue.fadeIn)

        if delayDuration > 0 {
            phase = .delay
            phaseStart = now
            lastFadeProgress = 0
        } else if fadeDuration > 0 {
            phase = .fade
            phaseStart = now
            lastFadeProgress = 0
            currentLook = LookMath.lerp(fromLook, toLook, t: 0)
        } else {
            phase = .active
            phaseStart = now
            currentLook = toLook
            lastFadeProgress = 1
            scheduleFollowLocked(cue: cue, at: now)
        }
    }

    private func scheduleFollowLocked(cue: Cue, at now: TimeInterval) {
        pendingFollowAt = nil
        switch cue.follow {
        case .afterTime:
            if let t = cue.followTime, t >= 0 {
                pendingFollowAt = now + t
                pendingFollowIsGo = true
            }
        case .afterGo:
            // Auto-advance immediately after becoming active (link-style).
            pendingFollowAt = now
            pendingFollowIsGo = true
        case .none, .manual:
            break
        }
    }

    private func tickLocked(now: TimeInterval) {
        if frozen { return }
        guard let list else { return }

        // Follow timer.
        if let followAt = pendingFollowAt, now >= followAt {
            pendingFollowAt = nil
            if pendingFollowIsGo {
                let nextIndex = index + 1
                if nextIndex < list.cues.count {
                    beginTransition(to: nextIndex, at: now, list: list)
                }
            }
        }

        switch phase {
        case .idle:
            break
        case .delay:
            let elapsed = now - phaseStart
            if elapsed >= delayDuration {
                if fadeDuration > 0 {
                    phase = .fade
                    phaseStart = now
                    currentLook = LookMath.lerp(fromLook, toLook, t: 0)
                    lastFadeProgress = 0
                } else {
                    phase = .active
                    currentLook = toLook
                    lastFadeProgress = 1
                    if let cue = list.cues[safe: index] {
                        scheduleFollowLocked(cue: cue, at: now)
                    }
                }
            }
        case .fade:
            let elapsed = now - phaseStart
            let t = fadeDuration > 0 ? min(1, elapsed / fadeDuration) : 1
            lastFadeProgress = t
            currentLook = LookMath.lerp(fromLook, toLook, t: t)
            if t >= 1 {
                phase = .active
                currentLook = toLook
                if let cue = list.cues[safe: index] {
                    scheduleFollowLocked(cue: cue, at: now)
                }
            }
        case .active:
            currentLook = toLook
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
