import AuroraModel
import Foundation

public enum FixtureImportError: Error, Equatable, Sendable, LocalizedError {
    case emptyModes
    case invalidJSON
    case unsupportedFormat
    case invalidDefinition(String)

    public var errorDescription: String? {
        switch self {
        case .emptyModes:
            return "Fixture file has no modes or channel definitions."
        case .invalidJSON:
            return "Fixture file is not valid JSON."
        case .unsupportedFormat:
            return "Unsupported fixture format. Supported: Prism native JSON, OFL-lite, and Prism converter (.prism-fixture.json)."
        case .invalidDefinition(let message):
            return "Invalid fixture definition: \(message)"
        }
    }
}

/// Imports fixture definitions from simplified formats (OFL-lite, Prism, native Aurora JSON).
public enum FixtureImporter {
    public static func importDefinitions(from data: Data) throws -> [FixtureDefinition] {
        let decoder = JSONDecoder()

        // Distinguish bad JSON early so format probes can stay `try?`.
        guard (try? JSONSerialization.jsonObject(with: data)) != nil else {
            throw FixtureImportError.invalidJSON
        }

        // Prism fixture converter package (Lightkey / prism-fixture-converter export).
        // Prefer an explicit schema match so decode failures surface as invalidDefinition,
        // not a misleading "unsupported format".
        if looksLikePrismPackage(data) {
            do {
                let prism = try decoder.decode(PrismFixturePackage.self, from: data)
                guard !prism.fixtureDefinitions.isEmpty else {
                    throw FixtureImportError.emptyModes
                }
                return try prism.toDefinitions()
            } catch let err as FixtureImportError {
                throw err
            } catch let err as DecodingError {
                throw FixtureImportError.invalidDefinition(Self.describeDecodingError(err))
            } catch {
                throw FixtureImportError.invalidDefinition(error.localizedDescription)
            }
        }

        if let prism = try? decoder.decode(PrismFixturePackage.self, from: data),
           !prism.fixtureDefinitions.isEmpty {
            return try prism.toDefinitions()
        }

        // OFL-lite (name + modes[].channels labels).
        if let ofl = try? decoder.decode(OFLLiteFixture.self, from: data),
           !ofl.modes.isEmpty {
            return try ofl.toDefinitions()
        }

        // Native Aurora definitions array.
        if let defs = try? decoder.decode([FixtureDefinition].self, from: data), !defs.isEmpty {
            for d in defs { try FixtureDefinitionValidation.validate(d) }
            return defs
        }

        // Single native definition.
        if let def = try? decoder.decode(FixtureDefinition.self, from: data) {
            try FixtureDefinitionValidation.validate(def)
            return [def]
        }

        throw FixtureImportError.unsupportedFormat
    }

    /// True when JSON advertises a prism-fixture-converter schema or shape.
    private static func looksLikePrismPackage(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        if let schema = root["schema"] as? String,
           schema.lowercased().contains("prism-fixture") {
            return true
        }
        // Filename-free shape probe for exports that omit schema.
        return root["fixtureDefinitions"] is [Any]
    }

    private static func describeDecodingError(_ error: DecodingError) -> String {
        switch error {
        case .typeMismatch(let type, let ctx):
            let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
            return "type mismatch for \(type) at \(path.isEmpty ? "(root)" : path): \(ctx.debugDescription)"
        case .valueNotFound(let type, let ctx):
            let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
            return "missing \(type) at \(path.isEmpty ? "(root)" : path)"
        case .keyNotFound(let key, let ctx):
            let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
            return "missing key \(key.stringValue) at \(path.isEmpty ? "(root)" : path)"
        case .dataCorrupted(let ctx):
            let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
            return "corrupt data at \(path.isEmpty ? "(root)" : path): \(ctx.debugDescription)"
        @unknown default:
            return String(describing: error)
        }
    }

    public static func importDefinitions(from url: URL) throws -> [FixtureDefinition] {
        let data = try Data(contentsOf: url)
        return try importDefinitions(from: data)
    }

