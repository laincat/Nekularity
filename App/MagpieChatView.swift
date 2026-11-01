import SwiftUI
import NekularityKit

/// One conversation with a provider, through its own package.
///
/// This is a reader for the reply, not an agent: it sends what the user typed,
/// shows the text as it arrives, and stops when the screen closes. Tools and
/// multi-turn agent loops belong to a later phase, and pretending otherwise
/// would hide that nothing runs them yet.
struct MagpieChatView: View {
    let accounts: MagpieAccounts
    let provider: String
    let providerName: String

    @Environment(\.dismiss) private var dismiss
    @State private var model = ""
    @State private var models: [MagpieModel] = []
    @State private var modelNote: String?
    @State private var prompt = ""
    @State private var messages: [(role: String, text: String)] = []
    @State private var reply = ""
    @State private var reasoning = ""
    @State private var error: String?
    @State private var running = false
    @State private var task: Task<Void, Never>?
    @State private var usage = ""
    /// Set when the vendor stopped at the token limit: the reply on screen is
    /// complete as far as it goes, and saying so is better than letting someone
    /// read a cut-off sentence as the whole answer.
    @State private var truncated = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.element.role == "user" ? "你" : providerName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(item.element.text).textSelection(.enabled)
                            }
                        }
                        if !reasoning.isEmpty {
                            DisclosureGroup("思考") {
                                Text(reasoning).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        if !reply.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(providerName).font(.caption).foregroundStyle(.secondary)
                                Text(reply).textSelection(.enabled)
                            }
                        }
                        if let error {
                            Text(error).foregroundStyle(.red).font(.footnote)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }

                Divider()
                VStack(spacing: 8) {
                    if models.isEmpty {
                        // A vendor that does not list its models still works: the
                        // user types the name, and the note says why.
                        HStack {
                            TextField("模型名", text: $model)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.footnote)
                                .textFieldStyle(.roundedBorder)
                            if let modelNote {
                                Text(modelNote).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Picker("模型", selection: $model) {
                            ForEach(models) { entry in
                                Text(entry.detail.isEmpty ? entry.name : "\(entry.name) · \(entry.detail)")
                                    .tag(entry.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    HStack(alignment: .bottom) {
                        TextField("说点什么", text: $prompt, axis: .vertical)
                            .lineLimit(1...5)
                            .textFieldStyle(.roundedBorder)
                        if running {
                            Button("停止") { stop() }
                                .buttonStyle(.bordered)
                        }
                        Button("发送") { send() }
                            .buttonStyle(.borderedProminent)
                            .disabled(running || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isEmpty)
                    }
                    if truncated {
                        Label("已达长度上限,回复可能不完整", systemImage: "scissors")
                            .font(.caption2)
                            .foregroundStyle(Color.orange)
                    }
                    if !usage.isEmpty {
                        Text("用量 \(usage)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle(providerName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { stop(); dismiss() }
                }
            }
            .task { await loadModels() }
            .onDisappear { stop() }
        }
    }

    private func loadModels() async {
        do {
            let list = try await Task.detached { [accounts, provider] in
                try accounts.runner(for: provider).models(provider: provider)
            }.value
            models = list
            if model.isEmpty, let first = list.first { model = first.id }
            modelNote = list.isEmpty ? "这家不提供列表" : nil
        } catch {
            models = []
            modelNote = "读不到模型列表"
            self.error = error.localizedDescription
        }
    }

    private func send() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !model.isEmpty, !running else { return }
        prompt = ""
        reply = ""
        reasoning = ""
        error = nil
        usage = ""
        truncated = false
        messages.append((role: "user", text: text))
        let history = messages.map { MagpieMessage(role: $0.role, content: $0.text) }
        running = true
        task = Task {
            defer { running = false }
            do {
                let chat = try accounts.runner(for: provider).makeChat(provider: provider)
                for try await event in chat.send(model: model, messages: history) {
                    switch event.kind {
                    case .text: reply += event.text
                    case .reasoning: reasoning += event.text
                    case .error: error = event.text
                    case .done:
                        usage = event.usageJSON
                        truncated = event.truncated
                    case .end, .other: break
                    }
                }
                if !reply.isEmpty { messages.append((role: "assistant", text: reply)) }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func stop() {
        task?.cancel()
        task = nil
        running = false
    }
}
