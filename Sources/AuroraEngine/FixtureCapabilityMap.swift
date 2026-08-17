import AuroraModel
import Foundation

/// Authoritative fixture capability sets for Cue Block filtering and related engine paths.
///
/// Reuses `ProgrammerAttributePresentationResolver` physical/effective capability rules
/// (virtual intensity, soft HSV eligibility via RGB support).
public enum FixtureCapabilityMap {
    /// Effective capability map for every fixture in the project (includes virtual intensity when applicable).
    public static func build(from project: ShowProject) -> [UUID: Set<String>] {
        let ids = project.fixtures.map(\.id)
        return ProgrammerAttributePresentationResolver.capabilityMap(
            orderedFixtureIDs: ids,
            project: project
        )
    }

    /// Effective capability map for a subset of fixtures (missing fixtures → empty set).
    public static func build(from project: ShowProject, fixtureIDs: [UUID]) -> [UUID: Set<String>] {
        ProgrammerAttributePresentationResolver.capabilityMap(
            orderedFixtureIDs: fixtureIDs,
            project: project
        )
    }

    /// Filter attributes to those supported by a fixture, applying soft-authoring HSV rules.
    public static func filterAttributes(
        _ attributes: [String: Double],
        supported: Set<String>
    ) -> (kept: [String: Double], dropped: [String]) {
        let rgbOK = ProgrammerAttributePresentationResolver.supportsRGBAuthoring(supported)
        var kept: [String: Double] = [:]
        var dropped: [String] = []
        for (key, value) in attributes {
            let capable: Bool
            if CueBlockAttributeFamily.softAuthoringColorTags.contains(key) {
                capable = rgbOK
            } else if key == "intensity" || key == "dimmer" || key == "dim" {
                capable = supported.contains("intensity")
                    || supported.contains("dimmer")
                    || supported.contains("dim")
                    || supported.contains(key)
            } else {
                capable = supported.contains(key)
                    || supported.contains(CueBlockAttributeFamily.baseAttribute(key))
            }
            if capable {
                kept[key] = value
            } else {
                dropped.append(key)
            }
        }
        return (kept, dropped.sorted())
    }
}
