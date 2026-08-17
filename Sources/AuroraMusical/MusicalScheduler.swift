import Foundation

/// Result of applying per-action failure policies when musical timing becomes unavailable.
public struct TimingUnavailableResolution: Equatable, Sendable {
    public var fireImmediately: [ScheduledMusicalAction]
    public var canceled: [ScheduledMusicalAction]
    public var held: [ScheduledMusicalAction]

    public init(
        fireImmediately: [ScheduledMusicalAction] = [],
        canceled: [ScheduledMusicalAction] = [],
        held: [ScheduledMusicalAction] = []
    ) {
        self.fireImmediately = fireImmediately
        self.canceled = canceled
        self.held = held
    }
}

/// In-memory quantized action queue.
///
/// - Reject **newest** when full (never drop oldest accepted work).
/// - Decorative limited to `capacity - safetyReserved`; safety may use remaining capacity.
/// - Lock order when nested with MusicalEngine: **engine lock → scheduler lock** (never reverse).
public final class MusicalScheduler: @unchecked Sendable {
    public struct Config: Equatable, Sendable {
        public var capacity: Int
        public var safetyReserved: Int

        public init(capacity: Int = 256, safetyReserved: Int = 16) {
            self.capacity = max(1, capacity)
            self.safetyReserved = max(0, min(safetyReserved, capacity))
        }

        /// Max non-safety entries.
        public var decorativeCapacity: Int { max(0, capacity - safetyReserved) }
    }

    public struct PendingEntry: Equatable, Sendable, Identifiable {
        public var id: UUID { action.id }
        public var action: ScheduledMusicalAction
        /// Absolute musical position to fire; `nil` when held.
        public var targetPosition: QuarterNotePosition?
        public var isHeld: Bool
    }

    private let lock = NSLock()
    private var config: Config
    private var pending: [PendingEntry] = []

    public init(config: Config = Config()) {
        self.config = config
    }

    public var pendingCount: Int {
        lock.lock(); defer { lock.unlock() }
        return pending.count
    }

    public var snapshotPending: [PendingEntry] {
        lock.lock(); defer { lock.unlock() }
        return pending
    }

    /// Enqueue with pre-resolved target (or hold).
    ///
    /// Invariants:
    /// - non-safety count ≤ decorativeCapacity
    /// - total pending ≤ capacity
    /// - safety may use reserved + any unused decorative slots (up to total capacity)
    @discardableResult
    public func enqueue(
        _ action: ScheduledMusicalAction,
        targetPosition: QuarterNotePosition?,
        hold: Bool = false
    ) -> ScheduleEnqueueResult {
        lock.lock()
        defer { lock.unlock() }

        // Safety must never be queued behind a musical target — only MusicalEngine.schedule may deliver it.
        if action.isSafetyCritical {
            return .rejectedInvalid
        }

        if pending.contains(where: { $0.id == action.id }) {
            return .rejectedInvalid
        }

        let decorativeCount = pending.filter { !$0.action.isSafetyCritical }.count
        if decorativeCount >= config.decorativeCapacity || pending.count >= config.capacity {
            return .rejectedQueueFull
        }

        pending.append(PendingEntry(
            action: action,
            targetPosition: targetPosition,
            isHeld: hold
        ))
        return .accepted(action.id)
    }

    /// Remove by schedule ID; returns payload for token cleanup.
    @discardableResult
    public func cancel(id: UUID) -> ScheduledMusicalAction? {
        lock.lock()
        defer { lock.unlock() }
        guard let idx = pending.firstIndex(where: { $0.id == id }) else { return nil }
        return pending.remove(at: idx).action
    }

    /// Remove all; returns payloads for token cleanup.
    @discardableResult
    public func cancelAll() -> [ScheduledMusicalAction] {
        lock.lock()
        defer { lock.unlock() }
        let actions = pending.map(\.action)
        pending.removeAll()
        return actions
    }

    /// Apply per-action `QuantizationFailurePolicy` when transport stops / source lost / etc.
    public func timingBecameUnavailable() -> TimingUnavailableResolution {
        lock.lock()
        defer { lock.unlock() }

        var fire: [ScheduledMusicalAction] = []
        var canceled: [ScheduledMusicalAction] = []
        var held: [PendingEntry] = []

        for entry in pending {
            // Already held stays held
            if entry.isHeld {
                held.append(entry)
                continue
            }
            switch entry.action.failurePolicy {
            case .cancel:
                canceled.append(entry.action)
            case .executeImmediately:
                fire.append(entry.action)
            case .holdUntilTimingAvailable:
                var e = entry
                e.isHeld = true
                e.targetPosition = nil
                held.append(e)
            }
        }
        pending = held
        return TimingUnavailableResolution(
            fireImmediately: fire,
            canceled: canceled,
            held: held.map(\.action)
        )
    }

    /// Fire entries that are due; returns them in stable enqueue order.
    public func harvestDue(at position: QuarterNotePosition) -> [ScheduledMusicalAction] {
        lock.lock()
        defer { lock.unlock() }
        var due: [ScheduledMusicalAction] = []
        var remaining: [PendingEntry] = []
        for entry in pending {
            if entry.isHeld {
                remaining.append(entry)
                continue
            }
            if let target = entry.targetPosition,
               MusicalBoundaryMath.isDue(target: target, current: position) {
                due.append(entry.action)
            } else if entry.targetPosition == nil, entry.action.targetBoundary.isImmediate {
                due.append(entry.action)
            } else {
                remaining.append(entry)
            }
        }
        pending = remaining
        return due
    }

    /// Re-resolve held entries when transport/timing becomes available again.
    public func releaseHeld(
        position: QuarterNotePosition,
        meter: MusicalMeter?,
        transport: MusicalTransport
    ) -> [ScheduledMusicalAction] {
        lock.lock()
        defer { lock.unlock() }
        var immediate: [ScheduledMusicalAction] = []
        var remaining: [PendingEntry] = []
        for entry in pending {
            guard entry.isHeld else {
                remaining.append(entry)
                continue
            }
            switch entry.action.failurePolicy {
            case .cancel:
                continue
            case .executeImmediately:
                immediate.append(entry.action)
            case .holdUntilTimingAvailable:
                if let target = MusicalBoundaryMath.resolve(
                    entry.action.targetBoundary,
                    from: position,
                    meter: meter,
                    transport: transport
                ) {
                    var e = entry
                    e.isHeld = false
                    e.targetPosition = target
                    remaining.append(e)
                } else {
                    remaining.append(entry)
                }
            }
        }
        pending = remaining
        return immediate
    }
}
