import AuroraACP
import CryptoKit
import Foundation

/// Per-connection state owned by Prism. Remote role claims are deliberately not stored here.
struct PrismACPRemoteContext: Sendable {
    var helloCompleted = false
    var principalNodeID = ""
    var principalInstanceID = ""
    var layoutDelivered = false
    var layoutActivated = false
    var clientCapabilities: Set<String> = []
    var subscribedResources: Set<String>?
    var snapshotDeliveredRevision: UInt64?
    var ready = false
}

public enum PrismACPRemoteProfile {
    static let permissionsRevision: UInt64 = 3
    static let surfaceRevision: UInt64 = 1
    static let viewerRoles: AnySendable = .array([.string("remote.viewer")])

    public static func stableUUID(seed: String) -> String {
        if let uuid = UUID(uuidString: seed) { return uuid.uuidString.lowercased() }
        let hex = SHA256.hash(data: Data(seed.utf8)).map { String(format: "%02x", $0) }.joined()
        return "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20).prefix(12))"
    }

    static func showID(for state: PrismACPAuthoritativeState?) -> String {
        stableUUID(seed: state?.showID ?? "prism.unloaded-show")
    }

    static func surfaceID(for state: PrismACPAuthoritativeState?) -> String {
        stableUUID(seed: "prism.remote.surface:\(showID(for: state))")
    }

    static func permissionsPayload(
        operatorEnabled: Bool = false,
        blackoutClearEnabled: Bool = false
    ) -> [String: AnySendable] {
        [
            "roles": operatorEnabled
                ? .array([.string("remote.viewer"), .string("remote.operator")])
                : viewerRoles,
            "permissions": operatorEnabled
                ? .array([
                    .string("observe"), .string("remote.surface.use"),
                    .string("cue.execute"), .string("output.grand_master"),
                    .string("output.blackout.engage"),
                ] + (blackoutClearEnabled ? [.string("output.blackout.clear")] : []))
                : .array([.string("observe"), .string("remote.surface.use")]),
            "revision": .uint(permissionsRevision),
        ]
    }

    static func layout(
        for state: PrismACPAuthoritativeState?,
        mutationsEnabled: Bool,
        blackoutClearEnabled: Bool = false
    ) -> [String: AnySendable] {
        let showID = showID(for: state)
        let revision = surfaceRevision
        let enabled = mutationsEnabled
        let controls: [AnySendable] = [
            control("cue_go", label: "GO", action: "cue.go", permission: "cue.execute", enabled: enabled),
            control(
                "grand_master",
                label: "Grand Master",
                type: "fader",
                action: "output.grand_master.set",
                permission: "output.grand_master",
                enabled: enabled,
                minimum: 0,
                maximum: 1,
                step: 0.01,
                delivery: "latest_value_wins",
                updateMode: "continuous"
            ),
            control(
                "blackout",
                label: "Blackout",
                type: "toggle",
                action: "output.blackout.set",
                permission: "output.blackout.engage",
                enabled: enabled,
                delivery: "latest_value_wins",
                safety: ["class": .string("dangerous"), "confirm": .string("explicit")]
            ),
        ]
        return [
            "surface_id": .string(surfaceID(for: state)),
            "revision": .uint(revision),
            "show_id": .string(showID),
            "show_revision": .uint(state?.revision ?? 0),
            "name": .string("\(state?.showName.isEmpty == false ? state!.showName : "Untitled") Remote"),
            "schema_version": .string("1.0"),
            "compatible_profile": .string("aurora.remote.prism.v1"),
            "asset_type": .string("aurora.remote.surface"),
            "pages": .array([.object([
                "page_id": .string("show-control"),
                "title": .string("Show Control"),
                "order": .uint(0),
                "groups": .array([.object([
                    "group_id": .string("transport"),
                    "title": .string("Transport"),
                    "order": .uint(0),
                    "controls": .array([
                        "cue_go", "grand_master", "blackout",
                    ].map(AnySendable.string)),
                ])]),
            ])]),
            "controls": .array(controls),
        ]
    }

