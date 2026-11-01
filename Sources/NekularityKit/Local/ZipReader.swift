import Compression
import Foundation

/// Reads a zip archive, which is what a `.cbz` is.
///
/// The system has an unzipper only through APIs that consume a file and hand back
/// a directory, which is the wrong shape for a comic: the pages have to be listed,
/// ordered and opened one at a time. So the container is read here — the central
/// directory, then each entry — and the two methods a comic uses (stored and
/// deflate) go through the system's own inflater.
public enum ZipReader {
    public struct Entry: Sendable, Hashable {
        public var name: String
        public var method: UInt16
        public var compressedSize: Int
        public var uncompressedSize: Int
        public var localHeaderOffset: Int
        /// Zero when the archive was written as a stream and never knew it.
        public var crc32: UInt32

        /// Directories and macOS's `__MACOSX` siblings are in every archive a Mac
        /// produced and none of them are pages.
        public var isPageCandidate: Bool {
            guard !name.hasSuffix("/") else { return false }
            guard !name.hasPrefix("__MACOSX/") else { return false }
            let file = name.split(separator: "/").last.map(String.init) ?? name
            guard !file.hasPrefix(".") else { return false }
            return Self.pageExtensions.contains((file as NSString).pathExtension.lowercased())
        }

        public static let pageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "heic", "bmp"]
    }

    public enum Failure: LocalizedError, Sendable {
        case notAZip
        case truncated
        case unsupported(String)
        case corrupt(String)

        public var errorDescription: String? {
            switch self {
            case .notAZip: "这个文件不是 zip/cbz"
            case .truncated: "压缩包不完整"
            case .unsupported(let what): "压缩方式不支持:\(what)"
            case .corrupt(let name): "\(name) 校验不通过,文件可能损坏"
            }
        }
    }

    public static func entries(_ data: Data) throws -> [Entry] {
        guard let eocd = endOfCentralDirectory(data) else { throw Failure.notAZip }
        let count = Int(read16(data, eocd + 10))
        var offset = Int(read32(data, eocd + 16))
        var entries: [Entry] = []
        for _ in 0..<count {
            guard offset + 46 <= data.count, read32(data, offset) == 0x0201_4b50 else {
                throw Failure.truncated
            }
            let method = read16(data, offset + 10)
            let compressed = Int(read32(data, offset + 20))
            let uncompressed = Int(read32(data, offset + 24))
            let crc = read32(data, offset + 16)
            let nameLength = Int(read16(data, offset + 28))
            let extraLength = Int(read16(data, offset + 30))
            let commentLength = Int(read16(data, offset + 32))
            let localOffset = Int(read32(data, offset + 42))
            guard offset + 46 + nameLength <= data.count else { throw Failure.truncated }
            let nameBytes = data[(offset + 46)..<(offset + 46 + nameLength)]
            let name = String(decoding: nameBytes, as: UTF8.self)
            entries.append(Entry(name: name, method: method, compressedSize: compressed,
                                 uncompressedSize: uncompressed, localHeaderOffset: localOffset,
                                 crc32: crc))
            offset += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    public static func contents(of entry: Entry, in data: Data) throws -> Data {
        let offset = entry.localHeaderOffset
        guard offset + 30 <= data.count, read32(data, offset) == 0x0403_4b50 else {
            throw Failure.truncated
        }
        let nameLength = Int(read16(data, offset + 26))
        let extraLength = Int(read16(data, offset + 28))
        let start = offset + 30 + nameLength + extraLength
        guard start + entry.compressedSize <= data.count else { throw Failure.truncated }
        let payload = data[start..<(start + entry.compressedSize)]
        let contents: Data
        switch entry.method {
        case 0:
            contents = Data(payload)
        case 8:
            contents = try inflate(Data(payload), expected: entry.uncompressedSize)
        default:
            throw Failure.unsupported("method \(entry.method)")
        }
        // A checksum the archive recorded but the bytes do not match means the file
        // is damaged. Without this the damage arrives as a page that half-decodes,
        // which looks like a reader bug rather than a bad file.
        if entry.crc32 != 0, Self.crc32(contents) != entry.crc32 {
            throw Failure.corrupt(entry.name)
        }
        return contents
    }

    /// The checksum zip has always used. Small enough to carry, and it is the only
    /// way to tell a damaged page from a decoder problem.
    public static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    // MARK: Plumbing

    private static func endOfCentralDirectory(_ data: Data) -> Int? {
        // The record sits at the end, followed only by a comment of at most 64 KB.
        let lower = max(0, data.count - 65_557)
        var index = data.count - 22
        while index >= lower {
            if read32(data, index) == 0x0605_4b50 { return index }
            index -= 1
        }
        return nil
    }

    private static func inflate(_ data: Data, expected: Int) throws -> Data {
        guard expected >= 0 else { throw Failure.truncated }
        // An empty deflate stream is legal and produces nothing.
        guard !data.isEmpty else { return Data() }
        var output = Data(count: max(expected, 1))
        let written: Int = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress,
                      let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(destinationBase, max(expected, 1),
                                                 sourceBase, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 || expected == 0 else { throw Failure.truncated }
        return output.prefix(written)
    }

    private static func read16(_ data: Data, _ offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func read32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }
}
