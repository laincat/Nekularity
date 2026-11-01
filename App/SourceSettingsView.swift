import NekularityKit
import Observation
import SwiftUI

/// The settings a comic source declares, drawn by type and stored as JSON in
/// that source's store — the same values Core hands back through `getSetting`.
///
/// A source may declare a number or a boolean, so a chosen value is written as
/// the source wrote it: `JSONValue` keeps the text instead of turning
/// everything into a string.
struct SourceSettingsView: View {
    let source: PluginRecord
    @Environment(SourceLibrary.self) private var library
    @State private var model = SettingsModel()

    var body: some View {
        Form {
            accountSection
            if model.loading {
                ProgressView().frame(maxWidth: .infinity)
            } else if let error = model.error {
                Section {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                    Button("重试") { Task { await model.load(library, key: source.key) } }
                }
            } else if model.settings.isEmpty {
                Section {
                    Text("这个源没有声明设置。").foregroundStyle(.secondary)
                }
            } else {
                ForEach(model.settings) { setting in
                    settingRow(setting)
                }
            }
        }
        .navigationTitle("\(source.name) 的设置")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: source.key) { await model.load(library, key: source.key) }
        .sheet(isPresented: $model.webviewSheet) {
            if let login = model.webviewLogin {
                WebviewLoginView(login: login, key: source.key, library: library) { result in
                    model.webviewLoginFinished(result)
                }
            }
        }
    }

    /// The source's own login, in whichever of the three styles it declares.
    /// Nothing is drawn for a source that needs no account.
    @ViewBuilder private var accountSection: some View {
        if model.account.needsAccount {
            Section("账号") {
                if model.account.webview {
                    Button("在网页里登录") {
                        Task { await model.openWebviewLogin(library, key: source.key) }
                    }
                    .accessibilityIdentifier("account.webviewLogin")
                    .disabled(model.accountBusy)
                }
                if model.account.onlyInPage {
                    Text("这个源只提供网页内登录,登录后窗口会自动关闭。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if model.account.cookies, !model.cookieFields.isEmpty {
                    ForEach(Array(model.cookieFields.enumerated()), id: \.offset) { index, name in
                        TextField(name, text: Binding(
                            get: { model.cookieValues[safe: index] ?? "" },
                            set: { model.setCookie($0, at: index) }))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Button("校验并保存") {
                        Task { await model.loginWithCookies(library, key: source.key) }
                    }
                    .disabled(model.accountBusy)
                }
                if model.account.password {
                    TextField("账号", text: $model.accountUser)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密码", text: $model.accountPassword)
                    Button("登录") {
                        Task { await model.login(library, key: source.key) }
                    }
                    .disabled(model.accountBusy || model.accountUser.isEmpty || model.accountPassword.isEmpty)
                }
                // Logout belongs to every login style: a source that logs in
                // with a browser page or pasted cookies declares it too, and
                // hiding it left no way out.
                if model.account.logout {
                    Button("登出", role: .destructive) {
                        Task { await model.logout(library, key: source.key) }
                    }
                    .disabled(model.accountBusy)
                }
                if model.accountBusy { ProgressView() }
                if !model.accountMessage.isEmpty {
                    Text(model.accountMessage).font(.footnote)
                }
            }
        }
    }

    @ViewBuilder
    private func settingRow(_ setting: SourceSetting) -> some View {
        switch setting.kind {
        case .choice:
            let options = setting.options ?? []
            Picker(model.title(setting), selection: Binding(
                get: { model.choiceIndex(setting) },
                set: { index in
                    guard options.indices.contains(index) else { return }
                    Task { await model.save(library, key: source.key, setting: setting, value: options[index].value) }
                }
            )) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    Text(option.text ?? option.value.stringValue ?? "").tag(index)
                }
            }
        case .toggle:
            Toggle(model.title(setting), isOn: Binding(
                get: { model.toggleValue(setting) },
                set: { on in
                    Task { await model.save(library, key: source.key, setting: setting, value: .bool(on)) }
                }
            ))
        case .text:
            VStack(alignment: .leading, spacing: 4) {
                Text(model.title(setting)).font(.footnote).foregroundStyle(.secondary)
                TextField(text(setting), text: Binding(
                    get: { model.textValue(setting) },
                    set: { model.texts[setting.key] = $0 }
                ))
                .textInputAutocapitalization(.never)
                .onSubmit {
                    Task {
                        let ok = await model.save(library, key: source.key, setting: setting,
                                                 value: .string(model.textValue(setting)))
                        if !ok { model.error = "内容不符合要求：\(setting.validator ?? "")" }
                    }
                }
            }
        case .action:
            // A callback is a function inside the source: the client can only
            // ask it to run and report what came back.
            VStack(alignment: .leading, spacing: 4) {
                // A plain row rather than `LabeledContent`: that container gave the
                // button a target the interface test could see but not press, which
                // is the same thing a person with an unsteady finger would meet.
                HStack(spacing: 8) {
                    Text(model.title(setting))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // The button stays on screen while the source runs: replacing it
                    // with a spinner takes away the control and its identifier, so a
                    // slow callback looks like a press that did nothing.
                    if model.callbackBusy == setting.key {
                        ProgressView().controlSize(.small)
                    }
                    Button(setting.buttonText.flatMap { $0.isEmpty ? nil : $0 } ?? "执行") {
                        Task { await model.runCallback(library, key: source.key, setting: setting.key) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.callbackBusy != nil)
                    .accessibilityIdentifier("setting.callback.\(setting.key)")
                }
                .contentShape(Rectangle())
                if model.callbackBusy == setting.key {
                    Text("正在执行…").font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("setting.running.\(setting.key)")
                }
                if let answer = model.callbackAnswers[setting.key], !answer.isEmpty {
                    Text(answer).font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("setting.answer.\(setting.key)")
                }
            }
        }
    }

    private func text(_ setting: SourceSetting) -> String {
        model.textValue(setting)
    }
}

