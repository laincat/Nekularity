import CryptoKit
import Foundation
import Observation

/// Errors raised by `NovelAdaptStore` on invalid writes or missing workspaces.
public enum NovelAdaptStoreError: Error, LocalizedError, Sendable, Equatable {
    case emptyProjectID
    case workspaceNotFound(String)
    case emptyImageData
    case invalidReferenceKey
    case unsafeStoragePath(String)

    public var errorDescription: String? {
        switch self {
        case .emptyProjectID:
            "改编项目 ID 不能为空"
        case .workspaceNotFound(let id):
            "找不到改编项目: \(id)"
        case .emptyImageData:
            "图片数据为空,无法写入缓存"
        case .invalidReferenceKey:
            "角色参考图需要指定角色标识"
        case .unsafeStoragePath(let path):
            "拒绝写入不安全的本地路径: \(path)"
        }
    }
}

/// Persisted metadata for one local style or character reference image.
///
/// The raw image bytes live in a content-addressed path relative to the store
/// root; no absolute container path or API credential is ever recorded.
public struct NovelAdaptReferenceEntry: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: AdaptImageRefKind
    /// Character ID, name, or alias when `kind == .character`; nil for style refs.
    public var characterKey: String?
    public var label: String?
    public var mimeType: String
    /// Relative path under `NovelAdaptStore.root` (never absolute, never `..`).
    public var relativePath: String
    public var byteCount: Int
    public var sha256: String
    /// Unix seconds when stored.
    public var addedAt: Int

    public init(
        id: String,
        kind: AdaptImageRefKind,
        characterKey: String? = nil,
        label: String? = nil,
        mimeType: String,
        relativePath: String,
        byteCount: Int,
        sha256: String,
        addedAt: Int = Int(Date().timeIntervalSince1970)
    ) {
        self.id = id
        self.kind = kind
        self.characterKey = characterKey
        self.label = label
        self.mimeType = mimeType
        self.relativePath = relativePath
        self.byteCount = byteCount
        self.sha256 = sha256
        self.addedAt = addedAt
    }
}

/// Persisted metadata for one cached static comic panel image.
public struct NovelAdaptPanelImageEntry: Codable, Sendable, Hashable, Identifiable {
    public var chapterID: String
    public var sceneID: String
    public var panelID: String
    /// Core's `Panel.imageRefId` (for example `"ch1/s1/p1"`).
    public var refID: String
    public var mimeType: String
    /// Relative path under `NovelAdaptStore.root` (never absolute, never `..`).
    public var relativePath: String
    public var byteCount: Int
    public var sha256: String
    public var revisedPrompt: String?
    /// Unix seconds when rendered and cached.
    public var renderedAt: Int

    public var id: String {
        Self.key(chapterID: chapterID, sceneID: sceneID, panelID: panelID)
    }

    public static func key(chapterID: String, sceneID: String, panelID: String) -> String {
        "\(chapterID)|\(sceneID)|\(panelID)"
    }

    public init(
        chapterID: String,
        sceneID: String,
        panelID: String,
        refID: String,
        mimeType: String,
        relativePath: String,
        byteCount: Int,
        sha256: String,
        revisedPrompt: String? = nil,
        renderedAt: Int = Int(Date().timeIntervalSince1970)
    ) {
        self.chapterID = chapterID
        self.sceneID = sceneID
        self.panelID = panelID
        self.refID = refID
        self.mimeType = mimeType
        self.relativePath = relativePath
        self.byteCount = byteCount
        self.sha256 = sha256
        self.revisedPrompt = revisedPrompt
        self.renderedAt = renderedAt
    }
}

