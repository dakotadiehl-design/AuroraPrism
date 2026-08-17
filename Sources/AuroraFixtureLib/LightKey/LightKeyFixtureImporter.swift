import AuroraModel
import CryptoKit
import Foundation

public enum FixtureImportIssueSeverity: String, Codable, Sendable, Hashable, CaseIterable {
    case information
    case warning
    case requiresReview
    case fatal
}

public enum FixtureImportIssueCode: String, Codable, Sendable, Hashable {
    case unknownCapability
    case unknownColorEmitter
    case conditionalCapability
    case compoundChannel
    case orphanedCapability
    case channelOutsideFootprint
    case fineWithoutCoarse
    case malformedPersonality
    case unsafeCommand
    case unsupportedBeamLayout
    case sourceVersion
}

public struct FixtureImportIssue: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var severity: FixtureImportIssueSeverity
    public var code: FixtureImportIssueCode
    public var message: String
    public var personalityIndex: Int?
    public var channelOffset: UInt16?

    public init(
        id: UUID = UUID(),
        severity: FixtureImportIssueSeverity,
        code: FixtureImportIssueCode,
        message: String,
        personalityIndex: Int? = nil,
        channelOffset: UInt16? = nil
    ) {
        self.id = id
        self.severity = severity
        self.code = code
        self.message = message
        self.personalityIndex = personalityIndex
        self.channelOffset = channelOffset
    }
}

public struct LightKeySourceMetadata: Codable, Sendable, Hashable {
    public var filename: String
    public var fixtureUUID: String?
    public var revisionUUID: String?
    public var savingAppVersion: String?
    public var requiredAppVersion: String?
    public var personalityIndex: Int
    public var fixtureType: Int?
    public var numberOfBeams: Int?
    public var beamLayoutClass: String?
    public var beamType: Int?
    public var beamSpreadDegrees: Double?
}

public struct LightKeyChannelSource: Codable, Sendable, Hashable {
    public var channelID: UUID
    public var capabilityClasses: [String]
    public var customName: String?
    public var hasCondition: Bool
    public var beamIndexes: [Int]
}

public struct LightKeyImportCandidate: Identifiable, Sendable, Hashable {
    public var id: UUID { definition.id }
    public var definition: FixtureDefinition
    public var source: LightKeySourceMetadata
    public var channelSources: [LightKeyChannelSource]
    public var issues: [FixtureImportIssue]

    public var hasFatalIssues: Bool { issues.contains { $0.severity == .fatal } }
    public var requiresReview: Bool { issues.contains { $0.severity == .requiresReview } }
}

public struct LightKeyImportResult: Sendable, Hashable {
    public var manufacturer: String
    public var model: String
    public var sourceURL: URL
    public var candidates: [LightKeyImportCandidate]
    public var issues: [FixtureImportIssue]
    public var numberOfBeams: Int?
    public var beamSpreadDegrees: Double?
}

public enum LightKeyFixtureImportError: Error, LocalizedError, Equatable {
    case fileTooLarge(Int)
    case notKeyedArchive
    case missingObjectTable
    case invalidObjectReference(UInt64)
    case invalidRootFixture
    case noPersonalities
    case malformed(String)

    public var errorDescription: String? {
        switch self {
        case .fileTooLarge(let bytes): return "The LightKey fixture is too large to import safely (\(bytes) bytes)."
        case .notKeyedArchive: return "The file is not a LightKey NSKeyedArchiver fixture."
        case .missingObjectTable: return "The LightKey archive is missing its object table."
        case .invalidObjectReference(let index): return "The LightKey archive contains invalid object reference \(index)."
        case .invalidRootFixture: return "The archive does not contain an LXFixtureProfile root object."
        case .noPersonalities: return "The LightKey fixture contains no importable personalities."
        case .malformed(let message): return "The LightKey fixture is malformed: \(message)"
        }
    }
}

