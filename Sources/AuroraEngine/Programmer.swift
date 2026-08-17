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
        attrs[attribute] = ColorMath.clampProgrammerAttribute(attribute, value: value)
        state.values[fixtureID] = attrs
        lock.unlock()
    }

    /// Batch set one attribute across fixtures (e.g. fan/align results).
    public func setMany(attribute: String, values: [UUID: Double]) {
        var batch: [UUID: [String: Double]] = [:]
        for (fixtureID, value) in values {
            batch[fixtureID] = [attribute: value]
        }
        setMany(batch)
    }

    /// Single-lock multi-fixture multi-attribute write (UI-03 Pass 2 color batching).
    public func setMany(_ values: [UUID: [String: Double]]) {
        guard !values.isEmpty else { return }
        lock.lock()
        for (fixtureID, attrs) in values {
            var merged = state.values[fixtureID] ?? [:]
            for (attribute, value) in attrs {
                merged[attribute] = ColorMath.clampProgrammerAttribute(attribute, value: value)
            }
            state.values[fixtureID] = merged
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

    /// Home: apply personality default/home values from the compiled show (P1-2).
    public func home(fixtureIDs: Set<UUID>, compiled: CompiledShow) {
        lock.lock()
        for id in fixtureIDs {
            if let fixture = compiled.fixtures.first(where: { $0.id == id }) {
                state.values[id] = fixture.homeValues
            } else {
                state.values[id] = nil
            }
        }
        lock.unlock()
    }

    /// Convenience: compile project then home.
    public func home(fixtureIDs: Set<UUID>, project: ShowProject) {
        home(fixtureIDs: fixtureIDs, compiled: .compile(project))
    }

    /// Legacy clear-only home (no personality defaults). Prefer `home(fixtureIDs:compiled:)`.
    public func home(fixtureIDs: Set<UUID>) {
        clear(fixtureIDs: fixtureIDs)
    }

    /// Locate: personality highlight for beam/color + centered pan/tilt when present (P1-2).
    public func locate(fixtureIDs: Set<UUID>, compiled: CompiledShow) {
        lock.lock()
        for id in fixtureIDs {
            guard let fixture = compiled.fixtures.first(where: { $0.id == id }) else { continue }
            var attrs = fixture.homeValues
            let attrsPresent = Set(fixture.attributeWrites.map(\.attribute))
            for (attribute, value) in fixture.highlightValues {
                if attribute == "intensity"
                    || attribute == "shutter"
                    || attribute.hasPrefix("color")
                    || attribute == "iris"
                    || attribute == "zoom"
                    || attribute == "focus" {
                    attrs[attribute] = value
                }
            }
            if attrsPresent.contains("pan") { attrs["pan"] = 0.5 }
            if attrsPresent.contains("tilt") { attrs["tilt"] = 0.5 }
            // Ensure intensity is open if personality has it but no highlight entry.
            if attrsPresent.contains("intensity"), attrs["intensity"] == nil {
                attrs["intensity"] = 1
            }
            state.values[id] = attrs
        }
        lock.unlock()
    }

    public func locate(fixtureIDs: Set<UUID>, project: ShowProject) {
        locate(fixtureIDs: fixtureIDs, compiled: .compile(project))
    }

    /// Set a wheel attribute from a personality slot's DMX value (normalized 0…1).
    @discardableResult
    public func setWheelSlot(
        fixtureID: UUID,
        wheelKind: WheelKind,
        slotIndex: UInt16,
        project: ShowProject
    ) -> Bool {
        guard let fixture = project.fixtures.first(where: { $0.id == fixtureID }),
              let definition = project.definition(id: fixture.definitionId),
              let wheel = definition.wheels.first(where: { $0.kind == wheelKind }),
              let slot = wheel.slots.first(where: { $0.index == slotIndex }),
              let dmx = slot.dmxValue
        else { return false }

        // Prefer a channel whose name/attribute matches the wheel; fall back to common tags.
        let attribute = Self.wheelAttributeName(wheel: wheel, definition: definition)
        set(fixtureID: fixtureID, attribute: attribute, value: Double(dmx) / 255.0)
        return true
    }

    private static func wheelAttributeName(wheel: WheelDef, definition: FixtureDefinition) -> String {
        let candidates = [
            wheel.name.lowercased(),
            wheel.kind == .color ? "colorWheel" : "goboWheel",
            wheel.kind == .color ? "color" : "gobo",
        ]
        for channel in definition.channels {
            let attr = channel.attribute.lowercased()
            let name = channel.name.lowercased()
            if candidates.contains(where: { attr.contains($0) || name.contains($0) }) {
                return channel.attribute
            }
        }
        // Last resort: first control-like channel or synthetic attribute from wheel name.
        return wheel.kind == .color ? "colorWheel" : "goboWheel"
    }

    public func captureLevels() -> CueLevelData {
        lock.lock()
        defer { lock.unlock() }
        let fixtures = state.values.map { FixtureCueLevels(fixtureId: $0.key, attributes: $0.value) }
        return CueLevelData(fixtures: fixtures)
    }

    /// Applies programmer (and highlight) on top of a playback look for output.
    public func apply(onPlayback playback: ActiveLook, project: ShowProject) -> ActiveLook {
        apply(onPlayback: playback, compiled: .compile(project))
    }

    public func apply(onPlayback playback: ActiveLook, compiled: CompiledShow) -> ActiveLook {
        lock.lock()
        let state = self.state
        lock.unlock()

        if state.isBlind {
            // Blind: programmer does not hit output. Highlight may still apply.
            if state.isHighlight {
                return applyHighlight(on: playback, selection: state.highlightSelection, compiled: compiled)
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
            look = applyHighlight(on: look, selection: state.highlightSelection, compiled: compiled)
        }
        return look
    }

    private func applyHighlight(
        on look: ActiveLook,
        selection: Set<UUID>,
        compiled: CompiledShow
    ) -> ActiveLook {
        var result = look
        for id in selection {
            guard let fixture = compiled.fixtures.first(where: { $0.id == id }) else { continue }
            var attrs = result.fixtureAttributes[id] ?? [:]
            // Personality highlight values (P1-2); fall back to full open for common beam attrs.
            if fixture.highlightValues.isEmpty {
                let tags = Set(fixture.attributeWrites.map(\.attribute))
                if tags.contains("intensity") { attrs["intensity"] = 1 }
                if tags.contains("colorR") { attrs["colorR"] = 1 }
                if tags.contains("colorG") { attrs["colorG"] = 1 }
                if tags.contains("colorB") { attrs["colorB"] = 1 }
                if tags.contains("colorW") { attrs["colorW"] = 1 }
            } else {
                for (attribute, value) in fixture.highlightValues {
                    attrs[attribute] = value
                }
            }
            result.fixtureAttributes[id] = attrs
        }
        return result
    }
}
