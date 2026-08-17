import Foundation

// MARK: - Dedicated color emitters (physical sources ≠ RGB wheel)

public enum ColorEmitterKind: String, Codable, Hashable, Sendable, CaseIterable {
    case red
    case green
    case blue
    case white
    case warmWhite
    case coolWhite
    case amber
    case uv
    case lime
    case cyan
    case custom

    /// Physical Programmer attribute key.
    public var attribute: String {
        switch self {
        case .red: return "colorR"
        case .green: return "colorG"
        case .blue: return "colorB"
        case .white: return "colorW"
        case .warmWhite: return "colorWarmWhite"
        case .coolWhite: return "colorCoolWhite"
        case .amber: return "colorA"
        case .uv: return "colorUV"
        case .lime: return "colorLime"
        case .cyan: return "colorCyan"
        case .custom: return "colorCustom"
        }
    }

    /// All physical light-producing emitter attributes (RGB + dedicated).
    public static var physicalEmitterAttributes: Set<String> {
        Set(ColorEmitterKind.allCases.map(\.attribute)).union(["colorC", "colorM", "colorY"])
    }

    /// RGB only.
    public static var rgbAttributes: [String] { ["colorR", "colorG", "colorB"] }

    /// Dedicated (non-RGB) physical emitters for palette capture etc.
    public static var dedicatedPhysicalAttributes: [String] {
        dedicatedUIOrder.map(\.attribute)
    }

    /// Color palette keys: authoring + physical RGB + dedicated emitters.
    public static var colorPaletteAttributeKeys: [String] {
        ColorAuthoringAttribute.all
            + rgbAttributes
            + dedicatedPhysicalAttributes
    }

    public var displayName: String {
        switch self {
        case .red: return "Red"
        case .green: return "Green"
        case .blue: return "Blue"
        case .white: return "White"
        case .warmWhite: return "Warm White"
        case .coolWhite: return "Cool White"
        case .amber: return "Amber"
        case .uv: return "UV"
        case .lime: return "Lime"
        case .cyan: return "Cyan"
        case .custom: return "Custom"
        }
    }

    /// Canonical fader column order (spec §15).
    public static let dedicatedUIOrder: [ColorEmitterKind] = [
        .white, .warmWhite, .coolWhite, .amber, .lime, .cyan, .uv,
    ]

    /// Primary production faders (v1 UI).
    public static let primaryDedicated: [ColorEmitterKind] = [.white, .amber, .uv]

    public static func kind(forAttribute attribute: String) -> ColorEmitterKind? {
        switch attribute {
        case "colorW": return .white
        case "colorWarmWhite", "colorWW": return .warmWhite
        case "colorCoolWhite", "colorCW": return .coolWhite
        case "colorA": return .amber
        case "colorUV": return .uv
        case "colorLime": return .lime
        case "colorCyan": return .cyan
        case "colorR": return .red
        case "colorG": return .green
        case "colorB": return .blue
        default: return nil
        }
    }

    public static func isPhysicalEmitter(_ attribute: String) -> Bool {
        if ColorAuthoringAttribute.isAuthoring(attribute) { return false }
        if physicalEmitterAttributes.contains(attribute) { return true }
        // Multi-cell: colorR@0 etc.
        let base = attribute.split(separator: "@").first.map(String.init) ?? attribute
        return physicalEmitterAttributes.contains(base)
    }
}

public enum EmitterAccent: Equatable, Sendable {
    case white
    case amber
    case uv
    case neutral

    public static func forKind(_ kind: ColorEmitterKind) -> EmitterAccent {
        switch kind {
        case .white, .warmWhite, .coolWhite: return .white
        case .amber: return .amber
        case .uv: return .uv
        default: return .neutral
        }
    }
}