/// Native, data-only importer for LightKey `.lightkeyfxt` keyed archives.
public enum LightKeyFixtureImporter {
    public static func inspect(url: URL) throws -> LightKeyImportResult {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        if let size = values.fileSize, size > LightKeyBinaryPlistReader.maximumFileSize {
            throw LightKeyFixtureImportError.fileTooLarge(size)
        }
        return try inspect(data: Data(contentsOf: url), sourceURL: url)
    }

    public static func inspect(data: Data, filename: String = "Imported.lightkeyfxt") throws -> LightKeyImportResult {
        try inspect(data: data, sourceURL: URL(fileURLWithPath: filename))
    }

    private static func inspect(data: Data, sourceURL: URL) throws -> LightKeyImportResult {
        guard data.count <= LightKeyBinaryPlistReader.maximumFileSize else {
            throw LightKeyFixtureImportError.fileTooLarge(data.count)
        }
        let plist = try LightKeyBinaryPlistReader(data: data).decode()
        let archive = try LightKeyArchive(root: plist)
        return try LightKeyProfileConverter(archive: archive, sourceURL: sourceURL).convert()
    }
}

// MARK: - Safe keyed-archive graph

private struct LightKeyArchive {
    let objects: [LightKeyPlistValue]
    let top: [String: LightKeyPlistValue]

    init(root: LightKeyPlistValue) throws {
        guard let root = root.dictionaryValue else { throw LightKeyBinaryPlistError.rootNotDictionary }
        guard root["$archiver"]?.stringValue == "NSKeyedArchiver" else {
            throw LightKeyFixtureImportError.notKeyedArchive
        }
        guard let objects = root["$objects"]?.arrayValue,
              let top = root["$top"]?.dictionaryValue
        else { throw LightKeyFixtureImportError.missingObjectTable }
        self.objects = objects
        self.top = top
    }

    func raw(_ value: LightKeyPlistValue?) throws -> LightKeyPlistValue {
        guard let value else { return .null }
        guard case .uid(let index) = value else { return value }
        guard index < UInt64(objects.count) else {
            throw LightKeyFixtureImportError.invalidObjectReference(index)
        }
        return objects[Int(index)]
    }

    func dictionary(_ value: LightKeyPlistValue?) throws -> [String: LightKeyPlistValue] {
        try raw(value).dictionaryValue ?? [:]
    }

    func className(_ value: LightKeyPlistValue?) throws -> String? {
        let object = try dictionary(value)
        let classObject = try dictionary(object["$class"])
        return classObject["$classname"]?.stringValue
    }

    func string(_ value: LightKeyPlistValue?) throws -> String? {
        let resolved = try raw(value)
        if case .string(let string) = resolved { return string == "$null" ? nil : string }
        if let dictionary = resolved.dictionaryValue {
            return try string(dictionary["NS.string"] ?? dictionary["string"])
        }
        return nil
    }

    func int(_ value: LightKeyPlistValue?) throws -> Int? {
        try raw(value).integerValue
    }

    func double(_ value: LightKeyPlistValue?) throws -> Double? {
        try raw(value).doubleValue
    }

    func array(_ value: LightKeyPlistValue?) throws -> [LightKeyPlistValue] {
        let resolved = try raw(value)
        if let array = resolved.arrayValue { return array }
        if let dictionary = resolved.dictionaryValue, let objects = dictionary["NS.objects"] {
            return try raw(objects).arrayValue ?? []
        }
        return []
    }

    func foundationDictionary(_ value: LightKeyPlistValue?) throws -> [String: LightKeyPlistValue] {
        let resolved = try dictionary(value)
        if let keysValue = resolved["NS.keys"], let valuesValue = resolved["NS.objects"] {
            let keys = try array(keysValue)
            let values = try array(valuesValue)
            var result: [String: LightKeyPlistValue] = [:]
            for (key, value) in zip(keys, values) {
                if let key = try string(key) { result[key] = value }
            }
            return result
        }
        return resolved.filter { $0.key != "$class" }
    }

