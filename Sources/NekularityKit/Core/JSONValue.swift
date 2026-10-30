import Foundation

/// A JSON value that keeps object key order and the exact text of numbers.
///
/// Core returns JSON whose key order carries meaning (chapter order is
/// reading order) and whose integers may exceed 2^53. `JSONSerialization`
/// and `Dictionary` lose both, so this small parser is used instead.
public indirect enum JSONValue: Sendable, Hashable, Decodable {
    case null
    case bool(Bool)
    /// The number exactly as written.
    case number(String)
    case string(String)
    case array([JSONValue])
    case object(OrderedObject)

    public var stringValue: String? {
        switch self {
        case .string(let s): s
        case .number(let n): n
        case .bool(let b): b ? "true" : "false"
        default: nil
        }
    }

    public var array: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    /// Decoding through Codable cannot see key order; prefer
    /// `JSONValue.parse`. This path exists so JSONValue can sit inside
    /// Codable types for values whose order does not matter.
    public init(from decoder: Decoder) throws {
        if let parsed = (decoder as? RawJSONDecoderBox)?.value {
            self = parsed
            return
        }
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let d = try? c.decode(Decimal.self) { self = .number("\(d)") }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? c.decode(OrderedObject.self) { self = .object(o) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "not JSON") }
    }

    /// Parses JSON text, keeping key order and number text.
    public static func parse(_ text: String) throws -> JSONValue {
        var p = Parser(Array(text.utf8))
        p.skipSpace()
        let v = try p.value(depth: 0)
        p.skipSpace()
        guard p.atEnd else { throw JSONParseError(offset: p.i, reason: "trailing characters") }
        return v
    }

    /// Serialises back to JSON text.
    public var jsonText: String {
        var out = ""
        write(to: &out)
        return out
    }

    func write(to out: inout String) {
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .number(let n): out += n
        case .string(let s): Self.quote(s, into: &out)
        case .array(let a):
            out += "["
            for (i, v) in a.enumerated() {
                if i > 0 { out += "," }
                v.write(to: &out)
            }
            out += "]"
        case .object(let o):
            out += "{"
            for (i, (k, v)) in o.entries.enumerated() {
                if i > 0 { out += "," }
                Self.quote(k, into: &out)
                out += ":"
                v.write(to: &out)
            }
            out += "}"
        }
    }

    static func quote(_ s: String, into out: inout String) {
        out += "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where u.value < 0x20: out += String(format: "\\u%04x", u.value)
            default: out.unicodeScalars.append(u)
            }
        }
        out += "\""
    }
}

/// A JSON object with its keys in document order.
public struct OrderedObject: Sendable, Hashable, Decodable {
    public var entries: [(String, JSONValue)]

    public init(_ entries: [(String, JSONValue)] = []) { self.entries = entries }

    public var array: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public subscript(key: String) -> JSONValue? {
        entries.first { $0.0 == key }?.1
    }

    public static func == (a: OrderedObject, b: OrderedObject) -> Bool {
        a.entries.count == b.entries.count && zip(a.entries, b.entries).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
    }

    public func hash(into h: inout Hasher) {
        for (k, v) in entries { h.combine(k); h.combine(v) }
    }

    /// Codable decoding. Order comes from the raw JSON when the decoder is
    /// `OrderedJSONDecoder`; plain JSONDecoder gives no order guarantee.
    public init(from decoder: Decoder) throws {
        if let parsed = (decoder as? RawJSONDecoderBox)?.value, case .object(let o) = parsed {
            self = o
            return
        }
        let c = try decoder.container(keyedBy: AnyKey.self)
        entries = try c.allKeys.map { ($0.stringValue, try c.decode(JSONValue.self, forKey: $0)) }
    }
}

struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// Marker for a decoder that carries an already parsed value.
protocol RawJSONDecoderBox { var value: JSONValue { get } }

public struct JSONParseError: Error, CustomStringConvertible {
    public var offset: Int
    public var reason: String
    public var description: String { "JSON error at byte \(offset): \(reason)" }
}

private struct Parser {
    let b: [UInt8]
    var i = 0
    init(_ b: [UInt8]) { self.b = b }

    var atEnd: Bool { i >= b.count }

    mutating func skipSpace() {
        while i < b.count, b[i] == 0x20 || b[i] == 0x0A || b[i] == 0x0D || b[i] == 0x09 { i += 1 }
    }

    func fail(_ reason: String) -> JSONParseError { JSONParseError(offset: i, reason: reason) }

    mutating func expect(_ word: String) throws {
        for c in word.utf8 {
            guard i < b.count, b[i] == c else { throw fail("expected \(word)") }
            i += 1
        }
    }

