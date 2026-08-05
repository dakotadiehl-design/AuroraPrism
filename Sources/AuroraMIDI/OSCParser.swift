import Foundation

/// Parsed OSC message (PR27).
public struct OSCMessage: Equatable, Sendable {
    public var address: String
    public var arguments: [OSCArgument]

    public init(address: String, arguments: [OSCArgument] = []) {
        self.address = address
        self.arguments = arguments
    }
}

public enum OSCArgument: Equatable, Sendable {
    case int32(Int32)
    case float32(Float)
    case string(String)
    case bool(Bool)
}

/// Minimal OSC 1.0 packet parser (single message or bundle of messages).
public enum OSCParser {
    public static func parse(packet: Data) -> [OSCMessage] {
        guard packet.count >= 4 else { return [] }
        if packet.starts(with: [0x23, 0x62, 0x75, 0x6E]) { // "#bundle"
            return parseBundle(packet)
        }
        if let msg = parseMessage(packet, start: 0) {
            return [msg.message]
        }
        return []
    }

    private static func parseBundle(_ data: Data) -> [OSCMessage] {
        // #bundle\0 + 8-byte timetag, then elements
        var offset = 16
        var messages: [OSCMessage] = []
        while offset + 4 <= data.count {
            let size = Int(readInt32(data, offset))
            offset += 4
            guard size > 0, offset + size <= data.count else { break }
            let slice = data.subdata(in: offset..<(offset + size))
            messages.append(contentsOf: parse(packet: slice))
            offset += size
            // pad to 4
            while offset % 4 != 0 { offset += 1 }
        }
        return messages
    }

    private static func parseMessage(_ data: Data, start: Int) -> (message: OSCMessage, end: Int)? {
        guard let (address, afterAddr) = readOSCString(data, start) else { return nil }
        guard address.hasPrefix("/") else { return nil }
        guard let (typeTag, afterTypes) = readOSCString(data, afterAddr) else {
            return (OSCMessage(address: address), afterAddr)
        }
        guard typeTag.hasPrefix(",") else {
            return (OSCMessage(address: address), afterTypes)
        }
        var offset = afterTypes
        var args: [OSCArgument] = []
        for ch in typeTag.dropFirst() {
            switch ch {
            case "i":
                guard offset + 4 <= data.count else { return nil }
                args.append(.int32(readInt32(data, offset)))
                offset += 4
            case "f":
                guard offset + 4 <= data.count else { return nil }
                args.append(.float32(readFloat32(data, offset)))
                offset += 4
            case "s":
                guard let (s, next) = readOSCString(data, offset) else { return nil }
                args.append(.string(s))
                offset = next
            case "T":
                args.append(.bool(true))
            case "F":
                args.append(.bool(false))
            case "N":
                break
            default:
                // unsupported type — stop parsing args
                return (OSCMessage(address: address, arguments: args), offset)
            }
        }
        return (OSCMessage(address: address, arguments: args), offset)
    }

    private static func readOSCString(_ data: Data, _ start: Int) -> (String, Int)? {
        guard start < data.count else { return nil }
        var end = start
        while end < data.count, data[end] != 0 {
            end += 1
        }
        guard end < data.count else { return nil }
        let str = String(data: data.subdata(in: start..<end), encoding: .utf8) ?? ""
        var next = end + 1
        while next % 4 != 0 { next += 1 }
        return (str, next)
    }

    private static func readInt32(_ data: Data, _ offset: Int) -> Int32 {
        let b0 = Int32(data[offset])
        let b1 = Int32(data[offset + 1])
        let b2 = Int32(data[offset + 2])
        let b3 = Int32(data[offset + 3])
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    }

    private static func readFloat32(_ data: Data, _ offset: Int) -> Float {
        let bitPattern = UInt32(bitPattern: readInt32(data, offset))
        return Float(bitPattern: bitPattern)
    }
}

/// Maps OSC addresses to `ShowAction` (shared control plane with MIDI).
public enum OSCAddressMap {
    public static func action(for message: OSCMessage) -> (ShowAction, value: Float?)? {
        let parts = message.address.split(separator: "/").map(String.init)
        // Expect aurora/... after leading empty from split on "/aurora/..."
        guard parts.first == "aurora" || parts.first == "Aurora" else {
            // also accept without prefix: /go
            return legacy(message)
        }
        let rest = Array(parts.dropFirst())
        guard let head = rest.first else { return nil }
        switch head.lowercased() {
        case "go":
            return (.go, firstFloat(message))
        case "stop":
            return (.stop, firstFloat(message))
        case "back":
            return (.back, firstFloat(message))
        case "fire":
            if rest.count >= 2, let idx = Int(rest[1]) {
                return (.fireCueIndex(idx), firstFloat(message))
            }
            if let idx = firstInt(message) {
                return (.fireCueIndex(Int(idx)), firstFloat(message))
            }
            return nil
        case "programmer":
            if rest.count >= 2 {
                let attr = rest[1]
                return (.programmerAttribute(attr), firstFloat(message))
            }
            return nil
        default:
            return nil
        }
    }

    private static func legacy(_ message: OSCMessage) -> (ShowAction, value: Float?)? {
        switch message.address {
        case "/go": return (.go, firstFloat(message))
        case "/stop": return (.stop, firstFloat(message))
        case "/back": return (.back, firstFloat(message))
        default: return nil
        }
    }

    private static func firstFloat(_ message: OSCMessage) -> Float? {
        for arg in message.arguments {
            switch arg {
            case .float32(let f): return f
            case .int32(let i): return Float(i)
            default: break
            }
        }
        return nil
    }

    private static func firstInt(_ message: OSCMessage) -> Int32? {
        for arg in message.arguments {
            if case .int32(let i) = arg { return i }
        }
        return nil
    }
}
