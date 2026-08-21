import Foundation

/// High-level color mixing capability advertised by a personality.
public enum ColorModel: String, Codable, Sendable, Hashable, CaseIterable {
    case rgb
    case rgbw
    case rgba
    case cmy
    case hsv
    case singleColor
}

/// Whether a DMX channel is the coarse or fine half of a 16-bit pair.
public enum ChannelResolution: String, Codable, Sendable, Hashable, CaseIterable {
    case coarse
    case fine
    case eightBit
}

/// Semantic meaning of a value range within one physical DMX channel.
/// This allows one channel to expose several functions without inventing extra output slots.
public enum DMXFunctionSemantic: String, Codable, Sendable, Hashable, CaseIterable {
    case generic
    case attribute
    case protectedCommand
}

public enum FixtureCommandCategory: String, Codable, Sendable, Hashable, CaseIterable {
    case reset
    case lampOn
    case lampOff
    case calibration
    case service
    case custom
}

/// Named DMX range on a channel (generic/raw fixture functions — A2).
public struct DMXFunctionRange: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var dmxMin: UInt8
    public var dmxMax: UInt8
    /// Optional Prism attribute active inside this range.
    public var attribute: String?
    public var semantic: DMXFunctionSemantic
    public var commandCategory: FixtureCommandCategory?
    /// Minimum deliberate activation time requested by the fixture definition.
    public var holdDurationMilliseconds: UInt32?
    public var requiresConfirmation: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        dmxMin: UInt8,
        dmxMax: UInt8,
        attribute: String? = nil,
        semantic: DMXFunctionSemantic = .generic,
        commandCategory: FixtureCommandCategory? = nil,
        holdDurationMilliseconds: UInt32? = nil,
        requiresConfirmation: Bool = false
    ) {
        self.id = id
        self.name = name
        self.dmxMin = min(dmxMin, dmxMax)
        self.dmxMax = max(dmxMin, dmxMax)
        self.attribute = attribute
        self.semantic = semantic
        self.commandCategory = commandCategory
        self.holdDurationMilliseconds = holdDurationMilliseconds
        self.requiresConfirmation = requiresConfirmation
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        let first = try c.decode(UInt8.self, forKey: .dmxMin)
        let second = try c.decode(UInt8.self, forKey: .dmxMax)
        dmxMin = min(first, second)
        dmxMax = max(first, second)
        attribute = try c.decodeIfPresent(String.self, forKey: .attribute)
        semantic = try c.decodeIfPresent(DMXFunctionSemantic.self, forKey: .semantic) ?? .generic
        commandCategory = try c.decodeIfPresent(FixtureCommandCategory.self, forKey: .commandCategory)
        holdDurationMilliseconds = try c.decodeIfPresent(UInt32.self, forKey: .holdDurationMilliseconds)
        requiresConfirmation = try c.decodeIfPresent(Bool.self, forKey: .requiresConfirmation) ?? false
    }

    public var isProtected: Bool {
        semantic == .protectedCommand || requiresConfirmation
    }

    public func contains(_ value: UInt8) -> Bool {
        dmxMin...dmxMax ~= value
    }
}

/// How a channel maps into Aurora semantics (or generic escape hatch).
public enum ChannelSemanticKind: String, Codable, Sendable, Hashable, CaseIterable {
    /// Known Aurora semantic attribute (intensity, colorR, pan, …).
    case semantic
    /// Named generic parameter with optional DMX function ranges (A2).
    case generic
}