    func uuidString(_ value: LightKeyPlistValue?) throws -> String? {
        let resolved = try raw(value)
        if case .string(let string) = resolved { return string }
        let object = resolved.dictionaryValue ?? [:]
        guard case .data(let bytes)? = object["NS.uuidbytes"], bytes.count == 16 else { return nil }
        let b = [UInt8](bytes)
        return String(format: "%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
                      b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                      b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15])
    }

    func oldStylePair(_ value: LightKeyPlistValue?) throws -> (Int, Int)? {
        guard try className(value) == "_NSKeyedCoderOldStyleArray" else { return nil }
        let object = try dictionary(value)
        guard var first = object["$0"]?.integerValue, var second = object["$1"]?.integerValue else { return nil }
        if (-128 ..< 0).contains(first) { first += 256 }
        if (-128 ..< 0).contains(second) { second += 256 }
        guard (0...255).contains(first), (0...255).contains(second) else { return nil }
        return (first, second)
    }
}

// MARK: - LightKey semantic conversion

private struct LightKeyProfileConverter {
    let archive: LightKeyArchive
    let sourceURL: URL

    private struct RawCapability {
        var offset: Int?
        var name: String
        var attribute: String
        var resolution: ChannelResolution
        var semanticKind: ChannelSemanticKind
        var sourceClass: String
        var customName: String?
        var functions: [DMXFunctionRange]
        var hasCondition: Bool
        var beamIndexes: [Int]
        var issues: [FixtureImportIssue]
    }

