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
    @Environment(\.scenePhase) private var scenePhase

    @State private var config = StandardAISettingsStore().load()
    @State private var apiKey = ""
    @State private var keyLoaded = false

    @State private var models: [String] = []
    /// The endpoint the catalog was fetched for. The list belongs to that root:
    /// editing the address hides it without touching state on every keystroke.
    @State private var modelsEndpoint: String?
    @State private var modelsNote: String?
    @State private var prompt = ""
    @State private var messages: [StandardMessage] = []
    @State private var reply: StandardAIReply?
    @State private var error: String?
    @State private var request = StandardAIRequest()

    /// The text fields own their text, and `config` follows it.
    ///
    /// Binding a field straight to `$config.baseURL` and saving on every
    /// `config` change made the field's source of truth race the save: the
    /// field showed what was typed while the saved value stayed a prefix, and
    /// rewrites kept the old tail. A plain `String` state per field has no such
    /// feedback loop, so display and storage read the same value.
    @State private var addressDraft = ""
    @State private var modelDraft = ""
    @State private var draftsLoaded = false
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var editingAddress: Bool

    private let keys = StandardAIKeyStore()
    private let settings = StandardAISettingsStore()

    var body: some View {
        Form {
            Section {
                Picker("接口", selection: $config.protocol) {
                    ForEach(StandardProtocol.allCases) { Text($0.title).tag($0) }
                }
                HStack(spacing: 6) {
                    TextField(config.protocol.defaultBaseURL, text: $addressDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($editingAddress)
                        .onSubmit { flushSave() }
                    // Clearing character by character left the old tail in
                    // place. This resets the whole value in one step. The button
                    // keeps its slot so the row does not re-flow under the caret
                    // when the first character arrives.
                    Button {
                        applyAddress("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(addressDraft.isEmpty)
                    .opacity(addressDraft.isEmpty ? 0 : 1)
                    .accessibilityLabel("清空地址")
                }
                LabeledContent("模型") {
                    TextField("模型名", text: $modelDraft)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if modelsEndpoint == config.effectiveBaseURL, !models.isEmpty {
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
                if let modelsNote, modelsEndpoint == config.effectiveBaseURL {
                    Text(modelsNote).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("密钥")
            } footer: {
                Text("密钥只写进这台设备的钥匙串，不随备份迁移；Core 不持久化它，请求时只放在鉴权头里。")
            }

            Section("对话") {
                ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.role == "user" ? "你" : config.protocol.vendor)
                            .font(.caption).foregroundStyle(.secondary)
                        Text(message.content).textSelection(.enabled)
                    }
                }
                if let reply {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(config.protocol.vendor).font(.caption).foregroundStyle(.secondary)
                        Text(reply.text).textSelection(.enabled)
                        // This standard-protocol path returns a whole reply;
                        // keep its delivery mode explicit.
                        Text(reply.streamed ? "流式" : "整包返回 · 流式尚未接通")
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
        // Saving waits for a pause instead of running on every keystroke.
        .onChange(of: config) { scheduleSave() }
        .onChange(of: addressDraft) { _, new in
            if config.baseURL != new { config.baseURL = new }
        }
        .onChange(of: modelDraft) { _, new in
            if config.model != new { config.model = new }
        }
        // Picking a catalog model writes `config`; the field follows it.
        .onChange(of: config.model) { _, new in
            if modelDraft != new { modelDraft = new }
        }
        // Editing the address must not clear models or stop requests on every
        // keystroke: mutating observable state inside onChange re-renders the
        // field mid-edit and used to drop the next character. The catalog is
        // filtered by its own endpoint in the body instead.
        .onChange(of: config.baseURL) {
            if request.isRunning { stop() }
        }
        .onChange(of: editingAddress) { _, focused in
            // Leaving the field commits without waiting for the debounce.
            if !focused { flushSave() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Killing or backgrounding the app must not discard what is on
            // screen just because the debounce has not fired yet.
            if phase != .active { flushSave() }
        }
        .onChange(of: config.protocol) { loadKey() }
        .task {
            if !draftsLoaded {
                addressDraft = config.baseURL
                modelDraft = config.model
                draftsLoaded = true
            }
            loadKey()
        }
        .onDisappear {
            flushSave()
            stop()
        }
    }

    private var client: StandardAI { StandardAI(core: library.core) }
    private var busy: Bool { request.isRunning }

    /// Sets the address field and its stored value together, cancelling the
    /// pending debounce so the two cannot end up describing different values.
    private func applyAddress(_ text: String) {
        saveTask?.cancel()
        saveTask = nil
        addressDraft = text
        config.baseURL = text
        settings.save(config)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            settings.save(config)
            saveTask = nil
        }
    }

    private func flushSave() {
        saveTask?.cancel()
        saveTask = nil
        settings.save(config)
    }

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
        modelsEndpoint = nil
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
            modelsEndpoint = nil
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
            self.modelsEndpoint = snapshot.effectiveBaseURL
            self.modelsNote = list.isEmpty ? "这家没有列出模型" : "共 \(list.count) 个模型"
            if self.config.model.isEmpty, let first = list.first { self.config.model = first }
        }, failure: { error in
            self.models = []
            self.modelsEndpoint = nil
            self.modelsNote = nil
            self.error = error.localizedDescription
        })
    }

    private func send() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        prompt = ""
        error = nil
        reply = nil
        messages.append(StandardMessage(role: "user", content: text))
        let history = messages
        let snapshot = config
        let key = apiKey
        request.start(operation: { [client, snapshot, key, history] in
            try await client.reply(config: snapshot, apiKey: key, messages: history)
        }, receive: { answer in
            self.reply = answer
            self.messages.append(StandardMessage(role: "assistant", content: answer.text))
        }, failure: { error in
            self.error = error.localizedDescription
        })
    }

    private func stop() {
        request.cancel()
    }
}
