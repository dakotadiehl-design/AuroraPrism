import AuroraModel
import Foundation

public struct ProgrammerState: Equatable, Sendable {
    public var values: [UUID: [String: Double]]
    public var isBlind: Bool
    public var isHighlight: Bool
    public var highlightSelection: Set<UUID>

    public init(
        values: [UUID: [String: Double]] = [:],
        isBlind: Bool = false,
        isHighlight: Bool = false,
        highlightSelection: Set<UUID> = []
    ) {
        self.values = values
        self.isBlind = isBlind
        self.isHighlight = isHighlight
        self.highlightSelection = highlightSelection
    }

    public static let empty = ProgrammerState()
}

/// Live programmer layer above playback (temp values, blind, highlight, locate, home).
public final class Programmer: @unchecked Sendable {
    private let lock = NSLock()
    private var state = ProgrammerState()

    public init() {}

    public func snapshot() -> ProgrammerState {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    public func set(fixtureID: UUID, attribute: String, value: Double) {
        lock.lock()
        var attrs = state.values[fixtureID] ?? [:]
        attrs[attribute] = min(1, max(0, value))
        state.values[fixtureID] = attrs
        lock.unlock()
    }

    /// Batch set one attribute across fixtures (e.g. fan/align results).
    public func setMany(attribute: String, values: [UUID: Double]) {
        lock.lock()
        for (fixtureID, value) in values {
            var attrs = state.values[fixtureID] ?? [:]
            attrs[attribute] = min(1, max(0, value))
            state.values[fixtureID] = attrs
        }
        lock.unlock()
    }

    public func clear(fixtureIDs: Set<UUID>) {
        lock.lock()
        for id in fixtureIDs {
            state.values[id] = nil
        }
        lock.unlock()
    }

    public func clearAll() {
        lock.lock()
        state.values = [:]
        lock.unlock()
    }

    public func setBlind(_ blind: Bool) {
        lock.lock()
        state.isBlind = blind
        lock.unlock()
    }

    public func setHighlight(_ on: Bool) {
        lock.lock()
        state.isHighlight = on
        lock.unlock()
    }

    public func setHighlightSelection(_ ids: Set<UUID>) {
        lock.lock()
        state.highlightSelection = ids
        lock.unlock()
    }

    public func home(fixtureIDs: Set<UUID>) {
        clear(fixtureIDs: fixtureIDs)
    }

    /// Locate: intensity full, pan/tilt center when those attributes exist on the definition.
    public func locate(fixtureIDs: Set<UUID>, project: ShowProject) {
        lock.lock()
        for id in fixtureIDs {
            guard let fixture = project.fixtures.first(where: { $0.id == id }),
                  let definition = project.definition(id: fixture.definitionId)
            else { continue }
            var attrs = state.values[id] ?? [:]
            let tags = Set(definition.channels.map(\.attribute))
            if tags.contains("intensity") { attrs["intensity"] = 1 }
            if tags.contains("pan") { attrs["pan"] = 0.5 }
            if tags.contains("tilt") { attrs["tilt"] = 0.5 }
            state.values[id] = attrs
        }
        lock.unlock()
    }

    public func captureLevels() -> CueLevelData {
        lock.lock()
        defer { lock.unlock() }
        let fixtures = state.values.map { FixtureCueLevels(fixtureId: $0.key, attributes: $0.value) }
        return CueLevelData(fixtures: fixtures)
    }

    /// Applies programmer (and highlight) on top of a playback look for output.
    public func apply(onPlayback playback: ActiveLook, project: ShowProject) -> ActiveLook {
        lock.lock()
        let state = self.state
        lock.unlock()

        if state.isBlind {
            // Still allow highlight to affect output while blind? Spec: blind = programmer does not hit output.
            // Highlight is separate override above programmer — apply highlight only if on.
            if state.isHighlight {
                return applyHighlight(on: playback, selection: state.highlightSelection, project: project)
            }
            return playback
        }

        var look = playback
        for (fixtureID, attrs) in state.values {
            var existing = look.fixtureAttributes[fixtureID] ?? [:]
            for (key, value) in attrs {
                existing[key] = value
            }
            look.fixtureAttributes[fixtureID] = existing
        }

        if state.isHighlight {
            look = applyHighlight(on: look, selection: state.highlightSelection, project: project)
        }
        return look
    }

    private func applyHighlight(on look: ActiveLook, selection: Set<UUID>, project: ShowProject) -> ActiveLook {
        var result = look
        for id in selection {
            guard let fixture = project.fixtures.first(where: { $0.id == id }),
                  let definition = project.definition(id: fixture.definitionId)
            else { continue }
            var attrs = result.fixtureAttributes[id] ?? [:]
            let tags = Set(definition.channels.map(\.attribute))
            if tags.contains("intensity") { attrs["intensity"] = 1 }
            if tags.contains("colorR") { attrs["colorR"] = 1 }
            if tags.contains("colorG") { attrs["colorG"] = 1 }
            if tags.contains("colorB") { attrs["colorB"] = 1 }
            if tags.contains("colorW") { attrs["colorW"] = 1 }
            result.fixtureAttributes[id] = attrs
        }
        return result
    }
}
