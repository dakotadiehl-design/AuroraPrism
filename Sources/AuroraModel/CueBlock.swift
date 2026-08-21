import Foundation

// MARK: - Cue Block domain types

/// Semantic family of a Cue Block (independent of `PaletteType` so semantics may diverge).
public enum CueBlockType: String, Codable, Sendable, Hashable, CaseIterable {
    case intensity
    case color
    case position
    case beam
    case gobo
    case general
}

/// User-organized folder in the Cue Blocks library. A folder may remember the fixture
/// group that inspired it, but it remains valid and independently renameable if that
/// fixture group later changes or is removed.
public struct CueBlockGroup: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var sourceFixtureGroupID: UUID?
    public var notes: String
    /// Optional presentation names for semantic sections within this group.
    /// The Cue Block type remains unchanged; this only customizes the library label.
    public var sectionNames: [CueBlockType: String]

    public init(
        id: UUID = UUID(),
        name: String,
        sourceFixtureGroupID: UUID? = nil,
        notes: String = "",
        sectionNames: [CueBlockType: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.sourceFixtureGroupID = sourceFixtureGroupID
        self.notes = notes
        self.sectionNames = sectionNames
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, sourceFixtureGroupID, notes, sectionNames
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        sourceFixtureGroupID = try c.decodeIfPresent(UUID.self, forKey: .sourceFixtureGroupID)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        sectionNames = try c.decodeIfPresent([CueBlockType: String].self, forKey: .sectionNames) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(sourceFixtureGroupID, forKey: .sourceFixtureGroupID)
        try c.encode(notes, forKey: .notes)
        if !sectionNames.isEmpty {
            try c.encode(sectionNames, forKey: .sectionNames)
        }
    }
}

/// Named, fixture-scoped reusable package of attribute values. Cues store live references.
public struct CueBlock: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var type: CueBlockType
    public var levels: CueLevelData
    /// Organizational folder in the Cue Blocks library. Nil is presented as Unfiled.
    public var cueBlockGroupID: UUID?
    /// Fixture-group provenance only; concrete fixture IDs in `levels` remain authoritative.
    public var sourceGroupID: UUID?
    public var notes: String

    public init(
        id: UUID = UUID(),
        name: String,
        type: CueBlockType,
        levels: CueLevelData = .empty,
        cueBlockGroupID: UUID? = nil,
        sourceGroupID: UUID? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.levels = levels
        self.cueBlockGroupID = cueBlockGroupID
        self.sourceGroupID = sourceGroupID
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, type, levels, cueBlockGroupID, sourceGroupID, notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        type = try c.decode(CueBlockType.self, forKey: .type)
        levels = try c.decodeIfPresent(CueLevelData.self, forKey: .levels) ?? .empty
        cueBlockGroupID = try c.decodeIfPresent(UUID.self, forKey: .cueBlockGroupID)
        sourceGroupID = try c.decodeIfPresent(UUID.self, forKey: .sourceGroupID)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(type, forKey: .type)
        try c.encode(levels, forKey: .levels)
        try c.encodeIfPresent(cueBlockGroupID, forKey: .cueBlockGroupID)
        try c.encodeIfPresent(sourceGroupID, forKey: .sourceGroupID)
        try c.encode(notes, forKey: .notes)
    }
}

/// Membership of a Cue Block inside a cue. Own ID is stable for UI selection/reorder.
public struct CueBlockReference: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var cueBlockID: UUID
    public var enabled: Bool

    public init(id: UUID = UUID(), cueBlockID: UUID, enabled: Bool = true) {
        self.id = id
        self.cueBlockID = cueBlockID
        self.enabled = enabled
    }
}

/// Structured site of a Cue Block reference for dependency UI (not preformatted strings only).
public struct CueBlockReferenceSite: Equatable, Sendable, Hashable {
    public var cueListID: UUID
    public var cueListName: String
    public var cueID: UUID
    public var cueNumber: Decimal
    public var cueName: String
    public var referenceID: UUID

    public init(
        cueListID: UUID,
        cueListName: String,
        cueID: UUID,
        cueNumber: Decimal,
        cueName: String,
        referenceID: UUID
    ) {
        self.cueListID = cueListID
        self.cueListName = cueListName
        self.cueID = cueID
        self.cueNumber = cueNumber
        self.cueName = cueName
        self.referenceID = referenceID
    }
}

