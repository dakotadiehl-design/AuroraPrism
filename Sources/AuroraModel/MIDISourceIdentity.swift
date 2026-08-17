import Foundation

/// Canonical MIDI source identity strings shared by CoreMIDI ingress and AME bindings.
///
/// Production CoreMIDI endpoints use `uid:<UniqueID>`. Name-based fallbacks are secondary
/// and must not defeat UniqueID matching when a stable ID is configured.
public enum MIDISourceIdentity {
    public static func coreMIDIUniqueID(_ id: Int32) -> String {
        "uid:\(id)"
    }

    public static func parseCoreMIDIUniqueID(_ sourceID: String) -> Int32? {
        guard sourceID.hasPrefix("uid:") else { return nil }
        return Int32(sourceID.dropFirst(4))
    }

    public static func endpointRef(_ endpoint: UInt32) -> String {
        "ep:\(endpoint)"
    }

    public static func parseEndpointRef(_ sourceID: String) -> UInt32? {
        guard sourceID.hasPrefix("ep:") else { return nil }
        return UInt32(sourceID.dropFirst(3))
    }

    /// Match a live source ID against a persisted binding.
    /// Prefer UniqueID when configured; otherwise name/hint/uuid fallbacks.
    public static func matches(sourceID: String, binding: MIDISourceBinding) -> Bool {
        if let uid = binding.lastCoreMIDIUniqueID {
            return sourceID == coreMIDIUniqueID(uid) || sourceID == binding.id.uuidString
        }
        if sourceID == binding.id.uuidString { return true }
        if let hint = binding.endpointNameHint, !hint.isEmpty, sourceID == hint { return true }
        if !binding.displayName.isEmpty, sourceID == binding.displayName { return true }
        if let model = binding.modelHint, !model.isEmpty, sourceID == model { return true }
        return false
    }

    /// Lightweight inventory row for binding resolution (decoupled from CoreMIDI types).
    public struct InventorySource: Equatable, Sendable {
        public var id: String
        public var name: String
        public var manufacturer: String

        public init(id: String, name: String, manufacturer: String = "") {
            self.id = id
            self.name = name
            self.manufacturer = manufacturer
        }
    }

    public enum BindingResolution: Equatable, Sendable {
        /// Canonical live ID (`uid:…` / `ep:…`) ready for adapter/engine admission.
        case resolved(canonicalSourceID: String)
        case unresolved
        case ambiguous(candidateIDs: [String])
    }

    /// Resolve a persisted binding against the current live inventory.
    ///
    /// Rules:
    /// 1. UniqueID match first (when binding stores a UID).
    /// 2. Else match inventory by endpoint name / manufacturer / model hints.
    /// 3. Use the inventory row's canonical `id` for runtime admission.
    /// 4. Zero matches → unresolved; multiple distinct IDs → ambiguous.
    public static func resolve(
        binding: MIDISourceBinding,
        inventory: [InventorySource]
    ) -> BindingResolution {
        if let uid = binding.lastCoreMIDIUniqueID {
            let canonical = coreMIDIUniqueID(uid)
            if inventory.contains(where: { $0.id == canonical }) {
                return .resolved(canonicalSourceID: canonical)
            }
            // UID configured but not currently present — still prefer canonical form
            // so a reconnect with the same UniqueID admits immediately.
            return .resolved(canonicalSourceID: canonical)
        }

        var matches: [InventorySource] = []
        for source in inventory {
            if hintMatches(binding: binding, source: source) {
                matches.append(source)
            }
        }
        let uniqueIDs = Array(Set(matches.map(\.id))).sorted()
        switch uniqueIDs.count {
        case 0:
            return .unresolved
        case 1:
            return .resolved(canonicalSourceID: uniqueIDs[0])
        default:
            return .ambiguous(candidateIDs: uniqueIDs)
        }
    }

    private static func hintMatches(binding: MIDISourceBinding, source: InventorySource) -> Bool {
        let name = source.name
        if let hint = binding.endpointNameHint, !hint.isEmpty, namesEqual(hint, name) {
            return true
        }
        if !binding.displayName.isEmpty, namesEqual(binding.displayName, name) {
            return true
        }
        if let model = binding.modelHint, !model.isEmpty,
           name.localizedCaseInsensitiveContains(model) {
            return true
        }
        if let mfg = binding.manufacturerHint, !mfg.isEmpty,
           !source.manufacturer.isEmpty,
           namesEqual(mfg, source.manufacturer) {
            // Manufacturer alone is weak; only count when name also matches a hint.
            if let hint = binding.endpointNameHint, !hint.isEmpty, namesEqual(hint, name) {
                return true
            }
            if !binding.displayName.isEmpty, namesEqual(binding.displayName, name) {
                return true
            }
        }
        return false
    }

    private static func namesEqual(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(b.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    /// Result of attempting to build a durable Learn binding.
    public enum DurableBindingResult: Equatable, Sendable {
        case binding(MIDISourceBinding)
        /// Non-UID source with no usable inventory name/manufacturer — do not commit.
        case unavailable(reason: String)
    }

    /// Build a durable `MIDISourceBinding` from a live runtime source ID + optional inventory row.
    ///
    /// Rules:
    /// - Prefer CoreMIDI UniqueID when the runtime ID is `uid:…` (UID alone is durable).
    /// - Persist friendly endpoint **name** / manufacturer from inventory, never `ep:…` as a name hint.
    /// - `ep:…` without inventory name is **not** durable — returns `.unavailable` (do not invent "MIDI Source").
    public static func makeDurableBinding(
        runtimeSourceID: String,
        inventory: InventorySource? = nil
    ) -> DurableBindingResult {
        guard !runtimeSourceID.isEmpty else {
            return .unavailable(reason: "empty source ID")
        }

        let manufacturer = inventory.flatMap { $0.manufacturer.isEmpty ? nil : $0.manufacturer }
        let inventoryName = inventory.flatMap { $0.name.isEmpty ? nil : $0.name }

        if let uid = parseCoreMIDIUniqueID(runtimeSourceID) {
            let friendly = inventoryName ?? "MIDI Source \(uid)"
            return .binding(MIDISourceBinding(
                displayName: friendly,
                lastCoreMIDIUniqueID: uid,
                manufacturerHint: manufacturer,
                endpointNameHint: inventoryName
            ))
        }

        // Non-UID path: require a real endpoint name — never store ep: as a name hint.
        if parseEndpointRef(runtimeSourceID) != nil {
            guard let name = inventoryName else {
                return .unavailable(
                    reason: "ep: source has no inventory name; cannot create durable binding"
                )
            }
            return .binding(MIDISourceBinding(
                displayName: name,
                lastCoreMIDIUniqueID: nil,
                manufacturerHint: manufacturer,
                endpointNameHint: name
            ))
        }

        // Legacy free-form source ID string (not uid:/ep:) — treat as durable name.
        return .binding(MIDISourceBinding(
            displayName: runtimeSourceID,
            lastCoreMIDIUniqueID: nil,
            manufacturerHint: manufacturer,
            endpointNameHint: runtimeSourceID
        ))
    }
}
