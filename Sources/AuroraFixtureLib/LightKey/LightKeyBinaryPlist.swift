import Foundation

/// The subset of Apple's binary property-list format needed to read keyed archives.
/// UIDs are retained as data instead of being handed to `NSKeyedUnarchiver`, so no
/// classes named by an imported LightKey file are ever instantiated.
indirect enum LightKeyPlistValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case integer(Int64)
    case real(Double)
    case date(Date)
    case data(Data)
    case string(String)
    case uid(UInt64)
    case array([LightKeyPlistValue])
    case dictionary([String: LightKeyPlistValue])

    var dictionaryValue: [String: LightKeyPlistValue]? {
        guard case .dictionary(let value) = self else { return nil }
        return value
    }

    var arrayValue: [LightKeyPlistValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var integerValue: Int? {
        switch self {
        case .integer(let value): return Int(exactly: value)
        case .real(let value) where value.rounded() == value: return Int(exactly: value)
        default: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .integer(let value): return Double(value)
        case .real(let value): return value
        default: return nil
        }
    }
}

enum LightKeyBinaryPlistError: Error, LocalizedError, Equatable {
    case truncated
    case invalidHeader
    case invalidTrailer
    case unreasonableObjectCount(UInt64)
    case invalidOffset(UInt64)
    case invalidObjectReference(UInt64)
    case unsupportedObjectMarker(UInt8)
    case invalidCollectionLength
    case invalidDictionaryKey
    case cyclicObjectGraph
    case rootNotDictionary

    var errorDescription: String? {
        switch self {
        case .truncated: return "The LightKey property list is truncated."
        case .invalidHeader: return "The file is not an Apple binary property list."
        case .invalidTrailer: return "The LightKey property-list trailer is invalid."
        case .unreasonableObjectCount(let count): return "The archive contains an unreasonable number of objects (\(count))."
        case .invalidOffset(let offset): return "The archive contains an invalid object offset (\(offset))."
        case .invalidObjectReference(let reference): return "The archive contains an invalid object reference (\(reference))."
        case .unsupportedObjectMarker(let marker): return String(format: "The archive contains unsupported property-list marker 0x%02X.", marker)
        case .invalidCollectionLength: return "The archive contains an invalid collection length."
        case .invalidDictionaryKey: return "The archive contains a non-string dictionary key."
        case .cyclicObjectGraph: return "The property-list object graph contains a cycle."
        case .rootNotDictionary: return "The property-list root is not a dictionary."
        }
    }
}

struct LightKeyBinaryPlistReader {
    static let maximumFileSize = 32 * 1_024 * 1_024
    static let maximumObjects: UInt64 = 250_000
    static let maximumCollectionItems = 250_000

    private let data: Data
    private let offsetSize: Int
    private let referenceSize: Int
    private let objectCount: Int
    private let rootIndex: Int
    private let offsets: [Int]

    init(data: Data) throws {
        guard data.count >= 40 else { throw LightKeyBinaryPlistError.truncated }
        guard data.count <= Self.maximumFileSize else {
            throw LightKeyBinaryPlistError.unreasonableObjectCount(UInt64(data.count))
        }
        guard String(data: data.prefix(8), encoding: .ascii) == "bplist00" else {
            throw LightKeyBinaryPlistError.invalidHeader
        }

        let trailer = data.count - 32
        let offsetSize = Int(data[trailer + 6])
        let referenceSize = Int(data[trailer + 7])
        let count = try Self.readUnsigned(data, at: trailer + 8, byteCount: 8)
        let root = try Self.readUnsigned(data, at: trailer + 16, byteCount: 8)
        let tableOffset = try Self.readUnsigned(data, at: trailer + 24, byteCount: 8)
        guard (1...8).contains(offsetSize), (1...8).contains(referenceSize),
              count > 0, count <= Self.maximumObjects,
              root < count,
              tableOffset < UInt64(trailer)
        else { throw LightKeyBinaryPlistError.invalidTrailer }

        let tableBytes = count.multipliedReportingOverflow(by: UInt64(offsetSize))
        guard !tableBytes.overflow,
              tableOffset + tableBytes.partialValue <= UInt64(trailer)
        else { throw LightKeyBinaryPlistError.invalidTrailer }

        var offsets: [Int] = []
        offsets.reserveCapacity(Int(count))
        for index in 0..<Int(count) {
            let raw = try Self.readUnsigned(data, at: Int(tableOffset) + index * offsetSize, byteCount: offsetSize)
            guard raw >= 8, raw < tableOffset, let offset = Int(exactly: raw) else {
                throw LightKeyBinaryPlistError.invalidOffset(raw)
            }
            offsets.append(offset)
        }

        self.data = data
        self.offsetSize = offsetSize
        self.referenceSize = referenceSize
        self.objectCount = Int(count)
        self.rootIndex = Int(root)
        self.offsets = offsets
    }

    func decode() throws -> LightKeyPlistValue {
        var cache: [Int: LightKeyPlistValue] = [:]
        var active = Set<Int>()
        return try decodeObject(rootIndex, cache: &cache, active: &active, depth: 0)
    }

