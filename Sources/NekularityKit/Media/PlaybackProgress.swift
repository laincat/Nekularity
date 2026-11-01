import Foundation

/// One place for the arithmetic three screens used to do separately.
///
/// `MediaItem`, `ShelfHistory` and `VideoLibraryStore.Item` each computed a
/// fraction of the way through a video, and each could have got it slightly
/// different: a clamp in one, a divide-by-zero guard in another, a rounding in a
/// third. Two clocks formatted durations a fourth way. This is the one copy.
public enum PlaybackProgress {
    /// Jellyfin and Emby count 100 ns units.
    public static let ticksPerSecond: Double = 10_000_000

    public static func seconds(fromTicks ticks: Int64) -> Int {
        Int(Double(ticks) / ticksPerSecond)
    }

    public static func ticks(fromSeconds seconds: Double) -> Int64 {
        Int64((max(0, seconds) * ticksPerSecond).rounded())
    }

    /// 0–1, and 0 when the length is unknown: an unknown length is not a position.
    public static func fraction(position: Double, duration: Double) -> Double {
        guard duration > 0, position.isFinite, duration.isFinite else { return 0 }
        return min(1, max(0, position / duration))
    }

    /// The same fraction as the 0–100 an entry stores.
    public static func percent(position: Double, duration: Double) -> Int? {
        guard duration > 0 else { return nil }
        return Int((fraction(position: position, duration: duration) * 100).rounded())
    }

    /// A position worth resuming: past the opening credits, short of the end.
    ///
    /// Two seconds in is not a position and neither is two minutes before the
    /// credits, and both rules live here so the three stores cannot disagree about
    /// what "continue watching" means.
    public static func isResumable(position: Double, duration: Double,
                                   startGrace: Double = 5, endGrace: Double = 0.95) -> Bool {
        guard duration > 0 else { return false }
        let fraction = fraction(position: position, duration: duration)
        return position > startGrace && fraction < endGrace
    }

    /// `1:05` under an hour, `1:02:03` over it.
    public static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let rest = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }
}
