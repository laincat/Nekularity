import Foundation

/// The Core this build is expected to link.
///
/// `scripts/core-version` decides which Core is built; this constant is what the
/// app shows, so a bug report can name the Core it ran without asking anyone to
/// open a terminal. `scripts/check-core-pin.sh` fails when the two disagree —
/// a stale constant would be worse than none.
public enum CoreVersion {
    public static let pinned = "2380abd972d42b65c99d9ffc6cb7c3e12e44975d"

    /// The first twelve characters: enough to identify a build, short enough to
    /// read in a footer.
    public static var short: String {
        String(pinned.prefix(12))
    }
}
