import Foundation
import Testing

@testable import NekularityKit

@Suite("Airing reminders")
struct AiringPlanTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "UTC")!
        return value
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func show(_ id: Int, _ name: String, airs: String?) -> SeriesInfo {
        var info = SeriesInfo(source: "tmdb", id: id, name: name)
        if let airs {
            info.nextEpisode = .init(airDate: airs, season: 2, number: 5, name: "某集")
        }
        return info
    }

    @Test("a show with a date becomes a reminder on the morning of that day")
    func plansOnTheDay() {
        let plan = AiringPlan.plan([show(1, "某剧", airs: "2026-11-10")],
                                   now: date(2026, 11, 1), calendar: calendar)
        let reminder = try? #require(plan.first)
        #expect(plan.count == 1)
        #expect(reminder?.id == "tmdb/1")
        #expect(reminder?.title == "某剧")
        #expect(reminder?.body.contains("S2E5") == true)
        let parts = calendar.dateComponents([.month, .day, .hour], from: reminder!.fireAt)
        #expect(parts.month == 11 && parts.day == 10 && parts.hour == AiringPlan.hourOfDay)
    }

    @Test("a show without a date plans nothing rather than guessing")
    func noDateNoReminder() {
        #expect(AiringPlan.plan([show(1, "某剧", airs: nil)], now: date(2026, 11, 1), calendar: calendar).isEmpty)
        #expect(AiringPlan.plan([show(1, "某剧", airs: "not a date")], now: date(2026, 11, 1),
                                calendar: calendar).isEmpty)
    }

    @Test("a date already past is not scheduled, since it can only fire at once")
    func pastIsDropped() {
        let plan = AiringPlan.plan([show(1, "旧剧", airs: "2026-10-01")],
                                   now: date(2026, 11, 1), calendar: calendar)
        #expect(plan.isEmpty)
    }

    @Test("the same show twice is one reminder, and the soonest shows survive the cap")
    func dedupesAndCaps() {
        var shows = [show(1, "甲", airs: "2026-11-20"), show(1, "甲", airs: "2026-11-20")]
        for index in 0..<40 {
            let day = String(format: "2026-11-%02d", 2 + index % 20)
            shows.append(show(100 + index, "剧\(index)", airs: day))
        }
        let plan = AiringPlan.plan(shows, now: date(2026, 11, 1), calendar: calendar)
        #expect(plan.count == AiringPlan.limit)
        #expect(Set(plan.map(\.id)).count == plan.count)
        // Sorted by when they fire, so a cap drops the furthest shows.
        #expect(plan == plan.sorted { $0.fireAt < $1.fireAt })
    }

    @Test("a lead of one day says it the evening before")
    func leadDays() {
        let plan = AiringPlan.plan([show(1, "某剧", airs: "2026-11-10")],
                                   now: date(2026, 11, 1), leadDays: 1, calendar: calendar)
        let reminder = try? #require(plan.first)
        let parts = calendar.dateComponents([.day], from: reminder!.fireAt)
        #expect(parts.day == 9)
    }

    @Test("an airing today still gets a reminder if it is not yet morning")
    func todayStillPossible() {
        // Asked at 06:00 for a show airing that day: 09:00 is still ahead.
        let plan = AiringPlan.plan([show(1, "今天", airs: "2026-11-01")],
                                   now: date(2026, 11, 1, 6), calendar: calendar)
        #expect(plan.count == 1)
        // Asked at 10:00 the same day, the morning has gone.
        #expect(AiringPlan.plan([show(1, "今天", airs: "2026-11-01")],
                                now: date(2026, 11, 1, 10), calendar: calendar).isEmpty)
    }

    @Test("reminders that should no longer exist are named so they can be cancelled")
    func stale() {
        let planned = AiringPlan.plan([show(1, "甲", airs: "2026-11-10")],
                                      now: date(2026, 11, 1), calendar: calendar)
        #expect(AiringPlan.stale(existing: ["tmdb/1", "tmdb/9"], planned: planned) == ["tmdb/9"])
        #expect(AiringPlan.stale(existing: ["tmdb/1"], planned: planned).isEmpty)
    }
}
