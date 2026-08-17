import AuroraModel
import Foundation

/// Single-list cue playback: delay, linear fade (fadeIn/fadeOut), follow, loop, stop/back.
///
/// **Fade semantics (v1 / P1-1):**
/// - Incoming `fadeIn` and outgoing `fadeOut` set the crossfade duration to
///   `max(outgoing.fadeOut, incoming.fadeIn)` (whole-look linear lerp).
/// - Zero duration snaps immediately.
///
/// **Loop semantics (v1 / P1-1):**
/// - `LoopSpec` on a cue: after the cue becomes active, automatic Follow re-enters
///   the same cue until the count is exhausted (or forever if `infinite`).
/// - Manual **GO** always advances to the next cue and clears loop state.
/// - **Back** clears loop state and moves to the previous cue.
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
    /// Remaining automatic re-entries after the current play of a looped cue.
    private var loopRemaining: Int?
    private var loopInfinite = false

    public init() {}

    /// Destructive load: resets playback index, phase, and stage look.
    /// Use for New / Open / explicit cue-list replacement.
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
        clearLoopStateLocked()
        lock.unlock()
    }

    /// Non-destructive project update: refreshes model + cue list content while
    /// preserving **active cue UUID** (not array index), phase, and current stage look.
    ///
    /// If the active cue or list is deleted: keep the current stage look, set index to -1,
    /// phase idle, clear follow/loop. Next manual GO on a loaded list starts at cue 0.
    public func updateProject(_ project: ShowProject) {
        lock.lock()
        defer { lock.unlock() }
        self.project = project

        let previousListID = list?.id
        let previousCueID: UUID? = {
            guard let list, index >= 0, index < list.cues.count else { return nil }
            return list.cues[index].id
        }()

        guard let previousListID else {
            // No list was loaded; nothing to rebind.
            return
        }

        if let updated = project.cueLists.first(where: { $0.id == previousListID }) {
            self.list = updated
            if let previousCueID {
                if let newIndex = updated.cues.firstIndex(where: { $0.id == previousCueID }) {
                    // Same semantic cue — reindex after insert/reorder.
                    index = newIndex
                    if phase == .active {
                        toLook = CueResolver.resolveLook(
                            cues: updated.cues,
                            index: index,
                            project: project,
                            priorLook: currentLook
                        )
                    }
                } else {
                    // Active cue deleted: do not substitute another cue at the old index.
                    detachPlaybackIdentityLocked(keepList: true)
                }
            }
            // else: already idle on this list — leave index as-is (-1)
        } else {
            // Active list removed: detach identity, keep stage look.
            self.list = nil
            detachPlaybackIdentityLocked(keepList: false)
        }
    }

    /// Clears cue index / phase / follow / loop without blacking out currentLook.
    private func detachPlaybackIdentityLocked(keepList: Bool) {
        _ = keepList
        index = -1
        phase = .idle
        pendingFollowAt = nil
        lastFadeProgress = 0
        clearLoopStateLocked()
    }

    public func snapshot() -> PlaybackSnapshot {
        lock.lock()
        defer { lock.unlock() }
        let cue = (index >= 0 && index < (list?.cues.count ?? 0)) ? list?.cues[index] : nil
        let progress: Double
        switch phase {
        case .fade where fadeDuration > 0:
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
        // Manual GO always leaves a loop and advances.
        clearLoopStateLocked()

        // After detach (index == -1), next GO starts at the first cue.
        let nextIndex = index + 1
        guard nextIndex < list.cues.count else {
            return
        }
        beginTransition(to: nextIndex, at: now, list: list, isLoopReentry: false)
    }

    public func back(at now: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        guard let list, !list.cues.isEmpty else { return }
        frozen = false
        pendingFollowAt = nil
        clearLoopStateLocked()
        let prev = max(0, index - 1)
        if index < 0 {
            beginTransition(to: 0, at: now, list: list, isLoopReentry: false)
        } else {
            beginTransition(to: prev, at: now, list: list, isLoopReentry: false)
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
        clearLoopStateLocked()
    }

    /// Fire a cue by ID. Returns `false` when the cue is not on the active list.
    @discardableResult
    public func fire(cueID: UUID, at now: TimeInterval) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let list, let idx = list.cues.firstIndex(where: { $0.id == cueID }) else { return false }
        frozen = false
        pendingFollowAt = nil
        clearLoopStateLocked()
        beginTransition(to: idx, at: now, list: list, isLoopReentry: false)
        return true
    }

    private func clearLoopStateLocked() {
        loopRemaining = nil
        loopInfinite = false
    }

    private func beginTransition(to newIndex: Int, at now: TimeInterval, list: CueList, isLoopReentry: Bool) {
        let outgoingIndex = index
        let cue = list.cues[newIndex]
        fromLook = currentLook
        toLook = CueResolver.resolveLook(
            cues: list.cues,
            index: newIndex,
            project: project,
            priorLook: currentLook
        )
        index = newIndex
        delayDuration = max(0, cue.delay)

        // Crossfade length: max(outgoing fadeOut, incoming fadeIn).
        let outgoingFadeOut: TimeInterval
        if outgoingIndex >= 0, outgoingIndex < list.cues.count, !isLoopReentry {
            outgoingFadeOut = max(0, list.cues[outgoingIndex].fadeOut)
        } else {
            outgoingFadeOut = 0
        }
        let incomingFadeIn = max(0, cue.fadeIn)
        fadeDuration = max(outgoingFadeOut, incomingFadeIn)

        if !isLoopReentry {
            // Arm loop for this entry into the cue (not mid-loop re-fire accounting — already set).
            if let loop = cue.loop {
                if loop.infinite {
                    loopInfinite = true
                    loopRemaining = nil
                } else if let count = loop.count, count > 0 {
                    loopInfinite = false
                    // Current play counts as 1; remaining automatic re-entries = count - 1.
                    loopRemaining = max(0, count - 1)
                } else {
                    clearLoopStateLocked()
                }
            } else {
                clearLoopStateLocked()
            }
        }

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
            pendingFollowAt = now
            pendingFollowIsGo = true
        case .none, .manual:
            break
        }
    }

    /// Whether automatic advance should re-enter the current cue (loop).
    private func shouldLoopReenterLocked() -> Bool {
        if loopInfinite { return true }
        if let remaining = loopRemaining, remaining > 0 { return true }
        return false
    }

    private func consumeLoopReentryLocked() {
        if loopInfinite { return }
        if let remaining = loopRemaining, remaining > 0 {
            loopRemaining = remaining - 1
        }
    }

    private func advanceFromFollowLocked(at now: TimeInterval, list: CueList) {
        if shouldLoopReenterLocked() {
            consumeLoopReentryLocked()
            beginTransition(to: index, at: now, list: list, isLoopReentry: true)
            return
        }
        clearLoopStateLocked()
        let nextIndex = index + 1
        if nextIndex < list.cues.count {
            beginTransition(to: nextIndex, at: now, list: list, isLoopReentry: false)
        }
    }

    private func tickLocked(now: TimeInterval) {
        if frozen { return }
        guard let list else { return }

        if let followAt = pendingFollowAt, now >= followAt {
            pendingFollowAt = nil
            if pendingFollowIsGo {
                advanceFromFollowLocked(at: now, list: list)
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
