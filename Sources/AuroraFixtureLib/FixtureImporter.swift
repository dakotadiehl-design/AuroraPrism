import AuroraModel
import Foundation

public enum FixtureImportFormat: String, Sendable {
    case nativeAurora
    case oflLite
}

public enum FixtureImportError: Error, Equatable, Sendable {
    case unsupportedFormat(String)
    case decodingFailed(String)
    case validationFailed(String)
    case emptyModes
}

/// Imports external personality descriptions into `FixtureDefinition` (PR28).
public enum FixtureImporter {
    /// Auto-detect format and import the first definition (OFL-lite may yield one mode).
    public static func importDefinitions(from data: Data) throws -> [FixtureDefinition] {
        // Prefer native if it decodes as FixtureDefinition with channels.
        if let native = try? JSONDecoder().decode(FixtureDefinition.self, from: data),
           !native.channels.isEmpty {
            try FixtureDefinitionValidation.validate(native)
            return [native]
        }
        if let ofl = try? JSONDecoder().decode(OFLLiteFixture.self, from: data) {
            return try ofl.toDefinitions()
        }
        throw FixtureImportError.unsupportedFormat("unrecognized JSON fixture format")
    }

    public static func importDefinitions(from url: URL) throws -> [FixtureDefinition] {
        let data = try Data(contentsOf: url)
        return try importDefinitions(from: data)
    }

    /// Map human channel labels to Aurora attribute tags.
    public static func attribute(forChannelName name: String) -> String {
        let n = name.lowercased()
        if n.contains("dimmer") || n == "intensity" || n == "dim" || n == "master" {
            return "intensity"
        }
        if n == "red" || n == "r" || n.contains("red") { return "colorR" }
        if n == "green" || n == "g" || n.contains("green") { return "colorG" }
        if n == "blue" || n == "b" || n.contains("blue") { return "colorB" }
        if n == "white" || n == "w" || n.contains("white") { return "colorW" }
        if n.contains("amber") { return "colorA" }
        if n.contains("pan") { return "pan" }
        if n.contains("tilt") { return "tilt" }
        if n.contains("zoom") { return "zoom" }
        if n.contains("focus") { return "focus" }
        if n.contains("gobo") { return "gobo" }
        if n.contains("shutter") || n.contains("strobe") { return "shutter" }
        // Stable fallback from sanitized name
        let sanitized = n
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
        return sanitized.isEmpty ? "channel" : sanitized
    }
}

// MARK: - OFL-lite

/// Simplified Open Fixture Library–inspired schema (not full OFL).
struct OFLLiteFixture: Codable, Sendable {
    var name: String
    var manufacturer: String?
    var shortName: String?
    var modes: [OFLLiteMode]

    struct OFLLiteMode: Codable, Sendable {
        var name: String
        /// Channel names in DMX order (1-based offsets).
        var channels: [String]
    }

    func toDefinitions() throws -> [FixtureDefinition] {
        guard !modes.isEmpty else { throw FixtureImportError.emptyModes }
        let mfg = manufacturer ?? "Unknown"
        return try modes.map { mode in
            var channels: [ChannelDef] = []
            channels.reserveCapacity(mode.channels.count)
            var hasPanTilt = false
            var colorModel: ColorModel?
            var hasRGB = false
            var hasW = false
            for (idx, label) in mode.channels.enumerated() {
                let attr = FixtureImporter.attribute(forChannelName: label)
                if attr == "pan" || attr == "tilt" { hasPanTilt = true }
                if attr == "colorR" || attr == "colorG" || attr == "colorB" { hasRGB = true }
                if attr == "colorW" { hasW = true }
                channels.append(
                    ChannelDef(
                        offset: UInt16(idx + 1),
                        name: label,
                        attribute: attr,
                        defaultValue: 0,
                        highlightValue: attr == "intensity" ? 255 : 255
                    )
                )
            }
            if hasRGB && hasW {
                colorModel = .rgbw
            } else if hasRGB {
                colorModel = .rgb
            }
            let definition = FixtureDefinition(
                manufacturer: mfg,
                model: name,
                modeName: mode.name,
                channels: channels,
                colorModel: colorModel,
                hasPanTilt: hasPanTilt
            )
            try FixtureDefinitionValidation.validate(definition)
            return definition
        }
    }
}