/// Complete persisted adaptation workspace for one novel.
///
/// Structurally carries no AI API keys or provider credentials: only the Core
/// `AdaptProject` (storyboards, cross-chapter character sheet, budget/usage,
/// local style metadata), resumable `AdaptCheckpoint`s, local reference image
/// manifests, and rendered panel image cache manifests.
public struct NovelAdaptWorkspace: Codable, Sendable, Hashable, Identifiable {
    public var project: AdaptProject
    /// Resumable chapter checkpoints keyed by `chapterID`.
    public var checkpoints: [String: AdaptCheckpoint]
    /// Local style and character reference images stored under the store root.
    public var references: [NovelAdaptReferenceEntry]
    /// Cached static comic panel images keyed by `NovelAdaptPanelImageEntry.key(...)`.
    public var panelImages: [String: NovelAdaptPanelImageEntry]
    /// Unix seconds when created.
    public var createdAt: Int
    /// Unix seconds when last updated.
    public var updatedAt: Int

    public var id: String { project.id }

    public init(
        project: AdaptProject,
        checkpoints: [String: AdaptCheckpoint] = [:],
        references: [NovelAdaptReferenceEntry] = [],
        panelImages: [String: NovelAdaptPanelImageEntry] = [:],
        createdAt: Int = Int(Date().timeIntervalSince1970),
        updatedAt: Int? = nil
    ) {
        self.project = project
        self.checkpoints = checkpoints
        self.references = references
        self.panelImages = panelImages
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

/// Persisted store for Wave 4B novel-to-comic adaptation projects, checkpoints,
/// local style/character reference images, and rendered panel image caches.
///
/// Follows the kit's storage discipline:
/// - No API keys or secrets are ever part of the persisted schema.
/// - Every path on disk is built from deterministic SHA-256 digests of opaque
///   IDs and verified against `root` to prevent path traversal.
/// - Manifest and binary writes are atomic, `performBatch` folds multiple
///   mutations into one manifest write, and a damaged manifest is copied aside
///   via `StoreRescue` rather than silently discarded.
@MainActor
@Observable
public final class NovelAdaptStore {
    public static let defaultFilename = "novel_adapt.json"

    public private(set) var workspaces: [String: NovelAdaptWorkspace] = [:]
    public private(set) var lastError: String?
    public let root: URL

    @ObservationIgnored private let manifestURL: URL
    @ObservationIgnored private let encoder: JSONEncoder
    @ObservationIgnored private let decoder = JSONDecoder()
    @ObservationIgnored private let inMemory: Bool
    @ObservationIgnored private var memoryBlobs: [String: Data] = [:]
    @ObservationIgnored private var batchDepth = 0
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private(set) var diskWriteCount = 0
    @ObservationIgnored var fileWriter: ((Data, URL) throws -> Void)?

    public init(directory: URL, filename: String = NovelAdaptStore.defaultFilename) {
        let base = directory.standardizedFileURL
        let cleanName = Self.sanitizeFilename(filename)
        self.root = base
        self.manifestURL = base.appendingPathComponent(cleanName)
        self.inMemory = false
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = enc
        load()
    }

    /// In-memory store for previews and unit tests.
    public init() {
        self.root = URL(fileURLWithPath: "/dev/null")
        self.manifestURL = URL(fileURLWithPath: "/dev/null")
        self.inMemory = true
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = enc
    }

    // MARK: Queries

    public var orderedWorkspaces: [NovelAdaptWorkspace] {
        workspaces.values.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id < rhs.id
        }
    }

    public func workspace(id projectID: String) -> NovelAdaptWorkspace? {
        workspaces[projectID]
    }

    public func workspace(novelSourceKey: String, novelID: String) -> NovelAdaptWorkspace? {
        workspaces.values.first {
            $0.project.novelSourceKey == novelSourceKey && $0.project.novelID == novelID
        }
    }

    // MARK: Projects, storyboards, and character sheets

    /// Creates or updates the workspace for `project`, preserving existing
    /// checkpoints, local references, and cached panel images.
    @discardableResult
    public func upsertProject(_ project: AdaptProject, now: Int = Int(Date().timeIntervalSince1970)) -> NovelAdaptWorkspace {
        let trimmedID = project.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            lastError = NovelAdaptStoreError.emptyProjectID.errorDescription
            return NovelAdaptWorkspace(project: project, createdAt: now, updatedAt: now)
        }
        var normalized = project
        normalized.id = trimmedID
        var updated: NovelAdaptWorkspace
        if var existing = workspaces[trimmedID] {
            existing.project = normalized
            existing.updatedAt = now
            updated = existing
        } else {
            updated = NovelAdaptWorkspace(project: normalized, createdAt: now, updatedAt: now)
        }
        workspaces[trimmedID] = updated
        save()
        return updated
    }