/// Loads a source's declaration and the values in force.
@MainActor @Observable
final class SettingsModel {
    var settings: [SourceSetting] = []
    var values: [String: JSONValue] = [:]
    /// Text being typed into an input, before it is saved.
    var texts: [String: String] = [:]
    var loading = false
    var error: String?

    /// The UI strings the source declares for this device's locale, so a
    /// settings title shows 域名 where the source wrote "domain".
    var translations: [String: String] = [:]

    /// The title a source asks to be shown: its declared text, translated when
    /// the source supplied one.
    func title(_ setting: SourceSetting) -> String {
        let raw = setting.title.isEmpty ? setting.key : setting.title
        return translations[raw] ?? raw
    }

    /// The source's own login: which styles it declares, and what came back.
    var account = AccountStyles(password: false, webview: false, cookies: false, logout: false)
    var cookieFields: [String] = []
    var cookieValues: [String] = []
    var accountUser = ""
    var accountPassword = ""
    var accountBusy = false
    /// The setting whose callback is running, and what each one answered.
    var callbackBusy: String?
    var callbackAnswers: [String: String] = [:]

    var accountMessage = ""
    /// The source's own login page, when it declares one. Drawn as a sheet so
    /// the user can log in on the site itself.
    var webviewLogin: WebviewLogin?
    var webviewSheet = false

    func setCookie(_ value: String, at index: Int) {
        guard cookieValues.indices.contains(index) else { return }
        cookieValues[index] = value
    }

