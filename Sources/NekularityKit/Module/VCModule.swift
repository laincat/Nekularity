import Foundation

public enum VCModuleError: Error, LocalizedError, Equatable, Sendable {
    case invalidUTF8
    case tooLarge
    case syntax(line: Int, reason: String)
    case missingHeader(String)
    case unsupportedFormat
    case unsupportedCapability(String)
    case invalidIdentifier(String)
    case moduleNotFound(String)
    case pathEscape(String)
    case unreadableStore(String)

    public var errorDescription: String? {
        switch self {
        case .invalidUTF8: "模块文件需要使用 UTF-8 编码"
        case .tooLarge: "模块文件超过 \(VCModuleDocument.maximumBytes) 字节"
        case .syntax(let line, let reason): "模块第 \(line) 行：\(reason)"
        case .missingHeader(let name): "模块缺少元信息 #!\(name)"
        case .unsupportedFormat: "仅支持模块格式 \(VCModuleDocument.supportedFormat)"
        case .unsupportedCapability(let name): "模块要求未提供的能力：\(name)"
        case .invalidIdentifier(let id): "模块标识无效：\(id)"
        case .moduleNotFound(let id): "找不到已安装的模块：\(id)"
        case .pathEscape(let name): "模块存储路径无效：\(name)"
        case .unreadableStore(let detail): "模块存储读取失败：\(detail)"
        }
    }
}

public enum VCModuleSettingKey: String, Hashable, Sendable {
    case readerPageGap = "Reader.page-gap"
    case readerKeepScreenOn = "Reader.keep-screen-on"
    case readerLayout = "Reader.layout"
    case readerRightToLeft = "Reader.right-to-left"
    case readerAutoNext = "Reader.auto-next"
}

public enum VCModuleSettingValue: Hashable, Sendable {
    case int(Int)
    case bool(Bool)
    case string(String)
}

/// The draft has a deliberately small grammar. A future format can expand the
/// whitelist explicitly without making other INI dialects executable.
public struct VCModuleDocument: Hashable, Sendable {
    public static let supportedFormat = "veneracat-module/1-draft"
    public static let maximumBytes = 64 * 1024

    public let id: String?
    public let name: String
    public let description: String?
    public let version: String
    public let settings: [VCModuleSettingKey: VCModuleSettingValue]

    public static func parse(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else { throw VCModuleError.tooLarge }
        guard let text = String(data: data, encoding: .utf8) else { throw VCModuleError.invalidUTF8 }
        return try parse(text)
    }

    public static func parse(_ raw: String) throws -> Self {
        guard raw.utf8.count <= maximumBytes else { throw VCModuleError.tooLarge }
        let text = raw.hasPrefix("\u{FEFF}") ? String(raw.dropFirst()) : raw
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var headers: [String: String] = [:]
        var inReaderSection = false
        var settings: [VCModuleSettingKey: VCModuleSettingValue] = [:]

        for (offset, rawLine) in normalized.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let number = offset + 1
            if line.isEmpty || line.hasPrefix(";") || (line.hasPrefix("#") && !line.hasPrefix("#!")) { continue }
            if line.hasPrefix("[") {
                guard line == "[Reader]", !inReaderSection else {
                    throw VCModuleError.syntax(line: number, reason: "仅允许一个 [Reader] 分节")
                }
                inReaderSection = true
                continue
            }
            let header = line.hasPrefix("#!")
            let assignment = (header ? line.dropFirst(2) : line[...]).split(separator: "=", maxSplits: 1,
                                                                              omittingEmptySubsequences: false)
            guard assignment.count == 2 else {
                throw VCModuleError.syntax(line: number, reason: "需要键和值")
            }
            let key = assignment[0].trimmingCharacters(in: .whitespaces)
            let value = assignment[1].trimmingCharacters(in: .whitespaces)
            if header {
                guard !inReaderSection, ["id", "name", "desc", "version", "format", "requires"].contains(key), headers[key] == nil else {
                    throw VCModuleError.syntax(line: number, reason: "元信息未知、重复或位于分节内")
                }
                headers[key] = value
            } else {
                guard inReaderSection, let setting = VCModuleSettingKey(rawValue: "Reader.\(key)"),
                      settings[setting] == nil else {
                    throw VCModuleError.syntax(line: number, reason: "配置键未知、重复或位于分节外")
                }
                guard let parsed = parseValue(value, for: setting) else {
                    throw VCModuleError.syntax(line: number, reason: "配置值无效：\(key)")
                }
                settings[setting] = parsed
            }
        }
        guard let format = headers["format"], !format.isEmpty else { throw VCModuleError.missingHeader("format") }
        guard format == supportedFormat else { throw VCModuleError.unsupportedFormat }
        guard let name = headers["name"], !name.isEmpty else { throw VCModuleError.missingHeader("name") }
        guard let version = headers["version"], !version.isEmpty else { throw VCModuleError.missingHeader("version") }
        guard !settings.isEmpty else { throw VCModuleError.syntax(line: 1, reason: "至少需要一个阅读设置") }
        if let id = headers["id"], !VCModuleIdentifier.isValid(id) { throw VCModuleError.invalidIdentifier(id) }
        if let capability = headers["requires"], capability != "settings-module.v1" {
            throw VCModuleError.unsupportedCapability(capability)
        }
        return Self(id: headers["id"], name: name, description: headers["desc"], version: version, settings: settings)
    }

    private static func parseValue(_ raw: String, for key: VCModuleSettingKey) -> VCModuleSettingValue? {
        switch key {
        case .readerPageGap:
            guard let value = Int(raw), (0...128).contains(value) else { return nil }
            return .int(value)
        case .readerKeepScreenOn, .readerRightToLeft, .readerAutoNext:
            if raw == "true" { return .bool(true) }
            if raw == "false" { return .bool(false) }
            return nil
        case .readerLayout:
            return ["vertical", "paged"].contains(raw) ? .string(raw) : nil
        }
    }
}

enum VCModuleIdentifier {
    static func isValid(_ id: String) -> Bool {
        guard !id.isEmpty, id.utf8.count <= 128, !id.contains(".."),
              id.first?.isLetter == true || id.first?.isNumber == true else { return false }
        return id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || ".-_".contains($0)) }
    }
}
