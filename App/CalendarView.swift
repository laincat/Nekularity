import NekularityKit
import SwiftUI

/// 阅读日历: a month of what was read and watched, with the streak and the day's
/// own list.
///
/// It is honest about what it is not. There is no airing schedule to show, because
/// a comic source reports chapters that exist and gives no broadcast date — an
/// "upcoming" column would be invented. Reminders wait for a metadata source that
/// can answer for them.
struct CalendarView: View {
    @Environment(ShelfStore.self) private var shelf

    @State private var month = Date()
    @State private var selected = Date()

    private var calendar: Calendar { .current }

    private var history: [ShelfHistory] { shelf.history }
    private var counts: [String: Int] { ActivityCalendar.counts(history) }
    private var weeks: [[Date?]] { ActivityCalendar.grid(for: month) }

    private var selectedEntries: [ShelfHistory] {
        ActivityCalendar.entries(history, on: selected)
    }

    var body: some View {
        List {
            Section {
                monthHeader
                weekdayHeader
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    HStack(spacing: 0) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                            if let day {
                                dayCell(day)
                            } else {
                                Color.clear.frame(height: 44)
                            }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            }

            Section {
                HStack(spacing: 22) {
                    StatValue(value: "\(ActivityCalendar.streak(history, endingOn: Date()))",
                              unit: "天", label: "连续")
                    StatValue(value: "\(counts.values.reduce(0, +))", unit: "条", label: "总记录")
                    StatValue(value: "\(counts.count)", unit: "天", label: "有记录")
                }
            }

            Section(dayTitle) {
                if selectedEntries.isEmpty {
                    Text("这天没有阅读或观看记录。").font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(selectedEntries, id: \.key) { entry in
                        if entry.isVideo {
                            HStack {
                                Image(systemName: "play.rectangle").foregroundStyle(.secondary)
                                Text(entry.title).lineLimit(1)
                                Spacer()
                                if let percent = entry.videoPercent {
                                    Text("\(String(percent))%").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            NavigationLink {
                                ComicDetailView(route: ComicRoute(source: entry.source,
                                                                  comic: Comic(id: entry.id, title: entry.title,
                                                                               subtitle: entry.author, cover: entry.cover)))
                            } label: {
                                HStack {
                                    Text(entry.title).lineLimit(1)
                                    Spacer()
                                    if let chapter = entry.chapter {
                                        Text(chapter).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("阅读日历")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("今天") {
                    month = Date()
                    selected = Date()
                }
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                shift(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            Spacer()
            Text(month.formatted(.dateTime.year().month(.wide)))
                .font(.headline)
            Spacer()
            Button {
                shift(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
        }
        .accessibilityIdentifier("calendar.month")
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol).font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// The calendar's own first weekday, so the grid's columns and the header
    /// cannot disagree.
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    private func dayCell(_ day: Date) -> some View {
        let count = counts[ActivityCalendar.key(day)] ?? 0
        let isSelected = calendar.isDate(day, inSameDayAs: selected)
        let isToday = calendar.isDateInToday(day)
        return Button {
            selected = day
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.callout)
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundStyle(isToday ? Color.accentColor : .primary)
                Circle()
                    .fill(count > 0 ? Color.accentColor.opacity(0.25 + 0.75 * min(1, Double(count) / 4))
                                    : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(isSelected ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("calendar.day.\(ActivityCalendar.key(day))")
        .accessibilityValue(count == 0 ? "无记录" : "\(count) 条")
    }

    private var dayTitle: String {
        calendar.isDateInToday(selected) ? "今天" : selected.formatted(.dateTime.month().day().weekday(.wide))
    }

    private func shift(_ months: Int) {
        guard let moved = calendar.date(byAdding: .month, value: months, to: month) else { return }
        month = moved
    }
}