    /// Map human channel labels to Aurora attribute tags.
    /// Most-specific names first (C.E. 1.1): Warm/Cool White before White; UV aliases; Lime/Cyan.
    public static func attribute(forChannelName name: String) -> String {
        let n = name.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        // Dimmer / master intensity
        if n.contains("dimmer") || n == "intensity" || n == "dim" || n == "master"
            || n == "master dimmer" || n == "master intensity" {
            return "intensity"
        }

        // Dedicated emitters — most specific first
        if n.contains("warm white") || n == "warmwhite" || n == "ww"
            || n.contains("warmwhite") {
            return "colorWarmWhite"
        }
        if n.contains("cool white") || n == "coolwhite" || n == "cw"
            || n.contains("coolwhite") || n.contains("cold white") {
            return "colorCoolWhite"
        }
        if n.contains("ultraviolet") || n == "uv" || n == "u.v." || n.contains(" u v")
            || n.hasPrefix("uv ") || n.hasSuffix(" uv") || n == "u v" {
            return "colorUV"
        }
        if n.contains("amber") || n == "a" {
            return "colorA"
        }
        if n.contains("lime") { return "colorLime" }
        if n.contains("cyan") && !n.contains("magenta") { return "colorCyan" }

        // Generic white after warm/cool
        if n == "white" || n == "w" || n.contains("white") { return "colorW" }

        // RGB — avoid matching single letters inside longer words when possible
        if n == "red" || n == "r" || (n.contains("red") && !n.contains("amber")) { return "colorR" }
        if n == "green" || n == "g" || n.contains("green") { return "colorG" }
        if n == "blue" || n == "b" || (n.contains("blue") && !n.contains("warm")) { return "colorB" }

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

    /// Normalize prism/source attribute tags into Aurora attribute + semantic kind.
    static func normalizeAttribute(_ raw: String?, channelName: String) -> (attribute: String, kind: ChannelSemanticKind) {
        let attr = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if attr.isEmpty {
            return (attribute(forChannelName: channelName), .semantic)
        }
        switch attr {
        case "shutterStrobe", "shutter_strobe":
            return ("shutter", .semantic)
        case "generic", "custom":
            // Prefer name-based semantic when possible; otherwise keep generic escape hatch.
            let fromName = attribute(forChannelName: channelName)
            if fromName == "channel" || fromName == channelName.lowercased().replacingOccurrences(of: " ", with: "_") {
                return (channelName.isEmpty ? "generic" : channelName, .generic)
            }
            // Name mapped to something useful (e.g. Intensity → intensity)
            if ["intensity", "colorR", "colorG", "colorB", "colorW", "colorA", "colorUV",
                "colorWarmWhite", "colorCoolWhite", "pan", "tilt", "shutter", "zoom", "focus", "gobo"]
                .contains(fromName) {
                return (fromName, .semantic)
            }
            return (channelName.isEmpty ? attr : channelName, .generic)
        case "colorCoolWhite", "colorWarmWhite", "colorUV", "colorA", "colorR", "colorG", "colorB",
             "colorW", "colorLime", "colorCyan", "intensity", "pan", "tilt", "shutter", "zoom", "focus", "gobo":
            return (attr, .semantic)
        default:
            // Unknown tag — try channel name heuristics, else keep as semantic tag.
            let fromName = attribute(forChannelName: channelName)
            if fromName != "channel" && fromName != channelName.lowercased().replacingOccurrences(of: " ", with: "_") {
                return (fromName, .semantic)
            }
            return (attr, .semantic)
        }
    }
}

// MARK: - Flexible JSON strings (Lightkey / Cocoa keyed archives)

/// Accepts a plain JSON string **or** Cocoa-style string bags from some Lightkey exports:
/// `{ "_class": "NSMutableString", "NS.string": "Slow > Fast" }`.
struct FlexibleJSONString: Codable, Sendable, Equatable {
    var value: String

    init(_ value: String) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            value = s
            return
        }
        // Lightkey sometimes re-encodes NSMutableString without collapsing to JSON string.
        if let bag = try? container.decode(CocoaStringBag.self), let s = bag.resolved {
            value = s
            return
        }
        throw DecodingError.typeMismatch(
            String.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected String or NS.string dictionary"
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    /// Keyed bag; unknown keys such as `_class` are ignored by `JSONDecoder`.
    private struct CocoaStringBag: Codable, Sendable {
        var nsString: String?
        var string: String?

        enum CodingKeys: String, CodingKey {
            case nsString = "NS.string"
            case string
        }

        var resolved: String? {
            guard let candidate = nsString ?? string else { return nil }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : candidate
        }
    }
}

// MARK: - Prism package (prism-fixture-converter / Lightkey export)

/// Wrapper produced by `prism-fixture-converter` (schema `prism-fixture-converter/0.1`).
struct PrismFixturePackage: Codable, Sendable {
    var schema: String?
    var fixture: PrismFixtureMeta?
    var fixtureDefinitions: [PrismDefinition]
    var warnings: [String]?

    struct PrismFixtureMeta: Codable, Sendable {
        var manufacturer: String?
        var model: String?
        var category: String?
    }

    struct PrismDefinition: Codable, Sendable {
        var id: UUID?
        var manufacturer: String?
        var model: String?
        var modeName: String?
        var channelCount: UInt16?
        var channels: [PrismChannel]
        var hasPanTilt: Bool?
    }

