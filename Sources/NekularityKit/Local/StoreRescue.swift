import Foundation

/// Keeps a copy of a store file that could not be read.
///
/// The dangerous sequence is not the failed read: a store that cannot decode its
/// file usually reports the error and carries on with an empty list, and the very
/// next change — recording a page, importing a comic — saves that empty list over
/// the file. What the user sees is "the upgrade lost my shelf", and the data was
/// destroyed by a save, not by the decode.
///
/// So a file that will not decode is copied aside first. It costs one file and it
/// turns an unrecoverable loss into a recoverable one.
public enum StoreRescue {
    /// Copies `url` to a sibling named `<name>.unreadable-<stamp>` and returns the copy.
    ///
    /// The original is left in place: a later version may be able to read it, and a
    /// repair by hand is easier when the file is where it belongs.
    @discardableResult
    public static func keepCopy(of url: URL, now: Date = Date()) -> URL? {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else { return nil }
        let stamp = Self.stamp(now)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "json" : url.pathExtension
        let copy = url.deletingLastPathComponent()
            .appending(path: "\(base).unreadable-\(stamp).\(ext)")
        do {
            try manager.copyItem(at: url, to: copy)
            return copy
        } catch {
            // A copy that cannot be made is still worth nothing to crash over: the
            // original is untouched either way.
            return nil
        }
    }

    /// Copies that were made, newest last, so a store can tell the user where the
    /// old data went rather than only that something went wrong.
    public static func copies(of url: URL) -> [URL] {
        let manager = FileManager.default
        let base = url.deletingPathExtension().lastPathComponent
        let directory = url.deletingLastPathComponent()
        guard let entries = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return entries
            .filter { $0.lastPathComponent.hasPrefix(base + ".unreadable-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
