import CryptoKit
import Foundation
import Observation

/// The service packages installed under one environment.
///
/// Core owns the packages: it verifies the archive, unpacks it and keeps the
/// record. This type only carries what a screen needs — the list, an install
/// from a file the user picked, and a removal — and keeps the interface's
/// wording out of Core's English errors.
@MainActor
@Observable
public final class ServiceStore {
    public private(set) var records: [ServiceRecord] = []
    /// The last failure, already worded for the interface.
    public private(set) var error: String?
    public private(set) var installing = false

    /// The answer to one run: what came back, or why nothing did.
    public struct RunResult: Sendable, Equatable {
        public var id: String
        public var method: String
        public var text: String
        public var ok: Bool
    }

    public private(set) var running: String?
    /// What the package said it offers, once it has been asked, and which
    /// package that answer belongs to: a stale list must not be offered for a
    /// different service.
    public private(set) var methods: [ServiceMethod] = []
    public private(set) var methodsFor: String?

    public private(set) var describing: String?
    public private(set) var run: RunResult?

    private let directory: URL
    /// This client's side of Core, needed to run a service: the package's HTTP
    /// goes through it, so the transport, cookies and certificates stay here.
    private let host: CoreHost?
    /// The account values the person entered for a service. Only what is here is
    /// handed to Core for one call, so a service cannot read anything else.
    public let accounts: ServiceAccounts
    /// Services live beside the sources of the environment they belong to, so a
    /// profile switch takes them along without anyone copying anything.
    public init(directory: URL, host: CoreHost? = nil,
                accounts: ServiceAccounts = MemoryServiceAccounts()) {
        self.directory = directory
        self.host = host
        self.accounts = accounts
    }

    public var dataDir: String { directory.path(percentEncoded: false) }

    /// The methods that belong to this package, never another one's.
    public func offeredMethods(for id: String) -> [ServiceMethod] {
        methodsFor == id ? methods : []
    }


    public func reload() {
        do {
            records = try CoreService.list(dataDir: dataDir)
            error = nil
        } catch {
            records = []
            self.error = Self.wording(for: error)
        }
    }

    /// Installs the package at `url`, which the user picked from Files.
    ///
    /// The digest is computed here and handed to Core, so the record says what
    /// was actually installed rather than what a listing claimed.
    public func install(from url: URL) async {
        installing = true
        defer { installing = false }
        do {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let archive = try Data(contentsOf: url)
            let digest = Self.digest(of: archive)
            let record = try await Task.detached { [dataDir] in
                try CoreService.install(dataDir: dataDir, origin: url.lastPathComponent,
                                        digest: digest, archive: archive)
            }.value
            error = nil
            records = try CoreService.list(dataDir: dataDir)
            _ = record
        } catch {
            // Refresh the list, but keep the reason: a successful refresh used
            // to clear the message the user needed to read, so a package Core
            // rejected looked like nothing had happened.
            let message = Self.wording(for: error)
            let rows = try? CoreService.list(dataDir: dataDir)
            if let rows {
                records = rows
            }
            self.error = message
        }
    }

    public func remove(_ id: String) {
        do {
            try CoreService.remove(dataDir: dataDir, id: id)
            // The package's code is gone, so its account values and any runtime
            // Core still holds for it must go too: a reinstalled package must
            // not inherit either.
            try? accounts.removeAll(service: id)
            CoreService.forget(dataDir: dataDir)
            records = try CoreService.list(dataDir: dataDir)
            error = nil
        } catch {
            let message = Self.wording(for: error)
            let rows = try? CoreService.list(dataDir: dataDir)
            if let rows {
                records = rows
            }
            self.error = message
        }
    }

    /// Asks the package what it offers. Describing runs the package's own code,
    /// so it is asked without granting anything: a service whose description
    /// needs the network answers with an error, and the screen offers `ping`
    /// instead of guessing.
    public func describe(_ record: ServiceRecord, granted: [String] = []) async {
        guard let host else {
            methods = []
            methodsFor = record.id
            return
        }
        describing = record.id
        defer { describing = nil }
        do {
            let found = try await Task.detached { [dataDir] in
                try CoreService.describe(host: host, dataDir: dataDir, id: record.id,
                                         granted: granted)
            }.value
            methods = found
            methodsFor = record.id
        } catch {
            methods = []
            methodsFor = record.id
        }
    }

    /// Runs one method of a package the user allowed these permissions.
    ///
    /// `granted` comes from the person, not from the manifest: Core intersects
    /// it with what the package asked for, so an allowance can only narrow.
    public func call(_ record: ServiceRecord, method: String, payload: String = "null",
                     granted: [String]) async {
        let secrets = (try? accounts.values(service: record.id)) ?? [:]
        guard let host else {
            run = RunResult(id: record.id, method: method,
                            text: "没有宿主，无法运行服务", ok: false)
            return
        }
        running = record.id
        defer { running = nil }
        do {
            let text = try await Task.detached { [dataDir] in
                try CoreService.call(host: host, dataDir: dataDir, id: record.id,
                                     method: method, payload: payload, granted: granted,
                                     secrets: secrets)
            }.value
            run = RunResult(id: record.id, method: method, text: text, ok: true)
        } catch {
            let message = (error as? CoreServiceError)?.errorDescription
                ?? error.localizedDescription
            run = RunResult(id: record.id, method: method, text: message, ok: false)
        }
    }

    /// SHA-256 of the archive, lowercase hex, which is the form Core records.
    public nonisolated static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Core's own message is kept for diagnosis, but what the screen shows says
    /// what happened in the language the rest of the interface speaks.
    private static func wording(for error: Error) -> String {
        if let service = error as? CoreServiceError {
            switch service {
            case .core(let message): return "服务包未被接受：\(message)"
            case .unreadable(let what): return "无法解析\(what)"
            }
        }
        return "操作失败：\(error.localizedDescription)"
    }
}
