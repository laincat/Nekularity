import Foundation

public enum CoreVersion {
    public static let revision: String = {
        guard let url = Bundle.main.url(forResource: "CoreRevision", withExtension: "txt"),
              let value = try? String(contentsOf: url, encoding: .utf8) else { return "unknown" }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }()

    /// The first twelve characters: enough to identify a build, short enough to
    /// read in a footer.
    public static var short: String {
        let abbreviated = String(revision.prefix(12))
        return revision.hasSuffix("-dirty") ? abbreviated + "-dirty" : abbreviated
    }
}
