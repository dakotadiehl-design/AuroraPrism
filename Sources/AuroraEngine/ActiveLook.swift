import Foundation

/// Sparse live look applied by the PR10 merge stub (single layer; no multi-source HTP yet).
///
/// Attribute values are **normalized 0.0…1.0** and scaled to 0…255 for 8-bit channels.
public struct ActiveLook: Equatable, Sendable {
    /// fixtureId → attribute tag → normalized value
    public var fixtureAttributes: [UUID: [String: Double]]

    public init(fixtureAttributes: [UUID: [String: Double]] = [:]) {
        self.fixtureAttributes = fixtureAttributes
    }

    public static let empty = ActiveLook()

    public mutating func set(fixtureID: UUID, attribute: String, value: Double) {
        var attrs = fixtureAttributes[fixtureID] ?? [:]
        attrs[attribute] = min(1, max(0, value))
        fixtureAttributes[fixtureID] = attrs
    }
}