    private func decodeObject(
        _ index: Int,
        cache: inout [Int: LightKeyPlistValue],
        active: inout Set<Int>,
        depth: Int
    ) throws -> LightKeyPlistValue {
        guard index >= 0, index < objectCount else {
            throw LightKeyBinaryPlistError.invalidObjectReference(UInt64(max(index, 0)))
        }
        if let cached = cache[index] { return cached }
        guard depth <= 64, active.insert(index).inserted else {
            throw LightKeyBinaryPlistError.cyclicObjectGraph
        }
        defer { active.remove(index) }

        let start = offsets[index]
        guard start < data.count else { throw LightKeyBinaryPlistError.truncated }
        let marker = data[start]
        let kind = marker >> 4
        let info = marker & 0x0F
        var cursor = start + 1
        let value: LightKeyPlistValue

        switch kind {
        case 0x0:
            switch info {
            case 0x0: value = .null
            case 0x8: value = .bool(false)
            case 0x9: value = .bool(true)
            default: throw LightKeyBinaryPlistError.unsupportedObjectMarker(marker)
            }
        case 0x1:
            let byteCount = 1 << Int(info)
            let raw = try Self.readUnsigned(data, at: cursor, byteCount: byteCount)
            if byteCount == 8 {
                value = .integer(Int64(bitPattern: raw))
            } else {
                value = .integer(Int64(raw))
            }
        case 0x2:
            let byteCount = 1 << Int(info)
            guard byteCount == 4 || byteCount == 8 else {
                throw LightKeyBinaryPlistError.unsupportedObjectMarker(marker)
            }
            let raw = try Self.readUnsigned(data, at: cursor, byteCount: byteCount)
            if byteCount == 4 {
                value = .real(Double(Float(bitPattern: UInt32(raw))))
            } else {
                value = .real(Double(bitPattern: raw))
            }
        case 0x3:
            guard info == 0x3 else { throw LightKeyBinaryPlistError.unsupportedObjectMarker(marker) }
            let raw = try Self.readUnsigned(data, at: cursor, byteCount: 8)
            value = .date(Date(timeIntervalSinceReferenceDate: Double(bitPattern: raw)))
        case 0x4:
            let count = try collectionLength(info: info, cursor: &cursor)
            value = .data(try bytes(at: cursor, count: count))
        case 0x5:
            let count = try collectionLength(info: info, cursor: &cursor)
            let bytes = try bytes(at: cursor, count: count)
            guard let string = String(data: bytes, encoding: .ascii) else {
                throw LightKeyBinaryPlistError.truncated
            }
            value = .string(string)
        case 0x6:
            let count = try collectionLength(info: info, cursor: &cursor)
            let bytes = try bytes(at: cursor, count: count * 2)
            var codeUnits: [UInt16] = []
            codeUnits.reserveCapacity(count)
            for i in 0..<count {
                codeUnits.append(UInt16(bytes[i * 2]) << 8 | UInt16(bytes[i * 2 + 1]))
            }
            value = .string(String(decoding: codeUnits, as: UTF16.self))
        case 0x8:
            let byteCount = Int(info) + 1
            value = .uid(try Self.readUnsigned(data, at: cursor, byteCount: byteCount))
        case 0xA, 0xC:
            let count = try collectionLength(info: info, cursor: &cursor)
            let refs = try objectReferences(at: cursor, count: count)
            value = .array(try refs.map {
                try decodeObject($0, cache: &cache, active: &active, depth: depth + 1)
            })
        case 0xD:
            let count = try collectionLength(info: info, cursor: &cursor)
            let keyRefs = try objectReferences(at: cursor, count: count)
            let valueRefs = try objectReferences(at: cursor + count * referenceSize, count: count)
            var dictionary: [String: LightKeyPlistValue] = [:]
            dictionary.reserveCapacity(count)
            for i in 0..<count {
                let key = try decodeObject(keyRefs[i], cache: &cache, active: &active, depth: depth + 1)
                guard case .string(let keyString) = key else {
                    throw LightKeyBinaryPlistError.invalidDictionaryKey
                }
                dictionary[keyString] = try decodeObject(valueRefs[i], cache: &cache, active: &active, depth: depth + 1)
            }
            value = .dictionary(dictionary)
        default:
            throw LightKeyBinaryPlistError.unsupportedObjectMarker(marker)
        }

        cache[index] = value
        return value
    }

    private func collectionLength(info: UInt8, cursor: inout Int) throws -> Int {
        if info < 0xF { return Int(info) }
        guard cursor < data.count else { throw LightKeyBinaryPlistError.truncated }
        let marker = data[cursor]
        guard marker >> 4 == 0x1 else { throw LightKeyBinaryPlistError.invalidCollectionLength }
        cursor += 1
        let byteCount = 1 << Int(marker & 0x0F)
        let length = try Self.readUnsigned(data, at: cursor, byteCount: byteCount)
        cursor += byteCount
        guard length <= UInt64(Self.maximumCollectionItems), let result = Int(exactly: length) else {
            throw LightKeyBinaryPlistError.invalidCollectionLength
        }
        return result
    }

    private func objectReferences(at offset: Int, count: Int) throws -> [Int] {
        let size = count.multipliedReportingOverflow(by: referenceSize)
        guard !size.overflow, offset >= 0, offset + size.partialValue <= data.count else {
            throw LightKeyBinaryPlistError.truncated
        }
        return try (0..<count).map { index in
            let raw = try Self.readUnsigned(data, at: offset + index * referenceSize, byteCount: referenceSize)
            guard raw < UInt64(objectCount), let result = Int(exactly: raw) else {
                throw LightKeyBinaryPlistError.invalidObjectReference(raw)
            }
            return result
        }
    }

    private func bytes(at offset: Int, count: Int) throws -> Data {
        guard count >= 0, offset >= 0, offset + count <= data.count else {
            throw LightKeyBinaryPlistError.truncated
        }
        return data.subdata(in: offset..<(offset + count))
    }

    private static func readUnsigned(_ data: Data, at offset: Int, byteCount: Int) throws -> UInt64 {
        guard (1...8).contains(byteCount), offset >= 0, offset + byteCount <= data.count else {
            throw LightKeyBinaryPlistError.truncated
        }
        var value: UInt64 = 0
        for byte in data[offset..<(offset + byteCount)] {
            value = (value << 8) | UInt64(byte)
        }
        return value
    }
}
