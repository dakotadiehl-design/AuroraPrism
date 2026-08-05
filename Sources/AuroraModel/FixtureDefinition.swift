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

/// One channel slot in a fixture personality.
public struct ChannelDef: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    /// 1-based offset within the fixture's DMX footprint.
    public var offset: UInt16
    public var name: String
    /// Semantic attribute tag (e.g. `intensity`, `pan`, `colorR`). Free-form for PR2.
    public var attribute: String
    public var resolution: ChannelResolution
    /// Default DMX value (0…255 for 8-bit).
    public var defaultValue: UInt8
    /// Highlight/locate suggestion (0…255).
    public var highlightValue: UInt8

    public init(
        id: UUID = UUID(),
        offset: UInt16,
        name: String,
        attribute: String,
        resolution: ChannelResolution = .eightBit,
        defaultValue: UInt8 = 0,
        highlightValue: UInt8 = 255
    ) {
        self.id = id
        self.offset = offset
        self.name = name
        self.attribute = attribute
        self.resolution = resolution
        self.defaultValue = defaultValue
        self.highlightValue = highlightValue
    }
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
        wheels: [WheelDef] = []
    ) {
        self.id = id
        self.manufacturer = manufacturer
        self.model = model
        self.modeName = modeName
        self.channels = channels
        self.channelCount = channelCount ?? UInt16(channels.count)
        self.colorModel = colorModel
        self.hasPanTilt = hasPanTilt
        self.panInvert = panInvert
        self.tiltInvert = tiltInvert
        self.wheels = wheels
    }

    public var displayName: String {
        "\(manufacturer) \(model) (\(modeName))"
    }
}
