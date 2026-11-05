import Foundation
import VeneraCatCore

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

/// One method a service offers to press.
public struct ServiceMethod: Decodable, Sendable, Hashable, Identifiable {
    public var name: String
    public var title: String?

    /// The memberwise initialiser is internal, so a screen in the app target
    /// could not build the `ping` fallback without this.
    public init(name: String, title: String? = nil) {
        self.name = name
        self.title = title
    }

    public var id: String { name }
    /// What a button says: the service's own wording when it gave one.
    public var label: String { (title?.isEmpty == false ? title! : name) }
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

/// Installs, lists, removes and runs Core service packages.
///
/// A service's HTTP goes out through this client's host, so a run takes one:
/// the transport, cookies and certificate decisions stay the app's, and Core
/// never opens a socket of its own.
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

    /// Drops the runtimes Core keeps for this directory, so a package that was
    /// removed or replaced is loaded from disk next time rather than served
    /// from a runtime holding the old code.
    public static func forget(dataDir: String) {
        MobileServiceRunForget(dataDir)
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

    /// Runs one method of an installed service.
    ///
    /// `host` is this client's side of Core: a service's fetch goes through its
    /// HTTP method, and cancelling tells it to drop the request. `granted` is
    /// what the user allowed; Core intersects it with what the package asked
    /// for, so withholding a permission cannot be undone by the package.
    public static func call(host: CoreHost, dataDir: String, id: String, method: String,
                            payload: String, granted: [String],
                            secrets: [String: String] = [:]) throws -> String {
        var error: NSError?
        let values = secrets.isEmpty
            ? ""
            : String(decoding: try JSONEncoder().encode(secrets), as: UTF8.self)
        let out = MobileServiceCallWithSecrets(host, dataDir, id, method, payload,
                                               granted.joined(separator: ","), values, &error)
        if let error { throw CoreServiceError.core(error.localizedDescription) }
        return out ?? "null"
    }

    /// What the package offers to press, as it describes itself.
    ///
    /// A service without a `describe` export answers with an empty list: it is
    /// used by other code rather than by a button, which is not an error.
    public static func describe(host: CoreHost, dataDir: String, id: String,
                                granted: [String]) throws -> [ServiceMethod] {
        var error: NSError?
        let json = MobileServiceDescribe(host, dataDir, id, granted.joined(separator: ","), &error)
        if let error { throw CoreServiceError.core(error.localizedDescription) }
        return try decode(json, as: [ServiceMethod].self, what: "服务方法清单")
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
