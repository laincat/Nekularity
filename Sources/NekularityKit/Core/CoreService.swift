import Foundation

/// One installed service package, as Core reports it.
///
/// Core owns the package: it verifies the archive, unpacks it, and keeps the
/// record. This type is only what the client needs to list one and to ask what
/// it is allowed to do. Account values never appear here — those belong to the
/// client, not to Core.
public struct ServiceRecord: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var version: String
    /// Where the package came from, for showing a user what they installed.
    public var origin: String
    /// The archive digest Core checked, when the caller supplied one.
    public var sha256: String?
    /// Core's install time, kept as the string Core wrote so this type does not
    /// have to guess a date format Core owns.
    public var installed: String
    /// The directory Core unpacked the package into.
    public var dir: String
    /// The capabilities the package asks for. A client must intersect these
    /// with what it is willing to grant; asking is not being granted.
    public var permissions: [String]?
}

public enum CoreServiceError: Error, LocalizedError, Equatable {
    case core(String)
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .core(let message): return message
        case .unreadable(let what): return "Core 返回了无法解析的\(what)"
        }
    }
}

/// Installs, lists and removes Core service packages.
///
/// Running a service is deliberately absent: it needs this client's transport
/// and its account values, so the client that wires it also owns the host it
/// runs with. These five calls are the part Core can do on its own.
public enum CoreService {
    /// Verifies and installs a package archive, returning Core's record.
    public static func install(dataDir: String, origin: String, digest: String,
                               archive: Data) throws -> ServiceRecord {
        var error: NSError?
        let json = MobileServiceInstall(dataDir, origin, digest,
                                        archive.base64EncodedString(), &error)
        if let error { throw CoreServiceError.core(error.localizedDescription) }
        return try decode(json, as: ServiceRecord.self, what: "安装记录")
    }

    /// Every installed package, newest installation order as Core keeps it.
    public static func list(dataDir: String) throws -> [ServiceRecord] {
        var error: NSError?
        let json = MobileServiceList(dataDir, &error)
        if let error { throw CoreServiceError.core(error.localizedDescription) }
        return try decode(json, as: [ServiceRecord].self, what: "服务清单")
    }

    /// Removes one package. Core reports an error for an unknown id rather than
    /// pretending the removal happened.
    public static func remove(dataDir: String, id: String) throws {
        var error: NSError?
        MobileServiceRemove(dataDir, id, &error)
        if let error { throw CoreServiceError.core(error.localizedDescription) }
    }

    /// The record of one installed package, without unpacking it again.
    public static func manifest(dataDir: String, id: String) throws -> ServiceRecord {
        var error: NSError?
        let json = MobileServiceManifest(dataDir, id, &error)
        if let error { throw CoreServiceError.core(error.localizedDescription) }
        return try decode(json, as: ServiceRecord.self, what: "服务记录")
    }

    /// The entry code of an installed package, for a client that will run it.
    public static func source(dataDir: String, id: String) throws -> String {
        var error: NSError?
        let code = MobileServiceSource(dataDir, id, &error)
        if let error { throw CoreServiceError.core(error.localizedDescription) }
        return code ?? ""
    }

    private static func decode<T: Decodable>(_ json: String?, as type: T.Type,
                                             what: String) throws -> T {
        guard let json, let data = json.data(using: .utf8) else {
            throw CoreServiceError.unreadable(what)
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw CoreServiceError.unreadable(what)
        }
    }
}
