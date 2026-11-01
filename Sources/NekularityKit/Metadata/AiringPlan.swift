import Foundation

/// One reminder that should exist on the device.
public struct PlannedReminder: Hashable, Sendable, Identifiable {
    /// Stable across runs, so rescheduling replaces rather than duplicates.
    public var id: String
    public var title: String
    public var body: String
    /// When the device should say it.
    public var fireAt: Date

    public init(id: String, title: String, body: String, fireAt: Date) {
        self.id = id
        self.title = title
        self.body = body
        self.fireAt = fireAt
    }
}

/// Turning air dates into reminders, kept away from the notification framework.
///
/// The framework is not testable in a unit test and not available in a simulator
/// run that never grants permission, but *which* reminders should exist is plain
/// arithmetic over dates — and that is where the bugs are: duplicating a show,
/// scheduling one for yesterday, or scheduling 300 of them.
public enum AiringPlan {
    /// Reminders are said on the morning of the air day rather than at broadcast
    /// time, because a broadcast time is in the *server's* time zone and this device
    /// does not know it. A date is a date; a time would be a guess.
    public static let hourOfDay = 9

    /// No more than this many at once: iOS caps pending notifications per app, and
    /// a user with forty shows does not want forty banners.
    public static let limit = 20

    /// The reminders that should exist now.
    ///
    /// - Parameters:
    ///   - shows: what the metadata source knows, in any order.
    ///   - now: so a test can decide what "future" means.
    ///   - days: how far ahead to plan.
    ///   - leadDays: 0 says "on the day", 1 says "the evening before".
    public static func plan(_ shows: [SeriesInfo], now: Date = Date(), days: Int = 30,
                            leadDays: Int = 0, calendar: Calendar = .current) -> [PlannedReminder] {
        var seen = Set<String>()
        var planned: [(date: Date, reminder: PlannedReminder)] = []
        for show in shows {
            guard let airs = show.nextAirDate else { continue }
            // A show the source knows twice is one show.
            guard !seen.contains(show.key) else { continue }
            guard let day = calendar.date(byAdding: .day, value: -leadDays, to: airs) else { continue }
            guard var fireAt = calendar.date(bySettingHour: hourOfDay, minute: 0, second: 0, of: day) else {
                continue
            }
            // A reminder for a moment that has passed is worse than none: it can
            // only fire immediately, which reads as a bug.
            if fireAt <= now {
                // Still worth saying today if the air date itself is today or later.
                guard let soon = calendar.date(bySettingHour: hourOfDay, minute: 0, second: 0, of: airs),
                      soon > now else { continue }
                fireAt = soon
            }
            let horizon = calendar.date(byAdding: .day, value: days, to: now) ?? now
            guard fireAt <= horizon else { continue }
            seen.insert(show.key)
            let episode = show.nextEpisode
            let body: String
            if let episode, !episode.name.isEmpty {
                body = "S\(episode.season)E\(episode.number) · \(episode.name)"
            } else if let episode {
                body = "第 \(episode.season) 季第 \(episode.number) 集"
            } else {
                body = "新一集"
            }
            planned.append((fireAt, PlannedReminder(id: show.key, title: show.name, body: body, fireAt: fireAt)))
        }
        // Soonest first before capping, so the cap drops the furthest shows rather
        // than whichever happened to come last in a dictionary.
        return planned.sorted { $0.date < $1.date }.prefix(limit).map(\.reminder)
    }

    /// Identifiers that exist but should not, so they can be cancelled.
    public static func stale(existing: [String], planned: [PlannedReminder]) -> [String] {
        let keep = Set(planned.map(\.id))
        return existing.filter { !keep.contains($0) }.sorted()
    }
}
