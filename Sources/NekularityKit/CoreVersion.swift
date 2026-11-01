import Foundation

/// The Core this build is expected to link.
///
/// `scripts/core-version` decides which Core is built; this constant is what the
/// app shows, so a bug report can name the Core it ran without asking anyone to
/// open a terminal. `scripts/check-core-pin.sh` fails when the two disagree —
/// a stale constant would be worse than none.
public enum CoreVersion {
    public static let pinned = "b5b483bf52dd0a7896da33218eae9022020cc62c"

    /// The first twelve characters: enough to identify a build, short enough to
    /// read in a footer.
    public static var short: String {
        String(pinned.prefix(12))
    }
}
