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

/// Thread-safe live show action dispatcher (P1-1).
/// MIDI/OSC hot paths call here without waiting on MainActor.
final class ControlActionRouter: @unchecked Sendable {
    private let lock = NSLock()
    private weak var engine: LightingEngine?
    private var mappings: [MIDIMapping] = []
    private var project: ShowProject = .empty()
    private var selectedFixtureIDs: Set<UUID> = []
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
        lock.unlock()
    }

    /// Called from MIDI callback thread (not MainActor).
    func handleMIDIEvents(_ events: [MIDIEvent]) {
        lock.lock()
        let maps = mappings
        let eng = engine
        let notify = onUINotify
        let selection = selectedFixtureIDs
        lock.unlock()
        guard let eng else { return }

        for event in events {
            if let action = MIDIActionResolver.match(event: event, mappings: maps) {
                applyLive(action, engine: eng, midiValue: ccValue(event), selection: selection)
                notify?(action, event.summary)
            }
        }
    }

    /// Live actions that must not require MainActor.
    func applyLive(
        _ action: ShowAction,
        engine: LightingEngine,
        midiValue: UInt8? = nil,
        selection: Set<UUID> = []
    ) {
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
            lock.lock()
            let list = project.cueLists.first
            lock.unlock()
            if let list, list.cues.indices.contains(index) {
                engine.fire(cueID: list.cues[index].id)
            }
        case .programmerAttribute(let attr):
            let value = MIDIActionResolver.ccNormalized(midiValue ?? 0)
            for id in selection {
                engine.programmer.set(fixtureID: id, attribute: attr, value: value)
            }
        }
    }

    private func ccValue(_ event: MIDIEvent) -> UInt8? {
        if case .controlChange(_, _, let v, _) = event { return v }
        return nil
    }
}