    func convert() throws -> LightKeyImportResult {
        let profileValue = archive.top["fixtureProfile"]
        guard try archive.className(profileValue) == "LXFixtureProfile" else {
            throw LightKeyFixtureImportError.invalidRootFixture
        }
        let profile = try archive.dictionary(profileValue)
        let manufacturer = clean(try archive.string(profile["manufacturer"])) ?? "Unknown"
        let model = clean(try archive.string(profile["name"])) ?? sourceURL.deletingPathExtension().lastPathComponent
        let fixtureUUID = try archive.uuidString(profile["UUID"])
        let revisionUUID = try archive.uuidString(profile["revisionUUID"])
        let savingVersion = try archive.string(archive.top["savingAppVersion"])
        let requiredVersion = try archive.string(archive.top["requiredAppVersion"])
        let fixtureType = try archive.int(profile["type"])
        let beamType = try archive.int(profile["beamType"])
        let beamSpread = try archive.double(profile["beamSpread"])
        let beamLayout = try archive.dictionary(profile["beamLayout"])
        let beamLayoutClass = try archive.className(profile["beamLayout"])
        let numberOfBeams = try archive.int(beamLayout["numberOfBeams"])
        let personalities = try archive.array(profile["personalities"])
        guard !personalities.isEmpty else { throw LightKeyFixtureImportError.noPersonalities }

        var globalIssues: [FixtureImportIssue] = []
        if let beamLayoutClass, !["LXUndefinedBeamLayout", "LXBeamLayout"].contains(beamLayoutClass) {
            globalIssues.append(.init(
                severity: .requiresReview,
                code: .unsupportedBeamLayout,
                message: "LightKey beam layout \(beamLayoutClass) is preserved as metadata but is not yet modeled by Prism."
            ))
        }

        var candidates: [LightKeyImportCandidate] = []
        for (personalityIndex, personalityValue) in personalities.enumerated() {
            guard try archive.className(personalityValue) == "LXPersonality" else {
                globalIssues.append(.init(
                    severity: .warning,
                    code: .malformedPersonality,
                    message: "Personality \(personalityIndex + 1) has an unexpected archive class.",
                    personalityIndex: personalityIndex
                ))
                continue
            }
            let personality = try archive.dictionary(personalityValue)
            let footprint = try archive.int(personality["footprint"]) ?? 0
            guard footprint > 0, footprint <= Int(UInt16.max) else {
                globalIssues.append(.init(
                    severity: .fatal,
                    code: .malformedPersonality,
                    message: "Personality \(personalityIndex + 1) has invalid footprint \(footprint).",
                    personalityIndex: personalityIndex
                ))
                continue
            }
            let mode = clean(try archive.string(personality["customName"])) ?? "\(footprint) Channel"
            let rawCapabilities = try archive.array(personality["capabilities"]).map {
                try decodeCapability($0, personalityIndex: personalityIndex)
            }
            let converted = mergeCapabilities(
                rawCapabilities,
                footprint: footprint,
                personalityIndex: personalityIndex
            )
            guard !converted.channels.isEmpty else {
                globalIssues.append(.init(
                    severity: .fatal,
                    code: .malformedPersonality,
                    message: "Mode “\(mode)” has no usable channels.",
                    personalityIndex: personalityIndex
                ))
                continue
            }

            let attributes = Set(converted.channels.map(\.attribute))
            let hasRGB = ["colorR", "colorG", "colorB"].allSatisfy(attributes.contains)
            let hasWhite = !attributes.isDisjoint(with: ["colorW", "colorWarmWhite", "colorCoolWhite"])
            let colorModel: ColorModel? = hasRGB ? (hasWhite ? .rgbw : .rgb) : nil
            let identity = "lightkey:\(fixtureUUID ?? sourceURL.lastPathComponent):\(revisionUUID ?? "unknown"):personality:\(personalityIndex)"
            let definition = FixtureDefinition(
                id: deterministicUUID(identity),
                manufacturer: manufacturer,
                model: model,
                modeName: mode,
                channelCount: UInt16(footprint),
                channels: converted.channels,
                colorModel: colorModel,
                hasPanTilt: attributes.contains("pan") || attributes.contains("tilt"),
                category: fixtureCategory(fixtureType)
            )
            var issues = converted.issues
            do {
                try FixtureDefinitionValidation.validate(definition)
            } catch {
                issues.append(.init(
                    severity: .fatal,
                    code: .malformedPersonality,
                    message: error.localizedDescription,
                    personalityIndex: personalityIndex
                ))
            }
            let source = LightKeySourceMetadata(
                filename: sourceURL.lastPathComponent,
                fixtureUUID: fixtureUUID,
                revisionUUID: revisionUUID,
                savingAppVersion: savingVersion,
                requiredAppVersion: requiredVersion,
                personalityIndex: personalityIndex,
                fixtureType: fixtureType,
                numberOfBeams: numberOfBeams,
                beamLayoutClass: beamLayoutClass,
                beamType: beamType,
                beamSpreadDegrees: beamSpread
            )
            candidates.append(.init(
                definition: definition,
                source: source,
                channelSources: converted.sources,
                issues: globalIssues + issues
            ))
        }

        guard !candidates.isEmpty else { throw LightKeyFixtureImportError.noPersonalities }
        return LightKeyImportResult(
            manufacturer: manufacturer,
            model: model,
            sourceURL: sourceURL,
            candidates: candidates,
            issues: globalIssues,
            numberOfBeams: numberOfBeams,
            beamSpreadDegrees: beamSpread
        )
    }