// MARK: - Issues

public enum CueBlockIssueSeverity: String, Codable, Sendable, Hashable {
    case error
    case warning
    case information
}

public struct CueBlockRecordingIssue: Equatable, Sendable, Hashable {
    public var code: String
    public var severity: CueBlockIssueSeverity
    public var message: String
    public var fixtureID: UUID?
    public var attribute: String?

    public init(
        code: String,
        severity: CueBlockIssueSeverity,
        message: String,
        fixtureID: UUID? = nil,
        attribute: String? = nil
    ) {
        self.code = code
        self.severity = severity
        self.message = message
        self.fixtureID = fixtureID
        self.attribute = attribute
    }
}

public struct CueBlockResolutionIssue: Equatable, Sendable, Hashable {
    public var code: String
    public var severity: CueBlockIssueSeverity
    public var message: String
    public var cueID: UUID?
    public var referenceID: UUID?
    public var cueBlockID: UUID?
    public var fixtureID: UUID?
    public var paletteID: UUID?
    public var attribute: String?

    public init(
        code: String,
        severity: CueBlockIssueSeverity,
        message: String,
        cueID: UUID? = nil,
        referenceID: UUID? = nil,
        cueBlockID: UUID? = nil,
        fixtureID: UUID? = nil,
        paletteID: UUID? = nil,
        attribute: String? = nil
    ) {
        self.code = code
        self.severity = severity
        self.message = message
        self.cueID = cueID
        self.referenceID = referenceID
        self.cueBlockID = cueBlockID
        self.fixtureID = fixtureID
        self.paletteID = paletteID
        self.attribute = attribute
    }
}

// MARK: - Attribute family (canonical classifier)

/// Single source of truth for mapping semantic attribute tags to Cue Block families.
public enum CueBlockAttributeFamily {
    public static let intensityTags: Set<String> = [
        "intensity", "dimmer", "dim",
    ]

    public static let colorTags: Set<String> = [
        "colorHue", "colorSat", "colorVal", "colorWB",
        "colorR", "colorG", "colorB", "colorW", "colorA", "colorUV",
        "colorWarmWhite", "colorCoolWhite", "colorLime", "colorCyan",
        "cyan", "magenta", "yellow",
    ]

    public static let softAuthoringColorTags: Set<String> = [
        "colorHue", "colorSat", "colorVal", "colorWB",
    ]

    public static let positionTags: Set<String> = [
        "pan", "tilt",
    ]

    public static let beamTags: Set<String> = [
        "zoom", "focus", "iris", "frost", "prism", "prismRotate",
        "beam", "diffusion",
        "blade1", "blade2", "blade3", "blade4",
    ]

    public static let goboTags: Set<String> = [
        "gobo", "goboRotate", "goboIndex", "goboWheel",
    ]

    public static let strobeTags: Set<String> = [
        "shutter", "strobe", "strobeRate", "strobeDuration", "shutterStrobe",
    ]

    /// Classify a single attribute tag. Unknown returns `nil` (only valid under `.general`).
    public static func family(for attribute: String) -> CueBlockType? {
        let base = baseAttribute(attribute)
        if intensityTags.contains(base) || intensityTags.contains(attribute) {
            return .intensity
        }
        if colorTags.contains(base) || colorTags.contains(attribute) {
            return .color
        }
        if positionTags.contains(base) || positionTags.contains(attribute) {
            return .position
        }
        if goboTags.contains(base) || goboTags.contains(attribute)
            || base.hasPrefix("gobo") || attribute.hasPrefix("gobo") {
            return .gobo
        }
        if beamTags.contains(base) || beamTags.contains(attribute) {
            return .beam
        }
        // Strobe/shutter treated as beam family for typed blocks (console convention).
        if strobeTags.contains(base) || strobeTags.contains(attribute) {
            return .beam
        }
        return nil
    }

    /// Whether `attribute` may be recorded into a block of `type`.
    public static func isAllowed(_ attribute: String, for type: CueBlockType) -> Bool {
        switch type {
        case .general:
            return true
        case .intensity, .color, .position, .beam, .gobo:
            return family(for: attribute) == type
        }
    }

