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
    @State private var prompt = ""
    @State private var messages: [(role: String, text: String)] = []
    @State private var reply = ""
    @State private var reasoning = ""
    @State private var error: String?
    @State private var running = false
    @State private var task: Task<Void, Never>?
    @State private var usage = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(message.role == "user" ? "你" : providerName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(message.text).textSelection(.enabled)
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
                    HStack {
                        TextField("模型名(插件里声明的)", text: $model)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.footnote)
                            .textFieldStyle(.roundedBorder)
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
            .onDisappear { stop() }
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
        messages.append((role: "user", text: text))
        let history = messages.map { MagpieMessage(role: $0.role, content: $0.text) }
        running = true
        task = Task {
            defer { running = false }
            do {
                let chat = try accounts.runner(for: provider).makeChat()
                for try await event in chat.send(model: model, messages: history) {
                    switch event.kind {
                    case .text: reply += event.text
                    case .reasoning: reasoning += event.text
                    case .error: error = event.text
                    case .done: usage = event.usageJSON
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