    mutating func value(depth: Int) throws -> JSONValue {
        guard depth < 512 else { throw fail("nested too deeply") }
        guard i < b.count else { throw fail("unexpected end") }
        switch b[i] {
        case UInt8(ascii: "{"):
            i += 1
            var entries: [(String, JSONValue)] = []
            skipSpace()
            if i < b.count, b[i] == UInt8(ascii: "}") { i += 1; return .object(OrderedObject(entries)) }
            while true {
                skipSpace()
                guard i < b.count, b[i] == UInt8(ascii: "\"") else { throw fail("expected key") }
                let k = try string()
                skipSpace()
                try expect(":")
                skipSpace()
                entries.append((k, try value(depth: depth + 1)))
                skipSpace()
                guard i < b.count else { throw fail("unexpected end") }
                if b[i] == UInt8(ascii: ",") { i += 1; continue }
                if b[i] == UInt8(ascii: "}") { i += 1; return .object(OrderedObject(entries)) }
                throw fail("expected , or }")
            }
        case UInt8(ascii: "["):
            i += 1
            var items: [JSONValue] = []
            skipSpace()
            if i < b.count, b[i] == UInt8(ascii: "]") { i += 1; return .array(items) }
            while true {
                skipSpace()
                items.append(try value(depth: depth + 1))
                skipSpace()
                guard i < b.count else { throw fail("unexpected end") }
                if b[i] == UInt8(ascii: ",") { i += 1; continue }
                if b[i] == UInt8(ascii: "]") { i += 1; return .array(items) }
                throw fail("expected , or ]")
            }
        case UInt8(ascii: "\""):
            return .string(try string())
        case UInt8(ascii: "t"): try expect("true"); return .bool(true)
        case UInt8(ascii: "f"): try expect("false"); return .bool(false)
        case UInt8(ascii: "n"): try expect("null"); return .null
        default:
            return .number(try number())
        }
    }

    mutating func number() throws -> String {
        let start = i
        if i < b.count, b[i] == UInt8(ascii: "-") { i += 1 }
        let digits = i
        while i < b.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(b[i]) { i += 1 }
        guard i > digits else { throw fail("invalid value") }
        if i < b.count, b[i] == UInt8(ascii: ".") {
            i += 1
            let frac = i
            while i < b.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(b[i]) { i += 1 }
            guard i > frac else { throw fail("invalid number") }
        }
        if i < b.count, b[i] == UInt8(ascii: "e") || b[i] == UInt8(ascii: "E") {
            i += 1
            if i < b.count, b[i] == UInt8(ascii: "+") || b[i] == UInt8(ascii: "-") { i += 1 }
            let exp = i
            while i < b.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(b[i]) { i += 1 }
            guard i > exp else { throw fail("invalid number") }
        }
        return String(decoding: b[start..<i], as: UTF8.self)
    }

    mutating func string() throws -> String {
        i += 1 // opening quote
        var out = [UInt8]()
        while true {
            guard i < b.count else { throw fail("unterminated string") }
            let c = b[i]
            i += 1
            if c == UInt8(ascii: "\"") { break }
            if c < 0x20 { throw fail("control character in string") }
            if c != UInt8(ascii: "\\") { out.append(c); continue }
            guard i < b.count else { throw fail("unterminated escape") }
            let e = b[i]
            i += 1
            switch e {
            case UInt8(ascii: "\""): out.append(0x22)
            case UInt8(ascii: "\\"): out.append(0x5C)
            case UInt8(ascii: "/"): out.append(0x2F)
            case UInt8(ascii: "b"): out.append(0x08)
            case UInt8(ascii: "f"): out.append(0x0C)
            case UInt8(ascii: "n"): out.append(0x0A)
            case UInt8(ascii: "r"): out.append(0x0D)
            case UInt8(ascii: "t"): out.append(0x09)
            case UInt8(ascii: "u"):
                var scalar = try hex4()
                if (0xD800..<0xDC00).contains(scalar) {
                    // A surrogate pair; a lone surrogate becomes U+FFFD.
                    if i + 1 < b.count, b[i] == UInt8(ascii: "\\"), b[i + 1] == UInt8(ascii: "u") {
                        let save = i
                        i += 2
                        let low = try hex4()
                        if (0xDC00..<0xE000).contains(low) {
                            scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
                        } else {
                            i = save
                            scalar = 0xFFFD
                        }
                    } else {
                        scalar = 0xFFFD
                    }
                } else if (0xDC00..<0xE000).contains(scalar) {
                    scalar = 0xFFFD
                }
                out.append(contentsOf: Array(String(Unicode.Scalar(scalar)!).utf8))
            default:
                throw fail("invalid escape")
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    mutating func hex4() throws -> UInt32 {
        guard i + 4 <= b.count else { throw fail("short \\u escape") }
        var v: UInt32 = 0
        for _ in 0..<4 {
            let c = b[i]
            i += 1
            let d: UInt32
            switch c {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): d = UInt32(c - UInt8(ascii: "0"))
            case UInt8(ascii: "a")...UInt8(ascii: "f"): d = UInt32(c - UInt8(ascii: "a") + 10)
            case UInt8(ascii: "A")...UInt8(ascii: "F"): d = UInt32(c - UInt8(ascii: "A") + 10)
            default: throw fail("invalid \\u escape")
            }
            v = v << 4 | d
        }
        return v
    }
}