    static func layoutHash(_ layout: [String: AnySendable]) -> String {
        let object = layout.reduce(into: [String: Any]()) { result, item in
            guard item.key != "sha256" else { return }
            result[item.key] = foundationValue(item.value)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func layoutData(_ layout: [String: AnySendable]) -> Data? {
        let object = layout.reduce(into: [String: Any]()) { result, item in
            guard item.key != "sha256" else { return }
            result[item.key] = foundationValue(item.value)
        }
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func controlSnapshot(
        for state: PrismACPAuthoritativeState?,
        mutationsEnabled: Bool,
        blackoutClearEnabled: Bool = false,
        momentaryHolds: [PrismACPMomentaryHold] = []
    ) -> [String: AnySendable] {
        let revision = state?.revision ?? 0
        let available = mutationsEnabled && state?.showName.isEmpty == false
        func item(
            _ id: String,
            actionAvailable: Bool = true,
            unavailableReason: String = "no next cue",
            value: AnySendable? = nil,
            confidence: String = "confirmed"
        ) -> AnySendable {
            let controlAvailable = available && actionAvailable
            var payload: [String: AnySendable] = [
                "control_id": .string(id),
                "revision": .uint(revision),
                "enabled": .bool(controlAvailable),
                "available": .bool(controlAvailable),
                "confidence": .string(confidence),
            ]
            if let value { payload["value"] = value }
            if !controlAvailable {
                payload["reason"] = .string(
                    !available ? (mutationsEnabled ? "no show loaded" : "view-only policy") : unavailableReason
                )
            }
            return .object(payload)
        }
        return [
            "controls": .array([
                item("cue_go"),
                item("grand_master", value: state.map { .double($0.masterIntensity) }),
                item(
                    "blackout",
                    actionAvailable: state?.blackout == true ? blackoutClearEnabled : true,
                    unavailableReason: "blackout clear not authorized",
                    value: .bool(state?.blackout ?? false)
                ),
            ]),
            "snapshot_revision": .uint(revision),
        ]
    }

    /// Typed AuroraACP representation of the exact surface Prism publishes.
    /// Control execution resolves through this model instead of maintaining a
    /// second control-ID switch in the service.
    static func executionLayout(
        for state: PrismACPAuthoritativeState?,
        mutationsEnabled: Bool,
        blackoutClearEnabled: Bool = false
    ) -> ACPRemoteLayout {
        let payload = layout(
            for: state,
            mutationsEnabled: mutationsEnabled,
            blackoutClearEnabled: blackoutClearEnabled
        )
        let controls: [ACPRemoteControl]
        if case .array(let encoded) = payload["controls"] {
            controls = encoded.compactMap { value in
                guard case .object(let definition) = value,
                      case .string(let controlID) = definition["control_id"],
                      case .string(let label) = definition["label"],
                      case .string(let controlType) = definition["control_type"],
                      case .string(let permission) = definition["permission"],
                      case .object(let binding) = definition["binding"],
                      case .string(let action) = binding["action"]
                else { return nil }
                let failsafe: String
                let maxHoldMS: UInt64
                if case .object(let safety) = definition["safety"] {
                    if case .string(let value) = safety["failsafe"] { failsafe = value } else { failsafe = "release_on_disconnect" }
                    switch safety["max_hold_ms"] {
                    case .uint(let value): maxHoldMS = value
                    case .int(let value) where value >= 0: maxHoldMS = UInt64(value)
                    default: maxHoldMS = 10_000
                    }
                } else {
                    failsafe = "release_on_disconnect"
                    maxHoldMS = 10_000
                }
                return ACPRemoteControl(
                    controlID: controlID,
                    label: label,
                    controlType: controlType,
                    permission: permission,
                    action: action,
                    failsafe: failsafe,
                    maxHoldMs: maxHoldMS
                )
            }
        } else {
            controls = []
        }
        return ACPRemoteLayout(
            layoutID: surfaceID(for: state),
            revision: surfaceRevision,
            showID: showID(for: state),
            name: state?.showName ?? "Untitled",
            controls: controls
        )
    }

    private static func momentaryValue(_ holds: [PrismACPMomentaryHold]) -> AnySendable {
        let relevant = holds.filter { $0.controlID == "lease_test" }
        let active = relevant.contains { $0.physicalActive != false }
        let releasePending = relevant.contains { $0.releasePending }
        return .object([
            "active": .bool(active),
            "release_pending": .bool(releasePending),
            "physical_active": .bool(active),
        ])
    }

    private static func control(
        _ id: String,
        label: String,
        type: String = "button",
        action: String,
        permission: String,
        enabled: Bool,
        parameters: [String: AnySendable]? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil,
        step: Double? = nil,
        delivery: String? = nil,
        updateMode: String? = nil,
        safety: [String: AnySendable]? = nil
    ) -> AnySendable {
        var binding: [String: AnySendable] = ["target": .string("prism"), "action": .string(action)]
        if let parameters { binding["parameters"] = .object(parameters) }
        var definition: [String: AnySendable] = [
            "control_id": .string(id),
            "label": .string(label),
            "accessibility_label": .string(label),
            "control_type": .string(type),
            "permission": .string(permission),
            "enabled": .bool(enabled),
            "visible": .bool(true),
            "feedback": .string("state"),
            "binding": .object(binding),
        ]
        if let minimum { definition["min"] = .double(minimum) }
        if let maximum { definition["max"] = .double(maximum) }
        if let step { definition["step"] = .double(step) }
        if let delivery { definition["delivery"] = .string(delivery) }
        if let updateMode { definition["update_mode"] = .string(updateMode) }
        if let safety { definition["safety"] = .object(safety) }
        return .object(definition)
    }

    private static func foundationValue(_ value: AnySendable) -> Any {
        switch value {
        case .null: return NSNull()
        case .bool(let value): return value
        case .int(let value): return NSNumber(value: value)
        case .uint(let value): return NSNumber(value: value)
        case .double(let value): return NSNumber(value: value)
        case .string(let value): return value
        case .bytes(let value): return value.base64EncodedString()
        case .array(let values): return values.map(foundationValue)
        case .object(let values): return values.mapValues(foundationValue)
        }
    }
}
