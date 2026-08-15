import AuroraEngine
import AuroraMIDI
import AuroraModel
import Foundation

/// Thread-safe flag for MIDI learn arming (readable from CoreMIDI callbacks).
final class MIDILearnFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _armed = false
    var isArmed: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _armed }
        set { lock.lock(); _armed = newValue; lock.unlock() }
    }
}

/// Token for a control-event UI observer subscription (UI-GATE-1).
struct ControlEventObserverToken: Hashable, Sendable {
    let id: UUID
}

/// Unified show-control dispatcher for MIDI / OSC / UI / remote (P1-9 / UI-GATE-1).
///
/// Live paths avoid MainActor. `fireCueIndex` targets the **active** playback list,
/// not `cueLists.first`.
///
/// UI observation is multi-subscriber: installing a second observer never replaces the first.
final class ControlActionRouter: @unchecked Sendable {
    private let lock = NSLock()
    private weak var engine: LightingEngine?
    private var mappings: [MIDIMapping] = []
    private var rules: [MIDIRule] = []
    private var project: ShowProject = .empty()
    private var selectedFixtureIDs: Set<UUID> = []
    private var orderedFixtureIDs: [UUID] = []
    private var songSectionLabel: String?
    private let safety = MIDISafetyLimiter(maxEventsPerSecond: 250, debounceSeconds: 0)
    /// Multi-observer map (replaces single replaceable callback).
    private var uiObservers: [UUID: @Sendable (ShowAction, String) -> Void] = [:]

    init(engine: LightingEngine) {
        self.engine = engine
    }

    /// Register a UI/diagnostics observer. Returns a token for later removal.
    /// Multiple observers fire for each live action; none overwrites another.
    @discardableResult
    func addUIObserver(_ handler: @escaping @Sendable (ShowAction, String) -> Void) -> ControlEventObserverToken {
        let id = UUID()
        lock.lock()
        uiObservers[id] = handler
        lock.unlock()
        return ControlEventObserverToken(id: id)
    }

    func removeUIObserver(_ token: ControlEventObserverToken) {
        lock.lock()
        uiObservers[token.id] = nil
        lock.unlock()
    }

    /// Compatibility: clears existing observers and installs a single handler.
    /// Prefer `addUIObserver` so MIDI status and show-control both stay subscribed.
    func setUINotify(_ handler: @escaping @Sendable (ShowAction, String) -> Void) {
        lock.lock()
        uiObservers = [UUID(): handler]
        lock.unlock()
    }

    func updateMappings(_ mappings: [MIDIMapping], project: ShowProject) {
        lock.lock()
        self.mappings = mappings
        self.rules = project.midiRules
        self.project = project
        lock.unlock()
    }

    func updateSongSectionContext(_ label: String?) {
        lock.lock()
        songSectionLabel = label
        lock.unlock()
    }

    func updateSelection(_ fixtureIDs: Set<UUID>) {
        lock.lock()
        selectedFixtureIDs = fixtureIDs
        if orderedFixtureIDs.isEmpty || Set(orderedFixtureIDs) != fixtureIDs {
            orderedFixtureIDs = fixtureIDs.sorted { $0.uuidString < $1.uuidString }
        }
        lock.unlock()
    }

    func updateOrderedSelection(_ ids: [UUID]) {
        lock.lock()
        orderedFixtureIDs = ids
        selectedFixtureIDs = Set(ids)
        lock.unlock()
    }

    /// Called from MIDI callback thread (not MainActor).
    func handleMIDIEvents(_ events: [MIDIEvent]) {
        lock.lock()
        let maps = mappings
        let ruleList = rules
        let section = songSectionLabel
        let eng = engine
        let observers = Array(uiObservers.values)
        let selection = selectedFixtureIDs
        let ordered = orderedFixtureIDs
        let proj = project
        let midiEnabled = eng?.globalShowControl.midiPerformanceEnabled ?? true
        lock.unlock()
        guard let eng else { return }
        if !midiEnabled { return }

        let now = eng.currentResolvedSnapshot().timestamp
        let orderedSel = ordered.isEmpty ? Array(selection) : ordered

        for event in events {
            guard safety.allow(event: event) else { continue }
            let control = MIDIActionResolver.controlValue(for: event)

            // Advanced MIDI behaviors (drum roles + envelopes).
            var behaviorFired = false
            switch event {
            case .noteOn(let ch, let note, let vel, let src, _):
                let before = eng.midiBehaviors.liveCount
                eng.midiBehaviors.noteOn(
                    note: note,
                    velocity: vel,
                    channel: ch,
                    deviceID: src,
                    songSection: section,
                    time: now,
                    selection: orderedSel
                )
                behaviorFired = eng.midiBehaviors.liveCount > before
                if behaviorFired {
                    for notify in observers {
                        notify(.go, "BEHAVIOR note \(note) \(event.summary)")
                    }
                }
            case .noteOff(let ch, let note, _, let src, _):
                eng.midiBehaviors.noteOff(note: note, channel: ch, deviceID: src, time: now)
            default:
                break
            }

            var actions = MIDIActionResolver.matchAll(event: event, mappings: maps)
            actions.append(contentsOf: MIDIActionResolver.matchRules(
                event: event,
                rules: ruleList,
                songSection: section
            ))
            if actions.isEmpty && !behaviorFired {
                for notify in observers {
                    notify(.stop, "UNMATCHED \(event.summary)") // re-use notify path for log only
                }
                // Don't apply stop — observers filter by summary.
                continue
            }
            for action in actions {
                // Never run panic-disabling MIDI when disabled (already returned).
                applyLive(
                    action,
                    engine: eng,
                    project: proj,
                    control: control,
                    selection: selection,
                    orderedSelection: ordered
                )
                for notify in observers {
                    notify(action, event.summary)
                }
            }
        }
    }

