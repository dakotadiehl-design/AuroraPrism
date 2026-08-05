import Foundation

public struct MIDIDeviceInfo: Equatable, Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var manufacturer: String

    public init(id: String, name: String, manufacturer: String = "") {
        self.id = id
        self.name = name
        self.manufacturer = manufacturer
    }
}