    public static func baseAttribute(_ attribute: String) -> String {
        attribute.split(separator: "@").first.map(String.init) ?? attribute
    }

    /// Attribute keys preferred for palette-style family selection (exact lists).
    public static func knownTags(for type: CueBlockType) -> [String] {
        switch type {
        case .intensity:
            return Array(intensityTags).sorted()
        case .color:
            return Array(colorTags).sorted()
        case .position:
            return Array(positionTags).sorted()
        case .beam:
            return (Array(beamTags) + Array(strobeTags)).sorted()
        case .gobo:
            return Array(goboTags).sorted()
        case .general:
            return (
                Array(intensityTags)
                    + Array(colorTags)
                    + Array(positionTags)
                    + Array(beamTags)
                    + Array(goboTags)
                    + Array(strobeTags)
            ).sorted()
        }
    }
}

// MARK: - Recorder

/// UI-neutral recording of Programmer values into a Cue Block value (does not mutate the project).
public enum CueBlockRecorder {
    public struct Request: Sendable {
        public var name: String
        public var type: CueBlockType
        public var programmerValues: [UUID: [String: Double]]
        public var selectedFixtureIDs: [UUID]
        public var cueBlockGroupID: UUID?
        public var sourceGroupID: UUID?
        public var notes: String
        /// When set, the produced block keeps this identity (update path).
        public var existingID: UUID?
        /// Fixture → supported attributes (effective map including virtual intensity / soft authoring eligibility).
        public var capabilityMap: [UUID: Set<String>]

        public init(
            name: String,
            type: CueBlockType,
            programmerValues: [UUID: [String: Double]],
            selectedFixtureIDs: [UUID],
            cueBlockGroupID: UUID? = nil,
            sourceGroupID: UUID? = nil,
            notes: String = "",
            existingID: UUID? = nil,
            capabilityMap: [UUID: Set<String>] = [:]
        ) {
            self.name = name
            self.type = type
            self.programmerValues = programmerValues
            self.selectedFixtureIDs = selectedFixtureIDs
            self.cueBlockGroupID = cueBlockGroupID
            self.sourceGroupID = sourceGroupID
            self.notes = notes
            self.existingID = existingID
            self.capabilityMap = capabilityMap
        }
    }

    public struct Result: Equatable, Sendable {
        public var cueBlock: CueBlock?
        public var issues: [CueBlockRecordingIssue]

        public init(cueBlock: CueBlock?, issues: [CueBlockRecordingIssue]) {
            self.cueBlock = cueBlock
            self.issues = issues
        }
    }

    public static func record(_ request: Request) -> Result {
        var issues: [CueBlockRecordingIssue] = []

        guard !request.selectedFixtureIDs.isEmpty else {
            issues.append(CueBlockRecordingIssue(
                code: "no-selection",
                severity: .error,
                message: "At least one fixture must be selected to record a Cue Block"
            ))
            return Result(cueBlock: nil, issues: issues)
        }

        var fixtures: [FixtureCueLevels] = []
        fixtures.reserveCapacity(request.selectedFixtureIDs.count)

        for fixtureID in request.selectedFixtureIDs {
            let raw = request.programmerValues[fixtureID] ?? [:]
            let caps = request.capabilityMap[fixtureID] ?? []
            let filterResult = filterFixtureAttributes(
                raw: raw,
                type: request.type,
                supported: caps,
                fixtureID: fixtureID,
                issues: &issues
            )
            if filterResult.isEmpty {
                if raw.isEmpty {
                    issues.append(CueBlockRecordingIssue(
                        code: "fixture-no-matching-data",
                        severity: .warning,
                        message: "Selected fixture has no programmer values for this Cue Block type",
                        fixtureID: fixtureID
                    ))
                } else {
                    issues.append(CueBlockRecordingIssue(
                        code: "fixture-no-matching-data",
                        severity: .warning,
                        message: "Selected fixture had no recordable values after family/capability filtering",
                        fixtureID: fixtureID
                    ))
                }
                continue
            }
            fixtures.append(FixtureCueLevels(fixtureId: fixtureID, attributes: filterResult, paletteRefs: [:]))
        }

        guard !fixtures.isEmpty else {
            issues.append(CueBlockRecordingIssue(
                code: "no-matching-values",
                severity: .error,
                message: "No recordable values remained after filtering"
            ))
            return Result(cueBlock: nil, issues: issues)
        }

        let block = CueBlock(
            id: request.existingID ?? UUID(),
            name: request.name,
            type: request.type,
            levels: CueLevelData(fixtures: fixtures),
            cueBlockGroupID: request.cueBlockGroupID,
            sourceGroupID: request.sourceGroupID,
            notes: request.notes
        )
        return Result(cueBlock: block, issues: issues)
    }

