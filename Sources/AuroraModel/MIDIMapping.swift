import Foundation

/// Stored binding from a MIDI message to a show action (action execution is later PRs).
public struct MIDIMapping: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    /// Optional device identifier string from CoreMIDI.
    public var deviceID: String?
    public var channel: UInt8?
    /// e.g. `noteOn`, `cc`, `programChange`.
    public var messageType: String
    public var data1: UInt8?
    public var data2: UInt8?
    /// Opaque action key for the control plane (e.g. `go`, `stop`, `fireCue`).
    public var action: String
    public var actionParameter: String?

    public init(
        id: UUID = UUID(),
        name: String = "",
        deviceID: String? = nil,
        channel: UInt8? = nil,
        messageType: String,
        data1: UInt8? = nil,
        data2: UInt8? = nil,
        action: String,
        actionParameter: String? = nil
    ) {
        self.id = id
        self.name = name
        self.deviceID = deviceID
        self.channel = channel
        self.messageType = messageType
        self.data1 = data1
        self.data2 = data2
        self.action = action
        self.actionParameter = actionParameter
    }
}
