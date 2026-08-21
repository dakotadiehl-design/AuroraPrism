import AuroraDiagnostics
import AuroraModel
import Foundation

// MARK: - Deterministic RNG

/// Seedable RNG for random / weighted / shuffle sequence modes (tests + show reproduction).
struct AMESeededRNG: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0xDEAD_BEEF_CAFE_BABE : seed
    }

    var currentSeed: UInt64 { state }

    mutating func next() -> UInt64 {
        // SplitMix64
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func nextUnit() -> Double {
        Double(next() % 10_000_000) / 10_000_000.0
    }

    mutating func nextInt(upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        return Int(next() % UInt64(upperBound))
    }
}

// MARK: - State key (structured)

/// Runtime state key incorporating sequence state scope + structured show context.
struct AMESequenceStateKey: Hashable, Equatable, Sendable {
    enum Scope: Hashable, Equatable, Sendable {
        case global
        case song(UUID)
        /// Section identity retains owning song when known for domain-wide resets.
        case section(songID: UUID?, sectionID: UUID)
    }

    var sequenceID: UUID
    var scope: Scope

    static func make(
        sequence: AMETriggeredSequence,
        context: AMEShowContext
    ) -> AMESequenceStateKey {
        let scope: Scope
        switch sequence.stateScope {
        case .sequenceGlobal:
            scope = .global
        case .perSong:
            // Only create song keys for real song IDs (never song:nil).
            if let song = context.activeSongID {
                scope = .song(song)
            } else {
                // Fallback key used only if triggered with no song context.
                scope = .song(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
            }
        case .perSection:
            if let section = context.activeSectionID {
                scope = .section(songID: context.activeSongID, sectionID: section)
            } else {
                scope = .section(
                    songID: context.activeSongID,
                    sectionID: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
                )
            }
        }
        return AMESequenceStateKey(sequenceID: sequence.id, scope: scope)
    }

    /// Whether this key can be created for a real entry (non-nil context when scoped).
    static func canCreate(sequence: AMETriggeredSequence, context: AMEShowContext) -> Bool {
        switch sequence.stateScope {
        case .sequenceGlobal:
            return true
        case .perSong:
            return context.activeSongID != nil
        case .perSection:
            return context.activeSectionID != nil
        }
    }
}

struct AMESequenceRuntimeState: Sendable {
    /// Next step to fire (`fireThenAdvance`) or last-fired / pre-advance cursor (`advanceThenFire`).
    var cursor: Int
    /// Ping-pong direction: +1 forward, -1 reverse.
    var direction: Int
    /// Remaining indices in the current shuffle bag (front = next).
    var shuffleBag: [Int]
    /// Per-instance RNG stream (isolated from other sequences/scopes).
    var rng: AMESeededRNG
    /// Reserved; loop=false currently clamps/re-fires terminal (not one-shot exhaustion).
    var isExhausted: Bool

    init(
        cursor: Int = 0,
        direction: Int = 1,
        shuffleBag: [Int] = [],
        rng: AMESeededRNG,
        isExhausted: Bool = false
    ) {
        self.cursor = cursor
        self.direction = direction == 0 ? 1 : (direction > 0 ? 1 : -1)
        self.shuffleBag = shuffleBag
        self.rng = rng
        self.isExhausted = isExhausted
    }

