import Foundation

/// Decodes Decodable types from JSON while keeping object key order.
///
/// `JSONDecoder` gives keyed containers no order, so types that need order
/// (chapters, tag groups) decode `OrderedObject`, which this decoder fills
/// from `JSONValue.parse`.
public enum OrderedJSONDecoder {
    public static func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        let v: JSONValue
        do { v = try JSONValue.parse(json) } catch { throw CoreError("unexpected result from Core: \(error)") }
        do { return try T(from: ValueDecoder(value: v, codingPath: [])) } catch {
            throw CoreError("unexpected result from Core: \(error)")
        }
    }
}

struct ValueDecoder: Decoder, RawJSONDecoderBox {
    let value: JSONValue
    let codingPath: [CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard case .object(let o) = value else {
            throw DecodingError.typeMismatch(OrderedObject.self, .init(codingPath: codingPath, debugDescription: "not an object"))
        }
        return KeyedDecodingContainer(Keyed<Key>(object: o, codingPath: codingPath))
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        guard case .array(let a) = value else {
            throw DecodingError.typeMismatch([JSONValue].self, .init(codingPath: codingPath, debugDescription: "not an array"))
        }
        return Unkeyed(items: a, codingPath: codingPath)
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer { Single(value: value, codingPath: codingPath) }
}

private struct IndexKey: CodingKey {
    var intValue: Int?
    var stringValue: String { "\(intValue ?? 0)" }
    init(_ i: Int) { intValue = i }
    init?(intValue: Int) { self.intValue = intValue }
    init?(stringValue: String) { nil }
}

private struct Keyed<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let object: OrderedObject
    let codingPath: [CodingKey]

    var allKeys: [Key] { object.entries.compactMap { Key(stringValue: $0.0) } }
    func contains(_ key: Key) -> Bool { object[key.stringValue] != nil }

    func child(_ key: Key) throws -> JSONValue {
        guard let v = object[key.stringValue] else {
            throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "missing"))
        }
        return v
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        if case .null = try child(key) { return true }
        return false
    }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        try T(from: ValueDecoder(value: child(key), codingPath: codingPath + [key]))
    }

    func decodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
        guard let v = object[key.stringValue] else { return nil }
        if case .null = v { return nil }
        return try T(from: ValueDecoder(value: v, codingPath: codingPath + [key]))
    }

    func nestedContainer<N: CodingKey>(keyedBy type: N.Type, forKey key: Key) throws -> KeyedDecodingContainer<N> {
        try ValueDecoder(value: child(key), codingPath: codingPath + [key]).container(keyedBy: type)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        try ValueDecoder(value: child(key), codingPath: codingPath + [key]).unkeyedContainer()
    }

    func superDecoder() throws -> Decoder { ValueDecoder(value: .object(object), codingPath: codingPath) }
    func superDecoder(forKey key: Key) throws -> Decoder { ValueDecoder(value: try child(key), codingPath: codingPath + [key]) }
}

private struct Unkeyed: UnkeyedDecodingContainer {
    let items: [JSONValue]
    let codingPath: [CodingKey]
    var currentIndex = 0

    init(items: [JSONValue], codingPath: [CodingKey]) { self.items = items; self.codingPath = codingPath }

    var count: Int? { items.count }
    var isAtEnd: Bool { currentIndex >= items.count }

    mutating func next() throws -> (JSONValue, [CodingKey]) {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(JSONValue.self, .init(codingPath: codingPath, debugDescription: "end of array"))
        }
        defer { currentIndex += 1 }
        return (items[currentIndex], codingPath + [IndexKey(currentIndex)])
    }

    mutating func decodeNil() throws -> Bool {
        guard !isAtEnd else { return false }
        if case .null = items[currentIndex] { currentIndex += 1; return true }
        return false
    }

    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let (v, path) = try next()
        return try T(from: ValueDecoder(value: v, codingPath: path))
    }

    mutating func nestedContainer<N: CodingKey>(keyedBy type: N.Type) throws -> KeyedDecodingContainer<N> {
        let (v, path) = try next()
        return try ValueDecoder(value: v, codingPath: path).container(keyedBy: type)
    }

    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        let (v, path) = try next()
        return try ValueDecoder(value: v, codingPath: path).unkeyedContainer()
    }

    mutating func superDecoder() throws -> Decoder {
        let (v, path) = try next()
        return ValueDecoder(value: v, codingPath: path)
    }
}

private struct Single: SingleValueDecodingContainer {
    let value: JSONValue
    let codingPath: [CodingKey]

    func mismatch<T>(_ t: T.Type) -> DecodingError {
        .typeMismatch(t, .init(codingPath: codingPath, debugDescription: "found \(value)"))
    }

    func decodeNil() -> Bool { if case .null = value { return true }; return false }

    func decode(_ type: Bool.Type) throws -> Bool {
        guard case .bool(let b) = value else { throw mismatch(type) }
        return b
    }

    func decode(_ type: String.Type) throws -> String {
        guard case .string(let s) = value else { throw mismatch(type) }
        return s
    }

    private func numberText<T>(_ t: T.Type) throws -> String {
        guard case .number(let n) = value else { throw mismatch(t) }
        return n
    }

    func decode(_ type: Double.Type) throws -> Double {
        guard let d = Double(try numberText(type)) else { throw mismatch(type) }
        return d
    }

    func decode(_ type: Float.Type) throws -> Float { Float(try decode(Double.self)) }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try T(from: ValueDecoder(value: value, codingPath: codingPath))
    }

    // Integers parse the exact text; values like 1.0 or 1e3 are rejected
    // rather than silently converted.
    private func integer<I: FixedWidthInteger>(_ t: I.Type) throws -> I {
        guard let i = I(try numberText(t)) else { throw mismatch(t) }
        return i
    }

    func decode(_ type: Int.Type) throws -> Int { try integer(type) }
    func decode(_ type: Int8.Type) throws -> Int8 { try integer(type) }
    func decode(_ type: Int16.Type) throws -> Int16 { try integer(type) }
    func decode(_ type: Int32.Type) throws -> Int32 { try integer(type) }
    func decode(_ type: Int64.Type) throws -> Int64 { try integer(type) }
    func decode(_ type: UInt.Type) throws -> UInt { try integer(type) }
    func decode(_ type: UInt8.Type) throws -> UInt8 { try integer(type) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { try integer(type) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { try integer(type) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { try integer(type) }
}
