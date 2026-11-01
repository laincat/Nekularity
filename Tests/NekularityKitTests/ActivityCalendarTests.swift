import Foundation
import Testing

@testable import NekularityKit

@Suite("Activity calendar")
struct ActivityCalendarTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "UTC")!
        value.firstWeekday = 2 // Monday, so the leading padding is not accidentally zero.
        return value
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func entry(_ source: String, _ id: String, on day: Date, kind: String? = nil) -> ShelfHistory {
        var entry = ShelfHistory(comic: ShelfComic(source: source, id: id, title: id))
        entry.time = Int(day.timeIntervalSince1970)
        entry.kind = kind
        return entry
    }

    @Test("a month starts on the calendar's first weekday and ends on its last")
    func gridPads() {
        // 2026-11-01 is a Sunday; with Monday as the first weekday it needs six
        // empty slots before it.
        let weeks = ActivityCalendar.grid(for: date(2026, 11, 1), calendar: calendar)
        #expect(weeks.first?.prefix(6).allSatisfy { $0 == nil } == true)
        #expect(weeks.first?.last != nil)
        #expect(weeks.flatMap { $0 }.compactMap { $0 }.count == 30)
        #expect(weeks.allSatisfy { $0.count == 7 })
    }

    @Test("a month whose first day is the first weekday has no leading gap")
    func gridWithoutGap() {
        // 2026-06-01 is a Monday.
        let weeks = ActivityCalendar.grid(for: date(2026, 6, 1), calendar: calendar)
        #expect(weeks.first?.first != nil)
        #expect(weeks.count == 5)
    }

    @Test("entries land on the day they happened, newest first")
    func entriesByDay() {
        let history = [entry("s", "a", on: date(2026, 11, 1)),
                       entry("s", "b", on: date(2026, 11, 1)),
                       entry("s", "c", on: date(2026, 10, 31))]
        let onFirst = ActivityCalendar.entries(history, on: date(2026, 11, 1), calendar: calendar)
        #expect(onFirst.count == 2)
        #expect(onFirst.allSatisfy { $0.time >= onFirst.last?.time ?? 0 })
        #expect(ActivityCalendar.entries(history, on: date(2026, 11, 2), calendar: calendar).isEmpty)
    }

    @Test("counts separate the days")
    func counts() {
        let history = [entry("s", "a", on: date(2026, 11, 1)),
                       entry("s", "b", on: date(2026, 11, 2)),
                       entry("s", "c", on: date(2026, 11, 2))]
        let counts = ActivityCalendar.counts(history, calendar: calendar)
        #expect(counts[ActivityCalendar.key(date(2026, 11, 1), calendar: calendar)] == 1)
        #expect(counts[ActivityCalendar.key(date(2026, 11, 2), calendar: calendar)] == 2)
    }

    @Test("a streak counts back over consecutive days and stops at the first gap")
    func streak() {
        let history = [entry("s", "a", on: date(2026, 11, 3)),
                       entry("s", "b", on: date(2026, 11, 2)),
                       entry("s", "c", on: date(2026, 10, 31))]
        #expect(ActivityCalendar.streak(history, endingOn: date(2026, 11, 3), calendar: calendar) == 2)
        // Ending on a day with nothing yet still counts yesterday's streak, since
        // today is not over.
        #expect(ActivityCalendar.streak(history, endingOn: date(2026, 11, 4), calendar: calendar) == 2)
        #expect(ActivityCalendar.streak([], endingOn: date(2026, 11, 4), calendar: calendar) == 0)
    }
}