    static func initial(
        for sequence: AMETriggeredSequence,
        instanceSeed: UInt64
    ) -> AMESequenceRuntimeState {
        let n = sequence.steps.count
        let start: Int
        if n == 0 {
            start = 0
        } else {
            start = min(max(0, sequence.initialIndex), n - 1)
        }
        let dir = sequence.mode == .reverse ? -1 : 1
        // Both policies start with cursor = initialIndex; they differ on first trigger.
        return AMESequenceRuntimeState(
            cursor: start,
            direction: dir,
            shuffleBag: [],
            rng: AMESeededRNG(seed: instanceSeed),
            isExhausted: false
        )
    }
}

struct AMESequenceFireResult: Equatable, Sendable {
    var sequenceID: UUID
    var stepIndex: Int
    var stepID: UUID?
    var stepName: String
    var actions: [AuroraAction]
    var nextCursorDescription: String
}

enum AMESequenceTriggerError: Error, Equatable, Sendable {
    case missingSequence
    case emptySequence
    case invalidState
    case noContext
    case exhausted
}

extension AMESequenceTriggerError: LocalizedError, PrismDiagnosableError {
    var errorDescription: String? { userMessage }
    var prismErrorCode: String {
        switch self {
        case .missingSequence: return "ame.sequence.missing"
        case .emptySequence: return "ame.sequence.empty"
        case .invalidState: return "ame.sequence.invalid_step"
        case .noContext: return "ame.sequence.no_context"
        case .exhausted: return "ame.sequence.exhausted"
        }
    }
    var userTitle: String { "AME Sequence Couldn't Run" }
    var userMessage: String { "That AME sequence couldn't run." }
    var recoverySuggestion: String? { "Check the sequence steps and try arming AME again." }
    var technicalDetails: String { String(reflecting: self) }
    var prismCategory: PrismLogCategory { .ameSequence }
    var prismSeverity: PrismLogLevel { .warning }
}

// MARK: - Instance seed derivation

enum AMESequenceSeed {
    /// Derive a stable per-key substream from base show seed + key identity.
    static func instanceSeed(base: UInt64, key: AMESequenceStateKey) -> UInt64 {
        var h = base ^ 0xC0FFEE_A11A_5EED
        h = mix(h, uuidWords(key.sequenceID))
        switch key.scope {
        case .global:
            h = mix(h, 1)
        case .song(let id):
            h = mix(h, 2)
            h = mix(h, uuidWords(id))
        case .section(let songID, let sectionID):
            h = mix(h, 3)
            if let songID { h = mix(h, uuidWords(songID)) }
            h = mix(h, uuidWords(sectionID))
        }
        return h == 0 ? 1 : h
    }

    private static func uuidWords(_ id: UUID) -> UInt64 {
        let u = id.uuid
        let a = UInt64(u.0) << 56 | UInt64(u.1) << 48 | UInt64(u.2) << 40 | UInt64(u.3) << 32
            | UInt64(u.4) << 24 | UInt64(u.5) << 16 | UInt64(u.6) << 8 | UInt64(u.7)
        let b = UInt64(u.8) << 56 | UInt64(u.9) << 48 | UInt64(u.10) << 40 | UInt64(u.11) << 32
            | UInt64(u.12) << 24 | UInt64(u.13) << 16 | UInt64(u.14) << 8 | UInt64(u.15)
        return a ^ b
    }

    private static func mix(_ h: UInt64, _ v: UInt64) -> UInt64 {
        var x = h ^ v
        x &+= 0x9E3779B97F4A7C15
        x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9
        x = (x ^ (x >> 27)) &* 0x94D049BB133111EB
        return x ^ (x >> 31)
    }
}

// MARK: - Engine (internal — AMERuntime owns serialization)

/// Ephemeral sequence step state. **Not public.** Thread-safety owned exclusively by `AMERuntime` lock.
final class AMESequenceStateTable {
    private var states: [AMESequenceStateKey: AMESequenceRuntimeState] = [:]
    private var baseSeed: UInt64

    init(seed: UInt64 = 0xA11A_5EED) {
        self.baseSeed = seed == 0 ? 0xA11A_5EED : seed
    }

    func setBaseSeed(_ seed: UInt64) {
        baseSeed = seed == 0 ? 0xA11A_5EED : seed
        // Reseed all existing instance streams deterministically from new base.
        for (key, var state) in states {
            let s = AMESequenceSeed.instanceSeed(base: baseSeed, key: key)
            state.rng = AMESeededRNG(seed: s)
            states[key] = state
        }
    }

    func state(for key: AMESequenceStateKey) -> AMESequenceRuntimeState? {
        states[key]
    }

