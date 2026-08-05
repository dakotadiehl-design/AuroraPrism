import Foundation

/// E1.31 (sACN) DATA packet builder (PR26).
public enum SACNPacket {
    public static let defaultPort: UInt16 = 5568
    public static let vectorRootE131Data: UInt32 = 0x0000_0004
    public static let vectorE131DataPacket: UInt32 = 0x0000_0002
    public static let vectorDMPSetProperty: UInt8 = 0x02

    /// Builds a complete E1.31 DATA UDP payload for one universe.
    /// - Parameters:
    ///   - universe: sACN universe (1…63999).
    ///   - sequence: 0…255 sequence number.
    ///   - priority: 0…200.
    ///   - cid: 16-byte component identifier.
    ///   - sourceName: up to 64 UTF-8 bytes (padded).
    ///   - dmx: up to 512 slots (start code 0 is prepended).
    public static func dataPacket(
        universe: UInt16,
        sequence: UInt8,
        priority: UInt8 = 100,
        cid: uuid_t,
        sourceName: String = "Aurora",
        dmx: UnsafeBufferPointer<UInt8>
    ) -> Data {
        let propertyCount = min(512, dmx.count) + 1 // start code + data
        // DMP PDU: 10 header bytes + property values
        let dmpLength = 10 + propertyCount
        // Framing PDU: 77 fixed + DMP
        let framingLength = 77 + dmpLength
        // Root PDU: 22 fixed + framing
        let rootLength = 22 + framingLength

        var packet = Data(capacity: 16 + rootLength)

        // ---- Root Layer preamble ----
        packet.append(contentsOf: [0x00, 0x10]) // preamble size
        packet.append(contentsOf: [0x00, 0x00]) // post-amble size
        // ACN Packet Identifier "ASC-E1.17\0\0\0"
        packet.append(contentsOf: [
            0x41, 0x53, 0x43, 0x2D, 0x45, 0x31, 0x2E, 0x31, 0x37, 0x00, 0x00, 0x00,
        ])
        appendFlagsAndLength(&packet, pduLength: rootLength)
        appendUInt32BE(&packet, vectorRootE131Data)
        // CID 16 bytes
        withUnsafeBytes(of: cid) { raw in
            packet.append(contentsOf: raw)
        }

        // ---- Framing Layer ----
        appendFlagsAndLength(&packet, pduLength: framingLength)
        appendUInt32BE(&packet, vectorE131DataPacket)
        // Source name 64 bytes
        var nameBytes = Array(sourceName.utf8.prefix(63))
        while nameBytes.count < 64 { nameBytes.append(0) }
        packet.append(contentsOf: nameBytes)
        packet.append(min(200, priority))
        packet.append(contentsOf: [0x00, 0x00]) // sync address
        packet.append(sequence)
        packet.append(0x00) // options
        appendUInt16BE(&packet, universe)

        // ---- DMP Layer ----
        appendFlagsAndLength(&packet, pduLength: dmpLength)
        packet.append(vectorDMPSetProperty)
        packet.append(0xA1) // address type & data type
        packet.append(contentsOf: [0x00, 0x00]) // first property address
        packet.append(contentsOf: [0x00, 0x01]) // address increment
        appendUInt16BE(&packet, UInt16(propertyCount))
        packet.append(0x00) // start code
        let copyCount = min(512, dmx.count)
        if copyCount > 0 {
            packet.append(contentsOf: dmx.prefix(copyCount))
        }
        return packet
    }

    public static func dataPacket(
        universe: UInt16,
        sequence: UInt8,
        priority: UInt8 = 100,
        cid: UUID,
        sourceName: String = "Aurora",
        dmx: [UInt8]
    ) -> Data {
        dmx.withUnsafeBufferPointer {
            dataPacket(
                universe: universe,
                sequence: sequence,
                priority: priority,
                cid: cid.uuid,
                sourceName: sourceName,
                dmx: $0
            )
        }
    }

    private static func appendFlagsAndLength(_ data: inout Data, pduLength: Int) {
        // Low 12 bits = PDU length including flags+length field; high nibble flags = 0x7
        let flagsAndLength = 0x7000 | (pduLength & 0x0FFF)
        appendUInt16BE(&data, UInt16(flagsAndLength))
    }

    private static func appendUInt16BE(_ data: inout Data, _ value: UInt16) {
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    private static func appendUInt32BE(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8((value >> 24) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }
}
