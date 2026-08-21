import AuroraDiagnostics
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

public struct LightKeyBatchImportFailure: Identifiable, Sendable, Hashable {
    public var id: URL { sourceURL }
    public var sourceURL: URL
    public var message: String

    public init(sourceURL: URL, message: String) {
        self.sourceURL = sourceURL
        self.message = message
    }
}

public struct LightKeyBatchImportResult: Sendable, Hashable {
    public var sourceURL: URL
    public var fixtures: [LightKeyImportResult]
    public var failures: [LightKeyBatchImportFailure]

    public init(
        sourceURL: URL,
        fixtures: [LightKeyImportResult],
        failures: [LightKeyBatchImportFailure]
    ) {
        self.sourceURL = sourceURL
        self.fixtures = fixtures
        self.failures = failures
    }
}

public enum LightKeyFixtureImportError: Error, LocalizedError, Equatable {
    case fileTooLarge(Int)
    case notKeyedArchive
    case missingObjectTable
    case invalidObjectReference(UInt64)
    case invalidRootFixture
    case noPersonalities
    case malformed(String)

    public var errorDescription: String? { userMessage }
}

extension LightKeyFixtureImportError: PrismDiagnosableError {
    public var prismErrorCode: String {
        switch self {
        case .fileTooLarge: return "fixture.lightkey.too_large"
        case .notKeyedArchive: return "fixture.lightkey.not_keyed_archive"
        case .missingObjectTable: return "fixture.lightkey.missing_object_table"
        case .invalidObjectReference: return "fixture.lightkey.invalid_object_reference"
        case .invalidRootFixture: return "fixture.lightkey.invalid_root"
        case .noPersonalities: return "fixture.lightkey.no_personalities"
        case .malformed: return "fixture.lightkey.malformed"
        }
    }
    public var userTitle: String { "Prism Couldn't Import That LightKey Fixture" }
    public var userMessage: String {
        switch self {
        case .fileTooLarge:
            return "That LightKey fixture is too large to import safely."
        case .notKeyedArchive:
            return "This doesn’t look like a LightKey fixture file."
        case .missingObjectTable, .invalidObjectReference, .invalidRootFixture, .malformed:
            return "Prism couldn’t read that LightKey fixture."
        case .noPersonalities:
            return "That LightKey fixture has no personalities Prism can import."
        }
    }
    public var recoverySuggestion: String? {
        "Try another LightKey fixture file, or import a Prism fixture instead."
    }
    public var technicalDetails: String { String(reflecting: self) }
    public var prismCategory: PrismLogCategory { .fixtureLightkey }
    public var prismSeverity: PrismLogLevel { .error }
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

    /// Inspects one fixture or every `.lightkeyfxt` below a directory. A malformed file
    /// is reported independently so it cannot discard valid fixtures from the same batch.
    public static func inspectRecursively(sourceURL: URL) throws -> LightKeyBatchImportResult {
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }

        let values = try sourceURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        let urls: [URL]
        if values.isDirectory == true {
            let keys: [URLResourceKey] = [.isRegularFileKey, .isHiddenKey]
            guard let enumerator = FileManager.default.enumerator(
                at: sourceURL,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                return .init(sourceURL: sourceURL, fixtures: [], failures: [])
            }
            urls = enumerator.compactMap { $0 as? URL }.filter {
                $0.pathExtension.caseInsensitiveCompare("lightkeyfxt") == .orderedSame
            }.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        } else {
            urls = [sourceURL]
        }

        var fixtures: [LightKeyImportResult] = []
        var failures: [LightKeyBatchImportFailure] = []
        fixtures.reserveCapacity(urls.count)
        for url in urls {
            do {
                fixtures.append(try inspect(url: url))
            } catch {
                failures.append(.init(sourceURL: url, message: error.localizedDescription))
            }
        }
        return .init(sourceURL: sourceURL, fixtures: fixtures, failures: failures)
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
        guard var resolved = value else { return .null }
        var visited = Set<UInt64>()
        while case .uid(let index) = resolved {
            guard index < UInt64(objects.count) else {
                throw LightKeyFixtureImportError.invalidObjectReference(index)
            }
            guard visited.insert(index).inserted, visited.count <= 64 else {
                throw LightKeyFixtureImportError.malformed("The keyed archive contains a cyclic or excessively deep object reference.")
            }
            resolved = objects[Int(index)]
        }
        if case .string("$null") = resolved { return .null }
        return resolved
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