    public func updateCharacterSheet(projectID: String, sheet: AdaptCharacterSheet, now: Int = Int(Date().timeIntervalSince1970)) {
        guard var ws = workspaces[projectID] else { return }
        ws.project.characters = sheet
        ws.updatedAt = now
        workspaces[projectID] = ws
        save()
    }

    public func updateBudget(projectID: String, budget: AdaptBudget, now: Int = Int(Date().timeIntervalSince1970)) {
        guard var ws = workspaces[projectID] else { return }
        ws.project.budget = budget
        ws.updatedAt = now
        workspaces[projectID] = ws
        save()
    }

    public func updateStyleRef(projectID: String, styleRef: AdaptStyleRef?, now: Int = Int(Date().timeIntervalSince1970)) {
        guard var ws = workspaces[projectID] else { return }
        ws.project.styleRef = styleRef
        ws.updatedAt = now
        workspaces[projectID] = ws
        save()
    }

    /// Removes a workspace and deletes its locally cached panel and reference files.
    public func removeWorkspace(id projectID: String) {
        guard let removed = workspaces.removeValue(forKey: projectID) else { return }
        for entry in removed.panelImages.values {
            deleteBlob(relativePath: entry.relativePath)
        }
        for entry in removed.references {
            deleteBlob(relativePath: entry.relativePath)
        }
        if !inMemory {
            let projectDigest = Self.digest(projectID)
            for prefix in ["panels", "refs"] {
                if let folder = resolveSafeRelativePath("\(prefix)/\(projectDigest)") {
                    try? FileManager.default.removeItem(at: folder)
                }
            }
        }
        save()
    }

    // MARK: Checkpoints

    public func checkpoint(projectID: String, chapterID: String) -> AdaptCheckpoint? {
        workspaces[projectID]?.checkpoints[chapterID]
    }

    public func saveCheckpoint(
        _ checkpoint: AdaptCheckpoint,
        projectID: String,
        now: Int = Int(Date().timeIntervalSince1970)
    ) {
        guard var ws = workspaces[projectID], !checkpoint.chapterID.isEmpty else { return }
        ws.checkpoints[checkpoint.chapterID] = checkpoint
        ws.updatedAt = now
        workspaces[projectID] = ws
        save()
    }

    public func clearCheckpoint(
        projectID: String,
        chapterID: String,
        now: Int = Int(Date().timeIntervalSince1970)
    ) {
        guard var ws = workspaces[projectID], ws.checkpoints.removeValue(forKey: chapterID) != nil else { return }
        ws.updatedAt = now
        workspaces[projectID] = ws
        save()
    }

    // MARK: Local reference images (style & character)

