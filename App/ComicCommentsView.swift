import NekularityKit
import SwiftUI

/// A comic's comment thread.
///
/// Twenty official sources declare `comic.loadComments` and thirteen declare
/// `comic.sendComment`. The handlers hang off the source's `comic` object, and a
/// client looking for a top-level `loadComments` concludes every source keeps no
/// comments — so asking Core is the only way to know.
struct ComicCommentsView: View {
    let source: String
    let comicID: String
    let subID: String

    @Environment(SourceLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var pending = true
    @State private var error: String?
    @State private var notice: String?
    @State private var support: CommentSupport?
    @State private var comments: [ComicComment] = []
    @State private var page = 1
    @State private var maxPage = 0
    @State private var draft = ""
    @State private var sending = false
    @State private var voting = false
    @State private var replyTo: ComicComment?
    /// The comment whose replies are on screen; nil shows the thread itself.
    @State private var threadOf: ComicComment?
    /// Bumped on every load so a slower page cannot replace a newer one.
    @State private var generation = 0

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("评论")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await load(page) }
                        } label: {
                            Label("刷新", systemImage: "arrow.clockwise")
                        }
                        .disabled(pending)
                    }
                }
                .task { await first() }
                .safeAreaInset(edge: .bottom) { composer }
        }
    }

    @ViewBuilder private var content: some View {
        List {
            if let error {
                Section {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }
            }
            if support?.load == false {
                Section {
                    Text("这个源不提供评论。").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if !comments.isEmpty {
                if let threadOf {
                    Section {
                        HStack {
                            Text("回复 \(threadOf.userName) 的评论").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("返回全部评论") { Task { await showThread() } }
                                .font(.caption)
                        }
                    }
                }
                Section {
                    // Oldest first, as a thread reads.
                    ForEach(comments) { one in
                        row(one)
                    }
                } footer: {
                    if maxPage > 0 {
                        Text("第 \(page) / \(maxPage) 页").font(.caption2)
                    }
                }
                Section {
                    HStack {
                        Button("上一页") { Task { await load(page - 1) } }
                            .disabled(pending || page <= 1)
                        Spacer()
                        Button("下一页") { Task { await load(page + 1) } }
                            .disabled(pending || maxPage == 0 || page >= maxPage)
                    }
                }
            } else if pending {
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
            } else if support?.load != false {
                Section {
                    Text("这一页没有评论。").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .overlay { if pending && comments.isEmpty { ProgressView() } }
    }

    private func row(_ one: ComicComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(one.userName.isEmpty ? "匿名" : one.userName)
                    .font(.caption.weight(.semibold))
                if !one.time.isEmpty {
                    Text(one.time).font(.caption2).foregroundStyle(.secondary)
                }
                if !one.score.isEmpty {
                    Text("· \(one.score)").font(.caption2).foregroundStyle(.secondary)
                }
                if one.isLiked {
                    Text("· 已赞").font(.caption2).foregroundStyle(.tint)
                }
                Spacer()
            }
            Text(one.content).font(.subheadline)
            HStack(spacing: 12) {
                if one.replyCount > 0 {
                    // The count is the source's word that replies exist; reading
                    // them is a second call, and only from the thread itself.
                    if threadOf == nil, !one.identity.isEmpty {
                        Button("\(one.replyCount) 条回复") { Task { await showReplies(one) } }
                            .font(.caption2)
                    } else {
                        Text("\(one.replyCount) 条回复").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if support?.like == true, !one.identity.isEmpty {
                    // The same button takes the vote back: the source takes a flag,
                    // not two functions.
                    Button(one.isLiked ? "取消赞" : "赞") { Task { await vote(one) } }
                        .font(.caption2)
                        .disabled(voting)
                }
                if support?.send == true {
                    Button("回复") { replyTo = one }
                        .font(.caption2)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// The box to write in. It stays at the bottom so writing does not mean
    /// scrolling the thread away.
    private var composer: some View {
        VStack(spacing: 6) {
            if let notice {
                Text(notice).font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let replyTo {
                HStack(spacing: 8) {
                    Text("回复 \(replyTo.userName)").font(.caption2).foregroundStyle(.secondary)
                    Button("取消") { self.replyTo = nil }.font(.caption2)
                    Spacer()
                }
            }
            if support?.send == false {
                Text("这个源不支持在这里评论。")
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 8) {
                    TextField("写点什么…", text: $draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                    if sending {
                        ProgressView()
                    } else {
                        Button("发送") { Task { await send() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .padding(10)
        .background(.bar)
    }

    private func first() async {
        do {
            support = try await library.core.commentSupport(key: source)
        } catch {
            self.error = error.localizedDescription
        }
        await load(1)
    }

    private func load(_ wanted: Int) async {
        guard support?.load != false else { return }
        let target = max(1, wanted)
        generation += 1
        let ticket = generation
        pending = true
        error = nil
        notice = nil
        do {
            let result = try await library.core.comments(
                key: source, comicID: comicID, subID: subID, page: target,
                replyTo: threadOf?.identity ?? "")
            guard ticket == generation else { return }
            comments = result.comments
            page = target
            maxPage = result.maxPage
            pending = false
        } catch {
            guard ticket == generation else { return }
            pending = false
            if (error as? CoreError)?.isCancelled != true {
                self.error = error.localizedDescription
            }
            comments = []
        }
    }

    /// Loads the replies to one comment.
    private func showReplies(_ one: ComicComment) async {
        threadOf = one
        await load(1)
    }

    /// Returns to the thread itself.
    private func showThread() async {
        threadOf = nil
        await load(1)
    }

    /// Votes on one comment and reads the page again: a source may only report
    /// the new score on the next read.
    private func vote(_ one: ComicComment) async {
        voting = true
        error = nil
        do {
            try await library.core.likeComment(
                key: source, comicID: comicID, subID: subID,
                commentID: one.identity, isLike: !one.isLiked)
            await load(page)
        } catch {
            self.error = error.localizedDescription
        }
        voting = false
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        error = nil
        do {
            try await library.core.sendComment(
                key: source, comicID: comicID, subID: subID,
                content: text, replyTo: replyTo?.id ?? "")
            draft = ""
            replyTo = nil
            notice = "已发送"
            // Sources differ in whether the new comment comes back in the
            // response, so the thread is read again rather than guessed at.
            await load(1)
        } catch {
            self.error = error.localizedDescription
        }
        sending = false
    }
}