/// One channel slot in a fixture personality.
public struct ChannelDef: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    /// 1-based offset within the fixture's DMX footprint.
    public var offset: UInt16
    public var name: String
    /// Semantic attribute tag (e.g. `intensity`, `pan`, `colorR`) or generic key.
    public var attribute: String
    public var resolution: ChannelResolution
    /// Default DMX value (0…255 for 8-bit).
    public var defaultValue: UInt8
    /// Highlight/locate suggestion (0…255).
    public var highlightValue: UInt8
    /// Semantic vs generic (A2). Defaults to semantic for backward compatibility.
    public var semanticKind: ChannelSemanticKind
    /// Optional DMX function table for generic (or descriptive) channels.
    public var dmxFunctions: [DMXFunctionRange]
    /// Optional controllable-element owner within this personality. Nil means
    /// fixture-wide/shared. This is never a physical-emitter identity.
    public var elementID: String?

    public init(
        id: UUID = UUID(),
        offset: UInt16,
        name: String,
        attribute: String,
        resolution: ChannelResolution = .eightBit,
        defaultValue: UInt8 = 0,
        highlightValue: UInt8 = 255,
        semanticKind: ChannelSemanticKind = .semantic,
        dmxFunctions: [DMXFunctionRange] = [],
        elementID: String? = nil
    ) {
        self.id = id
        self.offset = offset
        self.name = name
        self.attribute = attribute
        self.resolution = resolution
        self.defaultValue = defaultValue
        self.highlightValue = highlightValue
        self.semanticKind = semanticKind
        self.dmxFunctions = dmxFunctions
        self.elementID = elementID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        offset = try c.decode(UInt16.self, forKey: .offset)
        name = try c.decode(String.self, forKey: .name)
        attribute = try c.decode(String.self, forKey: .attribute)
        resolution = try c.decodeIfPresent(ChannelResolution.self, forKey: .resolution) ?? .eightBit
        defaultValue = try c.decodeIfPresent(UInt8.self, forKey: .defaultValue) ?? 0
        highlightValue = try c.decodeIfPresent(UInt8.self, forKey: .highlightValue) ?? 255
        semanticKind = try c.decodeIfPresent(ChannelSemanticKind.self, forKey: .semanticKind) ?? .semantic
        dmxFunctions = try c.decodeIfPresent([DMXFunctionRange].self, forKey: .dmxFunctions) ?? []
        elementID = try c.decodeIfPresent(String.self, forKey: .elementID)
    }

    private enum CodingKeys: String, CodingKey {
        case id, offset, name, attribute, resolution, defaultValue, highlightValue, semanticKind, dmxFunctions, elementID
    }
}

/// Multi-cell / parameterized pixel fixture block (A1 / PR-P2B).
public struct FixtureCellBlock: Codable, Equatable, Sendable, Hashable {
    /// Channels that repeat per cell (offsets relative to cell start, 1-based within block).
    public var channels: [ChannelDef]
    /// Operator-configured cell count (variable footprint).
    public var cellCount: UInt16
    /// Optional label prefix (e.g. "Cell").
    public var cellLabelPrefix: String

    public init(
        channels: [ChannelDef] = [],
        cellCount: UInt16 = 1,
        cellLabelPrefix: String = "Cell"
    ) {
        self.channels = channels
        self.cellCount = max(1, cellCount)
        self.cellLabelPrefix = cellLabelPrefix
    }

    public var channelsPerCell: UInt16 { UInt16(channels.count) }
    public var footprint: UInt16 { channelsPerCell * cellCount }
}

/// A slot on a color or gobo wheel.
public struct WheelSlot: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var index: UInt16
    public var name: String
    /// Optional DMX value that selects this slot.
    public var dmxValue: UInt8?

    public init(
        id: UUID = UUID(),
        index: UInt16,
        name: String,
        dmxValue: UInt8? = nil
    ) {
        self.id = id
        self.index = index
        self.name = name
        self.dmxValue = dmxValue
    }
}

public enum WheelKind: String, Codable, Sendable, Hashable, CaseIterable {
    case color
    case gobo
    case other
}

public struct WheelDef: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var kind: WheelKind
    public var slots: [WheelSlot]

    public init(
        id: UUID = UUID(),
        name: String,
        kind: WheelKind,
        slots: [WheelSlot] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.slots = slots
    }
}

