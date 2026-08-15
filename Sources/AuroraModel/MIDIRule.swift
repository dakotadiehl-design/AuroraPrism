import Foundation

/// Advanced MIDI rule (P0-J foundation). Simple `MIDIMapping` remains supported.
public struct MIDIRule: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var enabled: Bool
    public var priority: Int
    /// Optional CoreMIDI device id filter.
    public var deviceID: String?
    public var channel: UInt8?
    public var messageType: String
    public var data1Min: UInt8?
    public var data1Max: UInt8?
    public var data2Min: UInt8?
    public var data2Max: UInt8?
    /// ShowAction storage keys to fire (multi-action).
    public var actionKeys: [String]
    public var actionParameters: [String]
    /// Optional song section label context (empty = any).
    public var songSectionContext: String?

    public init(
        id: UUID = UUID(),
        name: String = "",
        enabled: Bool = true,
        priority: Int = 0,
        deviceID: String? = nil,
        channel: UInt8? = nil,
        messageType: String,
        data1Min: UInt8? = nil,
        data1Max: UInt8? = nil,
        data2Min: UInt8? = nil,
        data2Max: UInt8? = nil,
        actionKeys: [String] = [],
        actionParameters: [String] = [],
        songSectionContext: String? = nil
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.priority = priority
        self.deviceID = deviceID
        self.channel = channel
        self.messageType = messageType
        self.data1Min = data1Min
        self.data1Max = data1Max
        self.data2Min = data2Min
        self.data2Max = data2Max
        self.actionKeys = actionKeys
        self.actionParameters = actionParameters
        self.songSectionContext = songSectionContext
    }

    /// Bridge from legacy simple mapping.
    public static func from(mapping: MIDIMapping) -> MIDIRule {
        MIDIRule(
            id: mapping.id,
            name: mapping.name,
            enabled: true,
            priority: 0,
            deviceID: mapping.deviceID,
            channel: mapping.channel,
            messageType: mapping.messageType,
            data1Min: mapping.data1,
            data1Max: mapping.data1,
            data2Min: mapping.data2,
            data2Max: mapping.data2,
            actionKeys: [mapping.action],
            actionParameters: [mapping.actionParameter].compactMap { $0 }
        )
    }
}