    /// Dispatch a show action from any control surface (MIDI/OSC/UI/remote).
    /// Safe from non-MainActor threads (UI-GATE-2).
    func dispatch(
        _ action: ShowAction,
        control: MIDIControlValue? = nil,
        midiValue: UInt8? = nil,
        notifySummary: String? = nil
    ) {
        lock.lock()
        let eng = engine
        let proj = project
        let selection = selectedFixtureIDs
        let ordered = orderedFixtureIDs
        let observers = Array(uiObservers.values)
        lock.unlock()
        guard let eng else { return }

        let resolved: MIDIControlValue?
        if let control {
            resolved = control
        } else if let midiValue {
            resolved = MIDIControlValue(normalized: MIDIActionResolver.ccNormalized(midiValue), isTrigger: false)
        } else {
            resolved = nil
        }

        applyLive(
            action,
            engine: eng,
            project: proj,
            control: resolved,
            selection: selection,
            orderedSelection: ordered
        )

        if let summary = notifySummary {
            for notify in observers {
                notify(action, summary)
            }
        }
    }

    /// Live actions that must not require MainActor.
    func applyLive(
        _ action: ShowAction,
        engine: LightingEngine,
        project: ShowProject? = nil,
        control: MIDIControlValue? = nil,
        midiValue: UInt8? = nil,
        selection: Set<UUID> = [],
        orderedSelection: [UUID] = []
    ) {
        let proj: ShowProject
        if let project {
            proj = project
        } else {
            lock.lock()
            proj = self.project
            lock.unlock()
        }

        let scalar: Double
        if let control {
            scalar = control.normalized
        } else if let midiValue {
            scalar = MIDIActionResolver.ccNormalized(midiValue)
        } else {
            scalar = 0
        }

        switch action {
        case .go:
            engine.go()
        case .stop:
            engine.stopPlayback()
        case .back:
            engine.back()
        case .fireCue(let id):
            engine.fire(cueID: id)
        case .fireCueIndex(let index):
            if let list = activeCueList(project: proj, engine: engine),
               list.cues.indices.contains(index) {
                engine.fire(cueID: list.cues[index].id)
            }
        case .programmerAttribute(let attr):
            let targets = orderedSelection.isEmpty ? Array(selection) : orderedSelection
            for id in targets {
                engine.programmer.set(fixtureID: id, attribute: attr, value: scalar)
            }
        case .blackout:
            engine.setBlackout(true)
        case .blackoutOff:
            engine.setBlackout(false)
        case .toggleBlackout:
            engine.toggleBlackout()
        case .freeze:
            engine.setFreeze(true)
        case .freezeOff:
            engine.setFreeze(false)
        case .toggleFreeze:
            engine.toggleFreeze()
        case .blind:
            engine.setBlind(true)
        case .blindOff:
            engine.setBlind(false)
        case .toggleBlind:
            engine.toggleBlind()
        case .masterIntensity:
            engine.setMasterIntensity(scalar)
        case .panic:
            engine.panic()
        case .clearOverrides:
            engine.clearOverrides()
        case .toggleMIDIPerformance:
            engine.toggleMIDIPerformance()
        }
    }

    /// Active playback list, falling back to first list only when nothing is loaded.
    private func activeCueList(project: ShowProject, engine: LightingEngine) -> CueList? {
        if let listID = engine.playback.snapshot().listID,
           let list = project.cueLists.first(where: { $0.id == listID }) {
            return list
        }
        return project.cueLists.first
    }
}
