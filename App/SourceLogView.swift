import NekularityKit
import SwiftUI
import UIKit

/// What the sources have printed, with the source each line came from.
///
/// The same lines go to the host's log, which on a phone is a console nobody can
/// open. Without this screen the only visible symptom of a source failing is the
/// error it threw afterwards — usually a misleading one such as a null
/// dereference — while the line naming the real cause stays invisible.
struct SourceLogView: View {
    @Environment(SourceLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var lines: [SourceLogEntry] = []
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            List {
                if let failure {
                    Section {
                        Text(failure).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if lines.isEmpty {
                    Section {
                        Text("还没有源输出日志。源打印的内容,以及 Core 代表源产生的错误,都会出现在这里。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        // Oldest first, as a terminal shows it: the line before a
                        // failure is usually the explanation for it.
                        ForEach(lines) { line in
                            row(line)
                        }
                    } footer: {
                        Text("最多保留 400 行,更早的行会被丢掉。")
                            .font(.caption2)
                    }
                }
            }
            .navigationTitle("源日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        UIPasteboard.general.string = text(lines)
                    } label: {
                        Label("复制全部", systemImage: "doc.on.doc")
                    }
                    .disabled(lines.isEmpty)
                    Button(role: .destructive) {
                        Task {
                            await library.core.clearLogLines()
                            await reload()
                        }
                    } label: {
                        Label("清空", systemImage: "trash")
                    }
                    .disabled(lines.isEmpty)
                }
            }
            .refreshable { await reload() }
            .task { await reload() }
        }
    }

    private func row(_ line: SourceLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(stamp(line.time))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(line.key.isEmpty ? "(app)" : line.key)
                    .font(.caption2.weight(.semibold))
                Spacer()
                Text(line.title.isEmpty ? "JS" : line.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(line.content)
                .font(.caption.monospaced())
                .foregroundStyle(colour(line.level))
                .lineLimit(6)
        }
    }

    /// Errors are called out without hiding anything: a source failing is the
    /// reason someone opens this screen.
    private func colour(_ level: String) -> Color {
        switch level.lowercased() {
        case "error": return .red
        case "warn", "warning": return .orange
        default: return .primary
        }
    }

    private func stamp(_ millis: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(millis) / 1000)
        return date.formatted(date: .omitted, time: .standard)
    }

    /// What 复制全部 puts on the clipboard: something that can be pasted into a
    /// bug report as it is.
    private func text(_ lines: [SourceLogEntry]) -> String {
        lines.map { line in
            let key = line.key.isEmpty ? "(app)" : line.key
            let title = line.title.isEmpty ? "JS" : line.title
            // A source may log CRLF; replacing only \n would leave the \r behind
            // as an invisible character in the copied text. The desktop client
            // folds both, and the two panels should read the same.
            let body = line.content
                .replacingOccurrences(of: "\r\n", with: " ⏎ ")
                .replacingOccurrences(of: "\n", with: " ⏎ ")
            return "\(stamp(line.time))  \(key)  \(title): \(body)"
        }.joined(separator: "\n")
    }

    private func reload() async {
        do {
            lines = try await library.core.logLines()
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }
}
