import NekularityKit
import SwiftUI

/// The built-in standard protocols: OpenAI Chat/Responses and Anthropic
/// Messages, with the user's own key.
///
/// This screen exists because a key should be enough. Everything that needs a
/// plugin — another vendor, routing between accounts, quota lookups, masking —
/// belongs on the "AI 供应商" list instead. Keeping them apart is honest about
/// which of the two paths will work on a fresh install.
struct StandardAIView: View {
    @Environment(SourceLibrary.self) private var library

    @State private var config = StandardAISettingsStore().load()
    @State private var apiKey = ""
    @State private var keyLoaded = false

    @State private var models: [String] = []
    @State private var modelsNote: String?
    @State private var prompt = ""
    /// One place holds the answer, so the screen cannot draw it twice: the view
    /// once kept a `reply` *and* appended it to a message list, and both were
    /// rendered.
    @State private var conversation = StandardConversation()
    @State private var error: String?
    @State private var request = StandardAIRequest()
    /// Text of the answer being written. Cleared when the reply lands, so the
    /// finished answer comes from one place (the conversation) rather than two.
    @State private var partial = ""

    private let keys = StandardAIKeyStore()
    private let settings = StandardAISettingsStore()

    var body: some View {
        Form {
            Section {
                Picker("接口", selection: $config.protocol) {
                    ForEach(StandardProtocol.allCases) { Text($0.title).tag($0) }
                }
                TextField(config.protocol.defaultBaseURL, text: $config.baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                LabeledContent("模型") {
                    TextField("模型名", text: $config.model)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if !models.isEmpty {
                    Picker("目录里的模型", selection: $config.model) {
                        Text("（自己填）").tag(config.model)
                        ForEach(models, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
                if config.protocol == .messages {
                    LabeledContent("最大 token") {
                        TextField("4096", value: $config.maxTokens, format: .number)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }
                }
            } header: {
                Text("协议")
            } footer: {
                Text("地址留空就用 \(config.protocol.vendor) 的默认 API 根。自定义地址会整体替换根路径，不会再追加版本目录。")
            }

            Section {
                SecureField("\(config.protocol.vendor) API 密钥", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("保存密钥") { saveKey() }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if keyLoaded {
                    Button("清除密钥", role: .destructive) { clearKey() }
                }
                Button("读取模型目录") { loadModels() }
                    .disabled(busy || !keyLoaded)
                if let modelsNote { Text(modelsNote).font(.footnote).foregroundStyle(.secondary) }
            } header: {
                Text("密钥")
            } footer: {
                Text("密钥只写进这台设备的钥匙串，不随备份迁移；Core 不持久化它，请求时只放在鉴权头里。")
            }

            Section("对话") {
                ForEach(Array(conversation.messages.enumerated()), id: \.offset) { _, message in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.role == "user" ? "你" : config.protocol.vendor)
                            .font(.caption).foregroundStyle(.secondary)
                        Text(message.content).textSelection(.enabled)
                    }
                }
                if busy && !partial.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(config.protocol.vendor).font(.caption).foregroundStyle(.secondary)
                        Text(partial).textSelection(.enabled)
                            .accessibilityIdentifier("standardAI.streaming")
                        Text("正在写…").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if let reply = conversation.pending {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(config.protocol.vendor).font(.caption).foregroundStyle(.secondary)
                        Text(reply.text).textSelection(.enabled)
                        // Say which delivery this answer was, rather than
                        // claiming a stream that may not have happened.
                        Text(reply.streamed ? "流式" : "整包返回")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                HStack {
                    TextField("说点什么", text: $prompt, axis: .vertical)
                        .lineLimit(1...4)
                    if busy {
                        Button("停止") { stop() }.buttonStyle(.bordered)
                    } else {
                        Button("发送") { send() }
                            .buttonStyle(.borderedProminent)
                            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .navigationTitle("标准接口")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: config) { settings.save(config) }
        .onChange(of: config.baseURL) {
            stop()
            models = []
            modelsNote = nil
        }
        .onChange(of: config.protocol) { loadKey() }
        .task { loadKey() }
        .onDisappear { stop() }
    }

    private var client: StandardAI { StandardAI(core: library.core) }
    private var busy: Bool { request.isRunning }

    private func loadKey() {
        stop()
        do {
            apiKey = try keys.load(vendor: config.protocol.vendor) ?? ""
            keyLoaded = !apiKey.isEmpty
        } catch {
            self.error = error.localizedDescription
            keyLoaded = false
        }
        models = []
        modelsNote = nil
    }

    private func saveKey() {
        stop()
        do {
            try keys.save(vendor: config.protocol.vendor, key: apiKey)
            keyLoaded = true
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func clearKey() {
        stop()
        do {
            try keys.remove(vendor: config.protocol.vendor)
            apiKey = ""
            keyLoaded = false
            models = []
            modelsNote = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadModels() {
        guard !busy else { return }
        let snapshot = config
        let key = apiKey
        request.start(operation: { [client, snapshot, key] in
            try await client.models(config: snapshot, apiKey: key)
        }, receive: { list in
            self.models = list
            self.modelsNote = list.isEmpty ? "这家没有列出模型" : "共 \(list.count) 个模型"
            if self.config.model.isEmpty, let first = list.first { self.config.model = first }
        }, failure: { error in
            self.models = []
            self.modelsNote = nil
            self.error = error.localizedDescription
        })
    }

    private func send() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        prompt = ""
        error = nil
        let history = conversation.ask(text)
        let snapshot = config
        let key = apiKey
        partial = ""
        request.startStream(operation: { [client, snapshot, key, history] emit in
            try await client.replyStreaming(config: snapshot, apiKey: key, messages: history) { piece in
                emit(piece)
            }
        }, receive: { answer in
            self.partial = ""
            self.conversation.answered(answer)
        }, delta: { piece in
            self.partial += piece
        }, failure: { error in
            self.partial = ""
            self.conversation.failed()
            self.error = error.localizedDescription
        })
    }

    private func stop() {
        request.cancel()
    }
}