    /// Saves a local personal style or character reference image into the store
    /// and registers it on the project workspace.
    @discardableResult
    public func saveReferenceImage(
        projectID: String,
        kind: AdaptImageRefKind,
        characterKey: String? = nil,
        label: String? = nil,
        mimeType: String,
        data: Data,
        id: String? = nil,
        now: Int = Int(Date().timeIntervalSince1970)
    ) throws -> NovelAdaptReferenceEntry {
        guard var ws = workspaces[projectID] else {
            throw NovelAdaptStoreError.workspaceNotFound(projectID)
        }
        guard !data.isEmpty else {
            throw NovelAdaptStoreError.emptyImageData
        }
        let normalizedCharKey: String?
        if kind == .character {
            let trimmed = characterKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else {
                throw NovelAdaptStoreError.invalidReferenceKey
            }
            normalizedCharKey = trimmed
        } else {
            normalizedCharKey = nil
        }

        let refID = (id?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? UUID().uuidString.lowercased()
        let normalizedMIME = Self.normalizeMIME(mimeType, data: data)
        let ext = Self.fileExtension(for: normalizedMIME)
        let relativePath = "refs/\(Self.digest(projectID))/\(kind.rawValue)/\(Self.digest(refID)).\(ext)"

        let previousPath = ws.references.first(where: { $0.id == refID })?.relativePath
        try writeBlob(data, relativePath: relativePath)
        if let previousPath, previousPath != relativePath {
            deleteBlob(relativePath: previousPath)
        }

        let entry = NovelAdaptReferenceEntry(
            id: refID,
            kind: kind,
            characterKey: normalizedCharKey,
            label: label,
            mimeType: normalizedMIME,
            relativePath: relativePath,
            byteCount: data.count,
            sha256: Self.sha256Hex(data),
            addedAt: now
        )
        ws.references.removeAll { $0.id == refID }
        ws.references.append(entry)
        ws.updatedAt = now
        workspaces[projectID] = ws
        save()
        return entry
    }

    public func referenceImages(projectID: String, kind: AdaptImageRefKind? = nil) -> [NovelAdaptReferenceEntry] {
        guard let ws = workspaces[projectID] else { return [] }
        guard let kind else { return ws.references }
        return ws.references.filter { $0.kind == kind }
    }

    public func loadReferenceImageData(projectID: String, referenceID: String) -> Data? {
        guard let entry = workspaces[projectID]?.references.first(where: { $0.id == referenceID }) else {
            return nil
        }
        return readBlob(relativePath: entry.relativePath)
    }

    /// Loads stored local reference images into inline `AdaptImageRef` values
    /// ready to attach to Core's `AdaptRenderOptions`. Missing or unsafe entries
    /// are skipped without failing the call.
    public func buildReferenceOptions(projectID: String) -> (style: [AdaptImageRef], characters: [String: [AdaptImageRef]]) {
        guard let ws = workspaces[projectID] else { return ([], [:]) }
        var styleRefs: [AdaptImageRef] = []
        var charRefs: [String: [AdaptImageRef]] = [:]
        for entry in ws.references {
            guard let data = readBlob(relativePath: entry.relativePath), !data.isEmpty else {
                continue
            }
            let ref = AdaptImageRef(
                id: entry.id,
                kind: entry.kind,
                label: entry.label,
                mimeType: entry.mimeType,
                data: data
            )
            switch entry.kind {
            case .style:
                styleRefs.append(ref)
            case .character:
                if let key = entry.characterKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
                    charRefs[key, default: []].append(ref)
                }
            }
        }
        return (styleRefs, charRefs)
    }

    public func removeReferenceImage(projectID: String, referenceID: String, now: Int = Int(Date().timeIntervalSince1970)) {
        guard var ws = workspaces[projectID],
              let idx = ws.references.firstIndex(where: { $0.id == referenceID }) else {
            return
        }
        let removed = ws.references.remove(at: idx)
        deleteBlob(relativePath: removed.relativePath)
        ws.updatedAt = now
        workspaces[projectID] = ws
        save()
    }

    // MARK: Rendered panel image cache

