import Foundation

/// The Core this build is expected to link.
///
/// `scripts/core-version` decides which Core is built; this constant is what the
/// app shows, so a bug report can name the Core it ran without asking anyone to
/// open a terminal. `scripts/check-core-pin.sh` fails when the two disagree —
/// a stale constant would be worse than none.
public enum CoreVersion {
    public static let pinned = "cc63215a5466cab7c0dc074d903a17a3bc770ffb"

    /// The first twelve characters: enough to identify a build, short enough to
    /// read in a footer.
    public static var short: String {
        String(pinned.prefix(12))
    }
}
