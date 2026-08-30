import Foundation

/// Application-level presentation choice for Stage fixture artwork.
/// This value must never be stored in a show document.
public enum StageGlyphStyle: String, Codable, CaseIterable, Sendable, Hashable {
    case legacyV1
    case prismV3

    public var displayName: String {
        switch self {
        case .legacyV1: "Legacy V1"
        case .prismV3: "Prism V3"
        }
    }
}
