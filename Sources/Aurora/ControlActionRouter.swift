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

/// Unified show-control dispatcher for MIDI / OSC / UI / remote (P1-9).
///
/// Live paths avoid MainActor. `fireCueIndex` targets the **active** playback list,
/// not `cueLists.first`.
final class ControlActionRouter: @unchecked Sendable {
    private let lock = NSLock()
    private weak var engine: LightingEngine?
    private var mappings: [MIDIMapping] = []
    private var project: ShowProject = .empty()
    private var selectedFixtureIDs: Set<UUID> = []
    private var orderedFixtureIDs: [UUID] = []
    private var onUINotify: (@Sendable (ShowAction, String) -> Void)?

    init(engine: LightingEngine) {
        self.engine = engine
    }

    func setUINotify(_ handler: @escaping @Sendable (ShowAction, String) -> Void) {
        lock.lock()
        onUINotify = handler
        lock.unlock()
    }

    func updateMappings(_ mappings: [MIDIMapping], project: ShowProject) {
        lock.lock()
        self.mappings = mappings
        self.project = project
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
        let eng = engine
        let notify = onUINotify
        let selection = selectedFixtureIDs
        let ordered = orderedFixtureIDs
        let proj = project
        lock.unlock()
        guard let eng else { return }

        for event in events {
            let control = MIDIActionResolver.controlValue(for: event)
            let actions = MIDIActionResolver.matchAll(event: event, mappings: maps)
            for action in actions {
                applyLive(
                    action,
                    engine: eng,
                    project: proj,
                    control: control,
                    selection: selection,
                    orderedSelection: ordered
                )
                notify?(action, event.summary)
            }
        }
    }

    /// Dispatch a show action from any control surface (MIDI/OSC/UI/remote).
    func dispatch(
        _ action: ShowAction,
        control: MIDIControlValue? = nil,
        midiValue: UInt8? = nil
    ) {
        lock.lock()
        let eng = engine
        let proj = project
        let selection = selectedFixtureIDs
        let ordered = orderedFixtureIDs
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