    func load(_ library: SourceLibrary, key: String) async {
        loading = true
        error = nil
        defer { loading = false }
        translations = (try? await library.core.translations(key: key)) ?? [:]
        account = await library.core.accountStyles(key: key)
        if account.cookies {
            cookieFields = (try? await library.core.accountCookieFields(key: key)) ?? []
            cookieValues = Array(repeating: "", count: cookieFields.count)
        }
        do {
            let declared = try await library.core.settings(key: key)
            settings = declared
            values = [:]
            texts = [:]
            let store = library.core.host.store
            for setting in declared {
                if let stored = try store.loadSetting(key: key, settingKey: setting.key),
                   let value = try? JSONValue.parse(stored) {
                    values[setting.key] = value
                } else if let fallback = setting.default {
                    values[setting.key] = fallback
                }
                texts[setting.key] = values[setting.key]?.stringValue ?? ""
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// The index of the option in force, for a Picker.
    func choiceIndex(_ setting: SourceSetting) -> Int {
        let options = setting.options ?? []
        let current = values[setting.key]?.stringValue
        if let index = options.firstIndex(where: { $0.value.stringValue == current }) {
            return index
        }
        return 0
    }

    func toggleValue(_ setting: SourceSetting) -> Bool {
        if case .bool(let on) = values[setting.key] ?? .null { return on }
        return false
    }

    func textValue(_ setting: SourceSetting) -> String {
        texts[setting.key] ?? values[setting.key]?.stringValue ?? ""
    }

    /// Writes one value and keeps what is on screen in step. Returns whether
    /// the value was accepted by the source's validator.
    @discardableResult
    func save(_ library: SourceLibrary, key: String, setting: SourceSetting, value: JSONValue) async -> Bool {
        if setting.kind == .text {
            if let pattern = setting.validator, !pattern.isEmpty,
               let regex = try? NSRegularExpression(pattern: pattern),
               value.stringValue.map({ regex.firstMatch(in: $0, range: NSRange(location: 0, length: $0.utf16.count)) == nil }) ?? false {
                return false
            }
        }
        do {
            try library.core.host.store.saveSetting(key: key, settingKey: setting.key, json: value.jsonText)
            values[setting.key] = value
            texts[setting.key] = value.stringValue ?? ""
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}

extension SettingsModel {
    /// Runs the source's own password login. What it answers, or the error it
    /// throws, is shown as the source said it.
    func login(_ library: SourceLibrary, key: String) async {
        guard !accountUser.isEmpty, !accountPassword.isEmpty else {
            accountMessage = "账号和密码都要填。"
            return
        }
        accountBusy = true
        accountMessage = ""
        defer { accountBusy = false }
        do {
            let answer = try await library.core.loginAccount(key: key, account: accountUser, password: accountPassword)
            accountMessage = "登录：" + (answer.isEmpty ? "已完成" : answer)
            accountPassword = ""
        } catch {
            accountMessage = error.localizedDescription
        }
    }

    /// Hands pasted cookies to the source's validate, which sets them. A false
    /// answer means the source looked and found them unusable, which is reported
    /// as such rather than as a failure.
    func loginWithCookies(_ library: SourceLibrary, key: String) async {
        accountBusy = true
        accountMessage = ""
        defer { accountBusy = false }
        do {
            let ok = try await library.core.loginWithCookies(key: key, values: cookieValues)
            accountMessage = ok ? "登录：已保存" : "源校验未通过：这组 Cookie 不能用。"
        } catch {
            accountMessage = error.localizedDescription
        }
    }

    /// Runs a callback setting and keeps its answer visible next to it.
    func runCallback(_ library: SourceLibrary, key: String, setting: String) async {
        guard callbackBusy == nil else { return }
        callbackBusy = setting
        defer { callbackBusy = nil }
        do {
            let answer = try await library.core.callSettingCallback(key: key, setting: setting)
            callbackAnswers[setting] = answer.isEmpty ? "已执行" : answer
        } catch {
            callbackAnswers[setting] = error.localizedDescription
        }
    }

    /// Reads the source's declared login page and shows it. A source that
    /// declares none says so instead of opening an empty window.
    func openWebviewLogin(_ library: SourceLibrary, key: String) async {
        accountBusy = true
        accountMessage = ""
        defer { accountBusy = false }
        do {
            let decl = try await library.core.webviewLogin(key: key)
            guard decl.isDeclared else {
                accountMessage = "这个源没有声明网页登录。"
                return
            }
            webviewLogin = decl
            webviewSheet = true
        } catch {
            accountMessage = error.localizedDescription
        }
    }

    /// Called when the login window closes: the cookies are already stored, so
    /// this only reports what happened.
    func webviewLoginFinished(_ result: Result<Int, Error>) {
        webviewSheet = false
        webviewLogin = nil
        switch result {
        case .success(let count):
            accountMessage = "登录状态已保存(\(count) 个 Cookie)"
        case .failure(let error):
            accountMessage = error.localizedDescription
        }
    }

    func logout(_ library: SourceLibrary, key: String) async {
        accountBusy = true
        accountMessage = ""
        defer { accountBusy = false }
        do {
            try await library.core.logoutAccount(key: key)
            accountMessage = "已登出"
        } catch {
            accountMessage = error.localizedDescription
        }
    }
}
