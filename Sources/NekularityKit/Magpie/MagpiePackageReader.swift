import Foundation

/// Reads a package from a folder the user picked, or from the zip / tar.gz a
/// package is usually downloaded as.
///
/// Extraction belongs to Core: `readPackageArchive` applies the same path and
/// size rules a folder install gets, and answers the file table this reader
/// produces. Doing it here would mean a second implementation of "what is a
/// package", and the two would drift.
///
/// A folder is read here and its limits checked here as well as in Core, because
/// a folder can be far larger than a provider package and the client should say
/// so before copying gigabytes.
public enum MagpiePackageReader {
    public static let maxFiles = 1024
    public static let maxFileBytes = 8 << 20
    public static let maxTotalBytes = 32 << 20

    public struct Rejection: Error, CustomStringConvertible, Sendable {
        public let description: String
        public init(_ description: String) { self.description = description }
    }

    /// Unpacks an archive through Core and returns the same table a folder
    /// produces: path to bytes, base64 having been decoded on the way.
    public static func files(fromArchive data: Data, core: MagpieRunner.Core) throws -> [String: Data] {
        let answer = try core.readPackageArchive(data)
        guard let decoded = try? JSONSerialization.jsonObject(with: Data(answer.utf8), options: [.fragmentsAllowed]),
              let encoded = decoded as? [String: String] else {
            throw Rejection("这个压缩包不是一个插件包")
        }
        var files: [String: Data] = [:]
        var total = 0
        for (name, base64) in encoded {
            guard let body = Data(base64Encoded: base64) else {
                throw Rejection("包里的 \(name) 不是有效的文件内容")
            }
            total += body.count
            if body.count > maxFileBytes {
                throw Rejection("包里的 \(name) 超过 8 MiB")
            }
            if total > maxTotalBytes {
                throw Rejection("这个包超过 32 MiB")
            }
            files[name] = body
        }
        if files.count > maxFiles {
            throw Rejection("这个包里的文件超过 1024 个")
        }
        return files
    }

    /// Reads every regular file under `directory`, keyed by package-relative
    /// path with `/` separators.
    public static func files(from directory: URL) throws -> [String: Data] {
        let manager = FileManager.default
        guard let walker = manager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw Rejection("读不了这个文件夹")
        }
        var files: [String: Data] = [:]
        var total = 0
        let prefix = directory.standardizedFileURL.path.hasSuffix("/")
            ? directory.standardizedFileURL.path
            : directory.standardizedFileURL.path + "/"
        for case let entry as URL in walker {
            let values = try entry.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
            // A symlink could point anywhere; a package is plain files.
            if values.isSymbolicLink == true {
                throw Rejection("包里不能有符号链接:\(entry.lastPathComponent)")
            }
            guard values.isRegularFile == true else { continue }
            let path = entry.standardizedFileURL.path
            guard path.hasPrefix(prefix) else {
                throw Rejection("这个文件不在所选文件夹里:\(entry.lastPathComponent)")
            }
            var relative = String(path.dropFirst(prefix.count))
            if relative.isEmpty || relative.hasPrefix("/") || relative.contains("/../") || relative.hasPrefix("../") {
                throw Rejection("包里有可疑路径:\(relative)")
            }
            if relative.hasSuffix("/") { relative.removeLast() }
            let size = values.fileSize ?? 0
            if size > maxFileBytes {
                throw Rejection("\(relative) 有 \(size) 字节,超过单个文件 8 MiB 的上限")
            }
            total += size
            if total > maxTotalBytes {
                throw Rejection("整个包超过 32 MiB 的上限")
            }
            if files.count >= maxFiles {
                throw Rejection("包里的文件超过 \(maxFiles) 个")
            }
            files[relative] = try Data(contentsOf: entry, options: .mappedIfSafe)
        }
        guard files["package.json"] != nil else {
            throw Rejection("这个文件夹里没有 package.json,它不是 Magpie 供应商插件")
        }
        return files
    }

    /// The provider id a package serves, read from its entry the way Magpie
    /// does: `exports["./server"]`, then `main`, then an index file.
    ///
    /// The id is the plugin's own `auth.provider`, which only exists after the
    /// package runs; so a caller names it, and this checks the folder is at
    /// least shaped like a package.
    public static func looksLikePackage(files: [String: Data]) -> Bool {
        guard let manifest = files["package.json"],
              let object = try? JSONSerialization.jsonObject(with: manifest) as? [String: Any]
        else { return false }
        if let exports = object["exports"] as? [String: Any] {
            if exports["./server"] != nil { return true }
            if exports["."] != nil { return true }
        }
        if object["main"] is String { return true }
        for name in ["index.ts", "index.tsx", "index.js", "index.mjs", "index.cjs"] {
            if files[name] != nil { return true }
        }
        return false
    }
}