    /// Soft authoring keys apply only when the fixture supports RGB authoring.
    private static func filterFixtureAttributes(
        raw: [String: Double],
        type: CueBlockType,
        supported: Set<String>,
        fixtureID: UUID,
        issues: inout [CueBlockRecordingIssue]
    ) -> [String: Double] {
        let rgbOK = supported.contains("colorR")
            && supported.contains("colorG")
            && supported.contains("colorB")
        var kept: [String: Double] = [:]

        for (key, value) in raw {
            if !CueBlockAttributeFamily.isAllowed(key, for: type) {
                if type != .general {
                    issues.append(CueBlockRecordingIssue(
                        code: "attribute-family-skipped",
                        severity: .warning,
                        message: "Attribute \(key) is not part of Cue Block type \(type.rawValue)",
                        fixtureID: fixtureID,
                        attribute: key
                    ))
                }
                continue
            }

            let isSoft = CueBlockAttributeFamily.softAuthoringColorTags.contains(key)
            let capable: Bool
            if isSoft {
                capable = rgbOK
            } else if key == "intensity" || key == "dimmer" || key == "dim" {
                // Effective map may include virtual intensity.
                capable = supported.contains("intensity")
                    || supported.contains("dimmer")
                    || supported.contains("dim")
                    || supported.contains(key)
            } else {
                capable = supported.contains(key)
                    || supported.contains(CueBlockAttributeFamily.baseAttribute(key))
            }

            if !capable {
                issues.append(CueBlockRecordingIssue(
                    code: "unsupported-attribute-skipped",
                    severity: .warning,
                    message: "Attribute \(key) is not supported by the fixture personality",
                    fixtureID: fixtureID,
                    attribute: key
                ))
                continue
            }

            kept[key] = value
        }
        return kept
    }
}

// MARK: - ShowProject queries

public extension ShowProject {
    func cueBlockReferenceCount(_ cueBlockID: UUID) -> Int {
        var count = 0
        for list in cueLists {
            for cue in list.cues {
                count += cue.cueBlockRefs.filter { $0.cueBlockID == cueBlockID }.count
            }
        }
        return count
    }

    func cueBlockReferenceSites(_ cueBlockID: UUID) -> [CueBlockReferenceSite] {
        var sites: [CueBlockReferenceSite] = []
        for list in cueLists {
            for cue in list.cues {
                for ref in cue.cueBlockRefs where ref.cueBlockID == cueBlockID {
                    sites.append(CueBlockReferenceSite(
                        cueListID: list.id,
                        cueListName: list.name,
                        cueID: cue.id,
                        cueNumber: cue.number,
                        cueName: cue.name,
                        referenceID: ref.id
                    ))
                }
            }
        }
        return sites
    }

    func cueBlocks(
        cueBlockGroupID: UUID? = nil,
        sourceGroupID: UUID? = nil,
        type: CueBlockType? = nil
    ) -> [CueBlock] {
        cueBlocks.filter { block in
            if let cueBlockGroupID, block.cueBlockGroupID != cueBlockGroupID { return false }
            if let sourceGroupID, block.sourceGroupID != sourceGroupID { return false }
            if let type, block.type != type { return false }
            return true
        }
    }

    func cueBlock(id: UUID) -> CueBlock? {
        cueBlocks.first { $0.id == id }
    }

    func cueBlockGroup(id: UUID) -> CueBlockGroup? {
        cueBlockGroups.first { $0.id == id }
    }
}