    func allKeys() -> [AMESequenceStateKey] {
        Array(states.keys)
    }

    func clear() {
        states.removeAll(keepingCapacity: true)
    }

    func pruneRemovedSequences(validSequenceIDs: Set<UUID>) {
        states = states.filter { validSequenceIDs.contains($0.key.sequenceID) }
    }

    /// Reset one instance for the given context to its initial runtime state (including RNG stream).
    func reset(sequence: AMETriggeredSequence, context: AMEShowContext) {
        guard AMESequenceStateKey.canCreate(sequence: sequence, context: context) else { return }
        let key = AMESequenceStateKey.make(sequence: sequence, context: context)
        let seed = AMESequenceSeed.instanceSeed(base: baseSeed, key: key)
        states[key] = .initial(for: sequence, instanceSeed: seed)
    }

    /// Reset all stored instances of a sequence matching the domain of a reset event.
    func resetDomain(
        sequence: AMETriggeredSequence,
        event: ResetDomainEvent,
        context: AMEShowContext
    ) {
        switch (sequence.stateScope, event) {
        case (.sequenceGlobal, .songStart), (.sequenceGlobal, .sectionEntry):
            let key = AMESequenceStateKey(sequenceID: sequence.id, scope: .global)
            let seed = AMESequenceSeed.instanceSeed(base: baseSeed, key: key)
            states[key] = .initial(for: sequence, instanceSeed: seed)

        case (.perSong, .songStart(let songID)):
            let key = AMESequenceStateKey(sequenceID: sequence.id, scope: .song(songID))
            let seed = AMESequenceSeed.instanceSeed(base: baseSeed, key: key)
            states[key] = .initial(for: sequence, instanceSeed: seed)

        case (.perSong, .sectionEntry):
            // Reset the current song's instance on each section entry.
            if let song = context.activeSongID {
                let key = AMESequenceStateKey(sequenceID: sequence.id, scope: .song(song))
                let seed = AMESequenceSeed.instanceSeed(base: baseSeed, key: key)
                states[key] = .initial(for: sequence, instanceSeed: seed)
            }

        case (.perSection, .sectionEntry(let sectionID, let songID)):
            let key = AMESequenceStateKey(
                sequenceID: sequence.id,
                scope: .section(songID: songID, sectionID: sectionID)
            )
            let seed = AMESequenceSeed.instanceSeed(base: baseSeed, key: key)
            states[key] = .initial(for: sequence, instanceSeed: seed)

        case (.perSection, .songStart(let songID)):
            // Reset **all** stored section instances belonging to the entered song.
            var toReset: [AMESequenceStateKey] = []
            for key in states.keys where key.sequenceID == sequence.id {
                if case .section(let sSong, _) = key.scope, sSong == songID {
                    toReset.append(key)
                }
            }
            // Also ensure the current section instance (if any) is reset even if never visited.
            if let section = context.activeSectionID {
                let current = AMESequenceStateKey(
                    sequenceID: sequence.id,
                    scope: .section(songID: songID, sectionID: section)
                )
                if !toReset.contains(current) { toReset.append(current) }
            }
            for key in toReset {
                let seed = AMESequenceSeed.instanceSeed(base: baseSeed, key: key)
                states[key] = .initial(for: sequence, instanceSeed: seed)
            }
        }
    }

    enum ResetDomainEvent: Equatable {
        case songStart(UUID)
        case sectionEntry(sectionID: UUID, songID: UUID?)
    }

