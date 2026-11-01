import Foundation
import Observation

/// Videos kept on this device, with where the user stopped watching.
///
/// This is the foundation of a library rather than a source: a file the user
/// brought in stays, it is listed by title, and its position is remembered. An
/// Emby or Jellyfin connection later feeds the same list, which is why the list
/// lives in the kit and not in a screen.
@MainActor
@Observable
public final class VideoLibraryStore {
    public struct Item: Codable, Sendable, Identifiable, Hashable {
        public var id: String
        public var title: String
        /// File name inside the library directory, not an absolute path: the
        /// container moves between launches and between devices restoring a
        /// backup.
        public var file: String
        public var seconds: Double
        public var position: Double
        public var added: Date
        /// Size on disk, so the library can say what it costs.
        public var bytes: Int

        public var progress: Double {
            PlaybackProgress.fraction(position: position, duration: seconds)
        }
    }

    public private(set) var items: [Item] = []
    public private(set) var failure: String?

    private let directory: URL
    private let videos: URL

    public init(directory: URL) {
        self.directory = directory
        videos = directory.appending(path: "Videos", directoryHint: .isDirectory)
        load()
    }

    public func url(for item: Item) -> URL {
        videos.appending(path: item.file)
    }

    /// Copies a picked file into the library and lists it.
    ///
    /// A copy rather than a bookmark: a security-scoped bookmark to another
    /// app's container is the kind of reference that works until the other app
    /// moves or the file is replaced, and "my video disappeared" is worse than
    /// spending the disk twice.
    public func importVideo(from url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try FileManager.default.createDirectory(at: videos, withIntermediateDirectories: true)
        let name = url.lastPathComponent
        let destination = videos.appending(path: name)
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)
        let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int) ?? 0
        let item = Item(id: UUID().uuidString, title: url.deletingPathExtension().lastPathComponent,
                        file: name, seconds: 0, position: 0, added: Date(),
                        bytes: size)
        items.insert(item, at: 0)
        save()
    }

    public func remove(_ item: Item) {
        try? FileManager.default.removeItem(at: videos.appending(path: item.file))
        items.removeAll { $0.id == item.id }
        save()
    }

    /// Records where playback got to. Called when the player closes, which is
    /// the only moment the position is both known and settled.
    public func update(_ item: Item, position: Double, seconds: Double) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].position = position
        if seconds > 0 { items[index].seconds = seconds }
        save()
    }

    /// The one to offer as "continue watching": furthest along but not finished.
    public var resume: Item? {
        items
            .filter { $0.position > 30 && $0.progress < 0.95 }
            .max { $0.added < $1.added }
    }

    private func load() {
        let manifest = directory.appending(path: "videos.json")
        guard let data = try? Data(contentsOf: manifest),
              let list = try? JSONDecoder().decode([Item].self, from: data) else { return }
        // A file deleted behind the app's back must not stay in the list.
        items = list.filter { FileManager.default.fileExists(atPath: videos.appending(path: $0.file).path) }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: directory.appending(path: "videos.json"), options: .atomic)
    }
}