    /// Atomically caches rendered static comic panel bytes on disk and updates
    /// the workspace manifest. Replacing an existing panel removes any stale
    /// file when the MIME extension changes (for example after `ForceRerender`).
    @discardableResult
    public func savePanelImage(
        projectID: String,
        chapterID: String,
        sceneID: String,
        panelID: String,
        refID: String,
        mimeType: String,
        data: Data,
        revisedPrompt: String? = nil,
        now: Int = Int(Date().timeIntervalSince1970)
    ) throws -> NovelAdaptPanelImageEntry {
        guard var ws = workspaces[projectID] else {
            throw NovelAdaptStoreError.workspaceNotFound(projectID)
        }
        guard !data.isEmpty else {
            throw NovelAdaptStoreError.emptyImageData
        }

        let normalizedMIME = Self.normalizeMIME(mimeType, data: data)
        let ext = Self.fileExtension(for: normalizedMIME)
        let relativePath = "panels/\(Self.digest(projectID))/\(Self.digest(chapterID))/\(Self.digest(sceneID))_\(Self.digest(panelID)).\(ext)"

        let key = NovelAdaptPanelImageEntry.key(chapterID: chapterID, sceneID: sceneID, panelID: panelID)
        let previousPath = ws.panelImages[key]?.relativePath

        try writeBlob(data, relativePath: relativePath)
        if let previousPath, previousPath != relativePath {
            deleteBlob(relativePath: previousPath)
        }

        let entry = NovelAdaptPanelImageEntry(
            chapterID: chapterID,
            sceneID: sceneID,
            panelID: panelID,
            refID: refID,
            mimeType: normalizedMIME,
            relativePath: relativePath,
            byteCount: data.count,
            sha256: Self.sha256Hex(data),
            revisedPrompt: revisedPrompt,
            renderedAt: now
        )
        ws.panelImages[key] = entry
        ws.updatedAt = now
        workspaces[projectID] = ws
        save()
        return entry
    }

    public func panelImageEntry(
        projectID: String,
        chapterID: String,
        sceneID: String,
        panelID: String
    ) -> NovelAdaptPanelImageEntry? {
        let key = NovelAdaptPanelImageEntry.key(chapterID: chapterID, sceneID: sceneID, panelID: panelID)
        return workspaces[projectID]?.panelImages[key]
    }

    /// Safe local file URL for a cached panel image, or nil when in-memory,
    /// missing, or rejected by path-containment checks.
    public func panelImageURL(
        projectID: String,
        chapterID: String,
        sceneID: String,
        panelID: String
    ) -> URL? {
        guard !inMemory,
              let entry = panelImageEntry(projectID: projectID, chapterID: chapterID, sceneID: sceneID, panelID: panelID),
              let url = resolveSafeRelativePath(entry.relativePath),
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    public func loadPanelImageData(
        projectID: String,
        chapterID: String,
        sceneID: String,
        panelID: String
    ) -> Data? {
        guard let entry = panelImageEntry(projectID: projectID, chapterID: chapterID, sceneID: sceneID, panelID: panelID) else {
            return nil
        }
        return readBlob(relativePath: entry.relativePath)
    }

    public func removePanelImage(
        projectID: String,
        chapterID: String,
        sceneID: String,
        panelID: String,
        now: Int = Int(Date().timeIntervalSince1970)
    ) {
        let key = NovelAdaptPanelImageEntry.key(chapterID: chapterID, sceneID: sceneID, panelID: panelID)
        guard var ws = workspaces[projectID], let removed = ws.panelImages.removeValue(forKey: key) else {
            return
        }
        deleteBlob(relativePath: removed.relativePath)
        ws.updatedAt = now
        workspaces[projectID] = ws
        save()
    }

    // MARK: Batching and flushing

    /// Groups multiple mutations into a single atomic manifest write when the
    /// outermost batch finishes.
    public func performBatch(_ body: () throws -> Void) rethrows {
        batchDepth += 1
        defer {
            batchDepth -= 1
            if batchDepth == 0, dirty {
                writeManifestNow()
            }
        }
        try body()
    }

    public func flush() {
        guard dirty else { return }
        writeManifestNow()
    }

    // MARK: Path safety & binary storage

    /// Resolves a manifest relative path strictly inside `root`, rejecting
    /// absolute paths, tilde prefixes, backslashes, `.`, `..`, and any path
    /// that escapes `root`.
    func resolveSafeRelativePath(_ relativePath: String) -> URL? {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("/"),
              !trimmed.hasPrefix("~"),
              !trimmed.contains("\\"),
              !trimmed.contains("\0") else {
            return nil
        }
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }
        let base = root.standardizedFileURL
        let candidate = parts.reduce(base) { $0.appendingPathComponent(String($1)) }.standardizedFileURL
        let basePrefix = base.path.hasSuffix("/") ? base.path : base.path + "/"
        guard candidate.path.hasPrefix(basePrefix) else { return nil }
        return candidate
    }