    /// Advance state without firing step actions.
    @discardableResult
    func advanceOnly(
        sequence: AMETriggeredSequence,
        context: AMEShowContext
    ) -> Result<Int, AMESequenceTriggerError> {
        guard !sequence.steps.isEmpty else { return .failure(.emptySequence) }
        guard AMESequenceStateKey.canCreate(sequence: sequence, context: context) else {
            return .failure(.noContext)
        }
        let key = AMESequenceStateKey.make(sequence: sequence, context: context)
        var state = states[key] ?? .initial(
            for: sequence,
            instanceSeed: AMESequenceSeed.instanceSeed(base: baseSeed, key: key)
        )
        // Advance cursor according to mode without returning step actions.
        let advanced = nextLinearIndex(from: state.cursor, sequence: sequence, direction: state.direction, state: &state)
        switch sequence.mode {
        case .advance, .reverse, .pingPong:
            state.cursor = advanced.index
            state.direction = advanced.direction
        case .random:
            state.cursor = state.rng.nextInt(upperBound: sequence.steps.count)
        case .weightedRandom:
            state.cursor = pickWeighted(steps: sequence.steps, rng: &state.rng)
        case .shuffleBag:
            state.cursor = popShuffleBag(sequence: sequence, state: &state)
        }
        states[key] = state
        return .success(state.cursor)
    }

    /// Fire one sequence step for a qualifying event and update state per trigger policy.
    func trigger(
        sequence: AMETriggeredSequence,
        context: AMEShowContext
    ) -> Result<AMESequenceFireResult, AMESequenceTriggerError> {
        guard !sequence.steps.isEmpty else { return .failure(.emptySequence) }
        guard AMESequenceStateKey.canCreate(sequence: sequence, context: context) else {
            return .failure(.noContext)
        }

        let key = AMESequenceStateKey.make(sequence: sequence, context: context)
        var state = states[key] ?? .initial(
            for: sequence,
            instanceSeed: AMESequenceSeed.instanceSeed(base: baseSeed, key: key)
        )

        let fireIndex: Int
        switch sequence.mode {
        case .advance, .reverse, .pingPong:
            switch sequence.triggerPolicy {
            case .fireThenAdvance:
                // Fire current cursor, then advance.
                fireIndex = clamped(state.cursor, count: sequence.steps.count)
                let advanced = nextLinearIndex(
                    from: fireIndex,
                    sequence: sequence,
                    direction: state.direction,
                    state: &state
                )
                state.cursor = advanced.index
                state.direction = advanced.direction
            case .advanceThenFire:
                // Advance first, then fire the resulting step.
                let advanced = nextLinearIndex(
                    from: state.cursor,
                    sequence: sequence,
                    direction: state.direction,
                    state: &state
                )
                state.cursor = advanced.index
                state.direction = advanced.direction
                fireIndex = advanced.index
            }
        case .random:
            fireIndex = state.rng.nextInt(upperBound: sequence.steps.count)
            state.cursor = fireIndex
        case .weightedRandom:
            fireIndex = pickWeighted(steps: sequence.steps, rng: &state.rng)
            state.cursor = fireIndex
        case .shuffleBag:
            fireIndex = popShuffleBag(sequence: sequence, state: &state)
            state.cursor = fireIndex
        }

        states[key] = state
        let step = sequence.steps[fireIndex]
        return .success(
            AMESequenceFireResult(
                sequenceID: sequence.id,
                stepIndex: fireIndex,
                stepID: step.id,
                stepName: step.name,
                actions: step.actions,
                nextCursorDescription: describe(state: state, sequence: sequence)
            )
        )
    }

    /// Last fired / current cursor (not necessarily next deterministic fire).
    func lastCursor(sequence: AMETriggeredSequence, context: AMEShowContext) -> Int? {
        guard AMESequenceStateKey.canCreate(sequence: sequence, context: context) else { return nil }
        let key = AMESequenceStateKey.make(sequence: sequence, context: context)
        return states[key]?.cursor
    }

    /// Next deterministic fire index when known without consuming RNG.
    func nextDeterministicFireIndex(sequence: AMETriggeredSequence, context: AMEShowContext) -> Int? {
        guard !sequence.steps.isEmpty else { return nil }
        guard AMESequenceStateKey.canCreate(sequence: sequence, context: context) else { return nil }
        let key = AMESequenceStateKey.make(sequence: sequence, context: context)
        let state = states[key] ?? .initial(
            for: sequence,
            instanceSeed: AMESequenceSeed.instanceSeed(base: baseSeed, key: key)
        )
        switch sequence.mode {
        case .shuffleBag:
            return state.shuffleBag.first
        case .random, .weightedRandom:
            return nil // next requires RNG consumption
        case .advance, .reverse, .pingPong:
            switch sequence.triggerPolicy {
            case .fireThenAdvance:
                return clamped(state.cursor, count: sequence.steps.count)
            case .advanceThenFire:
                var temp = state
                return nextLinearIndex(
                    from: state.cursor,
                    sequence: sequence,
                    direction: state.direction,
                    state: &temp
                ).index
            }
        }
    }

