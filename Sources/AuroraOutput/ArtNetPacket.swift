import Foundation

/// Art-Net packet builders (ArtDmx focus for PR25).
public enum ArtNetPacket {
    public static let defaultPort: UInt16 = 6454
    public static let opOutput: UInt16 = 0x5000
    public static let protocolVersion: UInt16 = 14

    /// Builds an ArtDmx UDP payload.
    /// - Parameters:
    ///   - universe: Art-Net port-address (15-bit style value in low bits).
    ///   - sequence: 0 disables sequencing; 1...255 cycles.
    ///   - physical: physical port id (usually 0).
    ///   - dmx: channel data (will be padded to even length, max 512).
    public static func artDmx(
        universe: UInt16,
        sequence: UInt8,
        physical: UInt8 = 0,
        dmx: UnsafeBufferPointer<UInt8>
    ) -> Data {
        var length = min(512, dmx.count)
        if length < 2 { length = 2 }
        if length % 2 != 0 { length += 1 }

        var packet = Data(capacity: 18 + length)
        // ID "Art-Net\0"
        packet.append(contentsOf: [0x41, 0x72, 0x74, 0x2D, 0x4E, 0x65, 0x74, 0x00])
        // OpCode little-endian
        packet.append(UInt8(opOutput & 0xFF))
        packet.append(UInt8((opOutput >> 8) & 0xFF))
        // ProtVer big-endian (hi, lo) — Art-Net uses Hi then Lo
        packet.append(UInt8((protocolVersion >> 8) & 0xFF))
        packet.append(UInt8(protocolVersion & 0xFF))
        packet.append(sequence)
        packet.append(physical)
        // Universe little-endian
        packet.append(UInt8(universe & 0xFF))
        packet.append(UInt8((universe >> 8) & 0xFF))
        // Length big-endian
        packet.append(UInt8((length >> 8) & 0xFF))
        packet.append(UInt8(length & 0xFF))

        let copyCount = min(length, dmx.count)
        if copyCount > 0 {
            packet.append(contentsOf: dmx.prefix(copyCount))
        }
        while packet.count < 18 + length {
            packet.append(0)
        }
        return packet
    }

    public static func artDmx(universe: UInt16, sequence: UInt8, physical: UInt8 = 0, dmx: [UInt8]) -> Data {
        dmx.withUnsafeBufferPointer { artDmx(universe: universe, sequence: sequence, physical: physical, dmx: $0) }
    }
}
