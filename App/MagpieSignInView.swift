import SwiftUI
import NekularityKit

/// Signing in to a provider through its own package: the methods it declares,
/// the page it names, and the code the user types there.
///
/// The package's callback does the polling; this screen only shows where to go
/// and lets the user give up, which also tells the package to stop.
struct MagpieSignInView: View {
    let accounts: MagpieAccounts
    let provider: String
    let providerName: String
    let onSignedIn: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var spec: MagpieAuthSpec?
    @State private var session: MagpieSignIn?
    @State private var start: MagpieSignInStart?
    @State private var pending = false
    @State private var message: String?

    @State private var copied = false
    /// The method whose fields the user is filling in, when it asks for any.
    @State private var collecting: MagpieAuthSpec.Method?
    @State private var answers: [String: String] = [:]

    var body: some View {
        NavigationStack {
            Form {
                if let spec, !spec.methods.isEmpty {
                    Section {
                        ForEach(spec.methods, id: \.index) { method in
                            Button {
                                // A method with fields collects them here; one
                                // with a page starts straight away.
                                if method.collectsInput && method.kind != "device" {
                                    collecting = method
                                    answers = Dictionary(uniqueKeysWithValues: method.prompts.map { ($0.key, "") })
                                } else {
                                    begin(method, inputs: [:])
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(method.label.isEmpty ? "登录" : method.label)
                                        if !method.hint.isEmpty {
                                            Text(method.hint)
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if pending { ProgressView() }
                                }
                            }
                            .disabled(pending)
                        }
                    } header: {
                        Text("登录方式")
                    } footer: {
                        Text("登录在这一台设备上使用 \(providerName) 自己的授权方式，不会经过漫画源，也不会共用漫画源的 Cookie。")
                    }
                } else if pending {
                    Section { ProgressView("正在读取插件提供的登录方式…") }
                } else {
                    Section {
                        Text("这个插件没有提供登录方式。")
                            .foregroundStyle(.secondary)
                    }
                }

                if let method = collecting {
                    Section {
                        ForEach(method.prompts, id: \.key) { prompt in
                            VStack(alignment: .leading, spacing: 4) {
                                if !prompt.message.isEmpty {
                                    Text(prompt.message).font(.footnote)
                                }
                                if prompt.isSecret {
                                    SecureField(prompt.placeholder, text: binding(for: prompt.key))
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                } else {
                                    TextField(prompt.placeholder, text: binding(for: prompt.key))
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                }
                            }
                        }
                        Button("登录") { begin(method, inputs: answers) }
                            .disabled(pending)
                    } header: {
                        Text(method.label)
                    } footer: {
                        Text("这些内容只存在这台设备的 Keychain 里,不会经过漫画源。")
                    }
                }

                if let start {
                    Section("还需要一步") {
                        if !start.instructions.isEmpty {
                            Text(start.instructions)
                        }
                        if !start.userCode.isEmpty {
                            HStack {
                                Text(start.userCode)
                                    .font(.system(.title3, design: .monospaced))
                                    .textSelection(.enabled)
                                Spacer()
                                Button(copied ? "已复制" : "复制") {
                                    UIPasteboard.general.string = start.userCode
                                    copied = true
                                }
                            }
                        }
                        if let url = start.url {
                            Button("打开授权页面") { UIApplication.shared.open(url) }
                        }
                        Button("我已完成，继续", role: .none) { wait() }
                            .disabled(pending)
                    }
                    Section {
                        Button("取消登录", role: .destructive) {
                            session?.cancel()
                            dismiss()
                        }
                    }
                }

                if let message {
                    Section {
                        Text(message).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("登录 \(providerName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        session?.cancel()
                        dismiss()
                    }
                }
            }
            .task { load() }
        }
    }

    /// Reading the spec starts the package's runtime the first time, so it is
    /// off the main thread like the provider list is.
    private func load() {
        pending = true
        Task {
            defer { pending = false }
            do {
                spec = try await Task.detached { [accounts, provider] in
                    try accounts.runner(for: provider).auth(provider: provider)
                }.value
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(get: { answers[key] ?? "" }, set: { answers[key] = $0 })
    }

    private func begin(_ method: MagpieAuthSpec.Method, inputs: [String: String]) {
        pending = true
        message = nil
        session?.cancel()
        session = nil
        start = nil
        Task {
            do {
                collecting = nil
                let newSession = try accounts.makeSignIn(provider: provider, inputs: inputs)
                session = newSession
                let started = try newSession.start(methodIndex: method.index)
                start = started
                // A key-based method has already finished: there is no page to
                // open and no callback to wait for, so asking the user to press
                // "I'm done" would be a step that does nothing.
                if started.immediateAuthJSON != nil {
                    pending = false
                    wait()
                    return
                }
            } catch {
                message = error.localizedDescription
                session?.cancel()
            }
            pending = false
        }
    }

    private func wait() {
        guard let session else { return }
        pending = true
        Task {
            let outcome = await session.waitForResult()
            pending = false
            switch outcome {
            case .success:
                onSignedIn()
                dismiss()
            case .failed(let reason):
                message = reason
            case .cancelled:
                dismiss()
            }
        }
    }
}