    // MARK: - Mode helpers

    private func nextLinearIndex(
        from current: Int,
        sequence: AMETriggeredSequence,
        direction: Int,
        state: inout AMESequenceRuntimeState
    ) -> (index: Int, direction: Int) {
        let count = sequence.steps.count
        guard count > 0 else { return (0, 1) }
        let cur = clamped(current, count: count)

        switch sequence.mode {
        case .advance:
            if cur + 1 < count {
                return (cur + 1, 1)
            }
            // loop=false: clamp at end (re-fire terminal on subsequent triggers).
            return sequence.loop ? (0, 1) : (cur, 1)

        case .reverse:
            if cur - 1 >= 0 {
                return (cur - 1, -1)
            }
            return sequence.loop ? (count - 1, -1) : (cur, -1)

        case .pingPong:
            var dir = direction >= 0 ? 1 : -1
            if count == 1 { return (0, dir) }
            if !sequence.loop {
                if cur == count - 1 && dir > 0 { return (cur, 1) }
                if cur == 0 && dir < 0 { return (cur, -1) }
            }
            var next = cur + dir
            if next >= count {
                dir = -1
                next = count - 2
                if next < 0 { next = 0 }
            } else if next < 0 {
                dir = 1
                next = min(1, count - 1)
            }
            return (next, dir)

        case .random, .weightedRandom, .shuffleBag:
            return (cur, direction)
        }
    }

    private func pickWeighted(steps: [AMESequenceStep], rng: inout AMESeededRNG) -> Int {
        let weights = steps.map { max(0, $0.weight) }
        let total = weights.reduce(0, +)
        guard total > 0 else {
            return rng.nextInt(upperBound: steps.count)
        }
        var r = rng.nextUnit() * total
        for (i, w) in weights.enumerated() {
            r -= w
            if r <= 0 { return i }
        }
        return steps.count - 1
    }

    private func popShuffleBag(sequence: AMETriggeredSequence, state: inout AMESequenceRuntimeState) -> Int {
        let count = sequence.steps.count
        if state.shuffleBag.isEmpty {
            var bag = Array(0..<count)
            if count > 1 {
                for i in stride(from: count - 1, through: 1, by: -1) {
                    let j = state.rng.nextInt(upperBound: i + 1)
                    bag.swapAt(i, j)
                }
            }
            // Avoid immediate repeat of last fired when reshuffling (if possible).
            if count > 1, bag.first == state.cursor {
                bag.swapAt(0, 1)
            }
            state.shuffleBag = bag
        }
        return state.shuffleBag.removeFirst()
    }

    private func clamped(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(0, index), count - 1)
    }

    private func describe(state: AMESequenceRuntimeState, sequence: AMETriggeredSequence) -> String {
        "cursor=\(state.cursor) dir=\(state.direction) bag=\(state.shuffleBag.count) mode=\(sequence.mode.rawValue) policy=\(sequence.triggerPolicy.rawValue)"
    }
}

// MARK: - Product helpers (defaults for editors)

public enum AMESequenceDefaults {
    /// Suggested initialIndex when creating a sequence of the given mode.
    /// Reverse defaults to last step so new reverse sequences match the feature-spec illustration.
    public static func suggestedInitialIndex(mode: AMESequenceMode, stepCount: Int) -> Int {
        guard stepCount > 0 else { return 0 }
        switch mode {
        case .reverse:
            return stepCount - 1
        default:
            return 0
        }
    }
}
