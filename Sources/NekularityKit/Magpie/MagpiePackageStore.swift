import Foundation

/// An installed provider package: the files Core loads, plus what a list needs
/// to show.
///
/// The files are kept as they arrived. Unpacking an archive happens before this
/// point, and this type never inspects a path it did not receive from an
/// unpacker that already validated it — Core validates again when the package
/// is loaded, because that is where a bad path would matter.
public struct MagpiePackage: Codable, Hashable, Sendable, Identifiable {
    /// The id the plugin serves, which is also the account's id.
    public var provider: String
    public var name: String
    public var version: String
    /// Package-relative path to the file's bytes, base64 encoded so one JSON
    /// file can hold a whole package.
    public var files: [String: String]
    /// When it was installed, as RFC 3339 text: a `Date` would need a custom
    /// coding strategy, and `DateDecodingStrategy.custom`'s closure capturing a
    /// formatter is exactly the kind of non-Sendable capture Swift 6 rejects.
    public var installedAt: String
    /// What the plugin declared when it was installed. Keeping it means the
    /// provider list costs no JavaScript runtime: evaluating a package to read
    /// its methods, for a list of ten, would start ten runtimes on the main
    /// path. Absent for packages installed before this was recorded, which fall
    /// back to evaluating once.
    public var specJSON: String?

    public var id: String { provider }

    /// Decodes the file table into the bytes Core expects.
    public var decodedFiles: [String: Data] {
        var out: [String: Data] = [:]
        for (path, encoded) in files {
            if let data = Data(base64Encoded: encoded) { out[path] = data }
        }
        return out
    }

    /// Reads the parts of `package.json` worth showing: a package's own name and
    /// version. Core reads the same file when it loads the package; this is for
    /// the list, before anything runs.
    public static func describe(files: [String: Data], provider: String,
                               specJSON: String? = nil) -> MagpiePackage {
        var name = provider
        var version = ""
        if let manifest = files["package.json"],
           let object = try? JSONSerialization.jsonObject(with: manifest) as? [String: Any] {
            if let declared = object["name"] as? String, !declared.isEmpty { name = declared }
            if let declared = object["version"] as? String { version = declared }
        }
        var encoded: [String: String] = [:]
        for (path, body) in files {
            encoded[path] = body.base64EncodedString()
        }
        return MagpiePackage(provider: provider, name: name, version: version,
                             files: encoded, installedAt: Date().ISO8601Format(),
                             specJSON: specJSON)
    }
}

/// Installed packages, kept beside the other client data.
public final class MagpiePackageStore: @unchecked Sendable {
    private let directory: URL
    private let lock = NSLock()

    /// `directory` is the app's Application Support folder, or a temporary one
    /// in tests.
    public init(directory: URL) {
        self.directory = directory
    }

    private var indexURL: URL { directory.appendingPathComponent("magpie-packages.json") }

    public func list() throws -> [MagpiePackage] {
        lock.lock()
        defer { lock.unlock() }
        return try read()
    }

    /// Stores a package under its provider id, replacing any earlier copy.
    ///
    /// `specJSON`, when given, is stored with the package in the same write:
    /// writing it afterwards would rewrite the whole file table, which for a
    /// package of a few megabytes is a second copy of everything.
    @discardableResult
    public func install(provider: String, files: [String: Data],
                        specJSON: String? = nil) throws -> MagpiePackage {
        guard files["package.json"] != nil else {
            throw MagpieError("这个包没有 package.json,不能当插件安装")
        }
        lock.lock()
        defer { lock.unlock() }
        var packages = try read()
        let package = MagpiePackage.describe(files: files, provider: provider, specJSON: specJSON)
        packages.removeAll { $0.provider == provider }
        packages.append(package)
        packages.sort { $0.provider < $1.provider }
        try write(packages)
        return package
    }

    /// Replaces one stored package, keeping the list sorted. Used after an
    /// install records what the plugin declared.
    public func replace(_ package: MagpiePackage) throws {
        lock.lock()
        defer { lock.unlock() }
        var packages = try read()
        guard let index = packages.firstIndex(where: { $0.provider == package.provider }) else {
            packages.append(package)
            packages.sort { $0.provider < $1.provider }
            try write(packages)
            return
        }
        packages[index] = package
        try write(packages)
    }

    public func remove(provider: String) throws {
        lock.lock()
        defer { lock.unlock() }
        var packages = try read()
        let before = packages.count
        packages.removeAll { $0.provider == provider }
        if packages.count != before { try write(packages) }
    }

    /// The files to hand Core.
    public func files(provider: String) throws -> [String: Data]? {
        lock.lock()
        defer { lock.unlock() }
        return try read().first { $0.provider == provider }?.decodedFiles
    }

    private func read() throws -> [MagpiePackage] {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return [] }
        let data = try Data(contentsOf: indexURL)
        return try JSONDecoder().decode([MagpiePackage].self, from: data)
    }

    private func write(_ packages: [MagpiePackage]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Written beside and moved into place: a crash mid-write must not leave
        // the list unreadable and take every installed package with it.
        let temporary = indexURL.appendingPathExtension("tmp")
        try encoder.encode(packages).write(to: temporary, options: .atomic)
        if FileManager.default.fileExists(atPath: indexURL.path) {
            _ = try FileManager.default.replaceItemAt(indexURL, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: indexURL)
        }
    }
}