    struct PrismChannel: Codable, Sendable {
        var offset: UInt16
        var name: String
        var attribute: String?
        var defaultValue: UInt8?
        var highlightValue: UInt8?
        var functions: [PrismFunction]?
        /// Prism custom capability name (often same as channel name).
        var customName: String?
    }

    struct PrismFunction: Codable, Sendable {
        var label: FlexibleJSONString?
        var dmxMin: UInt8?
        var dmxMax: UInt8?
        var params: PrismParams?

        struct PrismParams: Codable, Sendable {
            /// Lightkey exports occasionally encode `NSMutableString` as
            /// `{ "_class": "NSMutableString", "NS.string": "…" }` instead of a JSON string.
            var name: FlexibleJSONString?
            var componentName: FlexibleJSONString?
            var continuous: Bool?
            var mode: Int?
            var style: Int?
        }
    }

    func toDefinitions() throws -> [FixtureDefinition] {
        guard !fixtureDefinitions.isEmpty else { throw FixtureImportError.emptyModes }
        let packageMfg = fixture?.manufacturer
        let packageModel = fixture?.model

        return try fixtureDefinitions.map { def in
            try def.toFixtureDefinition(
                fallbackManufacturer: packageMfg ?? "Unknown",
                fallbackModel: packageModel ?? "Imported Fixture"
            )
        }
    }
}

extension PrismFixturePackage.PrismDefinition {
    func toFixtureDefinition(fallbackManufacturer: String, fallbackModel: String) throws -> FixtureDefinition {
        guard !channels.isEmpty else {
            throw FixtureImportError.invalidDefinition("mode “\(modeName ?? "?")” has no channels")
        }

        // Prism/Lightkey use 0-based offsets; Aurora requires 1-based.
        let minOffset = channels.map(\.offset).min() ?? 0
        let offsetBase: UInt16 = minOffset == 0 ? 1 : 0

        var hasPanTilt = self.hasPanTilt ?? false
        var hasRGB = false
        var hasW = false
        var mapped: [ChannelDef] = []
        mapped.reserveCapacity(channels.count)

        for ch in channels {
            let (attr, kind) = FixtureImporter.normalizeAttribute(ch.attribute, channelName: ch.name)
            if attr == "pan" || attr == "tilt" { hasPanTilt = true }
            if attr == "colorR" || attr == "colorG" || attr == "colorB" { hasRGB = true }
            if attr == "colorW" || attr == "colorWarmWhite" || attr == "colorCoolWhite" { hasW = true }

            var functions: [DMXFunctionRange] = []
            if let raw = ch.functions {
                for f in raw {
                    let name = f.label?.value
                        ?? f.params?.name?.value
                        ?? f.params?.componentName?.value
                        ?? ch.name
                    let lo = f.dmxMin ?? 0
                    let hi = f.dmxMax ?? 255
                    functions.append(DMXFunctionRange(name: name, dmxMin: lo, dmxMax: hi))
                }
            }

            let auroraOffset = ch.offset + offsetBase
            mapped.append(
                ChannelDef(
                    offset: auroraOffset,
                    name: ch.name,
                    attribute: attr,
                    resolution: .eightBit,
                    defaultValue: ch.defaultValue ?? 0,
                    highlightValue: ch.highlightValue
                        ?? (attr == "intensity" ? 255 : 0),
                    semanticKind: kind,
                    dmxFunctions: functions
                )
            )
        }

        // Sort by offset and ensure contiguous footprint count.
        mapped.sort { $0.offset < $1.offset }
        let footprint = mapped.map(\.offset).max() ?? UInt16(mapped.count)

        var colorModel: ColorModel?
        if hasRGB && hasW {
            colorModel = .rgbw
        } else if hasRGB {
            colorModel = .rgb
        }

        let definition = FixtureDefinition(
            id: id ?? UUID(),
            manufacturer: (manufacturer?.isEmpty == false ? manufacturer! : fallbackManufacturer),
            model: (model?.isEmpty == false ? model! : fallbackModel),
            modeName: modeName ?? "Default",
            channelCount: channelCount ?? footprint,
            channels: mapped,
            colorModel: colorModel,
            hasPanTilt: hasPanTilt
        )
        do {
            try FixtureDefinitionValidation.validate(definition)
        } catch let err as FixtureLibraryError {
            if case .definitionInvalid(let msg) = err {
                throw FixtureImportError.invalidDefinition(msg)
            }
            throw err
        }
        return definition
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
                if attr == "colorW" || attr == "colorWarmWhite" || attr == "colorCoolWhite" { hasW = true }
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