    private func decodeCapability(_ value: LightKeyPlistValue, personalityIndex: Int) throws -> RawCapability {
        let object = try archive.dictionary(value)
        let sourceClass = try archive.className(value) ?? "UnknownCapability"
        let offset = try archive.int(object["channel"])
        let customName = clean(try archive.string(object["customName"]))
        let settings = try archive.array(object["settings"])
        let decodedSettings = try settings.map(decodeSetting)
        let hasCondition: Bool = {
            guard let condition = object["condition"] else { return false }
            return (try? archive.raw(condition)) != .null
        }()
        let beamIndexes = (try? decodeIndexes(object["beamIndexes"])) ?? []
        var issues: [FixtureImportIssue] = []
        let mapping: (String, String, ChannelResolution, ChannelSemanticKind)

        if sourceClass == "LXColorComponentCapability" {
            let component = try decodedSettings.lazy.compactMap { setting -> String? in
                guard let params = setting.params else { return nil }
                return clean(try archive.string(params["componentName"]))
            }.first
            if let attribute = colorAttribute(component) {
                mapping = (attribute, component ?? customName ?? "Color Component", .eightBit, .semantic)
            } else {
                mapping = (sanitizedGeneric(component ?? customName ?? "Color Component"), component ?? customName ?? "Color Component", .eightBit, .generic)
                issues.append(.init(
                    severity: .requiresReview,
                    code: .unknownColorEmitter,
                    message: "LightKey color emitter “\(component ?? "unnamed")” has no matching Prism color attribute. Prism retained the channel and its DMX ranges as a generic control, but it will not participate in the color picker, RGB mixing, white balance, palettes, or color effects.",
                    personalityIndex: personalityIndex,
                    channelOffset: offset.flatMap { UInt16(exactly: $0 + 1) }
                ))
            }
        } else if sourceClass == "LXCustomCapability" {
            let name = customName ?? "Custom"
            mapping = (sanitizedGeneric(name), name, .eightBit, .generic)
        } else if let known = capabilityMapping[sourceClass] {
            mapping = known
        } else {
            let name = customName ?? sourceClass
            mapping = (sanitizedGeneric(name), name, .eightBit, .generic)
            issues.append(.init(
                severity: .requiresReview,
                code: .unknownCapability,
                message: "LightKey capability \(sourceClass) has no Prism semantic implementation. Prism retained its channel, name, and DMX function ranges as a generic control, but it has no dedicated Programmer control and Prism will not interpret its LightKey-specific behavior.",
                personalityIndex: personalityIndex,
                channelOffset: offset.flatMap { UInt16(exactly: $0 + 1) }
            ))
        }

        if hasCondition {
            issues.append(.init(
                severity: .requiresReview,
                code: .conditionalCapability,
                message: "LightKey applies \(mapping.1) only when another capability satisfies an archived condition. Prism does not decode or evaluate that condition, so it cannot enforce when this capability should be active. The channel and DMX ranges are retained, but conditional activation is not preserved during programming or playback.",
                personalityIndex: personalityIndex,
                channelOffset: offset.flatMap { UInt16(exactly: $0 + 1) }
            ))
        }
        if sourceClass == "LXCommandCapability" {
            issues.append(.init(
                severity: .requiresReview,
                code: .unsafeCommand,
                message: "This is a LightKey command/service capability. Prism retains its labeled DMX ranges as a generic channel, but does not interpret command intent or automatically protect individual reset, lamp, calibration, or service ranges. The imported default and highlight values remain zero.",
                personalityIndex: personalityIndex,
                channelOffset: offset.flatMap { UInt16(exactly: $0 + 1) }
            ))
        }

        return RawCapability(
            offset: offset,
            name: mapping.1,
            attribute: mapping.0,
            resolution: mapping.2,
            semanticKind: mapping.3,
            sourceClass: sourceClass,
            customName: customName,
            functions: decodedSettings.map(\.function),
            hasCondition: hasCondition,
            beamIndexes: beamIndexes,
            issues: issues
        )
    }

    private struct DecodedSetting {
        var function: DMXFunctionRange
        var params: [String: LightKeyPlistValue]?
    }

    private func decodeSetting(_ value: LightKeyPlistValue) throws -> DecodedSetting {
        let object = try archive.dictionary(value)
        let pair = try archive.oldStylePair(object["$0"])
        let params = try archive.foundationDictionary(object["params"])
        let name = clean(try archive.string(params["name"]))
        let explicitLabel = clean(try archive.string(params["label"]))
        let componentName = clean(try archive.string(params["componentName"]))
        let goboIdentifier = clean(try archive.string(params["goboIdentifier"]))
        let label = name ?? explicitLabel ?? componentName ?? goboIdentifier ?? "Function"
        let lo = UInt8(pair.map { min($0.0, $0.1) } ?? 0)
        let hi = UInt8(pair.map { max($0.0, $0.1) } ?? 255)
        return DecodedSetting(function: .init(name: label, dmxMin: lo, dmxMax: hi), params: params)
    }

