import SwiftUI
import NekularityKit

/// Bangumi 追番：连接账号、看收藏、改状态与进度、搜条目。
///
/// 追番提醒不在这里安排：`SettingsView` 把 Bangumi 的「在看」和 TMDB 的「即将播出」
/// 合到同一份计划里，两者共用一套通知。
struct BangumiView: View {
    @Environment(BangumiStore.self) private var bangumi
    @State private var token = ""
    @State private var filter: CollectionType = .doing
    @State private var keyword = ""
    @State private var results: [BangumiSubject] = []
    @State private var searching = false

    var body: some View {
        List {
            if !bangumi.hasToken {
                connectSection
            } else {
                accountSection
                collectionsSection
                searchSection
            }
            calendarSection
            if let failure = bangumi.failure {
                Section {
                    Text(failure).font(.footnote).foregroundStyle(Color.red)
                }
            }
        }
        .navigationTitle("Bangumi")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if bangumi.hasToken { await bangumi.refresh(type: filter) }
        }
        .onChange(of: filter) { _, newValue in
            Task { await bangumi.refresh(type: newValue) }
        }
    }

    // MARK: - Sections

    private var connectSection: some View {
        Section {
            SecureField("访问令牌", text: $token)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("bangumi.token")
            Button {
                Task {
                    await bangumi.signIn(token: token)
                    if bangumi.hasToken { token = "" }
                }
            } label: {
                Label(bangumi.busy ? "正在验证…" : "连接", systemImage: "link")
            }
            .disabled(bangumi.busy || token.isEmpty)
            .accessibilityIdentifier("bangumi.connect")
            Link("在 Bangumi 生成令牌", destination: URL(string: "https://next.bgm.tv/demo/access-token")!)
        } header: {
            Text("连接账号")
        } footer: {
            Text("令牌只保存在这台设备的钥匙串里，用来读写你自己的收藏。")
        }
    }

    private var accountSection: some View {
        Section {
            HStack(spacing: 12) {
                if let avatar = bangumi.user?.avatar?.medium, let url = URL(string: avatar) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.secondary.opacity(0.15)
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(bangumi.user?.displayName ?? "已连接")
                        .font(.headline)
                    if let username = bangumi.user?.username {
                        Text("@\(username)").font(.caption).foregroundStyle(Color.secondary)
                    }
                }
                Spacer()
                Button("退出") { bangumi.signOut() }
                    .buttonStyle(.borderless)
            }
        }
    }

    private var collectionsSection: some View {
        Section {
            Picker("状态", selection: $filter) {
                ForEach(CollectionType.allCases) { type in
                    Text(type.label).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("bangumi.filter")

            if bangumi.collections.isEmpty {
                Text(bangumi.busy ? "正在读取…" : "这里还没有条目")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
            ForEach(bangumi.collections) { entry in
                NavigationLink {
                    BangumiDetailView(subjectID: entry.subjectID)
                } label: {
                    BangumiRow(entry: entry)
                }
            }
        } header: {
            Text("我的收藏")
        }
    }

    private var searchSection: some View {
        Section {
            HStack {
                TextField("搜索动画", text: $keyword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await runSearch() } }
                    .accessibilityIdentifier("bangumi.keyword")
                Button {
                    Task { await runSearch() }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .disabled(searching || keyword.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(results) { subject in
                NavigationLink {
                    BangumiDetailView(subjectID: subject.id)
                } label: {
                    BangumiSubjectRow(subject: subject)
                }
            }
        } header: {
            Text("搜索")
        } footer: {
            Text("搜到条目后可以在里面加入收藏。")
        }
    }

    /// 每日放送: public data, so it is shown even without an account.
    private var calendarSection: some View {
        Section {
            if bangumi.calendar.isEmpty {
                Button("读取每日放送") { Task { await bangumi.loadCalendar() } }
                    .accessibilityIdentifier("bangumi.calendar")
            }
            ForEach(bangumi.calendar) { day in
                DisclosureGroup("\(day.label)（\(day.items.count)）") {
                    ForEach(day.items.prefix(12)) { subject in
                        NavigationLink {
                            BangumiDetailView(subjectID: subject.id)
                        } label: {
                            HStack {
                                Text(subject.title).font(.footnote).lineLimit(1)
                                Spacer()
                                // The calendar answers "what airs", and the date is
                                // the part that changes week to week.
                                if let date = subject.date, !date.isEmpty {
                                    Text(date).font(.caption2).foregroundStyle(Color.secondary)
                                }
                            }
                        }
                    }
                }
            }
        } header: {
            Text("每日放送")
        }
    }

    private func runSearch() async {
        searching = true
        defer { searching = false }
        results = await bangumi.search(keyword)
    }
}

/// 收藏列表里的一行：封面、标题、进度、评分。
private struct BangumiRow: View {
    let entry: BangumiCollection

    var body: some View {
        HStack(spacing: 10) {
            if let poster = entry.subject?.poster, let url = URL(string: poster) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.secondary.opacity(0.15)
                }
                .frame(width: 42, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.subject?.title ?? "条目 \(entry.subjectID)")
                    .font(.subheadline)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text("进度 \(entry.progressText)")
                    if let rate = entry.rate, rate > 0 { Text("评分 \(rate)") }
                }
                .font(.caption)
                .foregroundStyle(Color.secondary)
            }
        }
    }
}

/// 搜索结果里的一行。
private struct BangumiSubjectRow: View {
    let subject: BangumiSubject

    var body: some View {
        HStack(spacing: 10) {
            if let poster = subject.poster, let url = URL(string: poster) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.secondary.opacity(0.15)
                }
                .frame(width: 38, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(subject.title).font(.subheadline).lineLimit(2)
                if let score = subject.score, score > 0 {
                    Text(String(format: "%.1f", score)).font(.caption).foregroundStyle(Color.secondary)
                }
            }
        }
    }
}