    func diagnosticString(_ value: LightKeyPlistValue?, depth: Int = 0) throws -> String? {
        guard depth < 4 else { return "<nested>" }
        let resolved = try raw(value)
        switch resolved {
        case .null: return nil
        case .string(let value): return value
        case .integer(let value): return String(value)
        case .real(let value): return String(value)
        case .date(let value): return ISO8601DateFormatter().string(from: value)
        case .bool(let value): return String(value)
        case .data(let value): return "data:\(value.count)-bytes"
        case .uid(let value): return "uid:\(value)"
        case .array(let values):
            return "[" + (try values.prefix(128).compactMap { try diagnosticString($0, depth: depth + 1) }.joined(separator: ",")) + "]"
        case .dictionary(let values):
            return "{" + (try values.keys.sorted().prefix(128).compactMap { key in
                guard key != "$class", let rendered = try diagnosticString(values[key], depth: depth + 1) else { return nil }
                return "\(key):\(rendered)"
            }.joined(separator: ",")) + "}"
        }
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

        let physicalIdentity = "lightkey:\(fixtureUUID ?? sourceURL.lastPathComponent):physical"
        let physicalID = deterministicUUID(physicalIdentity)
        let physical = try makePhysicalDefinition(
            id: physicalID,
            manufacturer: manufacturer,
            model: model,
            profile: profile,
            layout: beamLayout,
            layoutClass: beamLayoutClass,
            declaredBeamCount: numberOfBeams,
            beamType: beamType,
            beamSpread: beamSpread
        )
        let physicalEmitters = physical.emitters

        var globalIssues: [FixtureImportIssue] = []
        let supportedLayouts: Set<String> = [
            "LXUndefinedBeamLayout", "LXBeamLayout", "LXSingleBeamLayout", "LXStripBeamLayout",
            "LXRowsBeamLayout", "LXGridBeamLayout", "LXRingsBeamLayout", "LXArrayBeamLayout",
            "LXNoBeamLayout", "LXHexagonsBeamLayout"
        ]
        if let beamLayoutClass, !supportedLayouts.contains(beamLayoutClass) {
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
                try decodeCapability($0, personalityIndex: personalityIndex, maximumBeamCount: physicalEmitters.count)
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
            let explicitOwnership = ownershipFromBeamMembership(
                channels: converted.channels,
                sources: converted.sources,
                physicalEmitterCount: physicalEmitters.count
            )
            let ownership = explicitOwnership == nil ? FixtureDefinition.inferredElementOwnership(
                channels: converted.channels,
                expectedElementCount: physicalEmitters.count > 1 ? physicalEmitters.count : nil
            ) : nil
            let identity = "lightkey:\(fixtureUUID ?? sourceURL.lastPathComponent):\(revisionUUID ?? "unknown"):personality:\(personalityIndex)"
            let authoredChannels = explicitOwnership ?? ownership?.channels ?? converted.channels
            var seenControlIDs: Set<String> = []
            let ownedIDs = authoredChannels.compactMap(\.elementID).filter { seenControlIDs.insert($0).inserted }
            let controlElements: [FixtureControlElement]
            let emitterMappings: [FixtureEmitterMapping]
            if !ownedIDs.isEmpty {
                controlElements = ownedIDs.enumerated().map { .init(id: $0.element, name: "Element \($0.offset + 1)") }
                let sourceByChannelID = Dictionary(uniqueKeysWithValues: converted.sources.map { ($0.channelID, $0) })
                emitterMappings = ownedIDs.enumerated().compactMap { index, controlID in
                    let beamIndexes = Set(authoredChannels
                        .filter { $0.elementID == controlID }
                        .flatMap { sourceByChannelID[$0.id]?.beamIndexes ?? [] })
                    let physicalIDs = Set(beamIndexes.compactMap { beamIndex in
                        physicalEmitters.indices.contains(beamIndex) ? physicalEmitters[beamIndex].id : nil
                    })
                    if !physicalIDs.isEmpty {
                        return .init(id: "map-\(controlID)", controlElementIDs: [controlID], physicalEmitterIDs: physicalIDs)
                    }
                    // Positional fallback is truthful only for a one-control-per-emitter
                    // personality. A count mismatch must remain unmapped, not silently
                    // collapse a zone of several physical beams onto one aperture.
                    guard ownedIDs.count == physicalEmitters.count,
                          physicalEmitters.indices.contains(index) else { return nil }
                    return .init(id: "map-\(controlID)", controlElementIDs: [controlID], physicalEmitterIDs: [physicalEmitters[index].id])
                }
            } else if !physicalEmitters.isEmpty {
                controlElements = [.init(id: "fixture-output", name: "Fixture Output")]
                emitterMappings = [.init(
                    id: "map-fixture-output",
                    controlElementIDs: ["fixture-output"],
                    physicalEmitterIDs: Set(physicalEmitters.map(\.id))
                )]
            } else {
                controlElements = []
                emitterMappings = []
            }
            let definition = FixtureDefinition(
                id: deterministicUUID(identity),
                manufacturer: manufacturer,
                model: model,
                modeName: mode,
                channelCount: UInt16(footprint),
                channels: authoredChannels,
                colorModel: colorModel,
                hasPanTilt: attributes.contains("pan") || attributes.contains("tilt"),
                category: fixtureCategory(fixtureType),
                physicalFixtureID: physicalID,
                portablePhysicalDefinition: physical,
                controlElements: controlElements,
                emitterMappings: emitterMappings
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
        PrismLog.notice(
            .fixtureLightkey,
            "fixture.lightkey.import_completed",
            "Prism read a LightKey fixture.",
            metadata: ["count": .count(candidates.count)]
        )
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

    /// Maps only corpus-verified LightKey layout classes. Every readable source
    /// field is retained in `sourceMetadata`, including fields not yet normalized.
    private func makePhysicalDefinition(
        id: UUID,
        manufacturer: String,
        model: String,
        profile: [String: LightKeyPlistValue],
        layout: [String: LightKeyPlistValue],
        layoutClass: String?,
        declaredBeamCount: Int?,
        beamType: Int?,
        beamSpread: Double?
    ) throws -> FixturePhysicalDefinition {
        let layoutClass = layoutClass ?? "LXUndefinedBeamLayout"
        let length = try archive.int(layout["length"])
        let beamShape = try archive.int(layout["beamShape"])
        let rowSegments = try integerArray(layout["rowSegments"])
        let rowHeights = try doubleArray(layout["rowHeights"])
        let rings = try nestedCounts(layout["beamsByRing"])
        let additional = profile["additionalBeamsData"] ?? layout["additionalBeamsData"]
        var metadata: [String: String] = ["beamLayoutClass": layoutClass]
        if let declaredBeamCount { metadata["numberOfBeams"] = String(declaredBeamCount) }
        if let length { metadata["length"] = String(length) }
        if let beamShape { metadata["beamShape"] = String(beamShape) }
        if let beamType { metadata["beamType"] = String(beamType) }
        if let beamSpread { metadata["beamSpread"] = String(beamSpread) }
        if !rowSegments.isEmpty { metadata["rowSegments"] = rowSegments.map { String($0) }.joined(separator: ",") }
        if !rowHeights.isEmpty { metadata["rowHeights"] = rowHeights.map { String($0) }.joined(separator: ",") }
        if !rings.isEmpty { metadata["beamsByRing"] = rings.map { String($0) }.joined(separator: ",") }
        if let rendered = try archive.diagnosticString(additional) { metadata["additionalBeamsData"] = rendered }
        for key in layout.keys.sorted() where key != "$class" && metadata[key] == nil {
            if let rendered = try archive.diagnosticString(layout[key]) { metadata["layout.\(key)"] = rendered }
        }

        let count: Int
        switch layoutClass {
        case "LXNoBeamLayout": count = 0
        case "LXStripBeamLayout": count = max(0, length ?? declaredBeamCount ?? 0)
        case "LXRowsBeamLayout": count = max(0, rowSegments.reduce(0, +) > 0 ? rowSegments.reduce(0, +) : (declaredBeamCount ?? 0))
        case "LXRingsBeamLayout": count = max(0, rings.reduce(0, +) > 0 ? rings.reduce(0, +) : (declaredBeamCount ?? 0))
        case "LXSingleBeamLayout": count = 1
        default: count = max(0, declaredBeamCount ?? length ?? 0)
        }

        let topology: FixturePhysicalTopologyKind
        switch layoutClass {
        case "LXNoBeamLayout": topology = .noBeam
        case "LXSingleBeamLayout": topology = .single
        case "LXStripBeamLayout": topology = .linear
        case "LXRowsBeamLayout": topology = rowSegments.count > 1 && Set(rowSegments).count > 1 ? .variableRows : .grid
        case "LXGridBeamLayout": topology = .grid
        case "LXRingsBeamLayout": topology = rings.count > 1 ? .rings : .ring
        case "LXArrayBeamLayout": topology = .array
        case "LXHexagonsBeamLayout": topology = .cluster
        default: topology = count == 1 ? .single : .unknown
        }

        let emitters: [FixturePhysicalEmitter]
        switch topology {
        case .linear:
            emitters = linearEmitters(count: count)
        case .grid, .variableRows:
            emitters = rowEmitters(segments: rowSegments.isEmpty ? inferredRows(count: count) : rowSegments, heights: rowHeights)
        case .ring, .rings:
            emitters = ringEmitters(counts: rings.isEmpty ? [count] : rings)
        case .array, .cluster:
            emitters = arrayEmitters(count: count)
        case .single:
            emitters = count > 0 ? [physicalEmitter(index: 0, x: 0.5, y: 0.5, width: 0.58, height: 0.58)] : []
        default:
            emitters = []
        }

        let modelKey = model.lowercased()
        let form: FixturePhysicalForm
        if topology == .noBeam { form = .atmospheric }
        else if layoutClass == "LXStripBeamLayout" { form = .linearBar }
        else if topology == .grid || topology == .variableRows || topology == .array { form = modelKey.contains("blinder") ? .blinder : .panel }
        else if modelKey.contains("scan") { form = .scanner }
        else if modelKey.contains("haze") || modelKey.contains("fog") { form = .atmospheric }
        else if modelKey.contains("laser") || modelKey.contains("scorpion") { form = .laser }
        else if modelKey.contains("strobe") || modelKey.contains("jolt") { form = .strobe }
        else if modelKey.contains("blinder") { form = .blinder }
        else if modelKey.contains("fresnel") { form = .fresnel }
        else if modelKey.contains("profile") || modelKey.contains("ellipsoid") { form = .profile }
        else if modelKey.contains("par") { form = .par }
        else { form = count > 1 ? .linearBar : .generic }
        if topology == .unknown && form != .generic { metadata["formInference"] = "model-name-low-confidence" }
        else if [FixturePhysicalTopologyKind.grid, .variableRows, .ring, .rings, .array].contains(topology) {
            metadata["formInference"] = "layout-default"
        }

        let rows = rowSegments.isEmpty ? nil : rowSegments.count
        let columns = rowSegments.isEmpty || Set(rowSegments).count != 1 ? nil : rowSegments.first
        let group = emitters.isEmpty && topology != .noBeam ? [] : [FixturePhysicalComponentGroup(
            id: topology == .noBeam ? "no-beam" : "primary-emitters",
            role: topology == .noBeam ? .atmosphericOutlet : .emitterArray,
            topology: topology,
            rows: rows,
            columns: columns,
            emitterIDs: emitters.map(\.id),
            movement: .static,
            provenance: .imported
        )]
        let aspect: Double = {
            switch form {
            case .linearBar, .multiHeadBar: return max(2.5, Double(max(count, 1)) * 0.55)
            case .panel, .blinder, .strobe: return max(1, Double(columns ?? 2) / Double(max(rows ?? 2, 1)))
            default: return 1
            }
        }()
        return FixturePhysicalDefinition(
            id: id,
            manufacturer: manufacturer,
            model: model,
            form: form,
            aspectRatio: aspect,
            emitters: emitters,
            componentGroups: group,
            opticalBehaviors: emitters.isEmpty ? [] : [.wash, count > 1 ? .pixel : .wash],
            movement: .unknown,
            beamShape: beamShape,
            beamType: beamType,
            beamSpreadDegrees: beamSpread,
            source: .imported,
            sourceMetadata: metadata
        )
    }

    private func integerArray(_ value: LightKeyPlistValue?) throws -> [Int] {
        try archive.array(value).compactMap { try archive.int($0) }
    }

    private func doubleArray(_ value: LightKeyPlistValue?) throws -> [Double] {
        try archive.array(value).compactMap { try archive.double($0) }
    }

    private func nestedCounts(_ value: LightKeyPlistValue?) throws -> [Int] {
        try archive.array(value).compactMap { entry in
            if let count = try archive.int(entry) { return count }
            let nested = try archive.array(entry)
            return nested.isEmpty ? nil : nested.count
        }
    }

    private func linearEmitters(count: Int) -> [FixturePhysicalEmitter] {
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            physicalEmitter(index: index, x: (Double(index) + 0.5) / Double(count), y: 0.5, width: min(0.7, 0.74 / Double(count)), height: 0.58)
        }
    }

    private func inferredRows(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let columns = max(1, Int(ceil(sqrt(Double(count)))))
        var remaining = count
        var rows: [Int] = []
        while remaining > 0 { let next = min(columns, remaining); rows.append(next); remaining -= next }
        return rows
    }

    private func rowEmitters(segments: [Int], heights: [Double]) -> [FixturePhysicalEmitter] {
        let valid = segments.filter { $0 > 0 }
        guard !valid.isEmpty else { return [] }
        let rawHeights = valid.indices.map { index in index < heights.count && heights[index] > 0 ? heights[index] : 1 }
        let totalHeight = rawHeights.reduce(0, +)
        var yCursor = 0.0
        var result: [FixturePhysicalEmitter] = []
        for (row, columns) in valid.enumerated() {
            let rowHeight = rawHeights[row] / totalHeight
            for column in 0..<columns {
                result.append(physicalEmitter(index: result.count, x: (Double(column) + 0.5) / Double(columns), y: yCursor + rowHeight / 2, width: min(0.7, 0.72 / Double(columns)), height: min(0.7, rowHeight * 0.7)))
            }
            yCursor += rowHeight
        }
        return result
    }

    private func ringEmitters(counts: [Int]) -> [FixturePhysicalEmitter] {
        let valid = counts.filter { $0 > 0 }
        guard !valid.isEmpty else { return [] }
        var result: [FixturePhysicalEmitter] = []
        for (ringIndex, count) in valid.enumerated() {
            let radius = valid.count == 1 ? 0.34 : 0.15 + 0.25 * Double(ringIndex + 1) / Double(valid.count)
            for index in 0..<count {
                let angle = -.pi / 2 + 2 * .pi * Double(index) / Double(count)
                result.append(physicalEmitter(index: result.count, x: 0.5 + cos(angle) * radius, y: 0.5 + sin(angle) * radius, width: min(0.24, 0.7 / Double(max(count, 3))), height: min(0.24, 0.7 / Double(max(count, 3)))))
            }
        }
        return result
    }

    private func arrayEmitters(count: Int) -> [FixturePhysicalEmitter] {
        rowEmitters(segments: inferredRows(count: count), heights: [])
    }

    private func physicalEmitter(index: Int, x: Double, y: Double, width: Double, height: Double) -> FixturePhysicalEmitter {
        FixturePhysicalEmitter(id: "physical-emitter-\(index)", name: "Emitter \(index + 1)", x: x, y: y, width: width, height: height, shape: .circle, opticalBehaviors: [.wash])
    }

    /// Converts LightKey's per-channel beam membership into Aurora's repeated cell block.
    /// Only exact contiguous/repeated layouts are accepted; irregular layouts remain flat.
    private func makeCellLayout(
        channels: [ChannelDef],
        sources: [LightKeyChannelSource],
        numberOfBeams: Int?
    ) -> (headerChannels: [ChannelDef], cellBlock: FixtureCellBlock)? {
        guard let numberOfBeams, numberOfBeams > 1 else { return nil }
        let sourceByChannel = Dictionary(uniqueKeysWithValues: sources.map { ($0.channelID, $0) })
        let elementChannels = channels.filter { sourceByChannel[$0.id]?.beamIndexes.count == 1 }
        guard !elementChannels.isEmpty else {
            guard let inferred = FixtureDefinition.inferredRepeatedCellLayout(
                channels: channels,
                expectedCellCount: numberOfBeams
            ) else { return nil }
            return (
                inferred.header,
                FixtureCellBlock(
                    channels: inferred.cellChannels,
                    cellCount: UInt16(inferred.cellCount),
                    cellLabelPrefix: "Element"
                )
            )
        }

        let grouped = Dictionary(grouping: elementChannels) { sourceByChannel[$0.id]!.beamIndexes[0] }
        guard grouped.count == numberOfBeams else { return nil }
        let orderedGroups = grouped.keys.sorted().compactMap { grouped[$0]?.sorted { $0.offset < $1.offset } }
        guard let first = orderedGroups.first, !first.isEmpty,
              orderedGroups.allSatisfy({ $0.count == first.count })
        else { return nil }

        let signature = first.map { ($0.attribute, $0.resolution, $0.semanticKind) }
        guard orderedGroups.dropFirst().allSatisfy({ group in
            zip(group, signature).allSatisfy { channel, expected in
                channel.attribute == expected.0
                    && channel.resolution == expected.1
                    && channel.semanticKind == expected.2
            }
        }) else { return nil }

        let elementIDs = Set(elementChannels.map(\.id))
        let header = channels.filter { !elementIDs.contains($0.id) }.sorted { $0.offset < $1.offset }
        let expectedHeaderOffsets = header.indices.map { UInt16($0 + 1) }
        guard header.map(\.offset) == expectedHeaderOffsets else { return nil }

        let flattened = orderedGroups.flatMap { $0 }
        let expectedOffsets = flattened.indices.map { UInt16(header.count + $0 + 1) }
        guard flattened.map(\.offset) == expectedOffsets else { return nil }

        let relative = first.enumerated().map { index, channel -> ChannelDef in
            var copy = channel
            copy.offset = UInt16(index + 1)
            return copy
        }
        return (
            header,
            FixtureCellBlock(channels: relative, cellCount: UInt16(numberOfBeams), cellLabelPrefix: "Element")
        )
    }

    private func decodeCapability(
        _ value: LightKeyPlistValue,
        personalityIndex: Int,
        maximumBeamCount: Int
    ) throws -> RawCapability {
        let object = try archive.dictionary(value)
        let sourceClass = try archive.className(value) ?? "UnknownCapability"
        let offset = try archive.int(object["channel"])
        let customName = clean(try archive.string(object["customName"]))
        let settings = try archive.array(object["settings"])
        let decodedSettings = try settings.map(decodeSetting)
        let conditionDescription: String?
        if let condition = object["condition"], try archive.raw(condition) != .null {
            conditionDescription = try archive.diagnosticString(condition) ?? "<unavailable>"
        } else {
            conditionDescription = nil
        }
        let hasCondition = conditionDescription != nil
        let beamIndexes = (try? decodeIndexes(object["beamIndexes"], maximumCount: maximumBeamCount)) ?? []
        var issues: [FixtureImportIssue] = []
        let mapping: (String, String, ChannelResolution, ChannelSemanticKind)

        if sourceClass == "LXColorComponentCapability" {
            let component = try decodedSettings.lazy.compactMap { setting -> String? in
                guard let params = setting.params else { return nil }
                return clean(try archive.string(params["componentName"]))
            }.first
            if let color = colorMapping(component) {
                mapping = (color.attribute, component ?? customName ?? "Color Component", color.resolution, .semantic)
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
                message: "LightKey applies \(mapping.1) only when this archived condition is satisfied: \(conditionDescription ?? "<unavailable>"). Prism does not evaluate that LightKey condition, so conditional activation is not preserved during programming or playback; the channel and DMX ranges remain available.",
                personalityIndex: personalityIndex,
                channelOffset: offset.flatMap { UInt16(exactly: $0 + 1) }
            ))
        }
        let functions = decodedSettings.map {
            annotatedFunction($0.function, sourceClass: sourceClass, attribute: mapping.0)
        }

        return RawCapability(
            offset: offset,
            name: mapping.1,
            attribute: mapping.0,
            resolution: mapping.2,
            semanticKind: mapping.3,
            sourceClass: sourceClass,
            customName: customName,
            functions: functions,
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

    private func decodeIndexes(_ value: LightKeyPlistValue?, maximumCount: Int) throws -> [Int] {
        let raw = try archive.raw(value)
        let limit = max(0, maximumCount)
        if let array = raw.arrayValue {
            return Array(Set(array.compactMap(\.integerValue).filter { $0 >= 0 && $0 < limit })).sorted()
        }
        let object = raw.dictionaryValue ?? [:]
        var indexes: [Int] = []

        // NSIndexSet/NSMutableIndexSet commonly archives one contiguous range using
        // NSLocation + NSLength rather than an NS.objects array.
        if let location = try archive.int(object["NSLocation"]),
           let length = try archive.int(object["NSLength"]),
           location >= 0, location < limit, length > 0 {
            let end = location.addingReportingOverflow(length)
            if !end.overflow {
                indexes.append(contentsOf: location..<min(end.partialValue, limit))
            }
        }

        // Preserve support for explicit index arrays and arrays of archived ranges.
        for key in ["NS.objects", "NSRanges", "ranges"] {
            guard let value = object[key] else { continue }
            for entry in try archive.array(value) {
                if let index = try archive.int(entry), index >= 0, index < limit {
                    indexes.append(index)
                    continue
                }
                let range = try archive.dictionary(entry)
                if let location = try archive.int(range["NSLocation"] ?? range["location"]),
                   let length = try archive.int(range["NSLength"] ?? range["length"]),
                   location >= 0, location < limit, length > 0 {
                    let end = location.addingReportingOverflow(length)
                    if !end.overflow {
                        indexes.append(contentsOf: location..<min(end.partialValue, limit))
                    }
                }
            }
        }
        return Array(Set(indexes)).sorted()
    }

    /// LightKey beam membership is authoritative personality ownership. Channels with
    /// the same non-empty beam set belong to one control element; fixture-wide channels
    /// remain unowned. This supports contiguous, interleaved, overlapping, and irregular
    /// beam groups without inspecting repeated DMX patterns.
    private func ownershipFromBeamMembership(
        channels: [ChannelDef],
        sources: [LightKeyChannelSource],
        physicalEmitterCount: Int
    ) -> [ChannelDef]? {
        guard physicalEmitterCount > 0 else { return nil }
        let sourceByChannel = Dictionary(uniqueKeysWithValues: sources.map { ($0.channelID, $0) })
        let memberships = Set(channels.compactMap { channel -> Set<Int>? in
            let valid = Set(sourceByChannel[channel.id]?.beamIndexes.filter { physicalEmitterCount > $0 } ?? [])
            return valid.isEmpty ? nil : valid
        })
        guard !memberships.isEmpty else { return nil }
        let ordered = memberships.sorted { lhs, rhs in
            let left = lhs.sorted(), right = rhs.sorted()
            return left.lexicographicallyPrecedes(right)
        }
        let controlByMembership = Dictionary(uniqueKeysWithValues: ordered.enumerated().map {
            ($0.element, "element-\($0.offset)")
        })
        return channels.map { channel in
            var copy = channel
            let membership = Set(sourceByChannel[channel.id]?.beamIndexes ?? [])
            if !membership.isEmpty { copy.elementID = controlByMembership[membership] }
            return copy
        }
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
            if capabilities.count > 1 && compoundCapabilitiesRequireReview(capabilities) {
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
        return (channels, sources, deduplicatedIssues(issues))
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
            "LXFocusFineCapability": ("focus", "Focus Fine", .fine, .semantic),
            "LXZoomCapability": ("zoom", "Zoom", .eightBit, .semantic),
            "LXZoomFineCapability": ("zoom", "Zoom Fine", .fine, .semantic),
            "LXFrostCapability": ("frost", "Frost", .eightBit, .semantic),
            "LXIrisCapability": ("iris", "Iris", .eightBit, .semantic),
            "LXShutterStrobeCapability": ("shutter", "Shutter / Strobe", .eightBit, .semantic),
            "LXGoboCapability": ("gobo", "Gobo", .eightBit, .semantic),
            "LXGoboAngleCapability": ("goboAngle", "Gobo Angle", .eightBit, .semantic),
            "LXGoboRotationCapability": ("goboRotation", "Gobo Rotation", .eightBit, .semantic),
            "LXPrismCapability": ("prism", "Prism", .eightBit, .semantic),
            "LXPrismAngleCapability": ("prismAngle", "Prism Angle", .eightBit, .semantic),
            "LXPrismAngleFineCapability": ("prismAngle", "Prism Angle Fine", .fine, .semantic),
            "LXPrismRotationCapability": ("prismRotation", "Prism Rotation", .eightBit, .semantic),
            "LXColorWheelCapability": ("colorWheel", "Color Wheel", .eightBit, .semantic),
            "LXColorFilterCapability": ("colorWheel", "Color Filter", .eightBit, .semantic),
            "LXOnOffCapability": ("switch", "Switch", .eightBit, .generic),
            "LXFogCapability": ("fogOutput", "Fog", .eightBit, .semantic),
            "LXModeCapability": ("mode", "Mode", .eightBit, .generic),
            "LXCommandCapability": ("command", "Command", .eightBit, .generic),
            "LXLampCapability": ("command", "Lamp Command", .eightBit, .generic),
            "LXCustomCapability": ("custom", "Custom", .eightBit, .generic),
        ]
    }

    private func colorMapping(_ name: String?) -> (attribute: String, resolution: ChannelResolution)? {
        guard let name else { return nil }
        let normalized = name.lowercased().filter(\.isLetter)
        let isFine = normalized.hasSuffix("fine")
        let base = isFine ? String(normalized.dropLast(4)) : normalized
        let attribute = [
            "red": "colorR", "green": "colorG", "blue": "colorB", "white": "colorW",
            "coolwhite": "colorCoolWhite", "coldwhite": "colorCoolWhite",
            "warmwhite": "colorWarmWhite", "amber": "colorA", "ultraviolet": "colorUV",
            "uv": "colorUV", "lime": "colorLime", "cyan": "colorCyan",
        ][base]
        return attribute.map { ($0, isFine ? .fine : .eightBit) }
    }

    private func annotatedFunction(
        _ function: DMXFunctionRange,
        sourceClass: String,
        attribute: String
    ) -> DMXFunctionRange {
        var result = function
        if sourceClass == "LXCommandCapability" || sourceClass == "LXLampCapability" {
            result.semantic = .protectedCommand
            result.commandCategory = commandCategory(label: function.name, sourceClass: sourceClass)
            result.requiresConfirmation = true
            result.holdDurationMilliseconds = 1_000
            result.attribute = nil
        } else {
            result.semantic = .attribute
            result.attribute = attribute
        }
        return result
    }

    private func commandCategory(label: String, sourceClass: String) -> FixtureCommandCategory {
        let normalized = label.lowercased()
        if normalized.contains("reset") { return .reset }
        if normalized.contains("lamp") && normalized.contains("off") { return .lampOff }
        if normalized.contains("lamp") && (normalized.contains("on") || normalized.contains("strike")) { return .lampOn }
        if normalized.contains("calibr") { return .calibration }
        if normalized.contains("service") || normalized.contains("test") { return .service }
        return .custom
    }

    private func compoundCapabilitiesRequireReview(_ capabilities: [RawCapability]) -> Bool {
        guard Set(capabilities.map(\.attribute)).count > 1 else { return false }
        for leftIndex in capabilities.indices {
            for rightIndex in capabilities.indices where rightIndex > leftIndex {
                guard capabilities[leftIndex].attribute != capabilities[rightIndex].attribute else { continue }
                for left in capabilities[leftIndex].functions {
                    for right in capabilities[rightIndex].functions
                    where left.dmxMin <= right.dmxMax && right.dmxMin <= left.dmxMax {
                        return true
                    }
                }
            }
        }
        return capabilities.contains { $0.functions.isEmpty }
    }

    private func deduplicatedIssues(_ issues: [FixtureImportIssue]) -> [FixtureImportIssue] {
        struct Key: Hashable {
            var severity: FixtureImportIssueSeverity
            var code: FixtureImportIssueCode
            var message: String
            var personalityIndex: Int?
            var channelOffset: UInt16?
        }
        var seen = Set<Key>()
        return issues.filter { issue in
            seen.insert(Key(
                severity: issue.severity,
                code: issue.code,
                message: issue.message,
                personalityIndex: issue.personalityIndex,
                channelOffset: issue.channelOffset
            )).inserted
        }
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