    private func decodeIndexes(_ value: LightKeyPlistValue?) throws -> [Int] {
        let raw = try archive.raw(value)
        if let array = raw.arrayValue { return array.compactMap(\.integerValue) }
        let object = raw.dictionaryValue ?? [:]
        if let indexes = object["NS.objects"] { return try archive.array(indexes).compactMap(\.integerValue) }
        return []
    }

    private func mergeCapabilities(
        _ capabilities: [RawCapability],
        footprint: Int,
        personalityIndex: Int
    ) -> (channels: [ChannelDef], sources: [LightKeyChannelSource], issues: [FixtureImportIssue]) {
        var grouped: [Int: [RawCapability]] = [:]
        var issues = capabilities.flatMap(\.issues)
        for capability in capabilities {
            guard let offset = capability.offset else {
                issues.append(.init(
                    severity: .warning,
                    code: .orphanedCapability,
                    message: "\(capability.name) has no channel offset and was not imported.",
                    personalityIndex: personalityIndex
                ))
                continue
            }
            guard offset >= 0, offset < footprint else {
                issues.append(.init(
                    severity: .warning,
                    code: .channelOutsideFootprint,
                    message: "Capability offset \(offset) lies outside the \(footprint)-channel footprint.",
                    personalityIndex: personalityIndex
                ))
                continue
            }
            grouped[offset, default: []].append(capability)
        }

        var channels: [ChannelDef] = []
        var sources: [LightKeyChannelSource] = []
        for offset in grouped.keys.sorted() {
            guard let capabilities = grouped[offset], let primary = capabilities.first else { continue }
            let allSameAttribute = capabilities.allSatisfy { $0.attribute == primary.attribute }
            let attribute = allSameAttribute ? primary.attribute : sanitizedGeneric(capabilities.map(\.name).joined(separator: "_"))
            let kind: ChannelSemanticKind = allSameAttribute ? primary.semanticKind : .generic
            let name = Array(NSOrderedSet(array: capabilities.map(\.name)))
                .compactMap { $0 as? String }.joined(separator: " / ")
            let channel = ChannelDef(
                offset: UInt16(offset + 1),
                name: name,
                attribute: attribute,
                resolution: primary.resolution,
                defaultValue: 0,
                highlightValue: ["intensity", "switch", "fog"].contains(attribute) ? 255 : 0,
                semanticKind: kind,
                dmxFunctions: capabilities.flatMap(\.functions)
            )
            channels.append(channel)
            sources.append(.init(
                channelID: channel.id,
                capabilityClasses: capabilities.map(\.sourceClass),
                customName: capabilities.compactMap(\.customName).first,
                hasCondition: capabilities.contains(where: \.hasCondition),
                beamIndexes: Array(Set(capabilities.flatMap(\.beamIndexes))).sorted()
            ))
            if capabilities.count > 1 {
                issues.append(.init(
                    severity: .requiresReview,
                    code: .compoundChannel,
                    message: "LightKey assigns \(capabilities.count) capabilities to this one physical DMX channel: \(capabilities.map(\.sourceClass).joined(separator: ", ")). Prism currently supports one primary attribute per channel, so the secondary capability semantics and their conditional selection are not independently evaluated. Their labeled DMX ranges are retained together on the generic Prism channel.",
                    personalityIndex: personalityIndex,
                    channelOffset: UInt16(offset + 1)
                ))
            }
        }

        pairFineChannels(&channels, issues: &issues, personalityIndex: personalityIndex)
        return (channels, sources, issues)
    }

