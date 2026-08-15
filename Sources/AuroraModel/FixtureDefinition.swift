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

/// Named DMX range on a channel (generic/raw fixture functions — A2).
public struct DMXFunctionRange: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var dmxMin: UInt8
    public var dmxMax: UInt8

    public init(id: UUID = UUID(), name: String, dmxMin: UInt8, dmxMax: UInt8) {
        self.id = id
        self.name = name
        self.dmxMin = min(dmxMin, dmxMax)
        self.dmxMax = max(dmxMin, dmxMax)
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

    public init(
        id: UUID = UUID(),
        offset: UInt16,
        name: String,
        attribute: String,
        resolution: ChannelResolution = .eightBit,
        defaultValue: UInt8 = 0,
        highlightValue: UInt8 = 255,
        semanticKind: ChannelSemanticKind = .semantic,
        dmxFunctions: [DMXFunctionRange] = []
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
    }

    private enum CodingKeys: String, CodingKey {
        case id, offset, name, attribute, resolution, defaultValue, highlightValue, semanticKind, dmxFunctions
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
        category: String = ""
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
        if let explicit = try c.decodeIfPresent(UInt16.self, forKey: .channelCount) {
            channelCount = explicit
        } else {
            channelCount = Self.computeFootprint(channels: channels, cellBlock: cellBlock)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, manufacturer, model, modeName, channelCount, channels, colorModel
        case hasPanTilt, panInvert, tiltInvert, wheels, cellBlock, category
    }
}
