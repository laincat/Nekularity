import Foundation
import Observation

/// What the reader searched for, newest first.
///
/// The file is `searches.json` in the profile, the same shape the desktop
/// client writes, and an official `.venera` backup's `searchHistory` merges
/// into it.
@MainActor
@Observable
public final class SearchHistoryStore {
    /// How many keywords are kept.
    public static let limit = 30

    public private(set) var queries: [String] = []
    public private(set) var lastError: String?

    private let url: URL
    private var inMemory = false

    public init(directory: URL) {
        self.url = directory.appendingPathComponent("searches.json")
        load()
    }

    /// A store that keeps its keywords in memory, for previews and tests.
    public init() {
        self.url = URL(fileURLWithPath: "/dev/null")
        self.inMemory = true
    }

    /// Puts a keyword at the front. Case-insensitive repeats replace the old
    /// entry, so "One Piece" after "one piece" keeps one.
    public func add(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        queries.removeAll { $0.compare(trimmed, options: .caseInsensitive) == .orderedSame }
        queries.insert(trimmed, at: 0)
        if queries.count > Self.limit {
            queries.removeLast(queries.count - Self.limit)
        }
        save()
    }

    /// Adds keywords from an import, keeping local ones ahead of them.
    @discardableResult
    public func merge(_ imported: [String]) -> Int {
        var added = 0
        for query in imported.reversed() {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if queries.contains(where: { $0.compare(trimmed, options: .caseInsensitive) == .orderedSame }) {
                continue
            }
            queries.insert(trimmed, at: 0)
            added += 1
        }
        if queries.count > Self.limit {
            queries.removeLast(queries.count - Self.limit)
        }
        if added > 0 { save() }
        return added
    }

    public func remove(_ query: String) {
        queries.removeAll { $0.compare(query, options: .caseInsensitive) == .orderedSame }
        save()
    }

    public func clear() {
        queries.removeAll()
        save()
    }

    // MARK: Storage

    private struct File: Codable {
        var queries: [String]
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        do {
            queries = try JSONDecoder().decode(File.self, from: data).queries
        } catch {
            lastError = "reading searches.json: \(error.localizedDescription)"
        }
    }

    private func save() {
        guard !inMemory else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(File(queries: queries))
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            lastError = nil
        } catch {
            lastError = "writing searches.json: \(error.localizedDescription)"
        }
    }
}