    private func pairFineChannels(
        _ channels: inout [ChannelDef],
        issues: inout [FixtureImportIssue],
        personalityIndex: Int
    ) {
        for fineIndex in channels.indices where channels[fineIndex].resolution == .fine {
            let attribute = channels[fineIndex].attribute
            let fineOffset = channels[fineIndex].offset
            let candidates = channels.indices.filter {
                channels[$0].attribute == attribute && channels[$0].resolution != .fine
            }
            guard let coarseIndex = candidates.filter({ channels[$0].offset < fineOffset }).max(by: {
                channels[$0].offset < channels[$1].offset
            }) ?? candidates.first else {
                issues.append(.init(
                    severity: .requiresReview,
                    code: .fineWithoutCoarse,
                    message: "\(channels[fineIndex].name) has no matching coarse channel.",
                    personalityIndex: personalityIndex,
                    channelOffset: fineOffset
                ))
                continue
            }
            channels[coarseIndex].resolution = .coarse
        }
    }

    private var capabilityMapping: [String: (String, String, ChannelResolution, ChannelSemanticKind)] {
        [
            "LXIntensityCapability": ("intensity", "Intensity", .eightBit, .semantic),
            "LXIntensityFineCapability": ("intensity", "Intensity Fine", .fine, .semantic),
            "LXPanCapability": ("pan", "Pan", .eightBit, .semantic),
            "LXPanFineCapability": ("pan", "Pan Fine", .fine, .semantic),
            "LXTiltCapability": ("tilt", "Tilt", .eightBit, .semantic),
            "LXTiltFineCapability": ("tilt", "Tilt Fine", .fine, .semantic),
            "LXPanTiltSpeedCapability": ("panTiltSpeed", "Pan/Tilt Speed", .eightBit, .semantic),
            "LXFocusCapability": ("focus", "Focus", .eightBit, .semantic),
            "LXZoomCapability": ("zoom", "Zoom", .eightBit, .semantic),
            "LXIrisCapability": ("iris", "Iris", .eightBit, .semantic),
            "LXShutterStrobeCapability": ("shutter", "Shutter / Strobe", .eightBit, .semantic),
            "LXGoboCapability": ("gobo", "Gobo", .eightBit, .semantic),
            "LXGoboAngleCapability": ("goboAngle", "Gobo Angle", .eightBit, .semantic),
            "LXGoboRotationCapability": ("goboRotation", "Gobo Rotation", .eightBit, .semantic),
            "LXPrismCapability": ("prism", "Prism", .eightBit, .semantic),
            "LXPrismAngleCapability": ("prismAngle", "Prism Angle", .eightBit, .semantic),
            "LXPrismRotationCapability": ("prismRotation", "Prism Rotation", .eightBit, .semantic),
            "LXColorWheelCapability": ("colorWheel", "Color Wheel", .eightBit, .semantic),
            "LXOnOffCapability": ("switch", "Switch", .eightBit, .generic),
            "LXFogCapability": ("fog", "Fog", .eightBit, .generic),
            "LXModeCapability": ("mode", "Mode", .eightBit, .generic),
            "LXCommandCapability": ("command", "Command", .eightBit, .generic),
            "LXCustomCapability": ("custom", "Custom", .eightBit, .generic),
        ]
    }

    private func colorAttribute(_ name: String?) -> String? {
        guard let name else { return nil }
        let normalized = name.lowercased().filter(\.isLetter)
        return [
            "red": "colorR", "green": "colorG", "blue": "colorB", "white": "colorW",
            "coolwhite": "colorCoolWhite", "coldwhite": "colorCoolWhite",
            "warmwhite": "colorWarmWhite", "amber": "colorA", "ultraviolet": "colorUV",
            "uv": "colorUV", "lime": "colorLime", "cyan": "colorCyan",
        ][normalized]
    }

    private func fixtureCategory(_ type: Int?) -> String {
        switch type {
        case 41: return "led"
        case 0: return "generic"
        case .some(let value): return "lightkey-type-\(value)"
        case nil: return "generic"
        }
    }

    private func clean(_ string: String?) -> String? {
        guard let string else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func sanitizedGeneric(_ string: String) -> String {
        let normalized = string.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : "_"
        }
        let collapsed = String(normalized).replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return collapsed.isEmpty ? "generic" : collapsed
    }

    private func deterministicUUID(_ seed: String) -> UUID {
        var bytes = Array(Insecure.SHA1.hash(data: Data(seed.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
