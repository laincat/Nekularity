import NekularityKit
import SwiftUI

/// The second tab: what was read, by day.
///
/// Rex's 我的 is a calendar with a day strip, today's totals, and a heat map of
/// the last months. The data here is reading rather than watching — same idea,
/// because "how much did I read this month" is the question such a screen
/// answers.
struct MineView: View {
    @Environment(ShelfStore.self) private var shelf
    @Environment(DownloadStore.self) private var downloads
    @Environment(ProfileStore.self) private var profiles
    @Environment(\.switchProfile) private var switchProfile
    @State private var showingProfiles = false

    @State private var selected = Date()

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    profileBar
                    weekStrip
                    dayCard
                    heatmap
                    watchlist
                    shelfLinks
                }
                .padding(16)
            }
            .navigationTitle("我的")
            .contentMargins(.bottom, 76, for: .scrollContent)
            .sheet(isPresented: $showingProfiles) {
                ProfilesView(profiles: profiles, switchTo: switchProfile)
            }
            .navigationDestination(for: ComicRoute.self) { ComicDetailView(route: $0) }
        }
    }

    /// Which account everything below belongs to, and the way to another one.
    private var profileBar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 38, height: 38)
                .overlay(Image(systemName: "person.crop.circle").foregroundStyle(.secondary))
            VStack(alignment: .leading, spacing: 1) {
                Text(profiles.active.name).font(.subheadline.weight(.semibold))
                Text("源、登录、书架与下载都只属于这个环境").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button("切换") { showingProfiles = true }
                .buttonStyle(Pill())
                .accessibilityIdentifier("profile.switch")
        }
        .glassCard()
    }

    /// One week, ending today: the strip Rex puts above the day's card.
    private var weekStrip: some View {
        HStack(spacing: 6) {
            ForEach(week, id: \.self) { day in
                let isSelected = calendar.isDate(day, inSameDayAs: selected)
                let isToday = calendar.isDateInToday(day)
                Button { selected = day } label: {
                    VStack(spacing: 4) {
                        Text(weekday(day)).font(.caption2).foregroundStyle(isToday ? .red : .secondary)
                        Text("\(calendar.component(.day, from: day))").font(.body.weight(isSelected ? .bold : .regular))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(isSelected ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.clear),
                                in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var dayCard: some View {
        let entries = shelf.history.filter { calendar.isDate(Date(timeIntervalSince1970: TimeInterval($0.time)),
                                                             inSameDayAs: selected) }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(calendar.isDateInToday(selected) ? "今天" : title(selected)).font(.headline)
                Spacer()
                Text(title(selected)).font(.caption).foregroundStyle(.secondary)
            }
            if entries.isEmpty {
                Text("这天没有阅读记录").font(.callout).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 22) {
                    StatValue(value: "\(entries.count)", unit: "部", label: "漫画")
                    StatValue(value: "\(Set(entries.map(\.chapter)).count)", unit: "话", label: "章节")
                }
                ForEach(entries.prefix(5), id: \.key) { entry in
                    NavigationLink(value: ComicRoute(source: entry.source,
                                                     comic: Comic(id: entry.id, title: entry.title,
                                                                  subtitle: entry.author, cover: entry.cover))) {
                        HStack {
                            Text(entry.comic.title).font(.callout).lineLimit(1)
                            Spacer()
                            if let chapter = entry.chapter {
                                Text(chapter).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    /// The last fifteen weeks, one square a day: the same question the day card
    /// answers, asked about months.
    private var heatmap: some View {
        let counts = dayCounts()
        let peak = max(1, counts.values.max() ?? 1)
        return VStack(alignment: .leading, spacing: 8) {
            Text("历史阅读").font(.headline)
            LazyHGrid(rows: Array(repeating: GridItem(.fixed(10), spacing: 3), count: 7), spacing: 3) {
                ForEach(0..<105, id: \.self) { index in
                    let day = calendar.date(byAdding: .day, value: index - 104, to: calendar.startOfDay(for: Date()))!
                    let count = counts[key(day)] ?? 0
                    RoundedRectangle(cornerRadius: 2)
                        .fill(count == 0 ? AnyShapeStyle(.quaternary)
                              : AnyShapeStyle(Color.accentColor.opacity(0.25 + 0.75 * Double(count) / Double(peak))))
                        .frame(width: 10, height: 10)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 82)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var watchlist: some View {
        let items = shelf.folders.flatMap(\.items).prefix(6)
        return VStack(alignment: .leading, spacing: 8) {
            Text("收藏").font(.headline)
            if items.isEmpty {
                Text("收藏夹还是空的").font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(items), id: \.id) { comic in
                            NavigationLink(value: ComicRoute(source: comic.source,
                                                            comic: Comic(id: comic.id, title: comic.title,
                                                                         subtitle: comic.author, cover: comic.cover))) {
                                VStack(spacing: 4) {
                                    Group {
                                        if let cover = comic.cover, let url = URL(string: cover) {
                                            SourceImage(key: .init(source: comic.source, url: url.absoluteString,
                                                                   isThumbnail: true), maxPixel: 240)
                                        } else {
                                            Color.secondary.opacity(0.2)
                                        }
                                    }
                                    .frame(width: 72, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    Text(comic.title).font(.caption2).lineLimit(1).frame(width: 72)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var shelfLinks: some View {
        VStack(spacing: 0) {
            NavigationLink { ShelfView() } label: {
                Label("书架与收藏夹", systemImage: "books.vertical")
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            Divider()
            NavigationLink { DownloadsView() } label: {
                Label("下载（\(downloads.chapters.count) 话）", systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .glassCard()
    }

    // MARK: - Dates

    private var week: [Date] {
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    private func weekday(_ day: Date) -> String {
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return names[calendar.component(.weekday, from: day) - 1]
    }

    private func title(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter.string(from: day)
    }

    private func key(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: day)
    }

    private func dayCounts() -> [String: Int] {
        var counts: [String: Int] = [:]
        for entry in shelf.history {
            counts[key(Date(timeIntervalSince1970: TimeInterval(entry.time))), default: 0] += 1
        }
        return counts
    }
}
