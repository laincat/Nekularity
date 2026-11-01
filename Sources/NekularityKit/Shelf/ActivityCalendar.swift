import Foundation

/// The calendar over what the user actually did: reading and watching.
///
/// There is no airing schedule here, and the reason is data rather than design:
/// a comic source reports chapters that already exist and gives no broadcast date,
/// and a media server reports episodes it holds. An "upcoming episode" list would
/// therefore be invented, so this shows the days that have something in them and
/// leaves reminders to the metadata source that could answer for them.
public enum ActivityCalendar {
    /// A day key that sorts and compares as text, in the user's own calendar.
    public static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The history entries on one day.
    public static func entries(_ history: [ShelfHistory], on day: Date,
                               calendar: Calendar = .current) -> [ShelfHistory] {
        let want = key(day, calendar: calendar)
        return history
            .filter { key(Date(timeIntervalSince1970: TimeInterval($0.time)), calendar: calendar) == want }
            .sorted { $0.time > $1.time }
    }

    /// How much happened on each day, for the grid's shading.
    public static func counts(_ history: [ShelfHistory], calendar: Calendar = .current) -> [String: Int] {
        var counts: [String: Int] = [:]
        for entry in history {
            counts[key(Date(timeIntervalSince1970: TimeInterval(entry.time)), calendar: calendar), default: 0] += 1
        }
        return counts
    }

    /// A month as weeks of seven slots, with `nil` for the days before the first
    /// and after the last. Padding here rather than in the view keeps every
    /// calendar a test can check without a screen.
    public static func grid(for date: Date, calendar: Calendar = .current) -> [[Date?]] {
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let days = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        // Weekday of the first day, rebased so the grid starts on the calendar's
        // own first weekday rather than on Sunday.
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var slots: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<days {
            slots.append(calendar.date(byAdding: .day, value: offset, to: first))
        }
        while slots.count % 7 != 0 { slots.append(nil) }
        return stride(from: 0, to: slots.count, by: 7).map { Array(slots[$0..<min($0 + 7, slots.count)]) }
    }

    /// Consecutive days with activity, ending at `date` (or not counting it when
    /// the day is empty). Today with nothing yet does not break yesterday's streak:
    /// a streak is broken by a day that ended empty, and today has not ended.
    public static func streak(_ history: [ShelfHistory], endingOn date: Date,
                              calendar: Calendar = .current) -> Int {
        var counts = counts(history, calendar: calendar)
        var day = date
        if counts[key(day, calendar: calendar), default: 0] == 0 {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var length = 0
        while counts[key(day, calendar: calendar), default: 0] > 0 {
            length += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        // The variable is only a scratch cursor; keeping the counts dictionary
        // local means a caller cannot mutate the input.
        counts.removeAll()
        return length
    }
}
