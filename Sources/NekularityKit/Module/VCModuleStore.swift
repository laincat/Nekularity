import Foundation
import Observation

public struct InstalledVCModule: Hashable, Sendable, Identifiable {
    public let id: String
    public let origin: String
    public let enabled: Bool
    public let document: VCModuleDocument
}

/// One atomic snapshot contains both module bodies and their enablement order.
/// The host supplies IDs from its catalog or local import. IDs are only data.
@MainActor
@Observable
public final class VCModuleStore {
    public private(set) var modules: [InstalledVCModule] = []
    public private(set) var invalidModuleIDs: [String] = []
    public private(set) var failure: String?

    private struct Record: Codable {
        var id: String
        var origin: String
        var enabled: Bool
        var body: Data

        func module() -> InstalledVCModule? {
            guard VCModuleIdentifier.isValid(id), let document = try? VCModuleDocument.parse(body) else { return nil }
            return InstalledVCModule(id: id, origin: origin, enabled: enabled, document: document)
        }
    }

    private let directory: URL
    private var file: URL { directory.appending(path: "modules.json") }

    public init(directory: URL) {
        self.directory = directory
        reload()
    }

    public func reload() {
        do {
            show(try read())
        } catch {
            modules = []
            invalidModuleIDs = []
            failure = error.localizedDescription
        }
    }

    /// Installed modules start disabled. Updating the same identity keeps its precedence and enablement.
    @discardableResult
    public func install(data: Data, id: String, origin: String = "") throws -> InstalledVCModule {
        guard VCModuleIdentifier.isValid(id) else { throw VCModuleError.invalidIdentifier(id) }
        let document = try VCModuleDocument.parse(data)
        var records = try read()
        let index = records.firstIndex { $0.id == id }
        let enabled = index.map { records[$0].enabled } ?? false
        let record = Record(id: id, origin: origin, enabled: enabled, body: data)
        if let index { records[index] = record } else { records.append(record) }
        try save(records)
        return InstalledVCModule(id: id, origin: origin, enabled: enabled, document: document)
    }

    public func setEnabled(_ enabled: Bool, id: String) throws {
        var records = try read()
        guard let index = records.firstIndex(where: { $0.id == id }) else {
            throw VCModuleError.moduleNotFound(id)
        }
        if enabled, records[index].module() == nil {
            throw VCModuleError.unreadableStore("模块正文无法通过校验")
        }
        records[index].enabled = enabled
        try save(records)
    }

    public func remove(_ id: String) throws {
        var records = try read()
        guard let index = records.firstIndex(where: { $0.id == id }) else {
            throw VCModuleError.moduleNotFound(id)
        }
        records.remove(at: index)
        try save(records)
    }

    public func effectiveSettings(over base: VCModuleBaseSettings) -> VCModuleBaseSettings {
        VCModuleOverlay.resolve(base: base, modules: modules)
    }

    private func read() throws -> [Record] {
        let manager = FileManager.default
        let type: FileAttributeType?
        do {
            let folderType = try manager.attributesOfItem(atPath: directory.path)[.type] as? FileAttributeType
            guard folderType == .typeDirectory else { throw VCModuleError.pathEscape(directory.lastPathComponent) }
            type = try manager.attributesOfItem(atPath: file.path)[.type] as? FileAttributeType
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return []
        }
        guard type == .typeRegular else { throw VCModuleError.pathEscape(file.lastPathComponent) }
        do {
            let data = try Data(contentsOf: file)
            let records = try JSONDecoder().decode([Record].self, from: data)
            guard Set(records.map(\.id)).count == records.count else {
                throw VCModuleError.unreadableStore("模块标识重复")
            }
            return records
        } catch {
            _ = StoreRescue.keepCopy(of: file)
            throw VCModuleError.unreadableStore("索引无法读取，原文件已保留")
        }
    }

    private func save(_ records: [Record]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(records)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        show(records)
    }

    private func show(_ records: [Record]) {
        var loaded: [InstalledVCModule] = []
        var invalid: [String] = []
        for record in records {
            if let module = record.module() { loaded.append(module) } else { invalid.append(record.id) }
        }
        modules = loaded
        invalidModuleIDs = invalid
        failure = invalid.isEmpty ? nil : "有 \(invalid.count) 个模块正文无法通过校验"
    }
}
