import AuroraDiagnostics
import AuroraModel
import Foundation

public enum FixtureImportError: Error, Equatable, Sendable, LocalizedError {
    case emptyModes
    case invalidJSON
    case unsupportedFormat
    case invalidDefinition(String)

    public var errorDescription: String? { userMessage }
}

extension FixtureImportError: PrismDiagnosableError {
    public var prismErrorCode: String {
        switch self {
        case .emptyModes: return "fixture.import.empty_modes"
        case .invalidJSON: return "fixture.import.invalid_file"
        case .unsupportedFormat: return "fixture.import.unsupported_format"
        case .invalidDefinition: return "fixture.import.invalid_definition"
        }
    }
    public var userTitle: String { "Prism Couldn't Import That Fixture" }
    public var userMessage: String {
        switch self {
        case .emptyModes:
            return "That fixture file has no modes or channels Prism can use."
        case .invalidJSON:
            return "This fixture file isn’t in a format Prism understands."
        case .unsupportedFormat:
            return "This fixture file isn’t in a format Prism understands."
        case .invalidDefinition:
            return "That fixture profile is missing required information."
        }
    }
    public var recoverySuggestion: String? {
        "Pick a Prism, OFL-lite, or .prism-fixture.json file."
    }
    public var technicalDetails: String { String(reflecting: self) }
    public var prismCategory: PrismLogCategory { .fixtureImport }
    public var prismSeverity: PrismLogLevel { .error }
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
        var beamSpreadDegrees: Double?
        var beamType: Int?
        var sourceBeamLayout: PrismSourceBeamLayout?
    }

    struct PrismSourceBeamLayout: Codable, Sendable {
        var _class: String?
        var numberOfBeams: Int?
        var length: Int?
        var beamShape: Int?
        var rowSegments: [Int]?
        var rowHeights: [Double]?
        var beamsByRing: [Int]?
        var additionalBeamsData: FlexibleJSONString?
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

        let physical = makePhysicalDefinition(manufacturer: packageMfg ?? "Unknown", model: packageModel ?? "Imported Fixture")
        return try fixtureDefinitions.map { def in
            try def.toFixtureDefinition(
                fallbackManufacturer: packageMfg ?? "Unknown",
                fallbackModel: packageModel ?? "Imported Fixture",
                physical: physical
            )
        }
    }

    private func makePhysicalDefinition(manufacturer: String, model: String) -> FixturePhysicalDefinition? {
        guard let source = fixtureDefinitions.compactMap(\.sourceBeamLayout).first else { return nil }
        let layoutClass = source._class ?? "LXUndefinedBeamLayout"
        let segments = source.rowSegments ?? []
        let rings = source.beamsByRing ?? []
        let count: Int = {
            switch layoutClass {
            case "LXNoBeamLayout": return 0
            case "LXStripBeamLayout": return max(0, source.length ?? source.numberOfBeams ?? 0)
            case "LXRowsBeamLayout": return max(0, segments.reduce(0, +))
            case "LXRingsBeamLayout": return max(0, rings.reduce(0, +))
            case "LXSingleBeamLayout": return 1
            default: return max(0, source.numberOfBeams ?? source.length ?? 0)
            }
        }()
        let topology: FixturePhysicalTopologyKind = {
            switch layoutClass {
            case "LXNoBeamLayout": return .noBeam
            case "LXSingleBeamLayout": return .single
            case "LXStripBeamLayout": return .linear
            case "LXRowsBeamLayout": return segments.count > 1 && Set(segments).count > 1 ? .variableRows : .grid
            case "LXGridBeamLayout": return .grid
            case "LXRingsBeamLayout": return rings.count > 1 ? .rings : .ring
            case "LXArrayBeamLayout": return .array
            default: return .unknown
            }
        }()
        let rows = segments.isEmpty ? (count > 0 ? [count] : []) : segments
        var emitters: [FixturePhysicalEmitter] = []
        if topology == .ring || topology == .rings {
            let counts = rings.isEmpty ? [count] : rings
            for (ringIndex, ringCount) in counts.enumerated() where ringCount > 0 {
                let radius = counts.count == 1 ? 0.34 : 0.15 + 0.25 * Double(ringIndex + 1) / Double(counts.count)
                for index in 0..<ringCount {
                    let angle = -.pi / 2 + 2 * .pi * Double(index) / Double(ringCount)
                    emitters.append(.init(id: "physical-emitter-\(emitters.count)", name: "Emitter \(emitters.count + 1)", x: 0.5 + cos(angle) * radius, y: 0.5 + sin(angle) * radius, width: 0.1, height: 0.1))
                }
            }
        } else if topology == .grid || topology == .variableRows || topology == .array {
            for (row, columns) in rows.enumerated() where columns > 0 {
                for column in 0..<columns {
                    emitters.append(.init(id: "physical-emitter-\(emitters.count)", name: "Emitter \(emitters.count + 1)", x: (Double(column) + 0.5) / Double(columns), y: (Double(row) + 0.5) / Double(max(rows.count, 1)), width: min(0.7, 0.72 / Double(columns)), height: min(0.7, 0.72 / Double(max(rows.count, 1)))))
                }
            }
        } else if count > 0 {
            emitters = (0..<count).map { index in .init(id: "physical-emitter-\(index)", name: "Emitter \(index + 1)", x: count == 1 ? 0.5 : (Double(index) + 0.5) / Double(count), y: 0.5, width: count == 1 ? 0.58 : min(0.7, 0.72 / Double(count)), height: 0.58) }
        }
        let modelKey = model.lowercased()
        let form: FixturePhysicalForm = topology == .noBeam ? .atmospheric
            : topology == .linear ? .linearBar
            : topology == .grid || topology == .variableRows || topology == .array ? (modelKey.contains("blinder") ? .blinder : .panel)
            : modelKey.contains("scan") ? .scanner
            : .generic
        var metadata = ["beamLayoutClass": layoutClass]
        if [.grid, .variableRows, .ring, .rings, .array].contains(topology) { metadata["formInference"] = "layout-default" }
        if let value = source.additionalBeamsData?.value { metadata["additionalBeamsData"] = value }
        return FixturePhysicalDefinition(
            manufacturer: manufacturer,
            model: model,
            form: form,
            aspectRatio: form == .linearBar ? max(2.5, Double(max(count, 1)) * 0.55) : 1,
            emitters: emitters,
            componentGroups: [.init(id: topology == .noBeam ? "no-beam" : "primary", role: topology == .noBeam ? .atmosphericOutlet : .emitterArray, topology: topology, rows: segments.isEmpty ? nil : segments.count, columns: Set(segments).count == 1 ? segments.first : nil, emitterIDs: emitters.map(\.id), provenance: .imported)],
            opticalBehaviors: emitters.isEmpty ? [] : [.wash],
            beamShape: source.beamShape,
            beamType: fixtureDefinitions.compactMap(\.beamType).first,
            beamSpreadDegrees: fixtureDefinitions.compactMap(\.beamSpreadDegrees).first,
            source: .imported,
            sourceMetadata: metadata
        )
    }
}

extension PrismFixturePackage.PrismDefinition {
    func toFixtureDefinition(fallbackManufacturer: String, fallbackModel: String, physical: FixturePhysicalDefinition?) throws -> FixtureDefinition {
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
            hasPanTilt: hasPanTilt,
            physicalFixtureID: physical?.id,
            portablePhysicalDefinition: physical,
            controlElements: physical?.emitters.isEmpty == false ? [.init(id: "fixture-output", name: "Fixture Output")] : [],
            emitterMappings: physical?.emitters.isEmpty == false ? [.init(id: "fixture-output-map", controlElementIDs: ["fixture-output"], physicalEmitterIDs: Set(physical?.emitters.map(\.id) ?? []))] : []
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