    private func writeBlob(_ data: Data, relativePath: String) throws {
        if inMemory {
            memoryBlobs[relativePath] = data
            return
        }
        guard let url = resolveSafeRelativePath(relativePath) else {
            throw NovelAdaptStoreError.unsafeStoragePath(relativePath)
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    private func readBlob(relativePath: String) -> Data? {
        if inMemory {
            return memoryBlobs[relativePath]
        }
        guard let url = resolveSafeRelativePath(relativePath) else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    private func deleteBlob(relativePath: String) {
        if inMemory {
            memoryBlobs.removeValue(forKey: relativePath)
            return
        }
        guard let url = resolveSafeRelativePath(relativePath) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: Manifest persistence

    private struct ManifestFile: Codable {
        var version: Int
        var workspaces: [String: NovelAdaptWorkspace]
    }

    private func load() {
        guard let data = try? Data(contentsOf: manifestURL) else { return }
        do {
            let file = try decoder.decode(ManifestFile.self, from: data)
            workspaces = file.workspaces
        } catch {
            let kept = StoreRescue.keepCopy(of: manifestURL)
            lastError = "reading \(manifestURL.lastPathComponent): \(error.localizedDescription)"
                + (kept.map { ", 旧数据已另存为 \($0.lastPathComponent)" } ?? "")
        }
    }

    private func save() {
        dirty = true
        if batchDepth > 0 { return }
        writeManifestNow()
    }

    private func writeManifestNow() {
        guard !inMemory else {
            dirty = false
            return
        }
        do {
            let payload = ManifestFile(version: 1, workspaces: workspaces)
            let data = try encoder.encode(payload)
            if let fileWriter {
                try fileWriter(data, manifestURL)
            } else {
                try FileManager.default.createDirectory(
                    at: manifestURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: manifestURL, options: .atomic)
            }
            diskWriteCount += 1
            dirty = false
            lastError = nil
        } catch {
            dirty = true
            lastError = "writing \(manifestURL.lastPathComponent): \(error.localizedDescription)"
        }
    }

    // MARK: Helpers

    static func sanitizeFilename(_ raw: String) -> String {
        let last = raw.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .last
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if last.isEmpty || last == "." || last == ".." || last.contains("\0") {
            return defaultFilename
        }
        return last
    }

    static func digest(_ value: String) -> String {
        let hash = SHA256.hash(data: Data(value.utf8))
        return hash.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func normalizeMIME(_ raw: String, data: Data) -> String {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch lower {
        case "image/png": return "image/png"
        case "image/jpeg", "image/jpg": return "image/jpeg"
        case "image/webp": return "image/webp"
        case "image/gif": return "image/gif"
        default:
            return detectMIME(data)
        }
    }

    static func detectMIME(_ data: Data) -> String {
        let bytes = [UInt8](data.prefix(12))
        if bytes.count >= 8,
           bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47,
           bytes[4] == 0x0D, bytes[5] == 0x0A, bytes[6] == 0x1A, bytes[7] == 0x0A {
            return "image/png"
        }
        if bytes.count >= 3, bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF {
            return "image/jpeg"
        }
        if bytes.count >= 12,
           bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46,
           bytes[8] == 0x57, bytes[9] == 0x45, bytes[10] == 0x42, bytes[11] == 0x50 {
            return "image/webp"
        }
        if bytes.count >= 6,
           bytes[0] == 0x47, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x38 {
            return "image/gif"
        }
        return "application/octet-stream"
    }

    static func fileExtension(for mimeType: String) -> String {
        switch mimeType.lowercased() {
        case "image/png": "png"
        case "image/jpeg", "image/jpg": "jpg"
        case "image/webp": "webp"
        case "image/gif": "gif"
        default: "bin"
        }
    }
}