/// Fixture personality (library or embedded in a project).
public struct FixtureDefinition: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var manufacturer: String
    public var model: String
    public var modeName: String
    public var channelCount: UInt16
    public var channels: [ChannelDef]
    public var colorModel: ColorModel?
    public var hasPanTilt: Bool
    public var panInvert: Bool
    public var tiltInvert: Bool
    public var wheels: [WheelDef]
    /// Optional multi-cell block (A1). When set, total footprint = base channels + cell block footprint.
    public var cellBlock: FixtureCellBlock?
    /// Broad fixture category for Stage symbols / library filtering.
    public var category: String
    /// Native, source-neutral Stage glyph/topology metadata.
    public var visual: FixtureVisualDefinition?
    /// Stable identity of the shared physical product represented by this personality.
    public var physicalFixtureID: UUID?
    /// Portable snapshot used when a personality travels outside a project catalog.
    /// A project-level physical definition with the same id is authoritative.
    public var portablePhysicalDefinition: FixturePhysicalDefinition?
    /// Personality-local controllable elements and their physical relationships.
    public var controlElements: [FixtureControlElement]
    public var emitterMappings: [FixtureEmitterMapping]

    public init(
        id: UUID = UUID(),
        manufacturer: String,
        model: String,
        modeName: String = "Default",
        channelCount: UInt16? = nil,
        channels: [ChannelDef] = [],
        colorModel: ColorModel? = nil,
        hasPanTilt: Bool = false,
        panInvert: Bool = false,
        tiltInvert: Bool = false,
        wheels: [WheelDef] = [],
        cellBlock: FixtureCellBlock? = nil,
        category: String = "",
        visual: FixtureVisualDefinition? = nil,
        physicalFixtureID: UUID? = nil,
        portablePhysicalDefinition: FixturePhysicalDefinition? = nil,
        controlElements: [FixtureControlElement] = [],
        emitterMappings: [FixtureEmitterMapping] = []
    ) {
        self.id = id
        self.manufacturer = manufacturer
        self.model = model
        self.modeName = modeName
        self.channels = channels
        self.colorModel = colorModel
        self.hasPanTilt = hasPanTilt
        self.panInvert = panInvert
        self.tiltInvert = tiltInvert
        self.wheels = wheels
        self.cellBlock = cellBlock
        self.category = category
        self.visual = visual
        self.physicalFixtureID = physicalFixtureID ?? portablePhysicalDefinition?.id
        self.portablePhysicalDefinition = portablePhysicalDefinition
        self.controlElements = controlElements
        self.emitterMappings = emitterMappings
        if let channelCount {
            self.channelCount = channelCount
        } else {
            self.channelCount = Self.computeFootprint(channels: channels, cellBlock: cellBlock)
        }
    }

    public var displayName: String {
        "\(manufacturer) \(model) (\(modeName))"
    }

    /// Calculated DMX footprint including multi-cell expansion.
    public var calculatedFootprint: UInt16 {
        Self.computeFootprint(channels: channels, cellBlock: cellBlock)
    }

    public static func computeFootprint(channels: [ChannelDef], cellBlock: FixtureCellBlock?) -> UInt16 {
        let base = UInt16(channels.map(\.offset).max() ?? UInt16(channels.count))
        let cells = cellBlock?.footprint ?? 0
        // If cell block is present and channels are only the header, sum; if channels already full, prefer max.
        if cells > 0 {
            return max(base, 0) + cells
        }
        return max(base, UInt16(channels.count))
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        manufacturer = try c.decode(String.self, forKey: .manufacturer)
        model = try c.decode(String.self, forKey: .model)
        modeName = try c.decodeIfPresent(String.self, forKey: .modeName) ?? "Default"
        channels = try c.decodeIfPresent([ChannelDef].self, forKey: .channels) ?? []
        colorModel = try c.decodeIfPresent(ColorModel.self, forKey: .colorModel)
        hasPanTilt = try c.decodeIfPresent(Bool.self, forKey: .hasPanTilt) ?? false
        panInvert = try c.decodeIfPresent(Bool.self, forKey: .panInvert) ?? false
        tiltInvert = try c.decodeIfPresent(Bool.self, forKey: .tiltInvert) ?? false
        wheels = try c.decodeIfPresent([WheelDef].self, forKey: .wheels) ?? []
        cellBlock = try c.decodeIfPresent(FixtureCellBlock.self, forKey: .cellBlock)
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
        visual = try c.decodeIfPresent(FixtureVisualDefinition.self, forKey: .visual)
        physicalFixtureID = try c.decodeIfPresent(UUID.self, forKey: .physicalFixtureID)
        portablePhysicalDefinition = try c.decodeIfPresent(FixturePhysicalDefinition.self, forKey: .portablePhysicalDefinition)
        controlElements = try c.decodeIfPresent([FixtureControlElement].self, forKey: .controlElements) ?? []
        emitterMappings = try c.decodeIfPresent([FixtureEmitterMapping].self, forKey: .emitterMappings) ?? []
        if let explicit = try c.decodeIfPresent(UInt16.self, forKey: .channelCount) {
            channelCount = explicit
        } else {
            channelCount = Self.computeFootprint(channels: channels, cellBlock: cellBlock)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, manufacturer, model, modeName, channelCount, channels, colorModel
        case hasPanTilt, panInvert, tiltInvert, wheels, cellBlock, category, visual
        case physicalFixtureID, portablePhysicalDefinition, controlElements, emitterMappings
    }

    /// Detect `shared header + N identical contiguous channel groups`.
    /// An importer can provide an authoritative element count; legacy decoding can
    /// omit it and use the strongest structurally valid repeated suffix.
    public static func inferredRepeatedCellLayout(
        channels: [ChannelDef],
        expectedCellCount: Int? = nil
    ) -> (header: [ChannelDef], cellChannels: [ChannelDef], cellCount: Int)? {
        let sorted = channels.sorted { $0.offset < $1.offset }
        guard sorted.count >= 2,
              sorted.map(\.offset) == Array(1...sorted.count).map(UInt16.init)
        else { return nil }

        let counts: [Int]
        if let expectedCellCount {
            guard expectedCellCount > 1 else { return nil }
            counts = [expectedCellCount]
        } else {
            counts = Array(2...min(64, sorted.count)).reversed()
        }

        var candidates: [(header: [ChannelDef], cellChannels: [ChannelDef], cellCount: Int)] = []
        for cellCount in counts {
            let maximumChannelsPerCell = sorted.count / cellCount
            guard maximumChannelsPerCell >= 1 else { continue }
            for perCell in 1...maximumChannelsPerCell {
                let repeatedCount = perCell * cellCount
                let headerCount = sorted.count - repeatedCount
                let tail = Array(sorted.dropFirst(headerCount))
                let groups = stride(from: 0, to: tail.count, by: perCell).map {
                    Array(tail[$0..<($0 + perCell)])
                }
                guard let first = groups.first else { continue }
                let signature = first.map { ($0.attribute, $0.resolution, $0.semanticKind) }
                let emitsLight = first.contains {
                    let base = $0.attribute.lowercased()
                    return base == "intensity" || base == "dimmer" || base.hasPrefix("color")
                }
                guard emitsLight,
                      groups.dropFirst().allSatisfy({ group in
                          zip(group, signature).allSatisfy { channel, expected in
                              channel.attribute == expected.0
                                  && channel.resolution == expected.1
                                  && channel.semanticKind == expected.2
                          }
                      })
                else { continue }
                let relative = first.enumerated().map { index, channel -> ChannelDef in
                    var copy = channel
                    copy.offset = UInt16(index + 1)
                    return copy
                }
                candidates.append((Array(sorted.prefix(headerCount)), relative, cellCount))
            }
        }
        // Prefer the candidate that explains the largest suffix, then the greatest
        // element count (the smallest true repeating unit).
        return candidates.max {
            let lhsCoverage = $0.cellChannels.count * $0.cellCount
            let rhsCoverage = $1.cellChannels.count * $1.cellCount
            return lhsCoverage == rhsCoverage ? $0.cellCount < $1.cellCount : lhsCoverage < rhsCoverage
        }
    }

    /// Finds the largest repeated light-producing channel window anywhere in a flat
    /// footprint, allowing shared channels before and after it.
    public static func inferredElementOwnership(
        channels: [ChannelDef],
        expectedElementCount: Int? = nil
    ) -> (channels: [ChannelDef], elementCount: Int)? {
        let sorted = channels.sorted { $0.offset < $1.offset }
        guard sorted.count >= 2 else { return nil }
        struct Candidate { var start: Int; var perElement: Int; var count: Int }
        var best: Candidate?
        let counts = expectedElementCount.map { [$0] } ?? Array(2...min(64, sorted.count))
        for count in counts where count > 1 {
            let maximumChannelsPerElement = sorted.count / count
            guard maximumChannelsPerElement >= 1 else { continue }
            for start in sorted.indices {
                for perElement in 1...maximumChannelsPerElement {
                    let end = start + perElement * count
                    guard end <= sorted.count else { continue }
                    let first = Array(sorted[start..<(start + perElement)])
                    let emits = first.contains {
                        let a = $0.attribute.lowercased()
                        return a == "intensity" || a == "dimmer" || a.hasPrefix("color")
                    }
                    guard emits else { continue }
                    let signature = first.map { ($0.attribute, $0.resolution, $0.semanticKind) }
                    var valid = true
                    for groupIndex in 1..<count {
                        let lo = start + groupIndex * perElement
                        let group = sorted[lo..<(lo + perElement)]
                        if !zip(group, signature).allSatisfy({ channel, expected in
                            channel.attribute == expected.0 && channel.resolution == expected.1 && channel.semanticKind == expected.2
                        }) { valid = false; break }
                    }
                    guard valid else { continue }
                    let candidate = Candidate(start: start, perElement: perElement, count: count)
                    let coverage = perElement * count
                    let bestCoverage = best.map { $0.perElement * $0.count } ?? 0
                    if coverage > bestCoverage || (coverage == bestCoverage && count > (best?.count ?? 0)) {
                        best = candidate
                    }
                }
            }
        }
        guard let best else { return nil }
        var owned = sorted
        for elementIndex in 0..<best.count {
            let lo = best.start + elementIndex * best.perElement
            for channelIndex in lo..<(lo + best.perElement) {
                owned[channelIndex].elementID = "element-\(elementIndex)"
            }
        }
        return (owned, best.count)
    }
}