/// 条目详情：简介、评分、话数，以及改状态和标记看过。
struct BangumiDetailView: View {
    let subjectID: Int

    @Environment(BangumiStore.self) private var bangumi
    @State private var subject: BangumiSubject?
    @State private var episodes: [BangumiEpisode] = []
    @State private var collection: BangumiCollection?
    @State private var loading = true
    @State private var note: String?
    @State private var marking: Int?
    @State private var type: CollectionType = .wish
    @State private var rate = 0

    var body: some View {
        List {
            header
            collectionSection
            episodesSection
            if let note {
                Section { Text(note).font(.footnote).foregroundStyle(Color.secondary) }
            }
        }
        .navigationTitle(subject?.title ?? "条目")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var header: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(subject?.title ?? (loading ? "正在读取…" : "读不出来"))
                    .font(.title3.bold())
                if let summary = subject?.summary, !summary.isEmpty {
                    Text(summary).font(.footnote).foregroundStyle(Color.secondary).lineLimit(12)
                }
                HStack(spacing: 12) {
                    if let score = subject?.score, score > 0 {
                        Label(String(format: "%.1f", score), systemImage: "star.fill")
                    }
                    if let total = subject?.totalEpisodes, total > 0 {
                        Label("\(total) 话", systemImage: "list.number")
                    }
                    if let date = subject?.date, !date.isEmpty {
                        Label(date, systemImage: "calendar")
                    }
                }
                .font(.caption)
                .foregroundStyle(Color.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var collectionSection: some View {
        Section {
            Picker("状态", selection: $type) {
                ForEach(CollectionType.allCases) { value in
                    Text(value.label).tag(value)
                }
            }
            .onChange(of: type) { _, newValue in
                Task { await save(type: newValue) }
            }
            Stepper("我的评分 \(rate)", value: $rate, in: 0...10)
                .onChange(of: rate) { _, newValue in
                    Task { await save(rate: newValue) }
                }
        } header: {
            Text("我的收藏")
        } footer: {
            if collection == nil {
                Text("还没有加入收藏。改一下状态就会加入。")
            } else {
                Text("进度 \(collection?.progressText ?? "0")")
            }
        }
    }

    private var episodesSection: some View {
        Section("话") {
            if episodes.isEmpty {
                Text(loading ? "正在读取…" : "没有话数可显示")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
            ForEach(episodes) { episode in
                HStack(spacing: 8) {
                    Text(episode.number.map { "\($0)" } ?? "—")
                        .font(.caption.monospacedDigit())
                        .frame(width: 26, alignment: .trailing)
                        .foregroundStyle(Color.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(episode.title.isEmpty ? "第 \(episode.number ?? 0) 话" : episode.title)
                            .font(.subheadline)
                            .lineLimit(1)
                        if let airdate = episode.airdate, !airdate.isEmpty {
                            Text(airdate).font(.caption2).foregroundStyle(Color.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        Task { await mark(episode) }
                    } label: {
                        Image(systemName: marking == episode.id ? "clock" : "checkmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(marking != nil)
                }
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        guard let answer = await bangumi.detail(subjectID: subjectID) else { return }
        subject = answer.subject
        episodes = answer.episodes.filter(\.isMainStory)
        collection = answer.collection
        if let existing = answer.collection {
            type = existing.type
            rate = existing.rate ?? 0
        }
    }

    private func save(type newType: CollectionType? = nil, rate newRate: Int? = nil) async {
        await bangumi.set(type: newType ?? type,
                          rate: newRate ?? (rate == 0 ? nil : rate),
                          epStatus: collection?.epStatus,
                          for: subjectID)
        collection = (try? await bangumi.detail(subjectID: subjectID))?.collection
        note = bangumi.failure
    }

    private func mark(_ episode: BangumiEpisode) async {
        marking = episode.id
        defer { marking = nil }
        await bangumi.markWatched(subjectID: subjectID, episodeID: episode.id)
        if let refreshed = await bangumi.detail(subjectID: subjectID) {
            collection = refreshed.collection
        }
        note = bangumi.failure
    }
}
